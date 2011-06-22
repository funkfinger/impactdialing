require "spec_helper"

describe CampaignsController do
  let(:user) { Factory(:user) }

  before(:each) do
    login_as user
  end

  it "renders a campaign" do
    get :show, :id => Factory(:campaign, :user => user).id
    response.code.should == '200'
  end

  def type_name
    'campaign'
  end

  it_should_behave_like 'all controllers of deletable entities'
end
