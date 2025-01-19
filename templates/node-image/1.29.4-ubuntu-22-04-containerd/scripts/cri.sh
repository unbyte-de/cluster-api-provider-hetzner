#!/bin/bash

# Copyright 2022 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

echo '--> Starting CRI Script.'
# Prerequisites
cat <<'EOF' | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Setting up sysctl properties
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
echo fs.inotify.max_user_instances=8192 | sudo tee -a /etc/sysctl.conf
echo vm.max_map_count=524288 | sudo tee -a /etc/sysctl.conf

# Set up required sysctl params, these persist across reboots.
cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Required by protectedKernelDefaults=true
cat >/etc/sysctl.d/99-kubelet.conf <<'EOF'
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
EOF

# Apply sysctl params without reboot
sysctl --system

# Install containerd
wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD}/cri-containerd-cni-${CONTAINERD}-linux-${PACKER_ARCH}.tar.gz
wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD}/cri-containerd-cni-${CONTAINERD}-linux-${PACKER_ARCH}.tar.gz.sha256sum
sha256sum --check cri-containerd-cni-${CONTAINERD}-linux-${PACKER_ARCH}.tar.gz.sha256sum
tar --no-overwrite-dir -C / -xzf cri-containerd-cni-${CONTAINERD}-linux-${PACKER_ARCH}.tar.gz

# Cleanup
rm -f cri-containerd-cni-${CONTAINERD}-linux-${PACKER_ARCH}.tar.gz cri-containerd-cni-${CONTAINERD}-linux-${PACKER_ARCH}.tar.gz.sha256sum

# Sets permission accordingly to CIS Benchmark
chmod -R 644 /etc/cni
chown -R root:root /etc/cni

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i "s/SystemdCgroup = false/SystemdCgroup = true/" /etc/containerd/config.toml

sed -i "s|config_path = \"\"|config_path = \"/etc/containerd/certs.d\"|" /etc/containerd/config.toml
mkdir -p /etc/containerd/certs.d

mkdir -p /etc/containerd/certs.d/docker.io
cat >/etc/containerd/certs.d/docker.io/hosts.toml <<EOL
server = "https://docker.io"

[host."http://harbor.devops1.pbm.sh/v2/proxy-docker.io"]
  capabilities = ["pull", "resolve"]
  override_path = true
EOL

mkdir -p /etc/containerd/certs.d/gcr.io
cat >/etc/containerd/certs.d/gcr.io/hosts.toml <<EOL
server = "https://gcr.io"

[host."http://harbor.devops1.pbm.sh/v2/proxy-gcr.io"]
  capabilities = ["pull", "resolve"]
  override_path = true
EOL

mkdir -p /etc/containerd/certs.d/ghcr.io
cat >/etc/containerd/certs.d/ghcr.io/hosts.toml <<EOL
server = "https://ghcr.io"

[host."http://harbor.devops1.pbm.sh/v2/proxy-ghcr.io"]
  capabilities = ["pull", "resolve"]
  override_path = true
EOL

mkdir -p /etc/containerd/certs.d/quay.io
cat >/etc/containerd/certs.d/quay.io/hosts.toml <<EOL
server = "https://quay.io"

[host."http://harbor.devops1.pbm.sh/v2/proxy-quay.io"]
  capabilities = ["pull", "resolve"]
  override_path = true
EOL

mkdir -p /etc/containerd/certs.d/registry.k8s.io
cat >/etc/containerd/certs.d/registry.k8s.io/hosts.toml <<EOL
server = "https://registry.k8s.io"

[host."http://harbor.devops1.pbm.sh/v2/proxy-registry.k8s.io"]
  capabilities = ["pull", "resolve"]
  override_path = true
EOL

mkdir -p /etc/containerd/certs.d/registry.gitlab.com
cat >/etc/containerd/certs.d/registry.gitlab.com/hosts.toml <<EOL
server = "https://registry.gitlab.com"

[host."http://harbor.devops1.pbm.sh/v2/proxy-registry.gitlab.com"]
  capabilities = ["pull", "resolve"]
  override_path = true
EOL

# enable systemd service after next boot
systemctl daemon-reload
systemctl enable containerd
systemctl start containerd
