class MonitorsController < ClientController
  skip_before_filter :check_login, :only => [:start,:stop,:switch_mode, :deactivate_session]
  layout 'client'
  
  def index
    @campaigns = account.campaigns.with_running_caller_sessions
    @all_campaigns = account.campaigns
    twilio_capability = Twilio::Util::Capability.new(TWILIO_ACCOUNT, TWILIO_AUTH)
    twilio_capability.allow_client_outgoing(MONITOR_TWILIO_APP_SID)
    @token = twilio_capability.generate
  end

  def start
    caller_session = CallerSession.find(params[:session_id])
    if caller_session.voter_in_progress && (caller_session.voter_in_progress.call_attempts.last.status == "Call in progress")
      status_msg = "Status: Monitoring in "+ params[:type] + " mode on "+ caller_session.caller.email + "."
    else
      status_msg = "Status: Caller is not connected to a lead."
    end
    Pusher[params[:monitor_session]].trigger('set_status',{:status_msg => status_msg})
    mute_type = params[:type]=="breakin" ? false : true
    render xml:  caller_session.join_conference(mute_type, params[:CallSid], params[:monitor_session])
  end

  def switch_mode
    type = params[:type]
    caller_session = CallerSession.find(params[:session_id])
    Moderator.update_caller_session(caller_session.id, params[:monitor_session]) if caller_session.moderator.nil?
    caller_session.moderator.switch_monitor_mode(caller_session, type)
    if caller_session.voter_in_progress && (caller_session.voter_in_progress.call_attempts.last.status == "Call in progress")
      render text: "Status: Monitoring in "+ type + " mode on "+ caller_session.caller.email + "."
    else
      render text: "Status: Caller is not connected to a lead."
    end 
  end

  def stop
    caller_session = CallerSession.find(params[:session_id])
    caller_session.moderator.stop_monitoring(caller_session)
    render text: "Switching to different caller"
  end
  
  def deactivate_session
    moderator = Moderator.find_by_session(params[:monitor_session])
    moderator.update_attributes(:active => false)
    # caller_session = CallerSession.find(params[:session_id])
    # caller_session.moderator.stop_monitoring(session)
    render nothing: true
  end
  
  
  def monitor_session
    @moderator = Moderator.create!(:session => generate_session_key, :account => @user.account, :active => true)
    render json: @moderator.session.to_json
  end
  
  def toggle_call_recording
    account.toggle_call_recording!
    flash_message(:notice, "Call recording turned #{account.record_calls? ? "on" : "off"}.")
    redirect_to monitors_path
  end

end
