#!/bin/bash

: ${SH_FILE_PATH:=/tmp}
: ${HOST_LIST:=dc01,dc02,dc03,dc04,dc05}

get-master-host(){
    cut -d',' -f 1 <<< $HOST_LIST
}

get-nodes-host(){
    cut -d',' -f 2- <<< $HOST_LIST
}

install-k8s(){
    local repo_path=/etc/yum.repos.d/virt7-docker-common-release.repo
    echo "[virt7-docker-common-release]
name=virt7-docker-common-release
baseurl=http://cbs.centos.org/repos/virt7-docker-common-release/x86_64/os/
gpgcheck=0" > $repo_path
    
    pdcp -w $HOST_LIST $repo_path $repo_path
    pdsh -w $HOST_LIST yum -y install --enablerepo=virt7-docker-common-release kubernetes etcd flannel

}

conf-kubernetes-common(){
    local config_path=/etc/kubernetes/config
    echo "# logging to stderr means we get it in the systemd journal
KUBE_LOGTOSTDERR=\"--logtostderr=true\"

# journal message level, 0 is debug
KUBE_LOG_LEVEL=\"--v=0\"

# Should this cluster be allowed to run privileged docker containers
KUBE_ALLOW_PRIV=\"--allow-privileged=false\"

# How the replication controller and scheduler find the kube-apiserver
KUBE_MASTER=\"--master=http://172.18.84.221:8080\"" > $config_path
    pdcp -w $HOST_LIST $config_path $config_path
}

conf-etcd-on-master(){
    local master_host=$(get-master-host)
    local config_path=/etc/etcd/etcd.conf
    echo "# [member]
ETCD_NAME=default
ETCD_DATA_DIR=\"/var/lib/etcd/default.etcd\"
ETCD_LISTEN_CLIENT_URLS=\"http://172.18.84.221:2379\"

#[cluster]
ETCD_ADVERTISE_CLIENT_URLS=\"http://172.18.84.221:2379\"" > $config_path
    pdcp -w $master_host $config_path $config_path
}

conf-apiserver-on-master(){
    local master_host=$(get-master-host)
    local config_path=/etc/kubernetes/apiserver
    echo "# The address on the local server to listen to.
KUBE_API_ADDRESS=\"--address=0.0.0.0\"

# The port on the local server to listen on.
KUBE_API_PORT=\"--port=8080\"

# Port minions listen on
KUBELET_PORT=\"--kubelet-port=10250\"

# Comma separated list of nodes in the etcd cluster
KUBE_ETCD_SERVERS=\"--etcd-servers=http://172.18.84.221:2379\"

# Address range to use for services
KUBE_SERVICE_ADDRESSES=\"--service-cluster-ip-range=10.254.0.0/16\"

# default admission control policies
# KUBE_ADMISSION_CONTROL=\"--admission-control=NamespaceLifecycle,NamespaceExists,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota\"
KUBE_ADMISSION_CONTROL=\"--admission-control=NamespaceLifecycle,NamespaceExists,LimitRanger,SecurityContextDeny,ResourceQuota\"

# Add your own!
KUBE_API_ARGS=\"--allow-privileged --client-ca-file=/srv/kubernetes/ca.crt --tls-cert-file=/srv/kubernetes/server.crt --tls-private-key-file=/srv/kubernetes/server.key\"" > $config_path
    pdcp -w $master_host $config_path $config_path
}

open-kubelet-connect-port(){
    pdsh -w $HOST_LIST firewall-cmd --zone=public --add-port=10250/tcp --permanent
    pdsh -w $HOST_LIST firewall-cmd --reload
}


conf-flanneld-on-etcd(){
    local master_host=$(get-master-host)
    pdsh -w $master_host systemctl start etcd
    pdsh -w $master_host "etcdctl --endpoint 172.18.84.221:2379 set /kube-centos-test/network/config \"{ \\\"Network\\\": \\\"172.30.0.0/16\\\", \\\"SubnetLen\\\": 24, \\\"Backend\\\": { \\\"Type\\\": \\\"vxlan\\\" } }\""
}

conf-flanneld() {
    local config_path=/etc/sysconfig/flanneld
    echo "# Flanneld configuration options  

# etcd url location.  Point this to the server where etcd runs
FLANNEL_ETCD_ENDPOINTS=\"http://172.18.84.221:2379\"

# etcd config key.  This is the configuration key that flannel queries
# For address range assignment
FLANNEL_ETCD_PREFIX=\"/kube-centos/network\"

# Any additional options that you want to pass
#FLANNEL_OPTIONS=\"\"" > $config_path
    pdcp -w $HOST_LIST $config_path $config_path
}

