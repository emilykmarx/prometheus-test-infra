#!/bin/bash -e

# 1. Prometheus

# Prometheus builder image
docker build --build-context conftamer=$HOME/projects/config_tracing/go-conftamer-ancestry -t prometheus-builder:conftamer ./tools/prometheus-builder
# Prometheus image
docker build -f ./tools/prometheus-builder/Dockerfile.image --build-arg VERSION=v3.2.1 -t prometheus-conftamer:v3.2.1 ./tools/prometheus-builder

# 2. Grafana

# Build patched Go image
docker build --build-context conftamer=$HOME/projects/config_tracing/go-conftamer-ancestry -t go-patched:v1.26.4 ./tools/patch-go

# Build Grafana image using patched Go image
echo 'CD TO GRAFANA SOURCE'
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

# 3. Alertmanager
echo 'CD TO ALERTMANAGER SOURCE'
mkdir -p .build/linux-amd64
PATH="/home/emily/projects/config_tracing/go-conftamer-ancestry/bin:$PATH" make build
cp alertmanager amtool .build/linux-amd64
docker build -t "alertmanager-conftamer:v0.25.1" \
        --build-arg ARCH="amd64" \
        --build-arg OS="linux" \
        ./

# 4. Save images
docker save prometheus-builder:conftamer prometheus-conftamer:v3.2.1 grafana-conftamer:v13.1.0 alertmanager-conftamer:v0.25.1 -o /tmp/conftamer-images.tar
