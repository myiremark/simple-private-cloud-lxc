#!/bin/bash
#
# Bash minimalist implementation of a boostrap script 
# for an lxc based 'private cloud' of resources consisting 
# of an lxc container hypervisor accessible via ssh from 
# only a bastion ssh host, with metadata API and service mesh 
# capabilities provided by Consul

# Usage:
#
# set bootrapping variables, then
# 
# ./bootstrap HOST_NAME DOMAIN_NAME MY_PUBLIC_IP
#
# 

set -eux;
shopt -s extglob;

BOOTSTRAP_DOMAIN_NAME="example.com"; # network you're bootstrapping off of.
BOOTSTRAP_HOSTNAME="domaincontroller"; # host your're boostrapping off of.
BOOTSTRAP_SSH_PUB_KEY="" # contents of SSH Public key which you'll be boostrapping from.
BOOTSTRAP_BASTION_IP=""; # IP of bastion which you'll be allowing SSH from.
BOOTSTRAP_NS_1=""; # Nameserver used by resolv.conf
BOOTSTRAP_NS_2=""; # Nameserver used by resolv.conf
BOOTSTRAP_NS_3=""; # Nameserver used by resolv.conf

_HOST_NAME="$1"; # The host name you want to set the bootstrapped (this) computer to

DOMAIN_NAME="$2"; # The domain name you want to set the bootstrapped (this) computer to

MY_PUBLIC_IP="$3"; # The public IP of the bootstrapped (this) computer

FQDN="$_HOST_NAME.$DOMAIN_NAME";

DEBIAN_FRONTEND=noninteractive;

while true
do
  # (1) prompt user, and read command line argument
  read -p "Bootstrapping $FQDN at $MY_PUBLIC_IP from $BOOTSTRAP_HOSTNAME.$BOOTSTRAP_DOMAIN_NAME at $BOOTSTRAP_BASTION_IP. Proceed?" answer

  # (2) handle the input we were given
  case $answer in
   [Yy]* ) echo "hold on to your butts.";
           break;;

   [Nn]* ) exit;;

   * )     echo "A simple Y or N will suffice.";;
  esac
done

BOOTSTRAP_FQDN="$BOOTSTRAP_HOSTNAME.$BOOTSTRAP_DOMAIN_NAME";

HOSTS_ENTRY_LOCALHOST="127.0.0.1 localhost.localdomain localhost"
HOSTS_ENTRY_BOOTSTRAP="$BOOTSTRAP_BASTION_IP $BOOTSTRAP_FQDN $BOOTSTRAP_HOSTNAME";
HOSTS_ENTRY_MY_PUBLIC_IP="$MY_PUBLIC_IP $FQDN $_HOST_NAME";

# update resolv.conf for DNS resolution

echo "nameserver $BOOTSTRAP_NS_1" > /run/systemd/resolve/resolv.conf
echo "nameserver $BOOTSTRAP_NS_2" >> /run/systemd/resolve/resolv.conf
echo "nameserver $BOOTSTRAP_NS_3" >> /run/systemd/resolve/resolv.conf

# update /etc/hosts for DNS resolution

echo $HOSTS_ENTRY_LOCALHOST > /etc/hosts;
echo $HOSTS_ENTRY_BOOTSTRAP >> /etc/hosts;
echo $HOSTS_ENTRY_MY_PUBLIC_IP >> /etc/hosts;

# update host name

echo $_HOST_NAME > /etc/hostname;
hostnamectl set-hostname $_HOST_NAME;

# add public key to ssh public keys

echo $BOOTSTRAP_SSH_PUB_KEY >> /root/.ssh/authorized_keys

# configure ssh to only allow key basd auth

cat >/etc/ssh/sshd_config<<EOF
PermitRootLogin without-password
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
AcceptEnv LANG LC_*
PubkeyAuthentication yes
EOF

# restart ssh server for config changes to take effect

service sshd restart;

# DISABLE IPV6

conf_file="/etc/sysctl.d/99-sysctl.conf";

echo "net.ipv6.conf.all.disable_ipv6=1" >> $conf_file;
echo "net.ipv6.conf.default.disable_ipv6=1" >> $conf_file;
echo "net.ipv6.conf.lo.disable_ipv6=1" >> $conf_file;
echo "net.ipv6.conf.all.autoconf=0" >> $conf_file;

sudo sysctl -w net.ipv6.conf.all.autoconf=0

sysctl -p;

