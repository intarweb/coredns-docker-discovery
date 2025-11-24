# ====== Stage 1: Builder ======
ARG GOLANG_VERS=1.24
ARG ALPINE_VERS=3.22

FROM golang:${GOLANG_VERS}-alpine${ALPINE_VERS} AS builder

# Set environment variables
ENV CGO_ENABLED=0 \
    PLUGIN_PRIO=50 \
    COREDNS_VERS=1.13.1

# Install build dependencies
RUN apk update && apk add --no-cache build-base git make binutils ca-certificates && update-ca-certificates

# Clone the CoreDNS repository
RUN git clone --branch v${COREDNS_VERS} https://github.com/coredns/coredns.git --depth=1 /go/src/github.com/coredns/coredns

# Change to the CoreDNS directory
WORKDIR /go/src/github.com/coredns/coredns

# Add the plugin configuration file
ADD plugin.cfg plugin.cfg

# Generate code and build CoreDNS
RUN make gen all

# Install binutils to use 'strip' for reducing binary size and strip the binary
RUN strip -v /go/src/github.com/coredns/coredns/coredns

# ====== Stage 2: Final Image ======
FROM alpine:${ALPINE_VERS}

# Copy CA certificates from the builder stage to support HTTPS
COPY --from=builder /etc/ssl/certs /etc/ssl/certs

# Copy the CoreDNS binary from the builder stage
COPY --from=builder /go/src/github.com/coredns/coredns/coredns /usr/local/bin/coredns

ADD Corefile /etc/Corefile

# Expose DNS ports (both TCP and UDP)
EXPOSE 15353 15353/udp

# Set the entrypoint to the CoreDNS binary
ENTRYPOINT ["coredns"]
CMD ["-conf", "/etc/Corefile"]
