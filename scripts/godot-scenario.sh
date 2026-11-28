#!/usr/bin/env bash
# Host-side Godot test setup. One process plays both personas and presses the
# console. Not the joining playbook (./scripts/godot-playbook.sh).
# Needs a fresh OTP (genesis must still be open) and a free listen port.
# Usage: ./scripts/godot-scenario.sh [scenario-name]
# Watch it: GODOT_SCENARIO_WINDOW=1 ./scripts/godot-scenario.sh helen-alice
#
# Windowed runs start in their own session, so an aborted launching shell does
# not take Godot with it. Output is always copied to lab/run/scenario.log.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="${ROOT}/lab/run"
LOG="${RUN}/scenario.log"
PIDFILE="${RUN}/scenario.pid"
GODOT_BIN="${GODOT_BIN:-}"
PORT="${CONCRETE_GODOT_PORT:-24567}"
HTTP_PORT="${CONCRETE_HTTP_PORT:-4000}"
NAME="${1:-helen-alice}"
PINS="${RUN}/scenario-pins.txt"

write_pins() {
  python3 - "${LOG}" "${PINS}" "${NAME}" <<'PY'
import datetime, json, sys
log_path, dest, fallback = sys.argv[1:]
line = ""
with open(log_path, encoding="utf-8", errors="replace") as fh:
    for raw in fh:
        raw = raw.strip()
        if raw.startswith("{") and '"helen_pin"' in raw:
            line = raw
if not line:
    sys.exit(0)
rec = json.loads(line)
if not rec.get("ok"):
    sys.exit(0)
when = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
text = (
    f"scenario: {rec.get('name') or fallback}\n"
    f"when: {when}\n"
    f"helen_pin: {rec.get('helen_pin', '')}\n"
    f"alice_pin: {rec.get('alice_pin', '')}\n"
    f"session: {rec.get('session', '')}\n"
    f"principal_id: {rec.get('principal_id', '')}\n"
)
with open(dest, "w", encoding="utf-8") as out:
    out.write(text)
PY
}

if [[ -z "${GODOT_BIN}" ]]; then
  if [[ -x /home/stuart/Downloads/godot ]]; then
    GODOT_BIN=/home/stuart/Downloads/godot
  elif command -v godot4 >/dev/null 2>&1; then
    GODOT_BIN=$(command -v godot4)
  elif command -v godot >/dev/null 2>&1; then
    GODOT_BIN=$(command -v godot)
  else
    echo "Godot not found. Set GODOT_BIN or install Godot 4.x." >&2
    exit 1
  fi
fi

if ss -ltn 2>/dev/null | grep -q ":${PORT} "; then
  echo "Port ${PORT} is in use. Stop the open Godot session before a scenario." >&2
  exit 1
fi

if ! curl -sf "http://127.0.0.1:${HTTP_PORT}/health" >/dev/null; then
  echo "OTP is not up on :${HTTP_PORT}. Run ./scripts/session-up.sh first." >&2
  exit 1
fi

export GODOT_BIN
"${ROOT}/scripts/ensure-godot-import.sh"

mkdir -p "${RUN}"
{
  echo "--- launch $(date -Is) parent $$ scenario ${NAME}"
  echo "display ${DISPLAY:-unset}"
  echo "wayland ${WAYLAND_DISPLAY:-unset}"
  echo "xdg_runtime ${XDG_RUNTIME_DIR:-unset}"
} >"${LOG}"

args=(--path "${ROOT}/godot" -- --scenario "${NAME}")
if [[ "${GODOT_SCENARIO_WINDOW:-}" == "1" ]]; then
  args+=(--stay)
  note_waiter_signal() {
    echo "--- waiter signal $(date -Is); detached pid $(cat "${PIDFILE}" 2>/dev/null || echo missing) should still be running" >>"${LOG}"
    exit 129
  }
  trap note_waiter_signal HUP TERM INT
  # setsid -f forks into a new session and returns. Godot is not in this shell's
  # process group, so aborting the launcher does not kill the window.
  setsid -f bash -c '
    echo $$ >"$1"
    shift
    echo "--- session pid $$ ppid $PPID $(date -Is)"
    trap "echo \"--- SIGHUP $(date -Is)\"; exit 129" HUP
    trap "echo \"--- SIGTERM $(date -Is)\"; exit 143" TERM
    trap "echo \"--- SIGINT $(date -Is)\"; exit 130" INT
    stdbuf -oL -eL "$@"
    rc=$?
    echo "--- godot exit ${rc} $(date -Is)"
    exit "$rc"
  ' _ "${PIDFILE}" "${GODOT_BIN}" "${args[@]}" >>"${LOG}" 2>&1 </dev/null
  echo "Window detached. Log: ${LOG}" >&2
  for _ in $(seq 1 50); do
    [[ -s "${PIDFILE}" ]] && break
    sleep 0.1
  done
  if [[ ! -s "${PIDFILE}" ]]; then
    echo "Godot did not record a pid. Log:" >&2
    cat "${LOG}" >&2
    exit 1
  fi
  pid="$(cat "${PIDFILE}")"
  echo "Pid: ${pid}" >&2
  for _ in $(seq 1 180); do
    if grep -q '"ok"' "${LOG}"; then
      grep '"ok"' "${LOG}"
      write_pins
      echo "Window left running. Log: ${LOG}" >&2
      echo "Pins: ${PINS}" >&2
      exit 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      echo "Godot exited before a result. Log:" >&2
      cat "${LOG}" >&2
      exit 1
    fi
    sleep 1
  done
  echo "No result after 180s. Godot pid ${pid} may still be running. Log: ${LOG}" >&2
  exit 1
fi

args=(--headless "${args[@]}")
set +e
timeout --kill-after=10s 180s stdbuf -oL -eL "${GODOT_BIN}" "${args[@]}" 2>&1 | tee -a "${LOG}"
rc="${PIPESTATUS[0]}"
set -e
if [[ "${rc}" -eq 124 ]]; then
  echo "Headless scenario produced no result after 180s. Tail of ${LOG}:" >&2
  tail -n 40 "${LOG}" >&2
  exit 124
fi
write_pins
exit "${rc}"
