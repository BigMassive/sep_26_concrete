#!/bin/sh
# Runs once inside the Kubo container after init (lab harness).
# Keep this IPFS node off the public network.
set -eu

ipfs bootstrap rm --all || true

# API / gateway must listen on all interfaces inside the container so Docker can publish to the host.
ipfs config Addresses.API /ip4/0.0.0.0/tcp/5001
ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080

# Avoid public DHT / autoconfig where the Kubo version supports it.
ipfs config --json Routing '{"Type":"none"}' 2>/dev/null \
  || ipfs config Routing.Type none 2>/dev/null \
  || true

echo "sep26 lab: IPFS configured as project-private (PNET + empty bootstrap)"
