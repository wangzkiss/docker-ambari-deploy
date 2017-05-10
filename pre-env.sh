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

# config host network
pre-network() {
    local host_name=${1:?"Usage: main <HOST-NAME> <IP-ADDR>"}
    local ip_addr=${2:?"Usage: main <HOST-NAME> <IP-ADDR>"}

    _set-hostname $host_name
    _change-ip 172.18.84.254 $ip_addr
    systemctl restart network
}

ssh-passwd-less() {
    local passwd=${1:?"Usage:_install-pdsh <PASSWD>"}
    
    # yum -y update
    echo -e  'y\n'|ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa

    for host in $HOST_FOR_LIST; do
        ssh-keyscan $host >> ~/.ssh/known_hosts
        sshpass -p $passwd ssh-copy-id root@$host
    done
}

_config-docker() {
    pdsh -w $HOST_LIST yum install -y epel-release docker-io

    pdsh -w $HOST_LIST "echo '{
    \"live-restore\": true,
    \"registry-mirrors\": [\"https://80kate9y.mirror.aliyuncs.com\"]
}' > /etc/docker/daemon.json" 

    pdsh -w $HOST_LIST systemctl restart docker
}

pre-deploy() {
    yum install -y epel-release sshpass pdsh git
    ssh-passwd-less
    _config-docker
}

$@