class CallerGroup < ActiveRecord::Base
  validates :name, presence: true
  validates :campaign_id, presence: true
  has_many :callers
  belongs_to :campaign
  belongs_to :account

  after_save :reassign_callers

  def reassign_in_background
    # callbacks must be triggered
    self.callers.each{|record| record.update_attributes({campaign_id: campaign_id})}
  end

  private

  def reassign_callers
    Resque.enqueue(CallerGroupJob, self.id) if campaign_id_changed?
  end
end

# ## Schema Information
#
# Table name: `caller_groups`
#
# ### Columns
#
# Name               | Type               | Attributes
# ------------------ | ------------------ | ---------------------------
# **`id`**           | `integer`          | `not null, primary key`
# **`name`**         | `string(255)`      | `not null`
# **`campaign_id`**  | `integer`          | `not null`
# **`created_at`**   | `datetime`         |
# **`updated_at`**   | `datetime`         |
# **`account_id`**   | `integer`          | `not null`
#
