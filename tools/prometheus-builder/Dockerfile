FROM quay.io/prometheus/golang-builder:1.26-base

# Replace Go with this version, and apply patch to it from conftamer build context
ARG GO_VERSION=1.26.4
ENV GOTOOLCHAIN=local

RUN rm -rf /usr/local/go && \
    curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz | tar -C /usr/local -xz

COPY --from=conftamer 0001-Send-ancestry-logging-first-conn.Write-after-connect.patch /tmp/go-inlibrary.patch
RUN cd /usr/local/go && git apply --verbose /tmp/go-inlibrary.patch && \
    go version && go build std

RUN mkdir -p /go/src/github.com

COPY ./build.sh /go/src/github.com/build.sh

RUN chmod +x /go/src/github.com/build.sh

ENTRYPOINT ["/go/src/github.com/build.sh"]
