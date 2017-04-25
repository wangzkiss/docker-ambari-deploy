:<<USAGE
########################################
curl -Lo .amb j.mp/docker-ambari && . .amb
########################################

full documentation: https://github.com/sequenceiq/docker-ambari
USAGE

: ${NODE_PREFIX=amb}
: ${AMBARI_SERVER_NAME:=${NODE_PREFIX}-server}
: ${AMBARI_SERVER_IMAGE:="registry.cn-hangzhou.aliyuncs.com/tospur/amb-server:latest"}
: ${AMBARI_AGENT_IMAGE:="registry.cn-hangzhou.aliyuncs.com/tospur/amb-agent:latest"}
: ${HTTPD_IMAGE:="registry.cn-hangzhou.aliyuncs.com/tospur/httpd:latest"}
: ${DOCKER_OPTS:=""}
: ${CONSUL:=${NODE_PREFIX}-consul}
: ${CONSUL_IMAGE:="sequenceiq/consul:v0.5.0-v6"}
: ${CLUSTER_SIZE:=3}
: ${DEBUG:=1}
: ${SLEEP_TIME:=2}
: ${DNS_PORT:=53}
: ${EXPOSE_DNS:=false}
: ${DRY_RUN:=false}
# 通过 calico 配置的跨节点网络
: ${CALICO_NET:=docker_test}
# 本地 HDP，HDP-UTIL 包所在的路径
: ${HDP_HOST_DIR:=/home/hdp_httpd_home/}
# HDP httpd service name
: ${HTTPD_NAME:=httpd}


amb-settings() {
  cat <<EOF
  NODE_PREFIX=$NODE_PREFIX
  CLUSTER_SIZE=$CLUSTER_SIZE
  AMBARI_SERVER_NAME=$AMBARI_SERVER_NAME
  AMBARI_SERVER_IMAGE=$AMBARI_SERVER_IMAGE
  AMBARI_AGENT_IMAGE=$AMBARI_AGENT_IMAGE
  HTTPD_IMAGE=$HTTPD_IMAGE
  DOCKER_OPTS=$DOCKER_OPTS
  AMBARI_SERVER_IP=$AMBARI_SERVER_IP
  CONSUL_IP=$CONSUL_IP
  CONSUL=$CONSUL
  CONSUL_IMAGE=$CONSUL_IMAGE
  EXPOSE_DNS=$EXPOSE_DNS
  DRY_RUN=$DRY_RUN
  CALICO_NET=$CALICO_NET
  HDP_HOST_DIR=$HDP_HOST_DIR
  HTTPD_NAME=$HTTPD_NAME
EOF
}

run-command() {
  CMD="$@"
  if [[ "$DRY_RUN" == "false" ]]; then
    debug "$CMD"
    "$@"
  else
    debug [DRY_RUN] "$CMD"
  fi
}

amb-clean() {
  unset NODE_PREFIX AMBARI_SERVER_NAME AMBARI_SERVER_IMAGE AMBARI_AGENT_IMAGE HTTPD_IMAGE CONSUL CONSUL_IMAGE DEBUG SLEEP_TIME AMBARI_SERVER_IP EXPOSE_DNS \
        DRY_RUN CALICO_NET HDP_HOST_DIR HTTPD_NAME
}

get-ambari-server-ip() {
  AMBARI_SERVER_IP=$(get-host-ip ${AMBARI_SERVER_NAME})
}

set-ambari-server-ip() {
  set-host-ip ${AMBARI_SERVER_NAME}
}

get-consul-ip() {
  CONSUL_IP=$(get-host-ip ${CONSUL})
}

set-consul-ip() {
  set-host-ip $CONSUL
}

get-host-ip() {
  HOST=$1
  etcdctl get /ips/${HOST}
}

set-host-ip() {
  HOST=$1
  IP=$(docker inspect --format="{{.NetworkSettings.Networks.${CALICO_NET}.IPAddress}}" ${HOST})
  etcdctl set /ips/${HOST} ${IP}
}

amb-members() {
  curl http://$CONSUL_IP:8500/v1/catalog/nodes | sed -e 's/,{"Node":"ambari-8080.*}//g' -e 's/,{"Node":"consul.*}//g'
}

debug() {
  [ ${DEBUG} -gt 0 ] && echo "[DEBUG] $@" 1>&2
}

