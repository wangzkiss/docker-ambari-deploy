#!/usr/bin/bash
: ${HOST_LIST=dokcer-220,docker-222}


install-etcd() {
    # wget https://github.com/coreos/etcd/releases/download/v3.1.5/etcd-v3.1.5-linux-amd64.tar.gz

    pdcp -w $HOST_LIST ./etcd-v3.1.5-linux-amd64.tar.gz ~

    pdsh -w $HOST_LIST cd ~
    pdsh -w $HOST_LIST tar -zxvf etcd-v3.1.5-linux-amd64.tar.gz
    pdsh -w $HOST_LIST cd etcd-v3.1.5-linux-amd64/
    pdsh -w $HOST_LIST mv etcd* /usr/bin

}

start-etcd() {
    # todo: open port 2380, 2379
    local cluster_size=$1
    # net interface eg: eth0
    local connect_net_interface=$2
    local token=$(curl "https://discovery.etcd.io/new?size=$cluster_size")


    local host_list=${HOST_LIST//,/ }
    for host in $host_list
    do
        local host_ip=$(grep -i $host /etc/hosts | awk '{print $1}')

        pdsh -w $host ETCD_DISCOVERY=${token} \
        etcd -name etcd0 -initial-advertise-peer-urls http://${host_ip}:2380 \
          -listen-peer-urls http://${host_ip}:2380 \
          -listen-client-urls http://${host_ip}:2379,http://127.0.0.1:2379 \
          -advertise-client-urls http://${host_ip}:2379 \
          -discovery ${token}
    done
    # local listen_ip=$(ip addr | grep inet | grep $connect_net_interface | awk -F" " '{print $2}'| sed -e 's/\/.*$//')
}