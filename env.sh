#!/usr/bin/bash

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

_copy_env_sh() {
    pdcp -w $HOST_LIST env.sh ~
}

_copy_this_sh() {
    _copy_env_sh
    pdcp -w $HOST_LIST $0 ~
}

_get-etcd-ip-list() {
    local input_type=${1:?"Usage:_get-etcd-ip-list <TYPE>(etcd,http)"}
    local host_num=$(awk '{print NF}' <<< "$HOST_FOR_LIST")

    local host1=$(awk '{print $1}' <<< "$HOST_FOR_LIST")
    local host1_ip=$(grep -i ${host1} /etc/hosts | awk '{print $1}')

    local result=""

    if [ $host_num -lt 3 ]; then
        result="etcd://${host1_ip}:2379"
    else
        local host2=$(awk '{print $2}' <<< "$HOST_FOR_LIST")
        local host3=$(awk '{print $3}' <<< "$HOST_FOR_LIST")

        local host2_ip=$(grep -i ${host2} /etc/hosts | awk '{print $1}')
        local host3_ip=$(grep -i ${host3} /etc/hosts | awk '{print $1}')

        result="etcd://${host1_ip}:2379,etcd://${host2_ip}:2379,etcd://${host3_ip}:2379"
    fi

    if [ $input_type == 'http' ]; then
        echo $result | sed -e "s/etcd/http/g"
    else
        # etcd for docker daemon only config one
        echo $result | awk -F , '{print $1}'
    fi
}