docker-ps() {
  #docker ps|sed "s/ \{3,\}/#/g"|cut -d '#' -f 1,2,7|sed "s/#/\t/g"
  docker inspect --format="{{.Name}} {{.NetworkSettings.Networks.${CALICO_NET}.IPAddress}} {{.Config.Image}} {{.Config.Entrypoint}} {{.Config.Cmd}}" $(docker ps -q)
}

docker-psa() {
  #docker ps|sed "s/ \{3,\}/#/g"|cut -d '#' -f 1,2,7|sed "s/#/\t/g"
  docker inspect --format="{{.Name}} {{.NetworkSettings.Networks.${CALICO_NET}.IPAddress}} {{.Config.Image}} {{.Config.Entrypoint}} {{.Config.Cmd}}" $(docker ps -qa)
}

# 启动集群
amb-start-cluster() {
  local act_cluster_size=$1
  : ${act_cluster_size:=$CLUSTER_SIZE}
  echo starting an ambari cluster with: $act_cluster_size nodes

  # 启动 server 节点
  amb-start-first

  [ $act_cluster_size -gt 1 ] && for i in $(seq $((act_cluster_size - 1))); do
    # 1, 2 (3个节点的集群), agent
    amb-start-node $i
  done
}


# 启动 ambari server 和 consul
amb-start-server() {
  amb-start-first
}

amb-net-install-sshpass() {
  # server 端添加 能上网的 nameserver
  local nameserver=$(docker exec -it $CONSUL  sh -c "sed -n '/.*nameserver.*/p' /etc/resolv.conf")

  docker exec -it $AMBARI_SERVER_NAME  sh -c "echo '$nameserver' >> /etc/resolv.conf"

  docker exec -it $AMBARI_SERVER_NAME  sh -c "cat /etc/resolv.conf"

  # install sshpass, 需要有上网能力
  docker exec -it $AMBARI_SERVER_NAME  sh -c "yum install -y sshpass"
}


amb-copy-ssh-ids() {
  docker exec -it $AMBARI_SERVER_NAME  sh -c "ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''"
  local agent_list=$(etcdctl ls /ips | grep amb'[0-9]')
  for i in $agent_list; do
    local agent_ip=$(etcdctl get $i)
    echo $agent_ip
    # 可能有问题，执行可以选择手工输入密码
    # docker exec -it $AMBARI_SERVER_NAME  sh -c "ssh-copy-id root@${agent_ip}"
    docker exec -it $AMBARI_SERVER_NAME  sh -c "sshpass -p Zasd_1234 ssh-copy-id root@${agent_ip}"
  done
}


amb-clean-etcd() {
  etcdctl rm /agent-nums

  local agent_list=$(etcdctl ls /ips | grep amb'[0-9]')
  for i in $agent_list; do
    etcdctl rm $i 
  done
}


# server passwdless login to agents
amb-ssh-passwdless() {
  amb-net-install-sshpass
  amb-copy-ssh-ids
}


# 启动 abmari agent
amb-start-agent() {
  local act_agent_size=$1
  local agent_nums=`etcdctl get /agent-nums`
  local first=1
  local last=$act_agent_size
  if [ -z "$agent_nums" ]; then
    etcdctl set /agent-nums $act_agent_size
  else
    etcdctl set /agent-nums $(($act_agent_size+$agent_nums))
    first=$(($agent_nums+1))
    last=$(($agent_nums+$act_agent_size))
  fi

  [ $act_agent_size -gt 1 ] && for i in $(seq $first $last); do
    amb-start-node $i
  done
}

_amb_run_shell() {
  COMMAND=$1
  : ${COMMAND:? required}
  get-ambari-server-ip
  EXPECTED_HOST_COUNT=$(docker inspect --format="{{.Config.Image}} {{.Name}}" $(docker ps -q)|grep $AMBARI_AGENT_IMAGE|grep $NODE_PREFIX|wc -l|xargs)
  run-command docker run -it --rm -e EXPECTED_HOST_COUNT=$EXPECTED_HOST_COUNT -e BLUEPRINT=$BLUEPRINT --link ${AMBARI_SERVER_NAME}:ambariserver \
     --entrypoint /bin/sh $AMBARI_SERVER_IMAGE -c $COMMAND
}

amb-shell() {
  _amb_run_shell /tmp/ambari-shell.sh
}

