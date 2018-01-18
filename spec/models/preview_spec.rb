require 'rails_helper'


describe Preview, :type => :model do
  # todo...
end

# ## Schema Information
#
# Table name: `campaigns`
#
# ### Columns
#
# Name                            | Type               | Attributes
# ------------------------------- | ------------------ | ---------------------------
# **`id`**                        | `integer`          | `not null, primary key`
# **`campaign_id`**               | `string(255)`      |
# **`name`**                      | `string(255)`      |
# **`account_id`**                | `integer`          |
# **`script_id`**                 | `integer`          |
# **`active`**                    | `boolean`          | `default(TRUE)`
# **`created_at`**                | `datetime`         |
# **`updated_at`**                | `datetime`         |
# **`caller_id`**                 | `string(255)`      |
# **`type`**                      | `string(255)`      |
# **`recording_id`**              | `integer`          |
# **`use_recordings`**            | `boolean`          | `default(FALSE)`
# **`calls_in_progress`**         | `boolean`          | `default(FALSE)`
# **`robo`**                      | `boolean`          | `default(FALSE)`
# **`recycle_rate`**              | `integer`          | `default(1)`
# **`answering_machine_detect`**  | `boolean`          |
# **`start_time`**                | `time`             |
# **`end_time`**                  | `time`             |
# **`time_zone`**                 | `string(255)`      |
# **`acceptable_abandon_rate`**   | `float`            |
# **`voicemail_script_id`**       | `integer`          |
#
