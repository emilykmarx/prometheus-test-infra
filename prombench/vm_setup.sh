#!/bin/bash -e

set -x
# bootstrap
# mkdir -p /home/emily/projects/config_tracing/; cd /home/emily/projects/config_tracing/; git clone https://github.com/emilykmarx/prometheus-test-infra.git

GO_VERSION=1.26.2
KIND_VERSION=v0.33.0
KUBECTL_VERSION=v1.31.13

ARCH=$(dpkg --print-architecture) # amd64 or arm64

sudo apt-get update
sudo apt-get install -y curl git ca-certificates

# Go
curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf /tmp/go.tar.gz
rm /tmp/go.tar.gz
if ! grep -q '/usr/local/go/bin' ~/.profile; then
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.profile
fi
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
go version

# kind
curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}" -o /tmp/kind
sudo install -m 0755 /tmp/kind /usr/local/bin/kind
rm /tmp/kind
kind version

# Docker Engine (https://docs.docker.com/engine/install/ubuntu/)
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
# Run docker without sudo (takes effect on next login)
sudo usermod -aG docker "$USER"

# kubectl
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" -o /tmp/kubectl
sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm /tmp/kubectl
kubectl version --client

# Playwright with headless Chromium, used by dump_ancestors/argmatch/experiment
# (view_dashboards.py) to load Grafana dashboards like a person viewing them
sudo apt-get install -y python3-pip
pip3 install --user playwright
python3 -m playwright install --with-deps chromium

# repos
pushd prometheus-test-infra; git checkout argmatch-prom; popd
git clone https://github.com/emilykmarx/prometheus.git
pushd prometheus; git checkout prombench; popd
git clone https://github.com/emilykmarx/argmatch.git dump_ancestors
git clone https://github.com/emilykmarx/golang.org-x-tools.git
git clone https://github.com/emilykmarx/go-conftamer-ancestry.git

# Build the infra CLI used by deploy.sh
cd prometheus-test-infra/infra
go build -o infra .

echo 'Log out and back in for docker group membership to take effect'

### MANUAL STUFF ###
# 1. Copy over any files needed for argmatch
# gcloud compute scp --zone "us-central1-a" /home/emily/projects/config_tracing/prom-test-infra/prombench/logs_alerts/fuzzed/pods/default_prometheus-meta-cf9b59db8-bzpcm_a5016e92-df63-46f6-a6ab-54dd81578ac6/prometheus/0.log emily@paramtrack:~/projects/config_tracing/prometheus/argmatch-stacklog.txt
# gcloud compute scp --zone "us-central1-a" /home/emily/projects/config_tracing/prom-test-infra/prombench/param_values.txt  emily@paramtrack:~/projects/config_tracing/prometheus/argmatch-matches.txt

# 2. Build Prometheus image
# build_images will require more clones for images besides Prometheus -
# using built-in images for now except for prom-meta
