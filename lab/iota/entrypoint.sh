#!/bin/sh
# Lab harness: private IOTA localnet for this compose project only.
set -eu

CONFIG_DIR="${IOTA_CONFIG_DIR:-/data/iota-config}"
mkdir -p "${CONFIG_DIR}"

export RUST_LOG="${RUST_LOG:-off,iota_node=info}"

# Persist genesis for this project instance under lab/data/iota (gitignored).
if [ ! -f "${CONFIG_DIR}/.sep26_genesis_done" ]; then
  echo "sep26 lab: generating private IOTA genesis in ${CONFIG_DIR}"
  iota-localnet genesis -f --with-faucet --working-dir "${CONFIG_DIR}" --committee-size 1
  touch "${CONFIG_DIR}/.sep26_genesis_done"
fi

echo "sep26 lab: starting IOTA localnet (RPC :9000, faucet :9123)"
exec iota-localnet start \
  --network.config "${CONFIG_DIR}" \
  --with-faucet=0.0.0.0:9123 \
  --fullnode-rpc-port 9000
