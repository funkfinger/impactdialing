require "spec_helper"

describe CampaignsController do
  let(:account) { Factory(:account) }
  let(:user) { Factory(:user, :account => account) }
  let(:another_users_campaign) { Factory(:campaign, :account => Factory(:account)) }

  before(:each) do
    login_as user
  end

  it "creates a new robo campaign" do
    manual_script = Factory(:script, :account => user.account, :robo => false)
    robo_script = Factory(:script, :account => user.account, :robo => true)
    lambda {
      post :create
    }.should change(user.account.campaigns.active.robo, :size).by(1)
    user.account.campaigns.active.robo.last.script.should == robo_script
    response.should redirect_to campaign_path(user.account.campaigns.last)
  end

  it "lists robo campaigns" do
    robo_campaign = Factory(:campaign, :account => user.account, :robo => true)
    manual_campaign = Factory(:campaign, :account => user.account, :robo => false)
    get :index
    assigns(:campaigns).should == [robo_campaign]
  end

  it "renders a campaign" do
    get :show, :id => Factory(:campaign, :account => user.account, :robo => true).id
    response.code.should == '200'
  end

  it "only provides robo scritps to select for a campaign" do
    robo_script = Factory(:script, :account => user.account, :robo => true)
    manual_script = Factory(:script, :account => user.account, :robo => false)
    get :show, :id => Factory(:campaign, :account => user.account, :robo => true).id
    assigns(:scripts).should == [robo_script]
  end

  describe "update a campaign" do
    let(:campaign) { Factory(:campaign, :account => user.account) }

    it "updates the campaign attributes" do
      post :update, :id => campaign.id, :campaign => {:name => "an impactful campaign"}
      campaign.reload.name.should == "an impactful campaign"
    end

    it "assigns one of the scripts of the current user" do
      script = Factory(:script, :account => user.account)
      post :update, :id => campaign.id, :campaign => {}
      campaign.reload.script.should == script
    end

    it "validates the caller id" do
      phone_number = "1234567890"
      validation_code = "xyzzyspoonshift1"
      caller_id_object = mock
      caller_id_object.should_receive(:validate).and_return(false)
      caller_id_object.should_receive(:validation_code).and_return("xyzzyspoonshift1")
      campaign.stub!(:caller_id_object).and_return(caller_id_object)
      Campaign.should_receive(:find).with(campaign.id).and_return(campaign)
      post :update, :id => campaign.id, :campaign => {:name => "an impactful campaign", :caller_id => phone_number}
      flash[:notice].join.should include validation_code
    end

    it "disables voters list which are not to be called" do
      voter_list1 = Factory(:voter_list, :campaign => campaign, :enabled => true)
      voter_list2 = Factory(:voter_list, :campaign => campaign, :enabled => false)
      post :update, :id => campaign.id, :voter_list_ids => [voter_list2.id]
      voter_list1.reload.should_not be_enabled
      voter_list2.reload.should be_enabled
    end

    it "can update only campaigns owned by the user'" do
      post :update, :id => another_users_campaign.id
      response.status.should == 401
    end
  end

  describe "caller id verification" do
    before :each do
      @campaign = Factory(:campaign, :account => user.account)
      @caller_id_object = mock
      @caller_id_object.stub!(:validate)
      @campaign.stub!(:caller_id_object).and_return(@caller_id_object)
      @campaign.update_attribute(:caller_id, "0123456789")
    end

    it "should render 'not verified' if caller id not verified" do
      @caller_id_object.stub!(:validate)
      Campaign.should_receive(:find).and_return(@campaign)
      @caller_id_object.should_receive(:validate).and_return(false)
      post :verify_callerid, :id => @campaign.id
      response.body.should include "not verified"
    end

    it "should render nothing if caller id is verified" do
      @caller_id_object.stub!(:validate).and_return(true)
      Campaign.should_receive(:find).and_return(@campaign)
      post :verify_callerid, :id => @campaign.id
      response.body.should be_blank
    end

    it "can verify caller id only for campaigns owned by the user'" do
      post :verify_callerid, :id => another_users_campaign.id
      response.status.should == 401
    end
  end

  it "deletes a campaign" do
    campaign = Factory(:campaign, :account => account, :robo => true)
    request.env['HTTP_REFERER'] = 'http://referer' if respond_to?(:request)
    delete :destroy, :id => campaign.id
    campaign.reload.should_not be_active
    response.should redirect_to(:back)
  end

  describe "dial statistics" do
    before :each do
      @campaign = Factory(:campaign, :account => user.account)
    end

    it "renders dial statistics for a campaign" do
      campaign = Factory(:campaign, :account => user.account)
      get :dial_statistics, :id => campaign.id
      assigns(:campaign).should == campaign
      response.code.should == '200'
    end
  end

  def type_name
    'campaign'
  end

  it_should_behave_like 'all controllers of deletable entities'
end
