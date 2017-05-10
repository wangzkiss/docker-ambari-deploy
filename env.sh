#!/usr/bin/bash

: ${HOST_LIST:=dc01,dc02,dc03,dc04,dc05}

# 通过 calico 配置的跨节点网络
: ${CALICO_NET:=docker_test}
: ${CALICO_CIDR:=192.0.2.0/24}

# split by space
HOST_FOR_LIST=${HOST_LIST//,/ }

# 本地 HDP，HDP-UTIL 包所在的路径
: ${HDP_PKG_DIR:=/home/hdp_httpd_home/}

# docker volume mount to docker
: ${HADOOP_DATA:=/home/hadoop_data}
: ${HADOOP_LOG:=/home/hadoop_log}
