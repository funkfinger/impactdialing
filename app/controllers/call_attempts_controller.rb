require 'new_relic/agent/method_tracer'
class CallAttemptsController < ApplicationController
  include NewRelic::Agent::MethodTracer
  
  def create
    call_attempt = CallAttempt.find(params[:id])
    robo_recording = RoboRecording.find(params[:robo_recording_id])
    call_response = CallResponse.log_response(call_attempt, robo_recording, params[:Digits])
    xml = call_attempt.next_recording(robo_recording, call_response)
    logger.info "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    logger.info "[dialer] DTMF input received. call_attempt: #{params[:id]} keypad: #{params[:Digits]} Response: #{xml}"
    render :xml => xml
  end

  def connect
    call_attempt = CallAttempt.find(params[:id])
    Rails.logger.debug("callconnect: #{params[:AnsweredBy]}")
    call_attempt.update_attribute(:connecttime, Time.now)
    response = case params[:AnsweredBy] #using the 2010 api
                 when "machine"
                   call_attempt.voter.update_attributes(:status => CallAttempt::Status::HANGUP)
                   call_attempt.update_attributes(:status => CallAttempt::Status::HANGUP)
                   if call_attempt.caller_session && (call_attempt.campaign.predictive_type == Campaign::Type::PREVIEW || call_attempt.campaign.predictive_type == Campaign::Type::PROGRESSIVE)
                     call_attempt.caller_session.publish('answered_by_machine', {})
                     call_attempt.caller_session.update_attribute(:voter_in_progress, nil)
                     next_voter = call_attempt.campaign.next_voter_in_dial_queue(call_attempt.voter.id)
                     call_attempt.caller_session.publish('voter_push', next_voter ? next_voter.info : {})
                     call_attempt.caller_session.publish('conference_started', {})
                   end
                   call_attempt.update_attributes(wrapup_time: Time.now)                    
                   (call_attempt.campaign.use_recordings? && call_attempt.campaign.answering_machine_detect) ? call_attempt.play_recorded_message : call_attempt.hangup
                 else
                   call_attempt.connect_to_caller(call_attempt.voter.caller_session)
               end
    render :xml => response
  end
  add_method_tracer :connect, "Custom/#{self.class.name}/connect"

  def disconnect
    call_attempt = CallAttempt.find(params[:id])
    call_attempt.debit
    render :xml => call_attempt.disconnect(params)
  end
  add_method_tracer :disconnect, "Custom/#{self.class.name}/disconnect"

  def hangup
    call_attempt = CallAttempt.find(params[:id])
    call_attempt.end_running_call if call_attempt
    render :nothing => true
  end
  add_method_tracer :hangup, "Custom/#{self.class.name}/hangup"

  def end
    call_attempt = CallAttempt.find(params[:id])
    if [CallAttempt::Status::HANGUP, CallAttempt::Status::VOICEMAIL, CallAttempt::Status::ABANDONED].include? call_attempt.status
      call_attempt.voter.update_attributes(:last_call_attempt_time => Time.now)
      call_attempt.update_attributes(:call_end => Time.now)
    else
      call_attempt.voter.update_attributes(:status => CallAttempt::Status::MAP[params[:CallStatus]], :last_call_attempt_time => Time.now)
      call_attempt.update_attributes(:status => CallAttempt::Status::MAP[params[:CallStatus]])
    end
    call_attempt.debit
  
    response = case params[:CallStatus] #using the 2010 api
                 when "no-answer", "busy", "failed"
                   call_attempt.fail
                 else
                   call_attempt.hangup
               end
    render :xml => response
  end
  add_method_tracer :end, "Custom/#{self.class.name}/end"

  def voter_response
    if params[:voter_id].nil? || params[:id].nil?
      render :nothing => true
    else
      call_attempt = CallAttempt.find(params[:id])      
      voter = !params[:voter_id].blank? ? Voter.find(params[:voter_id])  : call_attempt.voter
      params[:scheduled_date].blank? ? voter.capture(params, call_attempt) : schedule_for_later(call_attempt)
      call_attempt.update_attributes(wrapup_time: Time.now)
      begin
        Moderator.publish_event(call_attempt.campaign, 'voter_response_submitted', {:caller_session_id => params[:caller_session], :campaign_id => call_attempt.campaign.id, :dials_in_progress => call_attempt.campaign.call_attempts.not_wrapped_up.size, :voters_remaining => Voter.remaining_voters_count_for('campaign_id', call_attempt.campaign.id)})
      rescue Exception => e
        Rails.logger.debug("exception in publishing event to monitor.")
      end
      pusher_response_received(call_attempt, params[:stop_calling])
      render :nothing => true
    end
  end
  add_method_tracer :voter_response, "Custom/#{self.class.name}/voter_response"

  private

  def pusher_response_received(call_attempt,stop_calling)
    if call_attempt.campaign.predictive_type == Campaign::Type::PREVIEW || call_attempt.campaign.predictive_type == Campaign::Type::PROGRESSIVE 
      if stop_calling.blank?
        next_voter = call_attempt.campaign.next_voter_in_dial_queue(call_attempt.voter.id)
        call_attempt.caller_session.publish("voter_push", next_voter ? next_voter.info : {})
      else
        call_attempt.caller_session.update_attributes(endtime: Time.now)
      end
      
    else
      call_attempt.caller_session.publish("predictive_successful_voter_response", {})
    end
    call_attempt.voter.update_attribute(:caller_session, nil)
  end

  def schedule_for_later(call_attempt)
    scheduled_date = params[:scheduled_date] + " " + params[:callback_time_hours] +":" + params[:callback_time_minutes]
    call_attempt.schedule_for_later(DateTime.strptime(scheduled_date, "%m/%d/%Y %H:%M").to_time)
  end

end
