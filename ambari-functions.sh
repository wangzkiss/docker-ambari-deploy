#!/usr/bin/bash

# import common variable
. ./env.sh

: ${AMBARI_SERVER_NAME:=${NODE_PREFIX}-server}
: ${AMBARI_SERVER_IMAGE:="registry.cn-hangzhou.aliyuncs.com/tospur/amb-server:latest"}
: ${AMBARI_AGENT_IMAGE:="registry.cn-hangzhou.aliyuncs.com/tospur/amb-agent:latest"}
: ${HTTPD_IMAGE:="registry.cn-hangzhou.aliyuncs.com/tospur/httpd:latest"}
: ${HTTPD_NAME:=httpd}
: ${MYSQL_SERVER_NAME:=mysql}
: ${MYSQL_PASSWD:=123456}
: ${DOCKER_OPTS:=""}
: ${CONSUL_IMAGE:="sequenceiq/consul:v0.5.0-v6"}

: ${SLEEP_TIME:=2}
: ${DNS_PORT:=53}
: ${EXPOSE_DNS:=false}

: ${PULL_IMAGE:=false}

amb-settings() {
  cat <<EOF
  NODE_PREFIX=$NODE_PREFIX
  AMBARI_SERVER_NAME=$AMBARI_SERVER_NAME
  AMBARI_SERVER_IMAGE=$AMBARI_SERVER_IMAGE
  AMBARI_AGENT_IMAGE=$AMBARI_AGENT_IMAGE
  HTTPD_IMAGE=$HTTPD_IMAGE
  DOCKER_OPTS=$DOCKER_OPTS
  AMBARI_SERVER_IP=$(get-ambari-server-ip)
  CONSUL_IP=$(get-consul-ip)
  CONSUL=$CONSUL
  CONSUL_IMAGE=$CONSUL_IMAGE
  EXPOSE_DNS=$EXPOSE_DNS
  CALICO_NET=$CALICO_NET
  HDP_PKG_DIR=$HDP_PKG_DIR
  HTTPD_NAME=$HTTPD_NAME
EOF
}

amb-clean() {
  unset NODE_PREFIX AMBARI_SERVER_NAME AMBARI_SERVER_IMAGE AMBARI_AGENT_IMAGE HTTPD_IMAGE CONSUL \
        CONSUL_IMAGE DEBUG SLEEP_TIME EXPOSE_DNS \
        CALICO_NET HDP_PKG_DIR HTTPD_NAME
}

get-ambari-server-ip() {
  get-host-ip ${AMBARI_SERVER_NAME}
}

amb-members() {
  local consul_ip=$(get-consul-ip)
  docker run  --net ${CALICO_NET} --rm appropriate/curl sh -c "curl http://$consul_ip:8500/v1/catalog/nodes"
}

amb-start-agent() {
  local act_agent_size=${1:?"Usage:amb-start-agent <AGENT_NUM>"}
  local agent_nums=$(_etcdctl get /agent-nums)
  local first=1
  local last=$act_agent_size
  debug "amb-start-agent running ......................"
  if [ -z "$agent_nums" ]; then
    _etcdctl set /agent-nums $act_agent_size
  else
    _etcdctl set /agent-nums $(($act_agent_size+$agent_nums))
    first=$(($agent_nums+1))
    last=$(($agent_nums+$act_agent_size))
  fi

  local ip_list=$(amb-get-unusage-ip $act_agent_size)
  IFS=', ' read -r -a array <<< "$ip_list"

  if [ $act_agent_size -ge 1 ]; then
    local count=0
    for i in $(seq $first $last); do
      amb-start-node $i ${array[$count]}
      ((count+=1))
    done
  fi
}

amb-publish-port() {
  local port=${1:?"amb-publish-port <port> <des_ip>"}
  local des_ip=${2:?"amb-publish-port <port> <des_ip>"}
  firewall-cmd --zone=public --add-port=$port/tcp --permanent
  firewall-cmd --reload

  iptables -A PREROUTING -t nat -i eth0 -p tcp --dport $port -j DNAT  --to ${des_ip}:$port
  iptables -t nat -A OUTPUT -p tcp -o lo --dport $port -j DNAT --to-destination ${des_ip}:$port
  # TODO: need to save, in case of firewall-cmd --reload lost the dnat rules
}

