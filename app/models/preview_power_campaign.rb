module PreviewPowerCampaign
  
  def next_voter_in_dial_queue(current_voter_id = nil)
    voter = all_voters.priority_voters.first
    voter||= all_voters.scheduled.first
    voter||= all_voters.last_call_attempt_before_recycle_rate(recycle_rate).to_be_dialed.not_skipped.where("voters.id > #{current_voter_id}").first unless current_voter_id.blank?
    voter||= all_voters.last_call_attempt_before_recycle_rate(recycle_rate).to_be_dialed.not_skipped.first
    voter||= all_voters.last_call_attempt_before_recycle_rate(recycle_rate).to_be_dialed.where("voters.id != #{current_voter_id}").first unless current_voter_id.blank?
    voter||= all_voters.last_call_attempt_before_recycle_rate(recycle_rate).to_be_dialed.first
    unless voter.nil?
      begin
        voter.update_attributes(status: CallAttempt::Status::READY)
      rescue ActiveRecord::StaleObjectError
        next_voter_in_dial_queue(voter.id)
      end
    end
    voter
  end
  
  def call_answered_by_machine(call_attempt)
    call_attempt.caller_session.update_attribute(:voter_in_progress, nil)
    next_voter = campaign.next_voter_in_dial_queue(call_attempt.voter.id)
    call_attempt.caller_session.publish('voter_push', next_voter ? next_voter.info : {})
    call_attempt.caller_session.publish('conference_started', {})    
  end
  
  def push_next_voter_to_dial(call_attempt)
    next_voter = next_voter_in_dial_queue(call_attempt.voter.id)
    call_attempt.caller_session.publish('voter_push', next_voter ? next_voter.info : {})    
  end
  
end