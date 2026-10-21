#!/bin/bash -e

# UIs
export NODE_NAME=$(kubectl --context kind-$CLUSTER_NAME get pod -l "app=grafana" -o=jsonpath='{.items[*].spec.nodeName}')
export INTERNAL_IP=$(kubectl --context kind-$CLUSTER_NAME get nodes $NODE_NAME -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
export NODE_PORT=$(kubectl --context kind-$CLUSTER_NAME get -o jsonpath="{.spec.ports[0].nodePort}" services grafana)
echo "Grafana: http://$INTERNAL_IP:$NODE_PORT/grafana"
echo "Prometheus: http://$INTERNAL_IP:$NODE_PORT/prometheus-meta"
echo "Logs: http://$INTERNAL_IP:$NODE_PORT/grafana/explore"
echo "Profiles: http://$INTERNAL_IP:$NODE_PORT/profiles"

LOGS="logs_alerts"
mkdir -p $LOGS
pushd $LOGS

# Get cluster info
kubectl get node -o wide &> nodes.txt
kubectl get pods -A -o wide &> pods.txt
kubectl get service -A -o wide &> services.txt

# Get pod logs and other info from nodes
NODE_LOGS="node_logs"
mkdir -p $NODE_LOGS
pushd $NODE_LOGS

for debug_pod in $(kubectl get pods --no-headers -o custom-columns=":metadata.name" | grep debugger); do
    # Get ports
    kubectl exec $debug_pod -- sh -c "netstat -tup > ${NODE_MOUNT}/ports.txt"
done

for n in $(kind get nodes --name $CLUSTER_NAME); do
    docker cp $n:/ports.txt ${n}_ports.txt
    # Copy container logs off nodes - unlike `kubectl logs`, includes rotated files
    docker cp $n:/var/log/pods .
    docker cp $n:/any.pcap ${n}_any.pcap
done

# Check for pod log rotation using log line on process init in patch
pushd pods # pod logs
find . -name '0.log' | grep -E 'kube-system_kube-|/prometheus/|grafana|alertmanager' | while IFS= read -r log; do
    # 0.log is the oldest log - it should be the beginning of the container's lifetime
    head -n 5 "$log" | grep -q "Process start at" || echo "$log APPEARS ROTATED"
done
popd
popd

# Cleanup
../infra/infra kind cluster delete -v PR_NUMBER:$PR_NUMBER -v CLUSTER_NAME:$CLUSTER_NAME -f manifests/cluster_kind.yaml

# Run parser (not automated)
pushd $NODE_LOGS/pods
# Run on rotated files too
find . -type f | grep -E 'kube-system_kube-|/prometheus/|grafana|alertmanager' | while IFS= read -r log; do
    # Note there are 4 proxy pods
    MODULE_PREFIX=github.com/prometheus/prometheus
    MODULE_PREFIX=github.com/grafana/grafana # XXX
    MODULE_PREFIX=k8s.io/apiserver
    OUT=prometheus
    OUT=grafana # XXX
    OUT=k8s_apiserver
    echo "$GOPLS/gopls conftamer -m=$MODULE_PREFIX \
    -send_log=$log \
    -out=$PROMBENCH/logs/stacks/$OUT &> $GOPLS/tmp.md"
done
popd
