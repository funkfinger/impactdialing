require "spec_helper"

describe Client::CallersController do
  let(:user) { Factory(:user) }

  before(:each) do
    login_as user
  end

  def type_name
    'caller'
  end

  it_should_behave_like 'all controllers of deletable entities'
end
