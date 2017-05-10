#!/usr/bin/bash

: ${HOST_LIST:=dc01,dc02,dc03,dc04,dc05}

# split by space
HOST_FOR_LIST=${HOST_LIST//,/ }