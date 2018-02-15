
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

added this to top of `Vagrantfile`:

    $script = <<SCRIPT
    echo provisioning...
    sudo apt update
    sudo apt upgrade -s
    sudo apt install libxml2-dev libxslt1.1 libxslt1-dev qt5-default qt5-default libqt5webkit5-dev gstreamer1.0-plugins-base gstreamer1.0-tools gstreamer1.0-x mysql-server libmysqlclient-dev
    gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
    \curl -sSL https://get.rvm.io | bash -s stable
    source /home/vagrant/.rvm/scripts/rvm
    rvm install "ruby-2.2.4"
    gem install bundler
    SCRIPT

now trying to provision...

   vagrant up
   vagrant provision




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

# Dependencies

All can be installed through Homebrew.

* Ruby (see `Gemfile` or `.ruby-version` for version)
* Node 0.10.x (for the Angular app in `callveyor`)
* Redis 2.8
* MySQL 5.5.40
* Heroku toolbelt
* Ngrok

# Configuring Twilio

Create a separate Twilio account for dev/staging and production - it will be
much easier to track down errors in development. Use the ngrok.io subdomain as the
host for development, and the herokuapp.com host for production.

Create [TwiML apps](https://www.twilio.com/console/voice/dev-tools/twiml-apps):

* Browser phone: request and fallback to `/twiml/caller_sessions`, status callback to `/caller/end_session`
* Dial in: request and fallback to `/callin/create`, status callback to `/caller/end_session`
* Dashboard: request and fallback to `/client/monitors/callers/start`

Set TWILIO_APP_SID to the browser phone app's SID.

Set TWILIO_MONITOR_APP_SID to the dashboard app's SID.

For each call-in number, configure the number to use the dial in app.

# Running in development

Make sure to copy `.env.example` to `.env` and update credentials if needed.

Install gems with `bundle` from the app root. Set up the database with `rake db:create && db:schema:load`. Install caller interface deps with `npm install && bower install` from `callveyor`.

Start MySQL server and Redis server.

Launch the web app with `rails s` (for simple testing only). Launch the web app and background processes with `heroku local -f Procfile.dev` (customize `Procfile.dev` to choose which processes to launch) and visit `localhost:5000` for the admin interface, and `localhost:5000/app` for the caller interface.

Launch the caller interface from `callveyor` with `grunt serve` and visit `localhost:9000/app/login`. (Don't worry about assets not loading.) After logging in, you'll get the error `Cannot GET /app`. Remove `app` from the URL to visit `localhost:9000/` to reach the logged-in caller interface.

Receive Twilio callbacks through Ngrok by running `ngrok http -subdomain=impactdialing 5000`.

After making changes to Callveyor, build the Angular app into the Rails app with `rake callveyor:build`.

# Testing

Run `rspec spec` for Ruby tests.

Run `foreman run rspec features` for acceptance tests.

Run `grunt test` from `callveyor` to continuously run Callveyor tests in Firefox, Safari and Chrome.

# Deploying to production

We run Impact Dialing on Heroku. We deploy to two apps.
The main one ("impactdialing") serves admin.impactdialing.com and caller.impactdialing.
The other one ("impactdialing-twiml") is solely responsible for handling Twilio webhooks,
and runs a single Perforance dyno.

Performance dynos run on a dedicated VM and don't suffer from performance
leakage from neighboring dynos, and so have a consistently fast response time
that we couldn't achieve on standard dynos.
By isolating the two apps, we can be sure that slow requests on the main app don't disrupt call flow,
which is very latency-sensitive.

The main impactdialing app should be configured to have the Cloudflare proxy
enabled, to protect from attacks.
impactdialing-twiml should not have the Cloudflare proxy enabled, as it only
services requests from Twilio, and we want those requests to stay within the AWS
datacenter and not take a roundtrip through Cloudflare first.
Make sure to keep this URL a secret, since it does not have Cloudflare protection.

# Services

## Running the damn thing

* Heroku - hosting/platform
* HireFire - autoscaling Heroku
* Cloudflare - DNS, etc
* RDS - MySQL hosting
* S3 - list and audio storage, daily Redis backups, log backups
* RedisLabs - Redis hosting
* Pusher - realtime
* Twilio - calls
* Mandrill - emails

## Troubleshooting

* Bugsnag - exceptions
* Papertrail - logs
* Librato - dashboards
* PagerDuty - alerts

## Testing

* Blazemeter - load testing
* Sauce - browser testing
* CircleCI - continuous integration
* Ngrok - tunnel from a public domain to localhost

## Support

* Freshdesk - email support
* Olark - chat support
* Usersnap - screenshots/JS dump support

# Configuration

- `CALLIN_PHONE`: The Twilio phone number associated with the "Production call-in" TwiML app
- `CAMPAIGN_EXPIRY`: A number of days; campaigns that have not made any dials in this number of days will be auto-archived
- `DATABASE_READ_SLAVE1_URL`: URL to a MySQL read slave
- `DATABASE_READ_SLAVE2_URL`: URL to a second MySQL read slave
- `DATABASE_SIMULATOR_SLAVE_URL`: URL to a third MySQL read slave, intended for use by predictive simulator workers
- `DATABASE_URL`: URL to MySQL master
- `DO_NOT_CALL_PORTED_LISTS_PROVIDER_URL`: HTTP AUTH URL to tcpacompliance ported lists
- `DO_NOT_CALL_REDIS_URL`: URL to redis instance where block and ported cell lists are cached
- `DO_NOT_CALL_WIRELESS_BLOCK_LIST_PROVIDER_URL`: HTTP AUTH URL to qscdl block lists
- `HIREFIRE_TOKEN`: Auth token provided by HireFire for auto-scaling
- `INCOMING_CALLBACK_HOST`: HOST of end-points to process TwiML
- `INSTRUMENT_ACTIONS`: Toggle librato-rails experimental `instrument_action` usage; 0 = do not instrument controller actions; 1 = instrument controller actions
- `LIBRATO_SOURCE`: Names the source of the Librato metrics being collected
- `LIBRATO_TOKEN`: Auth token provided by Librato
- `LIBRATO_USER`: Username for Librato account (invoices@impactdialing.com)
- `MANDRILL_API_KEY`: ...
- `MAX_THREADS`: How many threads should puma start (1 - app not proven thread-safe yet)
- `PUSHER_APP_ID`: ...
- `PUSHER_KEY`: ...
- `PUSHER_SECRET`: ...
- `RACK_ENV`: ...
- `RACK_TIMEOUT`: Number of seconds before rack considers request timed out (max 30 for heroku)
- `RAILS_ENV`: ...
- `RECORDING_ENV`: Root-level folder to store recordings in on s3
- `REDIS_PHONE_KEY_INDEX_STOP`: CAUTION! Changing this requires migrating household data in redis, should be negative four (-4); this determines the position phone numbers are partitioned when creating redis keys and redis hash keys.
- `REDIS_URL`: URL of primary (default) redis instance to connect
- `S3_ACCESS_KEY`: ...
- `S3_BUCKET`: ...
- `S3_SECRET_ACCESS_KEY`: ...
- `STRIPE_PUBLISHABLE_KEY`: ...
- `STRIPE_SECRET_KEY`: ...
- `TWILIO_ACCOUNT`: ...
- `TWILIO_APP_SID`:  SID of the Browser Phone TwiML app
- `TWILIO_AUTH`: ...
- `TWILIO_CALLBACK_HOST`: the hostname of the impactdialing-twiml Heroku app
- `TWILIO_CALLBACK_PORT`: the port of the impactdialing-twiml Heroku app
- `TWILIO_CAPABILITY_TOKEN_TTL`: TTL of Twilio Client capability tokens (caller app & admin dashboard)
- `TWILIO_FAILOVER_HOST`: the same as the hostname of the impactdialing-twiml Heroku app
- `TWILIO_MONITOR_APP_SID`: SID of the Dashboard TwiML app
- `TWILIO_RETRIES`: Number of retries Twilio ruby client should perform before considering API request as failed
- `UPSERT_GEM_ON`: Upsert is a SLOWER & MORE ERROR-PRONE alternative to activerecord-import; 0 = use activerecord-import; 1 = use upsert
- `VOIP_API_URL`: Twilio's API host (api.twilio.com)
- `VOTER_BATCH_SIZE`: Number of rows of CSV data to process before committing to redis during uploads. Keep at a max of 100 down to a min of 20 or 30. Lower value will increase overall upload time but decrease commit time thereby improving redis throughput.
- `WEB_CONCURRENCY`: Number of puma workers to start.

# Queue names and their job classes

* billing -> Billing::Jobs::AutoRecharge, Billing::Jobs::StripeEvent, DebitJob
* call_flow -> CallerPusherJob, CampaignOutOfNumbersJob, Providers::Phones::Jobs::DropMessage, EndRunningCallJob, RedirectCallerJob, VoterConnectedPusherJob
* dial_queue -> CallFlow::DialQueue::Jobs::Recycle, CallFlow::Web::Jobs::CacheContactFields, DoNotCall::Jobs::BlockedNumberCreatedOrDestroyed, CachePhonesOnlyScriptQuestions, CallerGroupJob
* dialer_worker -> CalculateDialsJob, DialerJob
* general -> Archival::Jobs::CampaignArchived, Archival::Jobs::CampaignSweeper, DoNotCall::Jobs::CachePortedLists, DoNotCall::Jobs::CacheWirelessBlockList, DoNotCall::Jobs::RefreshPortedLists, DoNotCall::Jobs::RefreshWirelessBlockList, DeliverInvitationEmailJob, PhantomCallerJob, ResetVoterListCounterCache
* import -> CallList::Jobs::Import, CallList::Jobs::Prune, CallList::Jobs::ToggleActive, CallList::Jobs::Upload
* persist_jobs -> none!
* persistence -> CallFlow::Jobs::Persistence
* reports -> AdminReportJob, ReportAccountUsageJob, ReportDownloadJob
* simulator_worker -> SimulatorJob
* twilio_stats -> UpdateStatsAttemptsEm, UpdateStatsTransfersEm, UpdateTwilioStatsCallerSession

# Whitelabeling

1. Logo should look good at 300x57 and be png
  1. Use imagemagick to convert format if needed `convert img.jpg img.png`
  1. Use imagemagick to resize if needed `convert img.png -resize xx% img-h1.png`
1. Update `en.yml` (use previous whitelabel entries as template)
  1. Billing Link is only for certain customers
1. Add logo to `public/img` folder, naming file `domain-name-h1.ext`
1. Update CSS in `public/styles/style.css` (use previous whitelabel entries as template - *class names are dynamically generated in erb*)
1. Verify logo displays nicely on localhost
  1. Update `/etc/hosts`
1. Buy domain from badger.com (use visa xx8669)
1. Setup domain in Cloudflare
  1. Use other domains as template
  1. Verify security rules whitelist upload urls
  1. Verify High Security Profile is used
  1. Verify CDN + High Performance is used
  1. Update DNS w/ Badger
1. Add domain to heroku production app

## Test in staging

1. Add domain to heroku staging app
1. Add the following to `/etc/hosts`
  1. `impactdialing-staging.herokuapp.com whitelabel-domain.com`
1. Visit `whitelabel-domain.com`

# Heads up

## Resque

The `resque-loner` gem is used for a few jobs. This gem defines `.redis_key` and uses that to track job uniqueness. Careful not to override this in implementation classes.
