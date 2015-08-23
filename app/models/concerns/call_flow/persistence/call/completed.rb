class CallFlow::Persistence::Call::Completed
  attr_reader :dialed_call, :campaign, :household_record

  def initialize(account_sid, call_sid)
    @dialed_call      = CallFlow::Call::Dialed.new(account_sid, call_sid)
    @campaign         = Campaign.find(dialed_call.storage['campaign_id'])
    @household_record = campaign.households.where(phone: dialed_call.storage['phone']).first
  end

  def persist_call_outcome
    @household_record = call_persistence.create_or_update_household_record

    leads.import_records
    call_attempt_record = call_persistence.create_call_attempt(leads.dispositioned_voter)

    survey_responses.save(leads.dispositioned_voter, call_attempt_record)

    if leads.dispositioned_voter.present? and survey_responses.complete_lead?
      completed_lead_sequence = leads.target_lead['sequence']
      campaign.dial_queue.households.mark_lead_completed(completed_lead_sequence)
    end

    campaign.dial_queue.dialed_number_persisted(household_record.phone, leads.target_lead)
  end

  def call_persistence
    @call_persistence ||= CallFlow::Persistence::Call.new(dialed_call, campaign, household_record)
  end

  def leads
    @leads ||= CallFlow::Persistence::Leads.new(dialed_call, campaign, household_record)
  end

  def survey_responses
    @answers ||= CallFlow::Persistence::SurveyResponses.new(dialed_call, campaign, household_record)
  end
end

