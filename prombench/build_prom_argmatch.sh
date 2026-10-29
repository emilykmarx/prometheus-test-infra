# Assumes cluster is running

export CLUSTER_NAME=prombench

cd /home/emily/projects/config_tracing

# Run once per machine
export GOPATCH=patches/send_recv_short_contents.patch; pushd prometheus-test-infra/prombench
docker build \
        --build-context conftamer=$HOME/projects/config_tracing/go-conftamer-ancestry \
        --build-arg GOPATCH=$GOPATCH \
        -t prometheus-builder:conftamer \
        ../tools/prometheus-builder
popd

# Build image
docker build -f prometheus/prombench-argmatch.Dockerfile --build-arg VERSION=v3.2.1 \
    --build-arg ARGMATCH_MATCH= \
    --build-arg ARGMATCH_MATCHFILE=/src/argmatch-matches.txt \
    --build-arg ARGMATCH_FUNC= \
    --build-arg ARGMATCH_STACKLOG=/src/argmatch-stacklog.txt \
    --build-arg ARGMATCH_OUT=/argmatch-out/matches.csv \
    --build-arg ARGMATCH_RECVONLY=1 \
    --build-arg ARGMATCH_EXACT=true \
    --build-arg ARGMATCH_IGNORECLOSURES=true \
    --build-arg ARGMATCH_DEPTH=2 \
    --build-arg ARGMATCH_MAXFIELDS=-1 \
    --build-arg ARGMATCH_MAXELEMS=4 \
    --build-arg ARGMATCH_MAXCALLS=1 \
    --build-arg ARGMATCH_IGNORELIBS=true \
    --build-arg ARGMATCH_IGNORETYPES=config.Config \
    --build-arg ARGMATCH_MAXMEM=1GB \
    --build-arg ARGMATCH_MAXTIME=10s \
    -t prometheus-conftamer:v3.2.1 .
export IMAGETAR=prometheus-test-infra/prombench/images/conftamer-images.tar
mkdir -p prometheus-test-infra/prombench/images
docker save prometheus-builder:conftamer prometheus-conftamer:v3.2.1 -o $IMAGETAR

# Load into cluster
for n in $(kind get nodes --name $CLUSTER_NAME); do
    docker exec -i $n ctr -n k8s.io images import --all-platforms - < $IMAGETAR
done

# Delete Prometheus pod
