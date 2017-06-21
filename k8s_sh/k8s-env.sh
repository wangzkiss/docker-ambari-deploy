#!/usr/bin/bash

: ${HOST_LIST:=dc01,dc02,dc03,dc04,dc05}

HADOOP_DATA=/home/hadoop_data
HADOOP_LOG=/home/hadoop_log


_get-host-num(){
    awk '{print NF}' <<< "${HOST_LIST//,/ }"
}