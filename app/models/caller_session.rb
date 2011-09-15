class CallerSession < ActiveRecord::Base
  belongs_to :caller, :class_name => "Caller", :foreign_key => "caller_id"
  belongs_to :campaign
  named_scope :on_call, :conditions => {:on_call => true}
  named_scope :between, lambda{|from_date, to_date| { :conditions => { :created_at => from_date..to_date } }}
  unloadable

  def minutes_used
    return 0 if self.tDuration.blank?
    self.tDuration/60.ceil
  end

   def end_call(account=TWILIO_ACCOUNT,auth=TWILIO_AUTH,appurl=APP_URL)
      t = TwilioLib.new(account,auth)
      a=t.call("POST", "Calls/#{self.sid}", {'CurrentUrl'=>"#{appurl}/callin/callerEndCall?session=#{self.id}"})
      if a.index("RestException")
        self.on_call=false
        self.save
      end
  end

end
