#!/usr/bin/bash

: ${NODE_PREFIX=amb}
: ${CONSUL:=${NODE_PREFIX}-consul}

: ${HOST_LIST:=dc01,dc02,dc03,dc04,dc05}

# 通过 calico 配置的跨节点网络
: ${CALICO_NET:=docker_test}
: ${CALICO_CIDR:=192.0.2.0/24}

# 本地 HDP，HDP-UTIL 包所在的路径
: ${HDP_PKG_DIR:=/home/hdp_httpd_home/}
# docker volume mount to docker
: ${HADOOP_DATA:=/home/hadoop_data}
: ${HADOOP_LOG:=/home/hadoop_log}

# split by space
HOST_FOR_LIST=${HOST_LIST//,/ }

_copy_this_sh() {
    local host=$1
    if [[ "" == $host ]];then
        host=$HOST_LIST
    fi

    pdcp -w $host env.sh ~
    pdcp -w $host $0 ~
}

_get-host-num(){
    _get-host-num
}

##########################################################
# These functions only run on main host, because other node 
# may the /etc/hosts don't same with main host
_get-host-ip(){
    grep -i $1 /etc/hosts | awk '{print $1}'
}

_get-first-host() {
    echo $HOST_FOR_LIST | awk '{print $1}'
}

_get-second-host() {
    echo $HOST_FOR_LIST | awk '{print $2}'
}

_get-third-host() {
    echo $HOST_FOR_LIST | awk '{print $3}'
}

_get-first-host-ip() {
    _get-host-ip $(_get-first-host)
}

_get-second-host-ip() {
    _get-host-ip $(_get-second-host)
}

_get-third-host-ip() {
    _get-host-ip $(_get-third-host)
}

_get-etcd-ip-list() {
    local input_type=${1:?"Usage:_get-etcd-ip-list <TYPE>(etcd,http)"}
    local host_num=$(_get-host-num)
    local host1_ip=$(_get-first-host-ip)

    local result=""
    if [ $host_num -lt 3 ]; then
        result="etcd://${host1_ip}:2379"
    else
        local host2_ip=$(_get-second-host-ip)
        local host3_ip=$(_get-third-host-ip)

        result="etcd://${host1_ip}:2379,etcd://${host2_ip}:2379,etcd://${host3_ip}:2379"
    fi

    if [ $input_type == 'http' ]; then
        echo $result | sed -e "s/etcd/http/g"
    else
        # etcd for docker daemon only config one
        echo $result | awk -F , '{print $1}'
    fi
}
##########################################################

_etcdctl() {
    docker run  --rm tenstartups/etcdctl --endpoints $(_get-etcd-ip-list http) $@
}

get-host-ip() {
    local HOST=${1:?"Usage: get-host-ip <HOST>"}
     _etcdctl get /ips/${HOST}
}

set-host-ip() {
    local HOST=${1:?"Usage: set-host-ip <HOST> <ip>"}
    local IP=${2:?"Usage: set-host-ip <HOST> <ip>"}
    _etcdctl set /ips/${HOST} ${IP}
}

get-consul-ip() {
    get-host-ip ${CONSUL}
}

consul-register-service() {
    : ${1:?"Usage:consul-register-service <node_name> <node_ip>"}
    : ${2:?"Usage:consul-register-service <node_name> <node_ip>"}
    local consul_ip=$(get-consul-ip)
    docker run  --net ${CALICO_NET} --rm appropriate/curl sh -c "
    curl -X PUT -d \"{
        \\\"Node\\\": \\\"$1\\\",
        \\\"Address\\\": \\\"$2\\\",
        \\\"Service\\\": {
          \\\"Service\\\": \\\"$1\\\"
        }
      }\" http://$consul_ip:8500/v1/catalog/register
  "
}