conf-kubelet(){
    local config_path=/etc/kubernetes/kubelet
    echo "# kubernetes kubelet (minion) config

# The address for the info server to serve on (set to 0.0.0.0 or \"\" for all interfaces)
KUBELET_ADDRESS=\"--address=0.0.0.0\"

# The port for the info server to serve on
KUBELET_PORT=\"--port=10250\"

# You may leave this blank to use the actual hostname
#KUBELET_HOSTNAME=\"--hostname-override=127.0.0.1\"
KUBELET_HOSTNAME=\"\"

# location of the api-server
KUBELET_API_SERVER=\"--api-servers=http://172.18.84.221:8080\"

# pod infrastructure container
KUBELET_POD_INFRA_CONTAINER=\"--pod-infra-container-image=registry.access.redhat.com/rhel7/pod-infrastructure:latest\"

# Add your own!
KUBELET_ARGS=\"\"" > $config_path
    pdcp -w $HOST_LIST $config_path $config_path
}

start-master(){
    local master_host=$(get-master-host)
    pdcp -w $master_host $0 $SH_FILE_PATH
    pdsh -w $master_host bash $SH_FILE_PATH/$0 _local_start_master
}

open-port-on-master(){
    local master_host=$(get-master-host)
    pdsh -w $master_host firewall-cmd --zone=public --add-port=8080/tcp --permanent
    pdsh -w $master_host firewall-cmd --zone=public --add-port=2379/tcp --permanent
    pdsh -w $master_host firewall-cmd --reload
}

start-nodes(){
    # local nodes_host=$(get-nodes-host)
    pdcp -w $HOST_LIST $0 $SH_FILE_PATH
    pdsh -w $HOST_LIST bash $SH_FILE_PATH/$0 _local_start_nodes
}

stop-all(){
    local master_host=$(get-master-host)
    pdcp -w $HOST_LIST $0 $SH_FILE_PATH

    pdsh -w $HOST_LIST bash $SH_FILE_PATH/$0 _local_stop_nodes

    pdsh -w $master_host bash $SH_FILE_PATH/$0 _local_stop_master
}

_local_start_master(){
    for SERVICES in etcd kube-apiserver kube-controller-manager kube-scheduler flanneld; do
        systemctl restart $SERVICES
        systemctl enable $SERVICES
        systemctl status $SERVICES
    done
}

_local_stop_master(){
    for SERVICES in etcd kube-apiserver kube-controller-manager kube-scheduler flanneld; do
        systemctl stop $SERVICES
        systemctl status $SERVICES
    done
}

_local_stop_nodes(){
    for SERVICES in kube-proxy kubelet flanneld docker; do
        systemctl stop $SERVICES
        systemctl status $SERVICES
    done
}

_local_start_nodes(){
    for SERVICES in kube-proxy kubelet flanneld docker; do
        systemctl restart $SERVICES
        systemctl enable $SERVICES
        systemctl status $SERVICES
    done
}

conf-kubectl(){
    local master_host=$(get-master-host)
    pdsh -w $master_host "kubectl config set-cluster default-cluster --server=http://172.18.84.221:8080"
    pdsh -w $master_host "kubectl config set-context default-context --cluster=default-cluster --user=default-admin"
    pdsh -w $master_host "kubectl config use-context default-context"

    # config 
    pdsh -w $master_host "kubectl create namespace ambari"
    pdsh -w $master_host "kubectl label node $master_host role=master"
}

add-kube-dns(){
    # TODO use sed modify
    echo "KUBELET_ARGS=\"--cluster_dns=10.254.0.10 --cluster_domain=cluster.local --allow-privileged\"" >> /etc/kubernetes/kubelet
    pdcp -w $HOST_LIST /etc/kubernetes/kubelet /etc/kubernetes/kubelet
    # --kube-master-url=http://172.18.84.221:8080
}

main(){
    install-k8s
    conf-kubernetes-common
    conf-etcd-on-master
    conf-apiserver-on-master
    open-port-on-master
    open-kubelet-connect-port
    conf-flanneld-on-etcd
    conf-kubelet
    start-master

    start-nodes
    conf-kubectl
}

$@