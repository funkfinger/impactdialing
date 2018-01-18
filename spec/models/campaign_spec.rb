require 'rails_helper'

describe Campaign, :type => :model do
  describe '#fit_to_dial?' do
    include FakeCallData

    let(:account) do
      create(:user).account
    end
    let(:campaign) do
      create_campaign_with_script(:bare_predictive, account).last
    end
    context 'return false when' do
      it 'account not funded' do
        campaign.account.quota.update_attributes!(minutes_allowed: 0)
        expect(campaign.fit_to_dial?).to be_falsey
      end

      it 'outside calling hours' do
        make_it_outside_calling_hours(campaign)
        expect(campaign.fit_to_dial?).to be_falsey
      end

      it 'calling disabled' do
        campaign.account.quota.update_attributes!(disable_calling: true)
        expect(campaign.fit_to_dial?).to be_falsey
      end
    end
  end

  describe 'callbacks' do
    let(:campaign){ create(:campaign) }

    describe 'sanitizing message service settings' do
      before do
        campaign.call_back_after_voicemail_delivery = true
        campaign.answering_machine_detect           = true
        campaign.use_recordings                     = true
        campaign.save
        expect(campaign.use_recordings).to be_truthy
        expect(campaign.answering_machine_detect).to be_truthy
        expect(campaign.call_back_after_voicemail_delivery).to be_truthy
      end
      it 'should set use_recordings & call_back_after_voicemail_delivery to false, if it is true and answering_machine_detect is false' do
        campaign.answering_machine_detect = false
        campaign.save
        expect(campaign.use_recordings).to be_falsey
        expect(campaign.answering_machine_detect).to be_falsey
        expect(campaign.call_back_after_voicemail_delivery).to be_falsey
      end

      it 'should set call_back_after_voicemail_delivery to false, if it is true and use_recordings and caller_can_drop_message_manually are both false' do
        campaign.use_recordings = false
        campaign.save
        expect(campaign.call_back_after_voicemail_delivery).to be_falsey
        expect(campaign.answering_machine_detect).to be_truthy
        expect(campaign.use_recordings).to be_falsey
      end

      it 'should not abort callback chain' do
        campaign.use_recordings = false
        campaign.caller_can_drop_message_manually = true
        campaign.save
        expect(campaign.caller_can_drop_message_manually).to be_truthy
      end
    end

    describe 'dial queue lifecycle' do
      include ListHelpers

      let(:voter_list){ create(:voter_list, campaign: campaign) }

      let(:purge_job) do
        {
          'class' => 'CallFlow::DialQueue::Jobs::Purge',
          'args'  => [campaign.id]
        }
      end
      it 'queues purge when a campaign is archived and a dial queue is present' do
        import_list(voter_list, build_household_hash(voter_list))
        campaign.active = false
        campaign.save!

        expect(resque_jobs(:general)).to include(purge_job)
      end

      it 'does not queue purge when campaign is archived and dial queue not present' do
        campaign.active = false
        campaign.save!

        expect(resque_jobs(:general)).to_not include(purge_job)
      end
    end
  end

  describe "validations" do
    let(:campaign) { create(:campaign, :account => create(:account)) }
    it {expect(campaign).to validate_presence_of :name}
    it {expect(campaign).to validate_presence_of :script}
    it {expect(campaign).to validate_presence_of :type}
    it {
      # this breaks w/ NameError for some reason
      # campaign.should ensure_inclusion_of(:type).in_array(['Preview', 'Power', 'Predictive'])
      # => NameError: wrong constant name shouldamatchersteststring
      # => seems to do w/ the special :type attr but odd that it passed previously
      # => because this also breaks w/ NameError but different message
      # campaign.type = 'Blah'
      # campaign.should have(1).error_on(:type)
      # => NameError: uninitialized constant Blah
      # looks like an edge-case in shoulda
      campaign.type = 'Account'
      expect(campaign).to have(1).error_on(:type)
      campaign.type = 'Campaign'
      expect(campaign).to have(1).error_on(:type)
      campaign.type = 'Preview'
      expect(campaign).to have(0).errors_on(:type)
      campaign.type = 'Power'
      expect(campaign).to have(0).errors_on(:type)
      campaign.type = 'Predictive'
      expect(campaign).to have(0).errors_on(:type)

    }

    it {expect(campaign).to validate_presence_of :time_zone}
    it {expect(campaign).to ensure_inclusion_of(:time_zone).in_array(ActiveSupport::TimeZone.zones_map.map {|z| z.first})}
    it {expect(campaign).to validate_presence_of :start_time}
    it {expect(campaign).to validate_presence_of :end_time}
    it {expect(campaign).to validate_numericality_of :acceptable_abandon_rate}
    it {expect(campaign).to have_many :caller_groups}

    it 'requires recycle_rate must be present' do
      expect(campaign).to invalidate_recycle_rate nil
    end

    it 'requires recycle_rate is a number' do
      expect(campaign).to invalidate_recycle_rate 'abc'
    end

    it 'requires recycle_rate be at least 1' do
      expect(campaign).to invalidate_recycle_rate 0
    end

    it 'recycle_rate can be as large as folks want' do
      expect(campaign).to validate_recycle_rate 24*7
    end

    it 'return validation error, if caller id is either blank, not a number or not a valid length' do
      campaign = build(:campaign, account: create(:account))
      campaign.save(:validate => false)
      expect(campaign.update_attributes(:caller_id => '23456yuiid')).to be_falsey
      expect(campaign.errors[:base]).to eq(['Caller ID must be a 10-digit North American phone number or begin with "+" and the country code'])
      expect(campaign.update_attributes(:caller_id => '')).to be_falsey
      expect(campaign.errors[:base]).to eq(['Caller ID must be a 10-digit North American phone number or begin with "+" and the country code'])
    end

    it "skips validations for an international phone number when the ENV var is set" do
      ENV['INTERNATIONAL'] = 'true'
      campaign = build(:campaign, :caller_id => "+98743987")
      expect(campaign).to be_valid
      campaign = build(:campaign, :caller_id => "+987AB87A")
      expect(campaign).to be_valid
    end

    it 'removes the 1 from the beginning of a phone number' do
      campaign = build(:campaign, :caller_id => "1-503-555-121")
      expect(campaign).not_to be_valid
    end

    it 'return validation error, when callers are login and try to change dialing mode' do
      campaign = create(:preview)
      campaign.caller_sessions.create!(on_call: true, state: "initial")
      campaign.type = Campaign::Type::POWER
      expect(campaign.save).to be_falsey
      expect(campaign.errors[:base]).to eq(['You cannot change dialing modes while callers are logged in.'])
      campaign.reload
      expect(campaign.type).to eq(Campaign::Type::PREVIEW)
    end

    it 'can change dialing mode when not on call' do
      campaign = create(:preview)
      campaign.type = Campaign::Type::POWER
      expect(campaign.save).to be_truthy
      expect(campaign.type).to eq(Campaign::Type::POWER)
    end


    it "should not invoke Twilio if caller id is not present" do
      expect(TwilioLib).not_to receive(:new)
      campaign = create(:campaign, :type =>Campaign::Type::PREVIEW)
      campaign.caller_id = nil
      campaign.save
    end

    it "sets use_recordings to false when answering_machine_detect is false" do
      campaign = create(:power, {answering_machine_detect: false})
      campaign.use_recordings = true
      campaign.save
      expect(campaign.use_recordings).to be_falsey
    end

    it "sets call_back_after_voicemail_delivery to false when both use_recordings and caller_can_drop_message_manually are false" do
      campaign = create(:power, {use_recordings: false, caller_can_drop_message_manually: false})
      campaign.call_back_after_voicemail_delivery = true
      campaign.save
      expect(campaign.call_back_after_voicemail_delivery).to be_falsey
    end

    describe "archive campaign" do
      it 'is considered archived when Campaign#active => false' do
        campaign.active = false
        campaign.save!
        expect(campaign.archived?).to be_truthy
      end
      context 'when callers (active or inactive) are assigned' do
        let(:campaign){ create(:campaign) }
        let(:campaign_job) do
          {
            'class' => 'Archival::Jobs::CampaignArchived',
            'args' => [campaign.id]
          }
        end
        before do
          create(:caller, {campaign: campaign, active: true})
          create(:caller, {campaign: campaign, active: false})
          campaign.reload
          campaign.active = false
          campaign.save!
        end

        it 'queues job to un-assign callers from campaign' do
          expect(resque_jobs(:general)).to include(campaign_job)
        end
      end
    end
  end

  describe 'archived campaign' do
    let(:campaign){ build(:campaign) }

    it '#archived? => false' do
      campaign.active = false
      expect(campaign.archived?).to be_truthy
    end
  end


  describe "campaigns with caller sessions that are on call" do
    let(:user) { create(:user) }
    let(:campaign) { create(:preview, :account => user.account) }

    it "should give the campaign only once even if it has multiple caller sessions" do
      create(:caller_session, :campaign => campaign, :on_call => true)
      create(:caller_session, :campaign => campaign, :on_call => true)
      expect(user.account.campaigns.with_running_caller_sessions).to eq([campaign])
    end

    it "should not give campaigns without on_call caller sessions" do
      create(:caller_session, :campaign => campaign, :on_call => false)
      expect(user.account.campaigns.with_running_caller_sessions).to be_empty
    end

    it "should not give another user's campaign'" do
      create(:caller_session, :campaign => create(:campaign, :account => create(:account)), :on_call => true)
      expect(user.account.campaigns.with_running_caller_sessions).to be_empty
    end

  end

  describe "answer report" do
      let(:script) { create(:script)}
      let(:campaign) { create(:predictive, :script => script) }
      let(:call_attempt1) { create(:call_attempt,:campaign => campaign) }
      let(:call_attempt2) { create(:call_attempt,:campaign => campaign) }
      let(:call_attempt3) { create(:call_attempt,:campaign => campaign) }
      let(:call_attempt4) { create(:call_attempt,:campaign => campaign) }

      let(:voter1) { create(:voter, :campaign => campaign, :last_call_attempt => call_attempt1)}
      let(:voter2) { create(:voter, :campaign => campaign, :last_call_attempt => call_attempt2)}
      let(:voter3) { create(:voter, :campaign => campaign, :last_call_attempt => call_attempt3)}
      let(:voter4) { create(:voter, :campaign => campaign, :last_call_attempt => call_attempt4)}

    it "should give the final results of a campaign as a Hash" do
      now = Time.now
      campaign2 = create(:predictive)
      question1 = create(:question, :text => "hw are u", :script => script)
      question2 = create(:question, :text => "wr r u", :script => script)
      possible_response1 = create(:possible_response, :value => "fine", :question => question1)
      possible_response2 = create(:possible_response, :value => "super", :question => question1)
      create(:answer, :voter => create(:voter, :campaign => campaign), campaign: campaign, :possible_response => possible_response1, :question => question1, :created_at => now)
      create(:answer, :voter => create(:voter, :campaign => campaign), campaign: campaign,:possible_response => possible_response2, :question => question1, :created_at => now)
      create(:answer, :voter => create(:voter, :campaign => campaign), campaign: campaign,:possible_response => question1.possible_responses.first, :question => question1, :created_at => now)
      create(:answer, :voter => create(:voter, :campaign => campaign), campaign: campaign, :possible_response => possible_response2, :question => question2, :created_at => now)
      expect(campaign.answers_result(now, now)).to eq({script.id => {script: script.name, questions: {"hw are u" => [{:answer=>"[No response]", :number=>1, :percentage=>33}, {answer: possible_response1.value, number: 1, percentage: 33}, {answer: possible_response2.value, number: 2, percentage: 66}], "wr r u" => [{answer: "[No response]", number: 0, percentage: 0}]}}})
    end

    it "should give the final results of a campaign as a Hash" do
      now = Time.now
      new_script = create(:script, name: 'new script')
      campaign2 = create(:predictive)
      question1 = create(:question, :text => "hw are u", :script => script)
      question2 = create(:question, :text => "whos your daddy", :script => new_script)
      possible_response1 = create(:possible_response, :value => "fine", :question => question1)
      possible_response2 = create(:possible_response, :value => "super", :question => question1)
      possible_response3 = create(:possible_response, :value => "john", :question => question2)
      possible_response4 = create(:possible_response, :value => "dou", :question => question2)
      create(:answer, :voter => create(:voter, :campaign => campaign), campaign: campaign, :possible_response => possible_response1, :question => question1, :created_at => now)
      create(:answer, :voter => create(:voter, :campaign => campaign), campaign: campaign,:possible_response => possible_response2, :question => question1, :created_at => now)
      create(:answer, :voter => create(:voter, :campaign => campaign), campaign: campaign,:possible_response => possible_response3, :question => question2, :created_at => now)
      create(:answer, :voter => create(:voter, :campaign => campaign), campaign: campaign, :possible_response => possible_response4, :question => question2, :created_at => now)
      expect(campaign.answers_result(now, now)).to eq({
        script.id => {
          script: script.name,
          questions: {
            "hw are u" => [
              {:answer=>"[No response]", :number=>0, :percentage=>0},
              {answer: possible_response1.value, number: 1, percentage: 50},
              {answer: possible_response2.value, number: 1, percentage: 50}

            ]
          }
        },
        new_script.id => {
          script: new_script.name,
          questions: {
            "whos your daddy" => [
              {:answer=>"[No response]", :number=>0, :percentage=>0},
              {answer: possible_response3.value, number: 1, percentage: 50},
              {answer: possible_response4.value, number: 1, percentage: 50}

            ]
          }
        }
      })
    end

  end

  describe "amd" do
    describe "contine on amd" do
      it "should return true if answering machine detect and recording present" do
        campaign = create(:preview, answering_machine_detect: true, use_recordings: true)
        expect(campaign.continue_on_amd).to be_truthy
      end

      it "should return false if answering machine detect and recording not present" do
        campaign = create(:preview, answering_machine_detect: true, use_recordings: false)
        expect(campaign.continue_on_amd).to be_falsey
      end

      it "should return false if answering machine detect false and recording  present" do
        campaign = create(:preview, answering_machine_detect: false, use_recordings: true)
        expect(campaign.continue_on_amd).to be_falsey
      end
    end

    describe "hangup on amd" do
      it "should return true if answering machine detect and recording not present" do
        campaign = create(:preview, answering_machine_detect: true, use_recordings: false)
        expect(campaign.hangup_on_amd).to be_truthy
      end

      it "should return false if answering machine detect and recording  present" do
        campaign = create(:preview, answering_machine_detect: true, use_recordings: true)
        expect(campaign.hangup_on_amd).to be_falsey
      end

    end

  end

  describe "time period" do
    include FakeCallData

    let(:admin){ create(:user) }
    let(:account){ admin.account }
    let(:campaign) do
      create_campaign_with_script(:bare_predictive, account).last
    end

    it "should allow callers to dial, if time not expired" do
      campaign.start_time = 1.hour.ago.in_time_zone(campaign.time_zone)
      campaign.end_time   = 1.hours.from_now.in_time_zone(campaign.time_zone)

      expect(campaign.time_period_exceeded?).to be_falsy
    end

    it "should not allow callers to dial, if time  expired" do
      campaign.start_time = 4.hours.ago.in_time_zone(campaign.time_zone)
      campaign.end_time   = 3.hours.ago.in_time_zone(campaign.time_zone)

      expect(campaign.time_period_exceeded?).to(be_truthy, [
        "Expected to be outside calling hours with:",
        "Start time: #{campaign.start_time}",
        "End time: #{campaign.end_time}",
        "Current time: #{Time.now.utc.in_time_zone(campaign.time_zone)}"
      ].join("\n"))
    end
  end

   it "restoring makes it active" do
     campaign = create(:campaign, :active => false)
     campaign.restore
     expect(campaign).to be_active
   end

   describe "scopes" do

     it "gives only active voter lists" do
       campaign = create(:preview)
       active_voterlist = create(:voter_list, :campaign => campaign, :active => true)
       inactive_voterlist = create(:voter_list, :campaign => campaign, :active => false)
       expect(campaign.voter_lists).to eq([active_voterlist])
     end

     it "returns campaigns having a session with the given caller" do
       caller = create(:caller)
       campaign = create(:preview)
       create(:caller_session, :campaign => campaign, :caller => caller)
       expect(Campaign.for_caller(caller)).to eq([campaign])
     end

     it "sorts by the updated date" do
       Campaign.record_timestamps = false
       older_campaign = create(:power).tap { |c| c.update_attribute(:updated_at, 2.days.ago) }
       newer_campaign = create(:power).tap { |c| c.update_attribute(:updated_at, 1.day.ago) }
       Campaign.record_timestamps = true
       expect(Campaign.by_updated.to_a).to include (newer_campaign)
       expect(Campaign.by_updated.to_a).to include (older_campaign)

     end

     it "lists deleted campaigns" do
       deleted_campaign = create(:power, :active => false)
       other_campaign = create(:power, :active => true)
       expect(Campaign.deleted).to eq([deleted_campaign])
     end

     it "should return active campaigns" do
       campaign1 = create(:power)
       campaign2 = create(:preview)
       campaign3 = create(:predictive, :active => false)
       expect(Campaign.active).to include(campaign1)
       expect(Campaign.active).to include(campaign2)
     end
  end

  describe "callers_status" do

    before (:each) do
      @campaign = create(:preview)
      @caller_session1 = create(:webui_caller_session, campaign_id: @campaign.id, on_call:true, available_for_call: true)
      @caller_session2 = create(:webui_caller_session, on_call:true, available_for_call: false, campaign_id: @campaign.id)
    end

    it "should return callers logged in" do
      expect(@campaign.callers_status[0]).to eq(2)
    end

    it "should return callers on hold" do
      expect(@campaign.callers_status[1]).to eq(1)
    end

    it "should return callers on call" do
      expect(@campaign.callers_status[2]).to eq(1)
    end


  end

  describe "current status" do
    it "should return campaign details" do
      campaign = create(:predictive)
      c1= create(:phones_only_caller_session, on_call: false, available_for_call: false, campaign: campaign)

      c2= create(:webui_caller_session, on_call: true, available_for_call: false, attempt_in_progress: create(:call_attempt, connecttime: Time.now), campaign: campaign, state: "paused")
      c3= create(:phones_only_caller_session, on_call: true, available_for_call: false, attempt_in_progress: create(:call_attempt, connecttime: Time.now), campaign: campaign, state: "voter_response")
      c4= create(:phones_only_caller_session, on_call: true, available_for_call: false, attempt_in_progress: create(:call_attempt, connecttime: Time.now), campaign: campaign, state: "wrapup_call")

      c5= create(:webui_caller_session, on_call: true, available_for_call: true, attempt_in_progress: create(:call_attempt, campaign: campaign, status: CallAttempt::Status::RINGING, created_at: Time.now), campaign: campaign)
      c6= create(:phones_only_caller_session, on_call: true, available_for_call: true, campaign: campaign)
      c7= create(:webui_caller_session, on_call: true, available_for_call: true, attempt_in_progress: create(:call_attempt, campaign: campaign, status: CallAttempt::Status::RINGING, created_at: Time.now), campaign: campaign)
      c8= create(:webui_caller_session, on_call: true, available_for_call: false, campaign: campaign, attempt_in_progress: create(:call_attempt, connecttime: Time.now), state: "connected")
      c9= create(:phones_only_caller_session, on_call: true, available_for_call: false, campaign: campaign, attempt_in_progress: create(:call_attempt, connecttime: Time.now), state: "conference_started_phones_only_predictive")

      c10= create(:webui_caller_session, on_call: true, available_for_call: true, attempt_in_progress: create(:call_attempt, connecttime: Time.now), campaign: campaign)
      RedisStatus.set_state_changed_time(campaign.id, "On hold", c2.id)
      RedisStatus.set_state_changed_time(campaign.id, "On hold", c5.id)
      RedisStatus.set_state_changed_time(campaign.id, "On hold", c6.id)
      RedisStatus.set_state_changed_time(campaign.id, "On hold", c7.id)

      RedisStatus.set_state_changed_time(campaign.id, "On call", c8.id)
      RedisStatus.set_state_changed_time(campaign.id, "On call", c9.id)

      RedisStatus.set_state_changed_time(campaign.id, "Wrap up", c3.id)
      RedisStatus.set_state_changed_time(campaign.id, "Wrap up", c4.id)
      RedisStatus.set_state_changed_time(campaign.id, "Wrap up", c10.id)

      2.times{ campaign.send(:inflight_stats).inc('ringing') }

      expect(campaign.current_status).to eq ({callers_logged_in: 9, on_call: 2, wrap_up: 3, on_hold: 4, ringing_lines: 2, available: 0})
    end
  end

  describe "within_recycle_rate?(obj)" do
    let(:duck_available1) do
      double('AvailableDuckVoter1', {
        last_call_attempt_time: 4.days.ago
      })
    end
    let(:duck_available2) do
      double('AvailableDuckVoter2', {
        last_call_attempt_time: 25.hours.ago
      })
    end
    let(:duck_available3) do
      double('AvailableDuckVoter3', {
        last_call_attempt_time: nil
      })
    end
    let(:duck_in_recycle_rate1) do
      double('UnavailableDuckVoter1', {
        last_call_attempt_time: 5.seconds.ago
      })
    end
    let(:duck_in_recycle_rate2) do
      double('UnavailableDuckVoter1', {
        last_call_attempt_time: 4.hours.ago
      })
    end
    let(:duck_in_recycle_rate3) do
      double('UnavailableDuckVoter1', {
        last_call_attempt_time: 23.hours.ago + 59.minutes
      })
    end
    let(:non_duck) do
      double('NonDuck')
    end
    let(:campaign) do
      create(:preview, {
        recycle_rate: 24
      })
    end

    it 'returns true iff obj.last_call_attempt_time > Campaign#recycle_rate.hours.ago' do
      expect(campaign.within_recycle_rate?(duck_in_recycle_rate1)).to be_truthy
      expect(campaign.within_recycle_rate?(duck_in_recycle_rate2)).to be_truthy
    end

    it 'returns true if obj.last_call_attempt_time = Campaign#recycle_rate.hours.ago' do
      expect(campaign.within_recycle_rate?(duck_in_recycle_rate3)).to be_truthy
    end

    it 'returns false if obj.last_call_attempt_time < Campaign#recycle_rate.hours.ago' do
      expect(campaign.within_recycle_rate?(duck_available1)).to be_falsey
      expect(campaign.within_recycle_rate?(duck_available2)).to be_falsey
    end

    it 'returns false if obj.last_call_attempt_time.nil?' do
      expect(campaign.within_recycle_rate?(duck_available3)).to be_falsey
    end

    it 'raises ArgumentError if obj does not respond to last_call_attempt_time' do
      expect{ campaign.within_recycle_rate?(non_duck) }.to raise_error{ ArgumentError }
    end
  end