amb-start-consul() {
  local local_ip=${1:?"Usage: amb-start-consul <ip>"}
  local dns_port_command=""
  if [[ "$EXPOSE_DNS" == "true" ]]; then
     dns_port_command="-p 53:$DNS_PORT/udp"
  fi
  debug "starting consul container"
  run-command docker run -d $dns_port_command --net ${CALICO_NET} --ip $local_ip --name $CONSUL \
              -h $CONSUL.service.consul $CONSUL_IMAGE -server -advertise $local_ip -bootstrap
  set-host-ip $CONSUL $local_ip
}

amb-start-ambari-server() {
  local local_ip=${1:?"Usage: amb-start-ambari-server <ip>"}

  local consul_ip=$(get-consul-ip)
  if [[ "$PULL_IMAGE" == "true" ]]; then
    debug "pulling image"
    docker pull $AMBARI_SERVER_IMAGE
  fi
  # remove log dir
  rm -rf $HADOOP_LOG/$AMBARI_SERVER_NAME
  debug "starting amb-server"
  run-command docker run -d $DOCKER_OPTS --net ${CALICO_NET} --ip $local_ip \
              --privileged --name $AMBARI_SERVER_NAME \
              -v $HADOOP_LOG/$AMBARI_SERVER_NAME:/var/log \
              -h $AMBARI_SERVER_NAME.service.consul $AMBARI_SERVER_IMAGE \
              systemd.setenv=NAMESERVER_ADDR=$consul_ip

  set-host-ip $AMBARI_SERVER_NAME $local_ip
  local ambari_server_ip=$(get-ambari-server-ip)
  # publish ambari 8080 port
  amb-publish-port 8080 $ambari_server_ip

  run-command consul-register-service $AMBARI_SERVER_NAME $ambari_server_ip
  run-command consul-register-service ambari-8080 $ambari_server_ip
}

amb-start-mysql() {
  local local_ip=${1:?"Usage: amb-start-mysql <ip>"}
  run-command docker run --net ${CALICO_NET} --ip $local_ip --name $MYSQL_SERVER_NAME -e MYSQL_ROOT_PASSWORD=$MYSQL_PASSWD -d mysql
  set-host-ip $MYSQL_SERVER_NAME $local_ip
  run-command consul-register-service $MYSQL_SERVER_NAME $(get-host-ip $MYSQL_SERVER_NAME)
}

amb-start-server() {
  # get unusage ips
  local ip_list=$(amb-get-unusage-ip 4)
  IFS=', ' read -r -a array <<< "$ip_list"

  amb-start-consul ${array[0]}
  sleep $SLEEP_TIME
  amb-start-mysql ${array[1]}
  sleep $SLEEP_TIME
  amb-start-ambari-server ${array[2]}
  sleep $SLEEP_TIME
  amb-start-HDP-httpd ${array[3]}
  debug "replacing ambari.repo url"
  # agent register will copy ambari.repo from server
  amb-replace-ambari-url $AMBARI_SERVER_NAME
}

amb-start-node() {
  local number=${1:?"Usage: amb-start-node <node_num> <ip>"}
  local local_ip=${2:?"Usage: amb-start-node <node_num> <ip>"}
  local consul_ip=$(get-consul-ip)
  local node_name=${NODE_PREFIX}$number
  debug "amb-start-node running ................."

  if [[ "$PULL_IMAGE" == "true" ]]; then
    debug "pulling image"
    docker pull $AMBARI_AGENT_IMAGE
  fi

  # Remove data && log dir before node start
  rm -rf $HADOOP_DATA/${node_name} && rm -rf $HADOOP_LOG/${node_name}

  run-command docker run -d $DOCKER_OPTS --privileged --net ${CALICO_NET} --ip $local_ip --name $node_name \
              -v $HADOOP_DATA/${node_name}:/hadoop -v $HADOOP_LOG/${node_name}:/var/log \
              -h ${node_name}.service.consul $AMBARI_AGENT_IMAGE \
              systemd.setenv=NAMESERVER_ADDR=$consul_ip

  set-host-ip $node_name $local_ip
  run-command consul-register-service $node_name $(get-host-ip $node_name)

  _amb-start-node-service $node_name
}

