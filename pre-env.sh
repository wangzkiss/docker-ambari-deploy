#!/usr/bin/bash

# import common variable
. ./env.sh

_change-ip() {
    local GATEWAY=${1:?"Usage:change-ip <GATEWAY> <IPADDR>"}
    local IPADDR=${2:?"Usage:change-ip <GATEWAY> <IPADDR>"}
    local DNS1=172.30.100.3

    sed -i "s/ONBOOT=.*/ONBOOT=yes/g" /etc/sysconfig/network-scripts/ifcfg-eth0
    sed -i "s/BOOTPROTO=.*/BOOTPROTO=static/g" /etc/sysconfig/network-scripts/ifcfg-eth0

    for ele in DNS1 GATEWAY IPADDR; do
        if cat /etc/sysconfig/network-scripts/ifcfg-eth0 | grep $ele; then
            sed -i "s/$ele=.*/$ele=${!ele}/g" /etc/sysconfig/network-scripts/ifcfg-eth0
        else
            echo "$ele=${!ele}" >> /etc/sysconfig/network-scripts/ifcfg-eth0
        fi
    done
}

_set-hostname() {
    hostnamectl set-hostname $1
}

_host-ssh-passwd-less(){
    ssh-keyscan $1 >> ~/.ssh/known_hosts
    sshpass -p $2 ssh-copy-id root@$1
}

_hosts-ssh-passwd-less() {
    local passwd=${1:?"Usage:_install-pdsh <PASSWD>"}
    # yum -y update
    echo -e  'y\n'|ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa
    for host in $HOST_FOR_LIST; do
        _host-ssh-passwd-less $host $passwd
    done
}

_config-docker() {
    echo '{
    "live-restore": true,
    "registry-mirrors": ["https://80kate9y.mirror.aliyuncs.com"]
}' > /etc/docker/daemon.json

    systemctl restart docker
}

_pre-host(){
    # jq parse curl json
    yum install -y epel-release pdsh docker-io jq
    _config-docker
}

# config host network
pre-network() {
    local host_name=${1:?"Usage: main <HOST-NAME> <IP-ADDR>"}
    local ip_addr=${2:?"Usage: main <HOST-NAME> <IP-ADDR>"}

    _set-hostname $host_name
    _change-ip 172.18.84.254 $ip_addr
    systemctl restart network
}

pre-deploy() {
    local passwd=${1:?"Usage: pre-deploy <host-passwd>"}
    # install on local server
    yum install -y epel-release sshpass pdsh git

    _hosts-ssh-passwd-less $passwd
    _copy_this_sh
    pdsh -w $HOST_LIST bash ~/$0 _pre-host
}

add-new-host() {
    local host=${1:?"Usage: add-new-host <host> <passwd>"}
    local passwd=${2:?"sage: add-new-host <host> <passwd>"}

    _host-ssh-passwd-less $host $passwd
    _copy_this_sh
    pdsh -w $host bash ~/$0 _pre-host 
}

$@