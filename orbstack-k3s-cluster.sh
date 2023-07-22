#!/bin/zsh

set -ux

distro="alma"
saveConfigPath="$HOME/.kube/k3s.yaml"
clusterIpPath="$HOME/.kube/cluster-ip.yaml"

serveToken=12345
k3sUrl="https://get.k3s.io"

server1Script="curl -sfL $k3sUrl | K3S_TOKEN=$serveToken K3S_KUBECONFIG_MODE=644 sh -s - server --cluster-init"
serverNScript="curl -sfL $k3sUrl | K3S_TOKEN=$serveToken K3S_KUBECONFIG_MODE=644 sh -s - server --server https://127.0.0.1:6443"
clientsScript="curl -sfL $k3sUrl | K3S_TOKEN=$serveToken K3S_KUBECONFIG_MODE=644 sh -s - agent  --server https://127.0.0.1:6443"
clusterIp=""

serverScripts=(
  "sudo yum install vim -y"
  "sudo yum install haproxy keepalived rsyslog -y"
)

clientScripts=(
  "sudo yum install vim -y"
  "sudo mkdir -p /data/longhorn-storage"
  "sudo yum -y install iscsi-initiator-utils"
)

createMasters() {
  machineNames=("$@")
  for index in "${!machineNames[@]}"; do
    machineName="${machineNames[$index]}"
    orbctl create "$distro" "$machineName"

    if [[ index -eq 0 ]]; then
      orbctl run -m "$machineName" /bin/sh -c "$server1Script"
    else
      orbctl run -m "$machineName" /bin/sh -c "$serverNScript"
    fi

    for serverScript in "${serverScripts[@]}"; do
      orbctl run -m "$machineName" /bin/sh -c "$serverScript"
    done

    ipAddress=$(orbctl run -m "$machineName" /bin/sh -c "hostname -I | awk '{print \$1}'")
    clusterIp="$clusterIp$machineName: $ipAddress\n"

    if [[ index -eq 0 ]]; then
      clientsScript="${clientsScript/127.0.0.1/$ipAddress}"
      serverNScript="${serverNScript/127.0.0.1/$ipAddress}"
      k3sYaml=$(orbctl run -m "$machineName" cat /etc/rancher/k3s/k3s.yaml | sed "s/127.0.0.1/$ipAddress/")
    fi

  done
}

createWorkers() {
  machineNames=("$@")
  for machineName in "${machineNames[@]}"; do
    orbctl create "$distro" "$machineName"
    orbctl run -m "$machineName" /bin/sh -c "$clientsScript"

    for clientScript in "${clientScripts[@]}"; do
      orbctl run -m "$machineName" /bin/sh -c "$clientScript"
    done

    ipAddress=$(orbctl run -m "$machineName" /bin/sh -c "hostname -I | awk '{print \$1}'")
    clusterIp="$clusterIp$machineName: $ipAddress\n"
  done
}

run() {
  createMasters "k3s-master1" "k3s-master2"
  createWorkers "k3s-worker1" "k3s-worker2" "k3s-worker3"
  echo "$k3sYaml" >"$saveConfigPath"
  echo "$clusterIp" >"$clusterIpPath"
}

run
