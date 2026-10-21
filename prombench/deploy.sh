#!/bin/bash -e

set -x

# Env vars
export CLUSTER_NAME=prombench
export PR_NUMBER=16075 # 3.2.1
export RELEASE=v3.2.1
export GRAFANA_ADMIN_PASSWORD=password
export DOMAIN_NAME="ingress-nginx-controller.ingress-nginx.svc.cluster.local"
# Must be non-empty: amgithubnotifier exits on an empty token, and the infra tool waits for it to
# be ready before applying later waves (2_ingress-nginx-controller, 4_kube-state-metrics).
export OAUTH_TOKEN="dummy"
export WH_SECRET=""
export GITHUB_ORG=prometheus
export GITHUB_REPO=prometheus
export SERVICEACCOUNT_CLIENT_EMAIL=fakeemail
# Write files on node to /host/X so `docker cp` from node:/X works (faster than `kubectl cp`)
export NODE_MOUNT=/host
# These should be shared with build_images.sh
export IMAGEDIR="images"
export IMAGETAR=$IMAGEDIR/conftamer-images.tar

# 0. Per-machine:
sudo sysctl fs.inotify.max_user_instances=512

# 1. Start cluster
../infra/infra kind cluster delete -v PR_NUMBER:$PR_NUMBER -v CLUSTER_NAME:$CLUSTER_NAME -f manifests/cluster_kind.yaml
../infra/infra kind cluster create -v PR_NUMBER:$PR_NUMBER -v CLUSTER_NAME:$CLUSTER_NAME \
    -f manifests/cluster_kind.yaml

# 1.5. Taint
kubectl --context kind-$CLUSTER_NAME taint nodes $CLUSTER_NAME-control-plane node-role.kubernetes.io/control-plane-

# 1.5.1. Load images
for n in $(kind get nodes --name $CLUSTER_NAME); do
    docker exec -i $n ctr -n k8s.io images import --all-platforms - < $IMAGETAR
done

# Start tcpdump before deploying infra, to capture messages sent early
for n in $(kind get nodes --name $CLUSTER_NAME); do
    kubectl debug node/$n --image=nicolaka/netshoot \
        -- tcpdump -i any -w $NODE_MOUNT/any.pcap
done
# wait for capture to start
kubectl get pods -o name | grep node-debugger | \
    xargs kubectl wait --for=condition=Ready --timeout=120s

# 2. Start infra (including ingress controller), in the background so the benchmark can start in parallel
../infra/infra kind resource apply -v CLUSTER_NAME:$CLUSTER_NAME -v DOMAIN_NAME:$DOMAIN_NAME \
    -v GRAFANA_ADMIN_PASSWORD:$GRAFANA_ADMIN_PASSWORD \
    -v OAUTH_TOKEN="$(printf '%s' "$OAUTH_TOKEN" | base64 -w 0)" \
    -v WH_SECRET="$(printf '%s' "$WH_SECRET" | base64 -w 0)" \
    -v GITHUB_ORG:$GITHUB_ORG -v GITHUB_REPO:$GITHUB_REPO \
    -v SERVICEACCOUNT_CLIENT_EMAIL:$SERVICEACCOUNT_CLIENT_EMAIL \
    -f manifests/cluster-infra &
INFRA_PID=$!

# 3. Start benchmark
BENCH_ARGS=(-v "CLUSTER_NAME:$CLUSTER_NAME"
    -v "PR_NUMBER:$PR_NUMBER" -v "RELEASE:$RELEASE" -v "DOMAIN_NAME:$DOMAIN_NAME"
    -v "GITHUB_ORG:$GITHUB_ORG" -v "GITHUB_REPO:$GITHUB_REPO")

# Waves 1-6 don't depend on cluster-infra being finished, so run them concurrently
EARLY_FILES=()
for f in manifests/prombench/benchmark/[1-6]_*.yaml; do EARLY_FILES+=(-f "$f"); done
../infra/infra kind resource apply "${BENCH_ARGS[@]}" "${EARLY_FILES[@]}"

# Ingress creation is rejected by the ingress-nginx admission webhook (failurePolicy: Fail)
# until the controller is ready, so wait for cluster-infra before applying the ingress routes.
# `wait` returns cluster-infra's exit status, so `bash -e` stops here if it failed.
wait $INFRA_PID
../infra/infra kind resource apply "${BENCH_ARGS[@]}" \
    -f manifests/prombench/benchmark/7_nginx-ingress-routes.yaml \
    -f manifests/prombench/benchmark/8_loadgen.yaml

echo 'Wait for Grafana Prombench dashboard to show data on Prombench dashboard, and for alert to fire'
