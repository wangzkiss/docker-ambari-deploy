#!/usr/bin/bash

: ${HOST_LIST:=dc01,dc02,dc03,dc04,dc05}
: ${ENV_FILE:=$(dirname $0)/k8s-env.sh}
: ${SH_FILE_PATH:=/tmp}

HADOOP_DATA=/home/hadoop_data
HADOOP_LOG=/home/hadoop_log


_get-host-num(){
    awk '{print NF}' <<< "${HOST_LIST//,/ }"
}


_copy_this_sh() {
    local host=$1
    if [[ "" == $host ]];then
        host=$HOST_LIST
    fi
    pdcp -w $host $ENV_FILE $0 $SH_FILE_PATH
}