_amb-start-node-service() {
  local node_name=${1:?"Usage: amb-start-node-service <node_name>"}
  # set password to agent, for server ssh
  docker exec $node_name sh -c " echo Zasd_1234 | passwd root --stdin "
  docker exec $node_name sh -c " systemctl restart ntpd "
}

amb-start-HDP-httpd() {
  local local_ip=${1:?"Usage: amb-start-HDP-httpd <ip>"}
  # 这里需要先将 HDP, HDP-UTILS-1.1.0.20 (centos 7) 放到 ${HDP_PKG_DIR}, 提供httpd访问
  run-command docker run --net ${CALICO_NET} --ip $local_ip --privileged=true -d --name $HTTPD_NAME -v ${HDP_PKG_DIR}:/usr/local/apache2/htdocs/ $HTTPD_IMAGE

  set-host-ip $HTTPD_NAME $local_ip
}

amb-replace-ambari-url() {
  local NODE_NAME=$1
  local httpd_ip=$(get-host-ip $HTTPD_NAME)
  local baseurl=http://${httpd_ip}/AMBARI-2.4.0.1/centos7/2.4.0.1-1/
  local gpgkey=http://${httpd_ip}/AMBARI-2.4.0.1/centos7/2.4.0.1-1/RPM-GPG-KEY/RPM-GPG-KEY-Jenkins

  docker exec $NODE_NAME sh -c "sed -i 's/baseurl=.*/baseurl=${baseurl//\//\\/}/g' /etc/yum.repos.d/ambari.repo"
  docker exec $NODE_NAME sh -c "sed -i 's/gpgkey=.*/gpgkey=${gpgkey//\//\\/}/g' /etc/yum.repos.d/ambari.repo"
  docker exec $NODE_NAME sh -c "cat /etc/yum.repos.d/ambari.repo"
}

amb-tool-get-server-sshkey() {
  docker exec ${AMBARI_SERVER_NAME}  sh -c "cat ~/.ssh/id_rsa"
}

amb-tool-get-agent-host-list() {
  local agent_list=$(_etcdctl ls /ips | egrep "amb[0-9]+" | tr -d "/ips/")
  for i in $agent_list; do
    echo "${i}.service.consul"
  done
}

amb-tool-get-HDP-url() {
  local httpd_ip=$(get-host-ip $HTTPD_NAME)
  echo "http://${httpd_ip}/HDP/centos7/2.x/updates/2.4.0.0"
  echo "http://${httpd_ip}/HDP-UTILS-1.1.0.20/repos/centos7"
}

amb-tool-get-all-setting() {
  debug "=============HDP url============="
  amb-tool-get-HDP-url
  debug "=============agent host list============="
  amb-tool-get-agent-host-list
  debug "=============server sshkey============="
  amb-tool-get-server-sshkey
  debug "=========================="
}

_check-input() {
    read -p "Please input HDP, HDP-UTIL package path, default:$HDP_PKG_DIR, input:" INPUT
    if [ "$INPUT" != "" ];then
        HDP_PKG_DIR=$INPUT
    fi
    if [ ! -d "$HDP_PKG_DIR" ];then
      echo "$HDP_PKG_DIR doesn't exist"
      exit
    fi
    sed -i "s/HDP_PKG_DIR=\(.*\)/HDP_PKG_DIR=${HDP_PKG_DIR//\//\\/}/g" $ENV_FILE
    echo $HDP_PKG_DIR
    read -p "Please input Hadoop data storage dir, default:$HADOOP_DATA, input:" INPUT
    if [ "$INPUT" != "" ];then
        HADOOP_DATA=$INPUT
    fi
    sed -i "s/HADOOP_DATA=\(.*\)/HADOOP_DATA=${HADOOP_DATA//\//\\/}/g" $ENV_FILE
    echo $HADOOP_DATA
    read -p "Please input Hadoop log dir, default:$HADOOP_LOG, input:" INPUT
    if [ "$INPUT" != "" ];then
        HADOOP_LOG=$INPUT
    fi
    sed -i "s/HADOOP_LOG=\(.*\)/HADOOP_LOG=${HADOOP_LOG//\//\\/}/g" $ENV_FILE
    echo $HADOOP_LOG
}

_amb-config-mysql-driver(){
  docker exec $AMBARI_SERVER_NAME sh -c "ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar"
}

