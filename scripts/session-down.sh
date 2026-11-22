#!/usr/bin/env bash
# Stop this project's Godot and OTP processes, wipe the lab, and check the ports.
# Usage: ./scripts/session-down.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_REAL="$(readlink -f "${ROOT}")"
RUN="${ROOT}/lab/run"
PORTS=(4000 5001 8080 9000 9123 24567)

kill_matching() {
  local needle="$1" pid
  local -a pids=()
  mapfile -t pids < <(ps -eo pid=,args= | awk -v n="${needle}" 'index($0, n) && index($0, "awk -v n=") == 0 { print $1 }')
  for pid in "${pids[@]}"; do
    [[ -z "${pid}" || "${pid}" == "$$" || "${pid}" == "${PPID}" ]] && continue
    kill "${pid}" 2>/dev/null || true
  done
}

stop_otp() {
  local pid cwd
  if [[ -f "${RUN}/node.pid" ]]; then
    pid="$(tr -d '[:space:]' <"${RUN}/node.pid")"
    if [[ -n "${pid}" && -d "/proc/${pid}" ]]; then
      kill "${pid}" 2>/dev/null || true
    fi
  fi
  kill_matching "${ROOT}/scripts/node-up.sh"
  kill_matching "${ROOT_REAL}/scripts/node-up.sh"
  for pid in $(ps -eo pid= -C beam.smp 2>/dev/null || true); do
    cwd="$(readlink -f "/proc/${pid}/cwd" 2>/dev/null || true)"
    if [[ "${cwd}" == "${ROOT_REAL}/runtime" ]]; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}

stop_godot() {
  kill_matching "${ROOT}/godot"
  kill_matching "${ROOT_REAL}/godot"
  kill_matching "${ROOT}/scripts/godot-up.sh"
  kill_matching "${ROOT_REAL}/scripts/godot-join.sh"
}

wait_gone() {
  local i pid cwd cmd
  for i in 1 2 3 4 5 6 7 8 9 10; do
    local alive=0
    for pid in $(ps -eo pid= -C beam.smp 2>/dev/null || true); do
      cwd="$(readlink -f "/proc/${pid}/cwd" 2>/dev/null || true)"
      if [[ "${cwd}" == "${ROOT_REAL}/runtime" ]]; then
        alive=1
      fi
    done
    while read -r pid cmd; do
      [[ -z "${pid}" ]] && continue
      case "${cmd}" in
        *"${ROOT}/godot"*|*"${ROOT_REAL}/godot"*|*"${ROOT}/scripts/node-up.sh"*|*"${ROOT_REAL}/scripts/node-up.sh"*)
          alive=1
          ;;
      esac
    done < <(ps -eo pid=,args=)
    if [[ "${alive}" -eq 0 ]]; then
      return 0
    fi
    sleep 0.4
  done
  for pid in $(ps -eo pid= -C beam.smp 2>/dev/null || true); do
    cwd="$(readlink -f "/proc/${pid}/cwd" 2>/dev/null || true)"
    if [[ "${cwd}" == "${ROOT_REAL}/runtime" ]]; then
      kill -9 "${pid}" 2>/dev/null || true
    fi
  done
  while read -r pid cmd; do
    [[ -z "${pid}" ]] && continue
    case "${cmd}" in
      *"${ROOT}/godot"*|*"${ROOT_REAL}/godot"*|*"${ROOT}/scripts/node-up.sh"*|*"${ROOT_REAL}/scripts/node-up.sh"*)
        kill -9 "${pid}" 2>/dev/null || true
        ;;
    esac
  done < <(ps -eo pid=,args=)
}

assert_clear() {
  local port listeners names failed=0
  listeners="$(ss -ltn | awk 'NR > 1 { print $4 }')"
  for port in "${PORTS[@]}"; do
    if grep -Eq "(^|[^0-9]):${port}$" <<<"${listeners}"; then
      echo "port ${port} is still listening" >&2
      failed=1
    fi
  done
  names="$(docker ps -a --filter name=sep26_lab --format '{{.Names}}' || true)"
  if [[ -n "${names}" ]]; then
    echo "lab containers still present: ${names}" >&2
    failed=1
  fi
  if [[ -d "${ROOT}/lab/data" ]]; then
    echo "lab/data still exists after wipe" >&2
    failed=1
  fi
  return "${failed}"
}

echo "Stopping Godot and OTP for ${ROOT_REAL}…"
stop_godot
stop_otp
wait_gone
rm -f "${RUN}/node.pid" "${RUN}/godot.pid" "${RUN}/scenario.pid"

"${ROOT}/scripts/lab-down.sh" --wipe
assert_clear
echo "Session is down. Ports ${PORTS[*]} are clear."
