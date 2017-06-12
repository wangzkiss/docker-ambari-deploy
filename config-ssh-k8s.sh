#!/bin/bash
: ${DEBUG:=1}
: ${DRY_RUN:=false}

debug() {
  [ ${DEBUG} -gt 0 ] && echo "[DEBUG] $@" 1>&2
}

run_command() {
  CMD="$@"
  if [[ "$DRY_RUN" == "false" ]]; then
    debug "$CMD"
    "$@"
  else
    debug [DRY_RUN] "$CMD"
  fi
}

_get_amb_server_name(){
    kubectl get pod --namespace=ambari -o wide | grep ambari-server | awk '{print $1}'
}

_get_amb_agents_name(){
    kubectl get pod --namespace=ambari -o wide | grep amb-agent | awk '{print $1}'
}

_get_amb_agents_ip(){
    kubectl get pod --namespace=ambari -o wide | grep amb-agent | awk '{print $6}'
}

_amb_server_ssh_keygen(){
    
}

_amb_copy_ssh_to_agent(){
    local host_name=${1:?"Usage: _amb_copy_ssh_to_agent <host_name> <server-name> "}
    local ambari_server_name=${2:?"Usage: _amb_copy_ssh_to_agent <host_name> <server-name>"}
    run_command kubectl exec $ambari_server_name  sh -c "ssh-keyscan $host_name >> ~/.ssh/known_hosts"
    run_command kubectl exec $ambari_server_name  sh -c "sshpass -p Zasd_1234 ssh-copy-id root@${host_name}"
}

config_master(){
    local ambari_server_name=$(_get_amb_server_name)
    run_command kubectl exec $ambari_server_name  sh -c "echo -e  'y\n'|ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa"

    for i in $(_get_amb_agents_ip); do
        run_command _amb_copy_ssh_to_agent $i $ambari_server_name
    done
}

config_agents(){
    local agents_name=$(_get_amb_agents_name)
    for i in $agents_name; do
        run_command _amb_start_agent_service $i
    done
}

_amb_start_agent_service() {
  local agent_name=${1:?"Usage: _amb_start_agent_service <agent_name>"}
  # set password to agent, for server ssh
  run_command kubectl exec $agent_name sh -c " echo Zasd_1234 | passwd root --stdin "
  run_command kubectl exec $agent_name sh -c " systemctl restart ntpd "
}

amb_tool_get_server_sshkey() {
  kubectl exec $(_get_amb_server_name)  sh -c "cat ~/.ssh/id_rsa"
}

amb_tool_get_agent_host_list() {
    _get_amb_agents_ip
}

amb_tool_get_all_setting() {
  debug "=============HDP url============="
  # amb_tool_get_HDP_url
  debug "=============agent host list============="
  amb_tool_get_agent_host_list
  debug "=============server sshkey============="
  amb_tool_get_server_sshkey
  debug "=========================="
}

main(){
    config_agents
    config_master
    amb_tool_get_all_setting
}

$@