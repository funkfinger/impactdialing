require 'em-http-request'

class PowerPreviewDialJob
  @queue = :power_preview_dial_job
  
  def self.perform(caller_session_id, voter_id)    
    caller_session = CallerSession.find(caller_session_id)
    caller_session.dial_em(Voter.find(voter_id)) 
  end
end