
# Using Vagrant to get this project up and running...

## Install [Vagrant](https://www.vagrantup.com)

Follow the instructions to get [Vagrant](https://www.vagrantup.com) running on your OS. Using [VirtualBox](https://www.virtualbox.org) with Vagrant is probably your easiest path to success. **NOTE:** for OS X command line install, try [these instructions](http://sourabhbajaj.com/mac-setup/Vagrant/README.html). I did.

Once you have Vagrant installed, `cd` to the root of this project directory and run:

    vagrant up

This will take a while, and will require a good amount of downloading. Be patient. If all works, you should have a rails server running on (http://localhost:3001). If not, something went wrong.





____

#OLDER STUFF BELOW...

Below is a 'scratch pad' of all the things I went through to try and get this running on my OS X High Sierra machine.

____

# What I'm Doing Now...

## Vagrant Setup

Using `vagrant` - we need that installed on the host OS - for OS X I mostly followed [these instructions](http://sourabhbajaj.com/mac-setup/Vagrant/README.html) - at least to get `vagrant` installed...

Then...

    vagrant box update
    vagrant up
    vagrant ssh
    cd /vagrant
    bundle exec rake spec RAILS_ENV=test


## Create a Vagrant provision script - using shell method...

updated `Vagrantfile` - see project file.

now trying to provision...

   vagrant up
   vagrant provision

___

## notes -

after `bundle install`, these messages came up - probably need to do something about it...

    Post-install message from pagerduty:
    If upgrading to pagerduty 2.0.0 please note the API changes:
    https://github.com/envato/pagerduty#upgrading-to-version-200
    Post-install message from sauce-connect:
      To use the Sauce Connect gem, you'll need to download the appropriate
      Sauce Connect binary from https://docs.saucelabs.com/reference/sauce-connect

      Then, set the 'sauce_connect_4_executable' key in your Sauce.config block, to
      the path of the unzipped file's /bin/sc.





___

BELOW IS OLD - now working on provisioning the Vagrant image without the below nonsense...

## Vagrant Setup

Using `vagrant` - we need that installed on the host OS - for OS X I mostly followed [these instructions](http://sourabhbajaj.com/mac-setup/Vagrant/README.html) - at least to get `vagrant` installed...

    vagrant init

This creates a `Vagrantfile` and I edit that to be:

    VAGRANTFILE_API_VERSION = "2"
    Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
      config.vm.box = "ubuntu/trusty64"
      config.vm.network "private_network", type: "dhcp"
    end

then start and log into the VM:

    vagrant up
    vagrant ssh

## VM Setup

after the `vagrant ssh` command, I'm in the VM. Now I can start setting up the environment. This should happen in the provisioning phase of the `vagrant up` command, but I want to see if I can get it working this way.

### install RVM

Followed [these instructions](https://rvm.io)

    gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
    \curl -sSL https://get.rvm.io | bash -s stable
    source /home/vagrant/.rvm/scripts/rvm

### install ruby with rvm

    rvm install "ruby-2.2.4"

### install bundler

    gem install bundler

### install gems

    bundle install

**FAIL:** `nogogiri` failed to install - the output mentioned `If you are using Bundler, tell it to use the option:` might work... trying that

    bundle config build.nokogiri --use-system-libraries
    bundle install

**FAIL:** now nogogiri says `libxml2 version 2.6.21 or later is required!` - let's see if a simple system update will work...

    sudo apt update
    sudo apt upgrade -s
    bundle install

**FAIL:** nope, now what... let's install the dev package...

    sudo apt install libxml2-dev
    bundle install

**FAIL:** got a little further, needs more packages- `package configuration for libxslt is not found
package configuration for libexslt is not found`
....

    sudo apt install libxslt1.1
    sudo apt install libxslt1-dev
    bundle install

**FAIL:** got `nokogiri` installed, now blocking on `capybara`: `Command 'qmake ' not available`

    sudo apt install qt5-default
    bundle install

**FAIL:** according to [this](https://github.com/thoughtbot/capybara-webkit/wiki/Installing-Qt-and-compiling-capybara-webkit#debian--ubuntu) it looks like even more are necessary...

    sudo apt install qt5-default libqt5webkit5-dev gstreamer1.0-plugins-base gstreamer1.0-tools gstreamer1.0-x
    bundle install

**FAIL:** ran out of virtual memmory on the VM :frowning:

exit `vagrant ssh`

    exit

now stop `vagrant`

    vagrant halt

now I went into VirtualBox application and upped the amount of memory to 2mb.

then start `vagrant` and start `vagrant ssh` again, got to the right folder and try again...

    vagrant
    vagrant ssh
    cd /vagrant
    bundle install

**FAIL:** this solved the `capybara` issues, now a `mysql` error:

    sudo apt install mysql-server

this asked me to set a password (which isn't ideal if we are going to automatically provision this, but I will for now - set it to the one I know well BTW)

    bundle install

**FAIL:** more is required:

    sudo apt install libmysqlclient-dev
    bundle install

**SUCCESS!** gems are now installed. Now let's see if I can `rake`...

## setup the rails environment

Let's see what rake tasks are available...

    rake -T

I need to setup the database...

    rake db:create

**FAIL:** Since I setup a password in `mysql` the
.env file needs to be updated with the password on the mysql connection string**s**. The password follows the username `root` with a colon - as in `mysql2://username:password@...`

Once this was updated, tried again...

    rake db:create
    rake db:migrate

**FAIL:** migration `20100827134800_voter_add_result.rb` has an `uninitialized constant VoterAddResult::VoterResult` error on line 7. Hmmm.... maybe because there are no records? Wraped the update in an `if count > 0` and tried again...

    rake db:drop
    rake db:create
    rake db:migrate

**FAIL:** That didn't work, trying information from [this page](http://guides.rubyonrails.org/v3.2.8/migrations.html#using-models-in-your-migrations) - updated migration by adding "local model"

    rake db:drop
    rake db:create
    rake db:migrate

**SUCCESS:** the migrations seemed to run but got an error?:

    Unable to annotate report_web_ui_strategy.rb: cannot load a model from report_web_ui_strategy.rb
    Annotated (18): Power, CallAttempt, Script, Call, CallerGroup, Campaign, SimulatedValues, Moderator, NoteResponse, Voter, VoterList, Quota, Answer, Preview, Predictive, Billing::StripeEvent, Billing::CreditCard, Billing::Subscription

Realized that git wasn't installed, installing...

    sudo apt install git

added `.env.test` to `.gitignore` file. Then updated to include the MySQL password I created. Now let's see if we can create the database...

    bundle exec rake db:create RAILS_ENV=test
    bundle exec rake db:migrate RAILS_ENV=test

**SUCCESS!** now I have a test database, let's see if the tests can run...

    bundle exec rake spec

**FAIL:** issues with running the tests in `db:test:prepare` - let's try that on it's own...

    bundle exec rake db:test:prepare --trace

**FAIL:** following error... `ActiveRecord::StatementInvalid: Mysql2::Error: Cannot delete or update a parent row: a foreign key constraint fails: DROP TABLE 'accounts'` hmm, now what... maybe let's try again with test env... also, noticed that the schema file says **not to use migrations** to start up the db, but to use the schema load rake task:

    bundle exec rake db:drop RAILS_ENV=test
    bundle exec rake db:create RAILS_ENV=test
    bundle exec rake db:schema:load RAILS_ENV=test
    bundle exec rake db:test:prepare RAILS_ENV=test
    bundle exec rake spec RAILS_ENV=test

**SUCCESS!** IT'S RUNNING TESTS!!! :smile: :smile: :smile: :smile: :smile: :smile:




___
# What I Was Doing (which didn't work)...

try to install gems...

    bundle install

**failed**: looks like building the native extensions for `capybara-webkit 1.7.1` uses `webkit` which needs `qmake` (part of `qt`?)...

    brew install qt

try again...

    bundle install

**failed again**: `qmake` was installed with the homebrew keg, but not linked... so...

    echo 'export PATH="/usr/local/opt/qt/bin:$PATH"' >> ~/.bash_profile
    source ~/.bash_profile
    bundle install

**GRRR**: newer versions of `qt` do not work with `webkit`... trying agin...

    brew remove qt
    brew install qt@5.5
    echo 'export PATH="/usr/local/opt/qt@5.5/bin:$PATH"' >> ~/.bash_profile
    source ~/.bash_profile
    bundle install

**another fail**: `mysql2` has an error.

    brew install mysql
    bundle install
    rake

**fail**: `Sorry, you can't use byebug without Readline. To solve this, you need to rebuild Ruby with Readline support...` found [this page](https://github.com/deivid-rodriguez/byebug/issues/289) which suggested this solution:

    ln -s /usr/local/opt/readline/lib/libreadline.dylib /usr/local/opt/readline/lib/libreadline.6.dylib

**fail**: no, that didn't work... trying [this solution](https://gist.github.com/soultech67/33ba09706e091c06ce66684cd28015ac)

    brew --prefix readline
    rvm reinstall 2.2.4
    gem install bundler
    bundle install
    rake

**fail** same byebug issue... :anguished:

going to move on from `byebug` for a moment and install `redis`...

    sudo apt install redis-server
    sudo service redis-server start




___
