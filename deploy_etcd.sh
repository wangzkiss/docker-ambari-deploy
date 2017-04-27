#!/usr/bin/bash
# 必须配置好，本地host文件
: ${HOST_LIST:=docker-220,docker-222}
# 通过 calico 配置的跨节点网络
: ${CALICO_NET:=docker_test}

# split by space
HOST_FOR_LIST=${HOST_LIST//,/ }

etcd-install() {
    # wget https://github.com/coreos/etcd/releases/download/v3.1.5/etcd-v3.1.5-linux-amd64.tar.gz
    pdcp -w $HOST_LIST ./etcd-v3.1.5-linux-amd64.tar.gz ~

    pdsh -w $HOST_LIST tar -zxf ~/etcd-v3.1.5-linux-amd64.tar.gz
    pdsh -w $HOST_LIST mv -f ~/etcd-v3.1.5-linux-amd64/etcd* /usr/bin
}

etcd-open-ports() {
    pdsh -w $HOST_LIST firewall-cmd --zone=public --add-port=2380/tcp --permanent
    pdsh -w $HOST_LIST firewall-cmd --reload
}

_stop-etcd-progress() {
    ps -ef | grep 'etcd -name'| grep -v grep | awk '{print $2}' | xargs kill -9
}

etcd-start() {
    # todo: open port 2380, 2379
    local cluster_size=${1:?"usege: etcd-start <CLUSTER_SIZE>"}
    local token=$(curl "https://discovery.etcd.io/new?size=$cluster_size")

    _copy_this_sh

    local count=0
    for host in $HOST_FOR_LIST
    do
        if [ $count -eq $cluster_size ];then
            break
        fi

        local host_ip=$(grep -i $host /etc/hosts | awk '{print $1}')
        # stop it first
        pdsh -w $host bash ~/$0 _stop-etcd-progress

        pdsh -w $host ETCD_DISCOVERY=${token} \
        nohup etcd -name etcd-$host -initial-advertise-peer-urls http://${host_ip}:2380 \
              -listen-peer-urls http://${host_ip}:2380 \
              -listen-client-urls http://${host_ip}:2379,http://127.0.0.1:2379 \
              -advertise-client-urls http://${host_ip}:2379 \
              -discovery ${token} > ~/etcd.log &

        ((count+=1))
    done
    # local listen_ip=$(ip addr | grep inet | grep $connect_net_interface | awk -F" " '{print $2}'| sed -e 's/\/.*$//')
}

_get-first-host() {
    $(echo $HOST_FOR_LIST | awk '{print $1}')
}

_get-first-host-ip() {
    local host=$(_get-first-host)
    grep -i $host /etc/hosts | awk '{print $1}'
}

_get-second-host-ip() {
    local host=$(echo $HOST_FOR_LIST | awk '{print $2}')
    grep -i $host /etc/hosts | awk '{print $2}'
}

_copy_this_sh() {
    pdcp -w $HOST_LIST $0 ~
}

etcd-config-docker-daemon() {
    _copy_this_sh

    pdsh -w $HOST_LIST bash ~/$0 _config-docker-daemon $(_get-first-host-ip)

    pdsh -w $HOST_LIST systemctl restart docker

}

_config-docker-daemon() {
    local first_host_ip=$1
    local cluster_ip=""
    local docker_config="/etc/sysconfig/docker"

    # 本地监听 2379端口
    if netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".2379"'; then
        cluster_ip="0.0.0.0"
    else
        cluster_ip=$first_host_ip
    fi

    if cat $docker_config | grep -q "cluster-store"; then
        sed -i "s/cluster-store=[^\']*/cluster-store=etcd:\/\/${cluster_ip}:2379/g" $docker_config
    else
        sed -i "s/OPTIONS='\(.*\)'/OPTIONS='\1 --cluster-store=etcd:\/\/${cluster_ip}:2379'/g" $docker_config
    fi

}


_local_calico_start() {
    local first_host_ip=$1
    local host_ip=$2

    local cluster_ip=""
    if netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".2379"'; then
        cluster_ip="0.0.0.0"
    else
        cluster_ip=$first_host_ip
    fi
    # 默认的name 和hostName 一直，如果两台机器的hostName一致，则必须指定，不然bgp发现不了远端
    # ETCD_ENDPOINTS=http://${cluster_ip}:2379 calicoctl node run --ip=$host_ip --node-image calico/node --name node1
    ETCD_ENDPOINTS=http://${cluster_ip}:2379 calicoctl node run --ip=$host_ip --node-image calico/node

}

# ingress:
#   source:
#     tag: docker_test
# 默认的配置，source 有tag现在，只允许相同网络互相访问
# 外网无法访问 8080 端口
_config-calico-profile() {
cat << EOF | calicoctl apply -f -
- apiVersion: v1
  kind: profile
  metadata:
    name: $CALICO_NET
    tags:
    - $CALICO_NET
  spec:
    egress:
    - action: allow
      destination: {}
      source: {}
    ingress:
    - action: allow
      protocol: tcp
      destination: {}
      source: {}
EOF
}


calico-start() {
    if [ -e ./calicoctl ]; then
        :
    else
        echo "downloading calicoctl ......"
        wget -O ./calicoctl https://github.com/projectcalico/calicoctl/releases/download/v1.1.3/calicoctl
    fi

    # open port:179 for BPG protocol (calico use for node communication)
    pdsh -w $HOST_LIST firewall-cmd --zone=public --add-port=179/tcp --permanent
    pdsh -w $HOST_LIST firewall-cmd --reload

    pdcp -w $HOST_LIST ./calicoctl /usr/local/bin/calicoctl

    pdsh -w $HOST_LIST chmod +x /usr/local/bin/calicoctl

    # 拷贝当前脚本
    _copy_this_sh

    for host in $HOST_FOR_LIST
    do
        local host_ip=$(grep -i $host /etc/hosts | awk '{print $1}')

        pdsh -w $host bash ~/$0 _local_calico_start $(_get-first-host-ip) $host_ip

    done

    sleep 5

    pdsh -w $(_get-first-host) bash ~/$0 _config-calico-profile

    pdsh -w $(_get-first-host) bash calicoctl node status
}

calico-create-net() {
    docker network rm $CALICO_NET
    # 192.168.0.0/16 calico default CIDR
    docker network create --driver calico --ipam-driver calico-ipam --subnet=192.168.0.0/16 $CALICO_NET
}

test-calico-net-conn() {
    pdsh -w $(_get-first-host-ip) docker stop workload-A workload-B
    pdsh -w $(_get-first-host-ip) docker rm workload-A workload-B

    pdsh -w $(_get-first-host-ip) docker run --net $CALICO_NET --name workload-A -tid busybox
    pdsh -w $(_get-first-host-ip) docker run --net $CALICO_NET --name workload-B -tid busybox


    pdsh -w $(_get-second-host-ip) docker stop workload-C
    pdsh -w $(_get-second-host-ip) docker rm workload-C

    pdsh -w $(_get-second-host-ip) docker run --net $CALICO_NET --name workload-C -tid busybox

    pdsh -w $(_get-first-host-ip) docker exec workload-A ping -c 4 workload-B.$CALICO_NET
    pdsh -w $(_get-first-host-ip) docker exec workload-A ping -c 4 workload-C.$CALICO_NET

}

_clean-all-container() {
    docker stop $(docker ps -a -q)
    docker rm $(docker ps -a -q)
}

docker-stop-all() {
    _copy_this_sh

    pdsh -w $HOST_LIST bash ~/$0 _clean-all-container
}

main() {
    local cluster_size=${1:?"usege: main <ETCD_CLUSTER_SIZE>"}

    echo "docker-stop-all starting"
    docker-stop-all
    echo "etcd-install starting"
    etcd-install
    echo "etcd-open-ports starting"
    etcd-open-ports
    echo "etcd-start $cluster_size starting"
    etcd-start $cluster_size
    echo "etcd-config-docker-daemon starting"
    etcd-config-docker-daemon
    echo "calico-start starting"
    calico-start
    echo "calico-create-net starting"
    calico-create-net
    echo "test-calico-net-conn starting"
    test-calico-net-conn
}

# call arguments verbatim:
$@