_amb-config-nameserver() {
  # server can get the Internet
  local nameserver=$(docker exec $CONSUL  sh -c "sed -n '/.*nameserver.*/p' /etc/resolv.conf")
  docker exec $AMBARI_SERVER_NAME  sh -c "echo '$nameserver' >> /etc/resolv.conf"
  docker exec $AMBARI_SERVER_NAME  sh -c "cat /etc/resolv.conf"
}

_amb-copy-ssh-to-agent(){
  local node_name=${1:?"Usage: _amb-copy-ssh-to-agent <node_name> "}
  local host_name="$node_name.service.consul"
  docker exec $AMBARI_SERVER_NAME  sh -c "ssh-keyscan $host_name >> ~/.ssh/known_hosts"
  docker exec $AMBARI_SERVER_NAME  sh -c "sshpass -p Zasd_1234 ssh-copy-id root@${host_name}"
}

_amb-server-to-agents-passwdless() {
  local agent_list=$(_etcdctl ls /ips | egrep "amb[0-9]+" | awk -F / '{print $3}')
  for node_name in $agent_list; do
    _amb-copy-ssh-to-agent $node_name
  done
  # unique known_hosts
  docker exec $AMBARI_SERVER_NAME  sh -c "sort -u ~/.ssh/known_hosts > ~/.ssh/tmp_hosts"
  docker exec $AMBARI_SERVER_NAME  sh -c "mv ~/.ssh/tmp_hosts ~/.ssh/known_hosts"
}

_amb-server-ssh-keygen(){
  docker exec $AMBARI_SERVER_NAME  sh -c "echo -e  'y\n'|ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa"
}

_amb-start-services-after-server-started(){
  _amb-config-nameserver
  _amb-server-ssh-keygen
  _amb-server-to-agents-passwdless
  # config hive connect exist mysql
  _amb-config-mysql-driver
}

