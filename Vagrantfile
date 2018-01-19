VAGRANTFILE_API_VERSION = "2"

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

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "ubuntu/trusty64"
  config.vm.network "private_network", type: "dhcp"
  config.vm.provision "shell", inline: $script
end
