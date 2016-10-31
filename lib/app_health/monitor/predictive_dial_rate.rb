module AppHealth
  module Monitor
    class PredictiveDialRate

    private
      def on_hold_times(campaign)
        RedisStatus.on_hold_times(campaign.id, *campaign.caller_sessions.available.pluck(:id))
      end

      def any_callers_exceed_on_hold_threshold?(campaign)
        on_hold_times(campaign).detect{|n| n >= on_hold_threshold}
      end

      def no_recent_dials?(campaign)
        (Time.now.utc.to_i - campaign.last_dial_time) > 60
      end

      def on_hold_threshold
        (ENV['PREDICTIVE_ON_HOLD_THRESHOLD'] || 20).to_i
      end

    public
      def self.ok?
        instance = new
        instance.ok?
      end

      def self.alert_if_not_ok
        instance = new
        instance.alert_if_not_ok
      end

      def initialize
      end

      def alarm_key
        time = Time.now.strftime('%d/%m/%Y')
        "#{time} - #{stagnant_campaign_ids}"
      end

      def alarm_description
        "#{stagnant_campaign_ids.size} campaigns have no recent dials"
      end

      def alarm_details
        stagnant_campaigns.map do |campaign|
          { account_email: campaign.account.users.first.email,
            campaign_name: campaign.name,
            campaign_id: campaign.id,
            active_callers: campaign.caller_sessions_on_call.count }
        end.to_json
      end

      def alert_if_not_ok
        unless ok?
          # automatically fix the most common problem
          stagnant_campaigns.each do |campaign|
            if campaign.caller_sessions_on_call.count == 1 && campaign.presented_count > 0
              campaign.inflight_stats.set('presented', 0)
            end
          end

          AppHealth::Alarm.trigger!(alarm_key, alarm_description, alarm_details)
          return false
        end
        return true
      end

      def running_campaigns
        Campaign.find(RedisPredictiveCampaign.running_campaigns)
      end

      def stagnant_campaigns
        @stagnant_campaigns ||= running_campaigns.select do |campaign|
          any_callers_exceed_on_hold_threshold?(campaign) && no_recent_dials?(campaign)
        end
      end

      def stagnant_campaign_ids
        @stagnant_campaign_ids ||= stagnant_campaigns.map(&:id)
      end

      def ok?
        stagnant_campaign_ids.empty?
      end
    end
  end
end
