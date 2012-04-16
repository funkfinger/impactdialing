require 'new_relic/agent/method_tracer'
class CallerController < ApplicationController
  include NewRelic::Agent::MethodTracer
  layout "caller"
  before_filter :check_login, :except=>[:login, :feedback, :assign_campaign, :end_session, :pause, :start_calling, :gather_response, :choose_voter, :phones_only_progressive, :phones_only, :choose_instructions_option, :new_campaign_response_panel, :check_reassign, :call_voter]
  before_filter :redirect_to_ssl
  
  def index
    redirect_to callers_campaign_path(@caller.campaign)
  end

  def check_login
    if session[:caller].blank?
      redirect_to caller_login_path
      return
    end
    begin
      @caller = Caller.find(session[:caller])
    rescue
      logout
    end
  end

  def logout
    session[:caller]=nil
    redirect_to caller_login_path
  end

  def login
    @breadcrumb="Login"
    @title="Login to Impact Dialing"

    if !params[:email].blank?
      @caller = Caller.find_by_email_and_password(params[:email], params[:password])
      if @caller.blank?
        flash_now(:error, "Wrong email or password.")
      else
        session[:caller]= @caller.id
        redirect_to callers_campaign_path(@caller.campaign)
      end
    end
  end
  
  def kick_caller_off_conference
    caller = Caller.find(params[:id])
    caller_session = caller.caller_sessions.find(params[:caller_session])    
    conference_sid = caller_session.get_conference_id
    Twilio.connect(TWILIO_ACCOUNT, TWILIO_AUTH)
    Twilio::Conference.kick_participant(conference_sid, caller_session.sid)
    Twilio::Call.redirect(caller_session.sid, pause_caller_url(caller, :host => Settings.host, :port => Settings.port, :session_id => caller_session.id))            
    caller_session.publish('caller_kicked_off', {}) 
    render nothing: true
  end

  def stop_calling
    caller = Caller.find(params[:id])
    voters = Voter.find_all_by_caller_id_and_status(caller.id, CallAttempt::Status::READY)
    voters.each {|voter| voter.update_attributes(status: 'not called')}
    @session = caller.caller_sessions.find(params[:session_id])
    @session.end_running_call
    @session.debit
    CallAttempt.wrapup_calls(params[:id]) unless params[:id].empty?
    render :nothing => true
  end

  def pause
    caller = Caller.find(params[:id])
    caller_session = caller.caller_sessions.find(params[:session_id])
    if caller_session.disconnected?
      render :xml => Twilio::Verb.hangup
    else
      render :xml => caller_session.voter_in_progress ? caller_session.pause_for_results(params[:attempt]) : caller_session.start
    end
  end
  add_method_tracer :pause, "Custom/#{self.class.name}/pause"

  def gather_response
    caller = Caller.find(params[:id])
    caller_session = caller.caller_sessions.find(params[:session_id])
    question = Question.find_by_id(params[:question_id])
    voter = caller_session.voter_in_progress
    voter.answer(question, params[:Digits], caller_session) if voter && question

    xml = Twilio::Verb.hangup if caller_session.disconnected?
    xml ||= (voter.question_not_answered.try(:read, caller_session) if voter)
    xml ||= caller_session.ask_caller_to_choose_voter if (caller.is_phones_only? && caller.campaign.is_preview_or_progressive)
    xml ||= caller_session.start
    render :xml => xml
  end


  def end_session
    caller_session = CallerSession.find_by_sid(params[:CallSid])
    caller_session.debit if caller_session!=nil
    begin
      render :xml => caller_session.try(:end) || Twilio::Verb.hangup
    rescue ActiveRecord::StaleObjectError
      caller_session.reload
      render :xml =>  caller_session.end      
    end
  end

  def skip_voter
    caller_session = @caller.caller_sessions.find(params[:session_id])
    voter = Voter.find(params[:voter_id])
    voter.skip
    next_voter = caller_session.campaign.next_voter_in_dial_queue(params[:voter_id])
    caller_session.publish('caller_connected', next_voter ? next_voter.info : {}) 
    render :nothing => true
  end
  
  def check_reassign
    caller = Caller.find(params[:id])
    if caller.campaign.id == params[:campaign_id].to_i
      render :json => {:reassign => "false"}
    else
      render :json => {:reassign => "true", :campaign_id => caller.campaign.id, :script => caller.campaign.script.try(:script)}
    end
  end

  def start_calling
    if params[:caller_id].blank? || params[:campaign_id].blank?
      render :nothing => true
    else
      @caller = Caller.find(params[:caller_id])
      if !@caller.account.subscription_allows_caller?
        render :xml => @caller.max_callers_reached
      else      
        @identity = CallerIdentity.find_by_session_key(params[:session_key])
        @session = @caller.create_caller_session(@identity.session_key, params[:CallSid])
        Moderator.caller_connected_to_campaign(@caller, @caller.campaign, @session)
        @session.publish('start_calling', {caller_session_id: @session.id}) 
        unless @caller.is_on_call?
          @session.preview_voter
        end
        render xml:  @caller.is_on_call? ? @caller.already_on_call : @session.start
      end
    end
  end


  def call_voter
    caller = Caller.find(params[:id])
    caller_session = caller.caller_sessions.find(params[:session_id])
    if params[:voter_id]
      voter = Voter.find(params[:voter_id])
      caller_session.preview_dial(voter)
    end
    render :nothing => true
  end
  add_method_tracer :call_voter, "Custom/#{self.class.name}/call_voter"
  
  def choose_voter
    caller_session = CallerSession.find(params[:session])
    voter = Voter.find(params[:voter])
    caller = Caller.find(params[:id])
    caller_choice = params[:Digits]
    render :xml => caller.choice_result(caller_choice, voter, caller_session)
  end
  
  def phones_only_progressive
    caller_session = CallerSession.find(params[:session_id])
    voter = Voter.find(params[:voter_id])
    render :xml => caller_session.phones_only_start
    caller_session.preview_dial(voter)
  end
  
  def phones_only
    caller_session = CallerSession.find(params[:session_id])
    xml = (params[:campaign_reassigned] == "true") ?  caller_session.read_campaign_reassign_msg : caller_session.caller.instruction_choice_result("*", caller_session)
    render :xml => xml
  end
  
  def choose_instructions_option
    caller_session = CallerSession.find(params[:session])
    caller = Caller.find(params[:id])
    render :xml => caller.instruction_choice_result(params[:Digits], caller_session)
  end
  
  def new_campaign_response_panel
    caller = Caller.find(params[:id])
    @campaign = caller.campaign
    render :layout => false
  end
  
  def transfer_panel
    caller = Caller.find(params[:id])
    @campaign = caller.campaign
    render :layout => false    
  end
  
  
  def feedback
    Postoffice.feedback(params[:issue]).deliver
    render :text=> "var x='ok';"
  end

end
