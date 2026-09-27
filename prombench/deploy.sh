#!/bin/bash -e

# Env vars
export CLUSTER_NAME=prombench
export PR_NUMBER=16075 # 3.2.1
export RELEASE=v3.2.1
export GRAFANA_ADMIN_PASSWORD=password
export DOMAIN_NAME="ingress-nginx-controller.ingress-nginx.svc.cluster.local"
export OAUTH_TOKEN=""
export WH_SECRET=""
export GITHUB_ORG=prometheus
export GITHUB_REPO=prometheus
export SERVICEACCOUNT_CLIENT_EMAIL=fakeemail

# 0. Per-machine:
sudo sysctl fs.inotify.max_user_instances=512

# 1. Start cluster
../infra/infra kind cluster create -v PR_NUMBER:$PR_NUMBER -v CLUSTER_NAME:$CLUSTER_NAME \
    -f manifests/cluster_kind.yaml

echo 'WAIT FOR CLUSTER'

# 1.5. Taint
kubectl --context kind-$CLUSTER_NAME taint nodes $CLUSTER_NAME-control-plane node-role.kubernetes.io/control-plane-

# 1.5.1. Load images
for n in $(kind get nodes --name $CLUSTER_NAME); do docker exec -i $n ctr -n k8s.io images import --all-platforms - < /tmp/conftamer-images.tar; done

# 2. Start infra
../infra/infra kind resource apply -v CLUSTER_NAME:$CLUSTER_NAME -v DOMAIN_NAME:$DOMAIN_NAME \
    -v GRAFANA_ADMIN_PASSWORD:$GRAFANA_ADMIN_PASSWORD \
    -v OAUTH_TOKEN="$(printf $OAUTH_TOKEN | base64 -w 0)" \
    -v WH_SECRET="$(printf $WH_SECRET | base64 -w 0)" \
    -v GITHUB_ORG:$GITHUB_ORG -v GITHUB_REPO:$GITHUB_REPO \
    -v SERVICEACCOUNT_CLIENT_EMAIL:$SERVICEACCOUNT_CLIENT_EMAIL \
    -f manifests/cluster-infra

echo 'WAIT FOR CLUSTER INFRA'

# 3. Start benchmark
echo 'RESET ENV VARS IF NEEDED' # likely need new terminal tab, since amgithubnotifier keeps the previous command from finishing

../infra/infra kind resource apply -v CLUSTER_NAME:$CLUSTER_NAME \
    -v PR_NUMBER:$PR_NUMBER -v RELEASE:$RELEASE -v DOMAIN_NAME:$DOMAIN_NAME \
    -v GITHUB_ORG:${GITHUB_ORG} -v GITHUB_REPO:${GITHUB_REPO} \
    -f manifests/prombench/benchmark

# 4. Inspect
export NODE_NAME=$(kubectl --context kind-$CLUSTER_NAME get pod -l "app=grafana" -o=jsonpath='{.items[*].spec.nodeName}')
export INTERNAL_IP=$(kubectl --context kind-$CLUSTER_NAME get nodes $NODE_NAME -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
export NODE_PORT=$(kubectl --context kind-$CLUSTER_NAME get -o jsonpath="{.spec.ports[0].nodePort}" services grafana)
echo "Grafana: http://$INTERNAL_IP:$NODE_PORT/grafana"
echo "Prometheus: http://$INTERNAL_IP:$NODE_PORT/prometheus-meta"
echo "Logs: http://$INTERNAL_IP:$NODE_PORT/grafana/explore"
echo "Profiles: http://$INTERNAL_IP:$NODE_PORT/profiles"

# Cleanup
../infra/infra kind cluster delete -v PR_NUMBER:$PR_NUMBER -v CLUSTER_NAME:$CLUSTER_NAME -f manifests/cluster_kind.yaml