end

# ## Schema Information
#
# Table name: `campaigns`
#
# ### Columns
#
# Name                            | Type               | Attributes
# ------------------------------- | ------------------ | ---------------------------
# **`id`**                        | `integer`          | `not null, primary key`
# **`campaign_id`**               | `string(255)`      |
# **`name`**                      | `string(255)`      |
# **`account_id`**                | `integer`          |
# **`script_id`**                 | `integer`          |
# **`active`**                    | `boolean`          | `default(TRUE)`
# **`created_at`**                | `datetime`         |
# **`updated_at`**                | `datetime`         |
# **`caller_id`**                 | `string(255)`      |
# **`type`**                      | `string(255)`      |
# **`recording_id`**              | `integer`          |
# **`use_recordings`**            | `boolean`          | `default(FALSE)`
# **`calls_in_progress`**         | `boolean`          | `default(FALSE)`
# **`robo`**                      | `boolean`          | `default(FALSE)`
# **`recycle_rate`**              | `integer`          | `default(1)`
# **`answering_machine_detect`**  | `boolean`          |
# **`start_time`**                | `time`             |
# **`end_time`**                  | `time`             |
# **`time_zone`**                 | `string(255)`      |
# **`acceptable_abandon_rate`**   | `float`            |
# **`voicemail_script_id`**       | `integer`          |
#