amb-deploy-cluster() {
  local act_cluster_size=$1
  : ${act_cluster_size:=$CLUSTER_SIZE}

  if [[ $# -gt 1 ]]; then
    BLUEPRINT=$2
  else
    [ $act_cluster_size -gt 1 ] && BLUEPRINT=multi-node-hdfs-yarn || BLUEPRINT=single-node-hdfs-yarn
  fi

  : ${BLUEPRINT:?" required (single-node-hdfs-yarn / multi-node-hdfs-yarn / hdp-singlenode-default / hdp-multinode-default)"}

  amb-start-cluster $act_cluster_size
  _amb_run_shell /tmp/install-cluster.sh
}

amb-get-consul-ip() {
  docker run --net $CALICO_NET --name $CONSUL -tid  busybox

  set-consul-ip

  get-consul-ip

  docker stop $CONSUL && docker rm $CONSUL
}

amb-publish-ambari-port() {
  iptables -A PREROUTING -t nat -i eth0 -p tcp --dport 8080 -j DNAT  --to ${AMBARI_SERVER_IP}:8080
  iptables -t nat -A OUTPUT -p tcp -o lo --dport 8080 -j DNAT --to-destination ${AMBARI_SERVER_IP}:8080
}


amb-start-consul() {
  local dns_port_command=""
  if [[ "$EXPOSE_DNS" == "true" ]]; then
     dns_port_command="-p 53:$DNS_PORT/udp"
  fi

  # 因为启动 consul 必须预先知道 IP所以先获得一个 ip
  echo "getting consul ip"
  amb-get-consul-ip

  # 运行 consul image
  # run-command docker run -d $dns_port_command --name $CONSUL -h $CONSUL.service.consul $CONSUL_IMAGE -server -bootstrap
  echo "starting consul container"
  run-command docker run -d $dns_port_command --net ${CALICO_NET} --ip $CONSUL_IP --name $CONSUL -h $CONSUL.service.consul $CONSUL_IMAGE -server -advertise $CONSUL_IP -bootstrap
}


amb-start-ambari-server() {
  # 运行 Ambari Server image
  # 暂时不添加 --dns=$CONSUL_IP
  echo "starting amb-server"
  run-command docker run -d $DOCKER_OPTS --net ${CALICO_NET} \
                     --privileged --name $AMBARI_SERVER_NAME -h $AMBARI_SERVER_NAME.service.consul $AMBARI_SERVER_IMAGE \
          systemd.setenv=NAMESERVER_ADDR=$CONSUL_IP

  set-ambari-server-ip

  get-ambari-server-ip

  amb-publish-ambari-port

  _consul-register-service $AMBARI_SERVER_NAME $AMBARI_SERVER_IP
  _consul-register-service ambari-8080 $AMBARI_SERVER_IP
}

# 启动 consul 服务和 amb-server 服务
# 这里为什么要用 consul 的dns port?
amb-start-first() {
  amb-start-consul

  sleep 5

  amb-start-ambari-server

  amb-start-HDP-httpd
}

amb-copy-to-hdfs() {
  get-ambari-server-ip
  FILE_PATH=${1:?"usage: <FILE_PATH> <NEW_FILE_NAME_ON_HDFS> <HDFS_PATH>"}
  FILE_NAME=${2:?"usage: <FILE_PATH> <NEW_FILE_NAME_ON_HDFS> <HDFS_PATH>"}
  DIR=${3:?"usage: <FILE_PATH> <NEW_FILE_NAME_ON_HDFS> <HDFS_PATH>"}
  amb-create-hdfs-dir $DIR
  DATANODE=$(curl -si -X PUT "http://$AMBARI_SERVER_IP:50070/webhdfs/v1$DIR/$FILE_NAME?user.name=hdfs&op=CREATE" |grep Location | sed "s/\..*//; s@.*http://@@")
  DATANODE_IP=$(get-host-ip $DATANODE)
  curl -T $FILE_PATH "http://$DATANODE_IP:50075/webhdfs/v1$DIR/$FILE_NAME?op=CREATE&user.name=hdfs&overwrite=true&namenoderpcaddress=$AMBARI_SERVER_IP:8020"
}

amb-create-hdfs-dir() {
  get-ambari-server-ip
  DIR=$1
  curl -X PUT "http://$AMBARI_SERVER_IP:50070/webhdfs/v1$DIR?user.name=hdfs&op=MKDIRS" > /dev/null 2>&1
}

amb-scp-to-first() {
  get-ambari-server-ip
  FILE_PATH=${1:?"usage: <FILE_PATH> <DESTINATION_PATH>"}
  DEST_PATH=${2:?"usage: <FILE_PATH> <DESTINATION_PATH>"}
  scp $FILE_PATH root@$AMBARI_SERVER_IP:$DEST_PATH
}

# 启动 amb agent 节点
amb-start-node() {
  get-ambari-server-ip
  get-consul-ip

  : ${AMBARI_SERVER_IP:?"AMBARI_SERVER_IP is needed"}
  : ${CONSUL_IP:?"CONSUL_IP is needed"}
  NUMBER=${1:?"please give a <NUMBER> parameter it will be used as node<NUMBER>"}
  if [[ $# -eq 1 ]]; then
    MORE_OPTIONS="-d"
  else
    shift
    MORE_OPTIONS="$@"
  fi


  run-command docker run $MORE_OPTIONS $DOCKER_OPTS --privileged --net ${CALICO_NET} --name ${NODE_PREFIX}$NUMBER -h ${NODE_PREFIX}${NUMBER}.service.consul $AMBARI_AGENT_IMAGE \
              systemd.setenv=NAMESERVER_ADDR=$CONSUL_IP

  set-host-ip ${NODE_PREFIX}$NUMBER

  _consul-register-service ${NODE_PREFIX}${NUMBER} $(get-host-ip ${NODE_PREFIX}$NUMBER)

  # 给agent 添加密码, 方便后续server设置免密码
  docker exec -it ${NODE_PREFIX}$NUMBER sh -c " echo Zasd_1234 | passwd root --stdin "

  # 修改 amb reopo url to HDP httpd service
  amb-replace-ambari-url ${NODE_PREFIX}$NUMBER
}

_consul-register-service() {
  docker run -it  --net ${CALICO_NET} --rm appropriate/curl sh -c "
    curl -X PUT -d \"{
        \\\"Node\\\": \\\"$1\\\",
        \\\"Address\\\": \\\"$2\\\",
        \\\"Service\\\": {
          \\\"Service\\\": \\\"$1\\\"
        }
      }\" http://$CONSUL_IP:8500/v1/catalog/register
  "
}


amb-start-HDP-httpd() {
  # build image
  docker build -t my/httpd:latest ./httpd
  # 这里需要先将 HDP, HDP-UTILS-1.1.0.20 (centos 7) 放到 ${HDP_HOST_DIR}, 提供httpd访问
  # TODO: 必须检查配置路径的有效性
  docker run --net ${CALICO_NET} --privileged=true  -itd --name $HTTPD_NAME -v ${HDP_HOST_DIR}:/usr/local/apache2/htdocs/ $HTTPD_IMAGE

  set-host-ip $HTTPD_NAME
}

amb-replace-ambari-url() {
  local NODE_NAME=$1

  local httpd_ip=$(get-host-ip $HTTPD_NAME)
  local baseurl=http://${httpd_ip}/ambari/centos7/2.4.0.1-1/
  local gpgkey=http://${httpd_ip}/ambari/centos7/2.4.0.1-1/RPM-GPG-KEY/RPM-GPG-KEY-Jenkins

  docker exec -it $NODE_NAME  sh -c "sed -i 's/baseurl=.*/baseurl=${baseurl//\//\\/}/g' /etc/yum.repos.d/ambari.repo"
  docker exec -it $NODE_NAME  sh -c "sed -i 's/gpgkey=.*/gpgkey=${gpgkey//\//\\/}/g' /etc/yum.repos.d/ambari.repo"

  docker exec -it $NODE_NAME  sh -c "cat /etc/yum.repos.d/ambari.repo"
}


amb-tool-get-server-sshkey() {
  docker exec -it ${AMBARI_SERVER_NAME}  sh -c "cat ~/.ssh/id_rsa"
}

amb-tool-get-agent-host-list() {
  local agent_list=$(etcdctl ls /ips | grep amb'[0-9]' | tr -d "/ips/")
  for i in $agent_list; do
    echo "${i}.service.consul"
  done
}

amb-tool-get-HDP-url() {
  local httpd_ip=$(get-host-ip $HTTPD_NAME)
  echo "http://${httpd_ip}/HDP/centos7/2.x/updates/2.4.0.0"
  echo "http://${httpd_ip}/HDP-UTILS-1.1.0.20/repos/centos7"
}


