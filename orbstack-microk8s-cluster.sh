#!/bin/zsh

set -ux

distro="alma"
saveConfigPath="$HOME/.kube/microk8s.yaml"
clusterIpPath="$HOME/.kube/cluster-ip.yaml"

serveToken=12345
k3sUrl="https://get.k3s.io"

server1Scripts=(
  "sudo dnf install epel-release -y"
  "sudo dnf upgrade -y"
  "sudo dnf install snapd -y"
  "sudo systemctl enable --now snapd.socket"
  "sudo ln -s /var/lib/snapd/snap /snap"
  "sudo snap install microk8s --classic --channel=1.27"
  "sudo usermod -a -G microk8s \$USER"
  "sudo chown -f -R \$USER ~/.kube"
)

serverNScript="curl -sfL $k3sUrl | K3S_TOKEN=$serveToken K3S_KUBECONFIG_MODE=644 sh -s - server --server https://127.0.0.1:6443"
clientsScript="curl -sfL $k3sUrl | K3S_TOKEN=$serveToken K3S_KUBECONFIG_MODE=644 sh -s - agent  --server https://127.0.0.1:6443"
clusterIp=""

createMasters() {
  machineNames=("$@")
  isFirstMaster=1
  for machineName in "${machineNames[@]}"; do
    orbctl create "$distro" "$machineName"

    if [[ isFirstMaster -eq 1 ]]; then
      for server1Scripts in "${server1Scripts[@]}"; do
        orbctl run -m "$machineName" /bin/sh -c "$server1Scripts"
      done
    else
      orbctl run -m "$machineName" /bin/sh -c "$serverNScript"
    fi

    ipAddress=$(orbctl run -m "$machineName" /bin/sh -c "hostname -I | awk '{print \$1}'")
    clusterIp="$clusterIp$machineName: $ipAddress\n"

    if [[ isFirstMaster -eq 1 ]]; then
      ipAddress=$(orbctl run -m "$machineName" /bin/sh -c "hostname -I | awk '{print \$1}'")
      clientsScript="${clientsScript/127.0.0.1/$ipAddress}"
      serverNScript="${serverNScript/127.0.0.1/$ipAddress}"
      k3sYaml=$(orbctl run -m "$machineName" cat /etc/rancher/k3s/k3s.yaml | sed "s/127.0.0.1/$ipAddress/")
    fi

    isFirstMaster=0
  done
}

createWorkers() {
  machineNames=("$@")
  for machineName in "${machineNames[@]}"; do
    orbctl create "$distro" "$machineName"
    orbctl run -m "$machineName" /bin/sh -c "$clientsScript"

    ipAddress=$(orbctl run -m "$machineName" /bin/sh -c "hostname -I | awk '{print \$1}'")
    clusterIp="$clusterIp$machineName: $ipAddress\n"

    orbctl run -m "$machineName" /bin/sh -c "sudo mkdir -p /data/longhorn-storage"
    orbctl run -m "$machineName" /bin/sh -c "sudo yum -y install iscsi-initiator-utils"
  done
}

run() {
  createMasters "microk8s-master1"
  #createWorkers "k3s-worker1" "k3s-worker2" "k3s-worker3"
  echo "$k3sYaml" >"$saveConfigPath"
  echo "$clusterIp" >"$clusterIpPath"
}

run