# 启动集群
amb-start-cluster() {
  local agents_per_host=${1:?"usage: AGENTS_PER_HOST"}
  local first_host=$(_get-first-host)

  _check-input

  debug "First clean cluster ......"
  amb-clean-cluster

  debug "Now starting the cluster ......"
  _copy_this_sh

  amb-start-server
  sleep $SLEEP_TIME
  for host in ${HOST_LIST//,/ }; do
    pdsh -w $host bash $SH_FILE_PATH/$0 amb-start-agent $agents_per_host
  done

  sleep $SLEEP_TIME
  _amb-start-services-after-server-started

  debug "test ambari started "
  amb-test-amb-server-start
  
  debug "print Ambari config settings"
  amb-tool-get-all-setting
}

amb-clean-agent() {
  docker stop $(docker ps -a -q -f "name=${NODE_PREFIX}*")
  docker rm -v $(docker ps -a -q -f "name=${NODE_PREFIX}*")
}

amb-clean-server() {
  docker stop $AMBARI_SERVER_NAME $CONSUL $HTTPD_NAME $MYSQL_SERVER_NAME
  docker rm -v $AMBARI_SERVER_NAME $CONSUL $HTTPD_NAME $MYSQL_SERVER_NAME

  amb-clean-etcd
}

amb-clean-etcd() {
  _etcdctl rm /agent-nums

  local agent_list=$(_etcdctl ls /ips | egrep "amb[0-9]+")
  for i in $agent_list; do
    _etcdctl rm $i 
  done
}

amb-clean-cluster() {
  local count=0
  _copy_this_sh

  for host in ${HOST_LIST//,/ }
  do
    if [ $count -eq 0 ];then
      pdsh -w $host bash $SH_FILE_PATH/$0 amb-clean-server
    fi

    pdsh -w $host bash $SH_FILE_PATH/$0 amb-clean-agent
    ((count+=1))
  done
}

amb-test-amb-server-start() {
  local ambari_server_ip=$(get-ambari-server-ip)

  while [ 1 -eq 1 ]; do
    if curl ${ambari_server_ip}:8080; then
      break
    else
      sleep $SLEEP_TIME
    fi
  done
}

amb-get-agent-stay-host(){
  local input_num=${1:?"amb-get-agent-stay-host <number>"}
  local agent_nums=$(_etcdctl get /agent-nums)
  local host_num=$(awk '{print NF}' <<< "${HOST_LIST//,/ }")
  local each_host_agents=$((agent_nums/host_num))
  local first=$(($input_num/$each_host_agents))
  local last=$(($input_num%$each_host_agents))

  local index=$first
  if [ $last -gt 0 ]; then
    index=$(($index+1))
  fi
  awk -v var=$index '{print $var}' <<< "${HOST_LIST//,/ }"
}

_get-local-amb-node-name() {
  docker ps --format '{{.Names}}' | egrep "amb[0-9]+" | head -n 1
}

amb-publish-hadoop-port(){
  # /ips/amb1
  local port=${1:?"Usage:amb-publish-port <port number>"}
  local agent_list=$(_etcdctl ls /ips | egrep "amb[0-9]+" | awk -F / '{print $3}')
  local amb_stay_host=""
  local amb_stay_host_ip=""

  local amb_node_name=$(_get-local-amb-node-name)

  for i in $agent_list; do
    local host_name="$i.service.consul"
    # server node must have ${NODE_PREFIX}1 amb-agent
    if docker exec $amb_node_name  sh -c "nc -w 2 -v ${host_name} $port < /dev/null"; then
      echo "$host_name have $port hive server port"
      amb_stay_host=$i
      amb_stay_host_ip=$(get-host-ip $amb_stay_host)
      break
    fi
  done

  local locate_host=$(amb-get-agent-stay-host ${amb_stay_host: -1})
  echo "located host: $locate_host"

  _etcdctl set /hadoop/open_ports/$port "${amb_stay_host}-${amb_stay_host_ip}" 

  pdsh -w $locate_host bash $SH_FILE_PATH/$0 amb-publish-port $port ${amb_stay_host_ip}
}

amb-publish-hadoop-ports() {
  local first_host=$(_get-first-host)
  _copy_this_sh

  # clean all port dnat
  pdsh -w $HOST_LIST firewall-cmd --reload

  # republish ambari 8080 port
  local ambari_server_ip=$(get-ambari-server-ip)
  amb-publish-port 8080 $ambari_server_ip

  # hive jdbc port 10000
  amb-publish-hadoop-port 10000
}

# ambari install have error
amb-install-hbase() {
  local amb_node_name=$(_get-local-amb-node-name)
  docker exec $amb_node_name  sh -c "su hdfs -c \"hadoop fs -rm -r -f /apps/hbase/\""
  # TODO: add Hbase service use api
  # docker exec $AMBARI_SERVER_NAME \
  #   sh -c "curl -u admin:admin -i -X POST -d '{\"ServiceInfo\":{\"service_name\":\"HBASE\"}}' http://localhost:8080/api/v1/clusters/test/services"
}

amb-get-unusage-ip(){
  local ip_nums=${1:?"Usage: amb-get-unusage-ip <ip_nums>"}
  # Get docker net usaging ip
  local network_usage_ips=$(docker network inspect --format "{{range .Containers}}{{.IPv4Address}} {{end}}" $CALICO_NET \
    | tr " " \\n \
    | grep -v '^$' \
    | awk -F "/" '{printf " -e %s", $1}')

  # get current etcd store usaging ips
  local etcd_host=$(_get-etcd-ip-list etcd | sed "s/etcd/http/g")
  local etcd_usage_ips=$(curl -s -L $etcd_host/v2/keys/ips \
    | jq ".node.nodes[].value" \
    | tr -d '"' \
    | awk '{printf " -e %s", $1}')

  local ip_range=$(ipcalc -b $CALICO_CIDR | awk -F = '{print $2}' | sed "s/255/{1..254}/g")

  eval "echo $ip_range" | tr " " \\n | grep -v $network_usage_ips $etcd_usage_ips | sort -R | head -n $ip_nums | paste -sd ','
}

amb-add-new-agent(){
  local host=${1:?"Usage: amb-add-new-agent <host> <amb-agent-num>"}
  local agent_num=${2:?"Usage: amb-add-new-agent <host> <amb-agent-num>"}

  local first_host=$(_get-first-host)
  _copy_this_sh $host

  pdsh -w $host bash $SH_FILE_PATH/$0 amb-start-agent $agent_num
  _amb-server-to-agents-passwdless
}

# call arguments verbatim:
$@