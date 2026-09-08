# syntax=docker/dockerfile:1
# Lab harness: stock IOTA localnet binary — not the product ledger fabric.
ARG IOTA_VERSION=v1.30.1
FROM ubuntu:24.04

ARG IOTA_VERSION
ARG TARGETARCH

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl libpq5 \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  case "${TARGETARCH}" in \
    amd64) ARCH=x86_64 ;; \
    arm64) ARCH=arm64 ;; \
    *) echo "unsupported arch: ${TARGETARCH}"; exit 1 ;; \
  esac; \
  curl -fsSL \
    "https://github.com/iotaledger/iota/releases/download/${IOTA_VERSION}/iota-${IOTA_VERSION}-linux-${ARCH}.tgz" \
    -o /tmp/iota.tgz; \
  mkdir -p /opt/iota; \
  tar --no-same-owner -xzf /tmp/iota.tgz -C /opt/iota; \
  rm /tmp/iota.tgz; \
  ln -sf /opt/iota/iota /usr/local/bin/iota; \
  ln -sf /opt/iota/iota-localnet /usr/local/bin/iota-localnet

ENV PATH="/opt/iota:${PATH}"
ENV IOTA_CONFIG_DIR=/data/iota-config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /data/iota-config
EXPOSE 9000 9123
ENTRYPOINT ["/entrypoint.sh"]
