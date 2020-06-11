# simple-private-cloud-lxc

Bash minimalist implementation of a boostrap script for an [lxc](https://linuxcontainers.org/) based 'private cloud' of resources consisting of an lxc container hypervisor accessible via ssh from only a bastion ssh host, with metadata API and service mesh capabilities provided by [Consul](consul.io)

# Highlights

- SSH Bastion Host
- Resource division via containerization (lxc)
- Service mesh ready

# Keywords

- iptables
- lxc
- consul

# Instructions

## clone repo

```
git clone git@github.com:myiremark/simple-private-cloud-lxc.git
```
# set bootrapping variables in bootstrap.sh
```
BOOTSTRAP_DOMAIN_NAME="example.com"; # network you're bootstrapping off of.
BOOTSTRAP_HOSTNAME="domaincontroller"; # host your're boostrapping off of.
BOOTSTRAP_SSH_PUB_KEY="" # contents of SSH Public key which you'll be boostrapping from.
BOOTSTRAP_BASTION_IP=""; # IP of bastion which you'll be allowing SSH from.
BOOTSTRAP_NS_1=""; # Nameserver used by resolv.conf
BOOTSTRAP_NS_2=""; # Nameserver used by resolv.conf
BOOTSTRAP_NS_3=""; # Nameserver used by resolv.conf
```
## Call script
```
./bootstrap.sh HOST_NAME DOMAIN_NAME MY_PUBLIC_IP
```

HOST_NAME="$1"; # The host name you want to set the bootstrapped (this) computer to

DOMAIN_NAME="$2"; # The domain name you want to set the bootstrapped (this) computer to

MY_PUBLIC_IP="$3"; # The public IP of the bootstrapped (this) computer
