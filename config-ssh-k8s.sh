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

_kubectl(){
    kubectl --namespace=ambari "$@"
}

_get_amb_server_name(){
    _kubectl get pod -o wide | grep ambari-server | awk '{print $1}'
}

_get_amb_agents_name(){
    _kubectl get pod -o wide | grep amb-agent | awk '{print $1}'
}

_get_amb_agents_ip(){
    _kubectl get pod -o wide | grep amb-agent | awk '{print $6}'
}

_run_amb_server_sh(){
    local ambari_server_name=$(_get_amb_server_name)
    run_command _kubectl exec $ambari_server_name -c ambari-server -- "$@"
}

_amb_copy_ssh_to_agent(){
    local host_name=${1:?"Usage: _amb_copy_ssh_to_agent <host_name> <server-name> "}
    _run_amb_server_sh sh -c "ssh-keyscan $host_name >> ~/.ssh/known_hosts"
    _run_amb_server_sh sh -c "sshpass -p Zasd_1234 ssh-copy-id root@${host_name}"
}

config_master(){
    _run_amb_server_sh sh -c "echo -e  'y\n'|ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa"

    for i in $(amb_tool_get_agent_host_list); do
        run_command _amb_copy_ssh_to_agent $i
    done

    _run_amb_server_sh sh -c "sort -u ~/.ssh/known_hosts > ~/.ssh/tmp_hosts"
    _run_amb_server_sh sh -c "mv ~/.ssh/tmp_hosts ~/.ssh/known_hosts"
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
  run_command _kubectl exec $agent_name -c amb-agent -- sh -c "echo Zasd_1234 | passwd root --stdin"
  run_command _kubectl exec $agent_name -c amb-agent -- sh -c "systemctl restart ntpd"
}

amb_tool_get_server_sshkey() {
  run_command _kubectl exec $(_get_amb_server_name) -c ambari-server -- sh -c "cat ~/.ssh/id_rsa"
}

amb_tool_get_agent_host_list() {
    for i in $(_get_amb_agents_ip); do
        echo "${i//./-}.ambari.pod.cluster.local"
    done
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