linkname=$(ip link | awk -F: '$0 !~ "lo|vir|^[^0-9]"{print $2;getline}' | head -1);
linkname="${linkname##*( )}";
linkloc="/proc/sys/net/ipv6/conf/$linkname/disable_ipv6";

echo "1" > "$linkloc";

# Make sure package manager is only using allowed IP protocols

echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4;

# Simple IP tables based firewall

# Allow local traffic

iptables -A INPUT -i lo -j ACCEPT;
iptables -A INPUT -s 127.0.0.1 -j ACCEPT;
iptables -A INPUT -s 127.0.1.1 -j ACCEPT;

# Allow related traffic
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT;

# Allow bastion
iptables -A INPUT -s $BOOTSTRAP_BASTION_IP -m comment --comment "bastion"  -j ACCEPT;

# Default drop for IPV4 and IPV6 since its not enabled

iptables -P INPUT DROP;
ip6tables -P INPUT DROP;

# Now that iptables are set up, make them persistent.

DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent;

iptables-save > /etc/iptables/rules.v4;
ip6tables-save > /etc/iptables/rules.v6;

# update and upgrade to latest packages
apt-get update;
apt-get upgrade -y;

# install pre-reqs for later
apt-get install -y unzip;

# install lxd
apt-get install -y lxd;

# init lxd
cat <<EOF | lxd init --preseed
config: {}
networks:
- config:
    ipv4.address: auto
    ipv6.address: auto
  description: ""
  managed: false
  name: lxdbr0
  type: ""
storage_pools:
- config:
    size: 100GB
  description: ""
  name: default
  driver: btrfs
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      nictype: bridged
      parent: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
cluster: null
EOF

# get newly created private ip

MY_PRIVATE_IP=$(ifconfig lxdbr0 2>/dev/null | awk '/inet / {print $2}');

# Download Consul;

wget https://releases.hashicorp.com/consul/1.6.2/consul_1.6.2_linux_amd64.zip;
unzip consul_1.6.2_linux_amd64.zip;

# add to path

mv consul /usr/local/bin/;

# enable autocomplete for later management

consul -autocomplete-install;
complete -C /usr/local/bin/consul consul;

# add consul user

sudo useradd --system --home /etc/consul.d --shell /bin/false consul;

# create service

sudo mkdir --parents /opt/consul;
sudo chown --recursive consul:consul /opt/consul;
sudo touch /etc/systemd/system/consul.service;

# update the service defintion.
#
# (IN)SECURITY NOTICE: THIS IS IMPORTANT
#
# this binds to public IPS and should not be used in production unless you know what you are doing.

cat >/etc/systemd/system/consul.service<<EOF
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul.d/consul.hcl

[Service]
Type=notify
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/ -bind=0.0.0.0 -serf-wan-bind=$MY_PUBLIC_IP -advertise-wan=$MY_PUBLIC_IP -serf-lan-bind=$MY_PRIVATE_IP -advertise=$MY_PRIVATE_IP -ui
ExecReload=/usr/local/bin/consul reload
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# create consul config dir

sudo mkdir --parents /etc/consul.d
sudo touch /etc/consul.d/consul.hcl

# generate consul key

CONSUL_KEY=$(consul keygen);

# create consul service .hcl
cat >/etc/consul.d/consul.hcl<<EOF
datacenter = "$_HOST_NAME"
data_dir = "/opt/consul"
encrypt = "$CONSUL_KEY"
retry_join = ["$MY_PRIVATE_IP"]
retry_join_wan = ["$MY_PUBLIC_IP"]
client_addr = "0.0.0.0"
translate_wan_addrs=true
EOF

# create consul server.hcl
sudo touch /etc/consul.d/server.hcl

cat >/etc/consul.d/server.hcl<<EOF
server = true
bootstrap_expect = 1
EOF

# fix permissions
sudo chown --recursive consul:consul /etc/consul.d
sudo chmod 640 /etc/consul.d/server.hcl
sudo chmod 640 /etc/consul.d/consul.hcl

systemctl enable consul
systemctl daemon-reload
systemctl start consul.service

# install fail2ban and Save iptables again

apt-get install -y fail2ban;

cat >/etc/fail2ban/jail.local<<EOF
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

service fail2ban enable;

service fail2ban restart;

iptables-save > /etc/iptables/rules.v4;
ip6tables-save > /etc/iptables/rules.v6;

# restart ssh server for good measure

service sshd restart;