#!/bin/bash
set -eux

# Add supporting software
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install apt-transport-https atop ca-certificates curl gpg lsb-release sudo
# Do not upgrade as triggers connection problems
# apt-get -y upgrade

## Monitoring stack

# Set up Docker repo
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list

# Add any tools we need/want
apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin jq
systemctl daemon-reload
systemctl enable docker
if ! groupadd docker; then
    echo "docker group already exists"
fi
usermod -aG docker ubuntu


# Node exporter
mkdir -p /opt/node_exporter
curl -sSfL https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz | tar -C /opt/node_exporter --strip-components 1 -xz
cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/opt/node_exporter/node_exporter

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable node_exporter

# Process exporter
curl -o /tmp/process_exporter.deb -sSfL https://github.com/ncabatoff/process-exporter/releases/download/v0.7.10/process-exporter_0.7.10_linux_arm64.deb
apt-get -y install /tmp/process_exporter.deb
rm -f /tmp/process_exporter.deb

systemctl daemon-reload
systemctl enable process_exporter

# Ensure we have all the directories we need for copying
declare -a DIRS_TO_OWN=("/config"
                        "/test"
                        "/opt")

for DIR in "${DIRS_TO_OWN[@]}"; do
    mkdir -p "${DIR}"
    chown -R ubuntu:ubuntu "${DIR}"
    chmod -R a+r "${DIR}"
done
