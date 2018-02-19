VAGRANTFILE_API_VERSION = "2"

$script1 = <<SCRIPT1
echo provisioning...
echo system update...
sudo apt update
sudo apt upgrade -s
sudo apt install libxml2 libxml2-dev libxslt1.1 libxslt1-dev libqt5webkit5-dev gstreamer1.0-plugins-base gstreamer1.0-tools gstreamer1.0-x redis-server -y
sudo apt install qt5base-dev qtdeclarative5-dev qt5-qmake qt5-default qttools5-dev-tools qt5-default qtchooser -y
sudo apt-get install qt5-default libqt5webkit5-dev gstreamer1.0-plugins-base gstreamer1.0-tools gstreamer1.0-x -y
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get -q -y install mysql-server mysql-client libmysqlclient-dev -y
SCRIPT1


# mysqladmin -u root password MYSQLPASS


$script2 = <<SCRIPT2
echo getting the keys for rvm...
gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
curl -sSL https://get.rvm.io | bash -s $1
SCRIPT2

$script3 = <<SCRIPT3
echo installing rvm and ruby...
# source /etc/profile.d/rvm.sh
source $HOME/.rvm/scripts/rvm
rvm use --default --install $1 --quiet-curl
gem install bundler
rvm cleanup all
SCRIPT3

$script4 = <<SCRIPT4
echo doing the bundle install...
source $HOME/.rvm/scripts/rvm
cd /vagrant
rvm use
bundle install
SCRIPT4

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  # add memory...
  config.vm.provider "virtualbox" do |v|
    v.memory = 2048
  end

  config.vm.box = "ubuntu/trusty64"
  config.vm.network "private_network", type: "dhcp"
  config.vm.network "forwarded_port", guest: 3000, host: 3001
  config.vm.provision :shell, inline: $script1, privileged: false
  config.vm.provision :shell, inline: $script2, args: "stable", privileged: false
  config.vm.provision :shell, inline: $script3, args: "2.2.4", privileged: false
  config.vm.provision :shell, inline: $script4, privileged: false
end


# sudo su vagrant
# echo user should be vagrant...
# gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
# curl -sSL https://get.rvm.io | bash -s stable
# source /home/vagrant/.rvm/scripts/rvm
# rvm install "ruby-2.2.4"
# gem install bundler
