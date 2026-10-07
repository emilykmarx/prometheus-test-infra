#!/bin/bash -e
set -x

# Run from prombench - other paths are set in env vars below

# To change the Go patch, update this PLUS the working tree of go-conftamer-ancestry (for alertmanager)
export GOPATCH=send_recv_short_contents.patch

# 1. Prometheus

# Build patched builder image
docker build \
        --build-context conftamer=$HOME/projects/config_tracing/go-conftamer-ancestry \
        --build-arg GOPATCH=$GOPATCH \
        -t prometheus-builder:conftamer \
        ../tools/prometheus-builder

# Build Prometheus image using patched Go image and local Prometheus source
PROMSRCPARENT=~/projects/config_tracing
PROMSRC=$PROMSRCPARENT/prometheus
pushd $PROMSRCPARENT
docker build -f $PROMSRC/prombench.Dockerfile \
        --build-arg VERSION=v3.2.1 \
        -t prometheus-conftamer:v3.2.1 \
        .

popd

# 2. Grafana

# Build patched Go image
docker build \
        --build-context conftamer=$HOME/projects/config_tracing/go-conftamer-ancestry \
        --build-arg GOPATCH=$GOPATCH \
        -t go-patched:v1.26.4 \
         ../tools/patch-go

# Build Grafana image using patched Go image and local Grafana source
GRAFANASRC=~/projects/config_tracing/grafana
pushd $GRAFANASRC
docker buildx build \
--platform linux/amd64 \
--build-arg NODE_ENV=production \
--build-arg JS_NODE_ENV=production \
--build-arg JS_YARN_INSTALL_FLAG=--immutable \
--build-arg JS_YARN_BUILD_FLAG=build \
--build-arg GO_BUILD_TAGS= \
--build-arg WIRE_TAGS="oss" \
--build-arg COMMIT_SHA=$(git rev-parse HEAD) \
--build-arg BUILD_BRANCH=$(git rev-parse --abbrev-ref HEAD) \
--build-arg SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) \
--build-arg GO_IMAGE=go-patched:v1.26.4 \
--build-arg SLIM=false \
--target=final-ubuntu \
--tag grafana-conftamer:v13.1.0 \
 \
.
popd

# 3. Alertmanager

# NOTE this uses the working tree of go-conftamer-ancestry, NOT a patch (TODO (CT) improve)
AMSRC=~/projects/config_tracing/alertmanager_prom
pushd $AMSRC
mkdir -p .build/linux-amd64
PATH="/home/emily/projects/config_tracing/go-conftamer-ancestry/bin:$PATH" make build
cp alertmanager amtool .build/linux-amd64
docker build -t "alertmanager-conftamer:v0.25.1" \
        --build-arg ARCH="amd64" \
        --build-arg OS="linux" \
        ./
popd

# 4. Kubernetes API server - NOTE this requires a fork of k8s with the changes in https://github.com/emilykmarx/kubernetes/tree/conftamer-ancestry
KUBESRC=~/go/src/k8s.io/kubernetes
pushd $KUBESRC
# Note k8s version must be within skew of other things: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#version-skew-policy
# (I have kubeadm v1.31.13, but I think what matters is the kind node version in cluster_kind.yaml)
# Changing k8s version may also require changing KUBE_CROSS_VERSION to build with compatible base image
K8S_VERSION=v1.31.1
KUBE_CROSS_VERSION=v1.31.0

# Build patched Go image
docker build -f ./build/build-image/patched_go.Dockerfile \
        --build-context conftamer=$HOME/projects/config_tracing/go-conftamer-ancestry \
        --build-arg GOPATCH=$GOPATCH \
        -t  kube-cross-conftamer:$KUBE_CROSS_VERSION \
        ./build/build-image

# Build Kubernetes images using patched Go image
FORCE_HOST_GO=1 KUBE_CROSS_IMAGE=docker.io/library/kube-cross-conftamer KUBE_CROSS_VERSION=$KUBE_CROSS_VERSION \
 kind build node-image --image kindest/node-conftamer:$K8S_VERSION ./
popd

# 5. Save images
export IMAGEDIR="images"
export IMAGETAR=$IMAGEDIR/conftamer-images.tar
mkdir -p $IMAGEDIR
docker save prometheus-builder:conftamer prometheus-conftamer:v3.2.1 grafana-conftamer:v13.1.0 alertmanager-conftamer:v0.25.1 -o $IMAGETAR
