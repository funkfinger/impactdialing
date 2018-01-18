class Quota < ActiveRecord::Base
  # Help out rails...
  self.table_name = 'quotas'

  belongs_to :account

  validates_presence_of :account

  def plans
    @plans ||= Billing::Plans.new
  end

  ##
  # Return true if +minutes_available+ > 0,
  # false otherwise.
  #
  def minutes_available?
    return minutes_available > 0
  end

  ##
  # Return true if +minutes_pending+ > 0,
  # false otherwise.
  #
  def minutes_pending?
    return minutes_pending > 0
  end

  ##
  # Return the number of minutes available, calculated as
  # +minutes_allowed+ - +minutes_used+ - +minutes_pending+.
  # Return value may be positive, negative or zero. Negative
  # indicates an overage.
  #
  def minutes_available
    minutes_allowed - minutes_used - minutes_pending
  end

  ##
  # Never returns a number < 0 in order to keep calculations
  # simple.
  #
  # *Note:* calculations in +debit+ depend on this never
  # returning a number < 0.
  #
  def _minutes_available
    n = minutes_available
    n = 0 if n < 0
    return n
  end

  ##
  # Return true if the +callers_allowed+ quota has not been reached,
  # false otherwise.
  #
  def caller_seats_available?
    # todo: Verify there are no phantom callers
    # Perform seat check auth/z
    return callers_allowed >= account.caller_seats_taken
  end

  ##
  # Add minutes_to_charge to one or both of +minutes_used+ and +minutes_pending+.
  # A background job (+ToBeNamed+) will run on some schedule to take appropriate
  # action for accounts w/ some positive number in +minutes_pending+.
  #
  def debit(minutes_to_charge)
    used    = minutes_to_charge
    pending = 0
    if minutes_to_charge > _minutes_available
      used    = _minutes_available
      pending = minutes_to_charge - (minutes_allowed - minutes_used)
    end
    used    += minutes_used
    pending += minutes_pending

    return update_attributes({
      minutes_used: used,
      minutes_pending: pending
    })
  end

  def zero_minutes_and_callers
    self.callers_allowed = 0
    zero_minutes
  end

  def zero_minutes
    self.minutes_allowed = 0
    zero_usage_minutes
  end

  def zero_usage_minutes
    self.minutes_used    = 0
    self.minutes_pending = 0
  end

  def toggle_calling!
    self.disable_calling = !disable_calling?
    save!
  end

  def toggle_access!
    self.disable_access = !disable_access?
    save!
  end

  ##
  #
  #
  def change_plans_or_callers(plan, provider_object, opts={})
    quantity    = provider_object.quantity
    old_plan_id = opts[:old_plan_id]

    if quantity == callers_allowed && old_plan_id == plan.id
      return # noop: nothing changed
    end

    if plans.is_upgrade?(old_plan_id, plan.id)
      upgrade_plans(plan, provider_object, opts)
    elsif old_plan_id != plan.id
      downgrade_plans(plan, provider_object, opts)
    end
    if quantity != callers_allowed
      change_callers(plan, provider_object, opts)
    end
  end

  def upgrade_plans(plan, provider_object, opts)
    old_plan_id          = opts[:old_plan_id]
    prorate              = opts[:prorate]
    quantity             = provider_object.quantity
    self.minutes_allowed = if prorate
                              prorated_minutes(plan, provider_object, opts, quantity)
                            else
                              quantity * plan.minutes_per_quantity
                            end
    self.callers_allowed = quantity
    self.minutes_used    = 0
  end

  def downgrade_plans(plan, provider_object, opts)
    quantity             = provider_object.quantity
    old_plan_id          = opts[:old_plan_id]
    self.callers_allowed = quantity

    if old_plan_id == 'per_minute'
      self.minutes_allowed += (quantity * plan.minutes_per_quantity)
    end
  end

  ##
  # When adding callers, update +minutes_allowed+ to prorated
  # number of minutes. The number of prorated minutes to add
  # is calculated as:
  #
  #     callers_to_add * minutes_per_caller * (days_left_in_billing_cycle/days_total_in_billing_cycle)
  #
  # When removing callers the +minutes_allowed+ does not change
  # because we don't prorate. +minutes_allowed+, +minutes_used+ and +minutes_pending+
  # will be updated when the corresponding `invoice.payment_succeeded`
  # event is received from Stripe at the end of the subscription's current billing cycle.
  #
  # When adding or removing callers, update +callers_allowed+ to the Int returned
  # from `provider_object.quantity`.
  #
  def change_callers(plan, provider_object, opts={})
    quantity       = provider_object.quantity
    callers_to_add = quantity - self.callers_allowed
    minutes_to_add = 0

    if callers_to_add > 0
      minutes_to_add = prorated_minutes(plan, provider_object, opts, callers_to_add)
    end
    # Negative callers_to_add does not change minutes_allowed
    # because we don't prorate removal of callers.
    self.callers_allowed = quantity
    self.minutes_allowed += minutes_to_add
  end

  def prorated_minutes(plan, provider_object, opts, quantity=nil)
    quantity         ||= provider_object.quantity
    now              = Time.now
    cycle_start      = provider_object.current_period_start
    cycle_end        = provider_object.current_period_end
    cycle_days_left  = (cycle_end.to_i - now.to_i).to_f
    cycle_days_total = (cycle_end.to_i - cycle_start.to_i).to_f
    left_total_ratio = ((cycle_days_left / cycle_days_total) * 100).to_i / 100.0
    (quantity * plan.minutes_per_quantity * left_total_ratio).to_i
  end

  ##
  # Returns true when adding minutes to an existing per minute plan.
  # Returns false when downgrading to a recurring plan.
  #
  def overwrite_minutes?(old_plan_id, new_plan)
    new_plan.per_minute?
  end

  def add_minutes(plan, old_plan_id, amount, contract=nil)
    price_per_quantity   = contract.try(:price_per_quantity) ||
                           plan.price_per_quantity
    price                = (price_per_quantity * 100) # convert dollars to cents
    minutes_purchased    = (amount / price).to_i

    self.callers_allowed = 0
    if minutes_available? && plan.id == old_plan_id
      self.minutes_allowed = minutes_available + minutes_purchased
      self.minutes_pending = 0
      self.minutes_used = 0
    else
      self.minutes_allowed = minutes_purchased

      if minutes_pending > minutes_purchased
        self.minutes_used     = minutes_purchased
        self.minutes_pending -= minutes_purchased
      else
        self.minutes_used    = minutes_pending
        self.minutes_pending = 0
      end
    end
  end

  ##
  # Perform any updates to quotas as needed when a plan changes.
  # Used for both recurring and per minute plans. Applicable during
  # upgrades/downgrades, when callers are added/removed to recurring plans
  # and when minutes are added to per minute plans.
  #
  def plan_changed!(new_plan_id, provider_object=nil, opts={})
    plan        = plans.find(new_plan_id)
    old_plan_id = opts[:old_plan_id]

    if plan.presence.recurring?
      change_plans_or_callers(plan, provider_object, opts)
      # minutes_pending is primarily for tracking overage on pay as you go plans.
      # For now, let's just reset it and log.
      Rails.logger.info("Account[#{account.id}] Plan[#{new_plan_id}] MinutesPending[#{self.minutes_pending}] MinutesUsed[#{self.minutes_used}] MinutesAllowed[#{self.minutes_allowed}] Resetting Quota#minutes_pending due to change in plans or callers.")
      self.minutes_pending = 0
    else
      # not going to support customer self-service changes from recurring to per minute as of Mar 18 2014
      # if plans.is_upgrade?(old_plan_id, new_plan_id)
      #   zero_minutes_and_callers
      # end
      if plan.per_minute?
        amount = provider_object.amount # in cents
        add_minutes(plan, old_plan_id, amount, opts[:contract])
      end
    end

    save!
  end

  def plan_cancelled!
    zero_minutes_and_callers
    save!
  end

  ##
  # Reset quota allowances.
  # Applicable to recurring plans only (see +Billing::Plans::RECURRING_PLANS+).
  #
  def renewed(plan)
    zero_usage_minutes
    self.minutes_allowed = callers_allowed * plan.minutes_per_quantity
  end
end

# ## Schema Information
#
# Table name: `quotas`
#
# ### Columns
#
# Name                   | Type               | Attributes
# ---------------------- | ------------------ | ---------------------------
# **`id`**               | `integer`          | `not null, primary key`
# **`account_id`**       | `integer`          | `not null`
# **`minutes_used`**     | `integer`          | `default(0), not null`
# **`minutes_pending`**  | `integer`          | `default(0), not null`
# **`minutes_allowed`**  | `integer`          | `default(0), not null`
# **`callers_allowed`**  | `integer`          | `default(0), not null`
# **`disable_calling`**  | `boolean`          | `default(FALSE), not null`
# **`created_at`**       | `datetime`         |
# **`updated_at`**       | `datetime`         |
# **`disable_access`**   | `boolean`          | `default(FALSE)`
#
# ### Indexes
#
# * `index_quotas_on_account_id`:
#     * **`account_id`**
#
