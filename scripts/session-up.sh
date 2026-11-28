#!/usr/bin/env bash
# Clean lab session: wipe, IPFS + IOTA, publish Identity, detached OTP.
# Usage: ./scripts/session-up.sh [--godot]
#   --godot  also open the windowed veneer (detached)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="${ROOT}/lab/run"
WITH_GODOT=0

for arg in "$@"; do
  case "${arg}" in
    --godot) WITH_GODOT=1 ;;
    -h|--help)
      echo "Usage: ./scripts/session-up.sh [--godot]"
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      exit 1
      ;;
  esac
done

"${ROOT}/scripts/check-host.sh"
"${ROOT}/scripts/session-down.sh"

echo "Starting a clean lab session…"
"${ROOT}/scripts/lab-up.sh"
"${ROOT}/scripts/identity-publish.sh"

# setsid may fork, so the shell's $! is not the server. The child records its own pid, then execs.
launch() {
  local name="$1"
  shift
  : >"${RUN}/${name}.log"
  rm -f "${RUN}/${name}.pid"
  setsid nohup bash -c 'echo $$ >"$1"; shift; exec "$@"' _ "${RUN}/${name}.pid" "$@" \
    >>"${RUN}/${name}.log" 2>&1 </dev/null &
  local i
  for i in $(seq 1 50); do
    if [[ -s "${RUN}/${name}.pid" ]] && kill -0 "$(cat "${RUN}/${name}.pid")" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  echo "Failed to launch ${name}. Log:" >&2
  cat "${RUN}/${name}.log" >&2 || true
  return 1
}

mkdir -p "${RUN}"
launch node "${ROOT}/scripts/node-up.sh"

echo "Waiting for OTP on http://127.0.0.1:4000 …"
ready=0
for _ in $(seq 1 180); do
  if curl -sf "http://127.0.0.1:4000/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$(cat "${RUN}/node.pid")" 2>/dev/null; then
    echo "OTP exited before /health answered. Log:" >&2
    tail -n 40 "${RUN}/node.log" >&2 || true
    exit 1
  fi
  sleep 1
done
if [[ "${ready}" -ne 1 ]]; then
  echo "OTP did not answer /health in time. Log:" >&2
  tail -n 40 "${RUN}/node.log" >&2 || true
  exit 1
fi

if [[ "${WITH_GODOT}" -eq 1 ]]; then
  launch godot "${ROOT}/scripts/godot-up.sh"
fi

cat <<EOF

Session is up.

  OTP health:  http://127.0.0.1:4000/health
  Node log:    lab/run/node.log
  Godot:       $([[ "${WITH_GODOT}" -eq 1 ]] && echo "window open (lab/run/godot.log)" || echo "not started (pass --godot)")
  Stop:        ./scripts/session-down.sh

EOF
