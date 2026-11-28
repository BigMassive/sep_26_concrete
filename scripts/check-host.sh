#!/usr/bin/env bash
# Fail before a session wipe if this machine cannot run the lab.
# Usage: ./scripts/check-host.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

note() {
  echo "$*" >&2
  failed=1
}

need_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    note "Missing ${cmd}. ${hint}"
  fi
}

need_cmd openssl "It generates the project-private IPFS swarm key."
need_cmd curl "Session and health checks call it."
need_cmd git "The first session clones the IOTA Identity sources into lab/cache."

if ! command -v docker >/dev/null 2>&1; then
  note "Docker is not installed. Install Docker Engine and the Compose v2 plugin."
elif ! docker compose version >/dev/null 2>&1; then
  note "Docker Compose v2 is not available. Install the docker-compose-plugin package (the command is \`docker compose\`, not docker-compose)."
else
  docker_err="$(docker info 2>&1 >/dev/null || true)"
  if [[ -n "${docker_err}" ]]; then
    if grep -qi "permission denied" <<<"${docker_err}"; then
      note "Docker is installed, but this shell cannot open /var/run/docker.sock."
      note "Add your user to the docker group, then open a new shell:"
      note '  sudo usermod -aG docker "$USER"'
    else
      note "Docker is installed but \`docker info\` failed:"
      note "${docker_err}"
    fi
  fi
fi

if ! command -v elixir >/dev/null 2>&1; then
  note "Elixir is not on PATH. Install Elixir 1.17 or newer (runtime/mix.exs)."
else
  elixir_ver="$(elixir --version 2>/dev/null | awk '/^Elixir / { print $2; exit }')"
  if ! awk -v v="${elixir_ver}" 'BEGIN {
    n = split(v, a, ".")
    major = a[1] + 0
    minor = (n >= 2 ? a[2] : 0) + 0
    exit !((major > 1) || (major == 1 && minor >= 17))
  }'; then
    note "Elixir ${elixir_ver:-unknown} is too old. Install 1.17 or newer (runtime/mix.exs)."
  fi
fi

GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "${GODOT_BIN}" ]]; then
  if [[ -x /home/stuart/Downloads/godot ]]; then
    GODOT_BIN=/home/stuart/Downloads/godot
  elif command -v godot4 >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot4)"
  elif command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  fi
fi
if [[ -z "${GODOT_BIN}" ]]; then
  note "Godot 4.7 is not on PATH. Install it, then use \`godot\` or \`godot4\`, or set GODOT_BIN."
elif [[ ! -x "${GODOT_BIN}" ]]; then
  note "GODOT_BIN=${GODOT_BIN} is not executable."
else
  godot_ver="$("${GODOT_BIN}" --version 2>/dev/null | awk '{ print $1; exit }')"
  case "${godot_ver}" in
    4.7|4.7.*) ;;
    *) note "Godot ${godot_ver:-unknown} at ${GODOT_BIN} is not 4.7. The project features pin 4.7." ;;
  esac
fi

venv_py="${ROOT}/lab/.venv/bin/python"
if [[ -x "${venv_py}" ]]; then
  if ! "${venv_py}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'; then
    note "lab/.venv is older than Python 3.11. Remove it and recreate it with Python 3.11 or newer."
  fi
elif ! command -v python3 >/dev/null 2>&1; then
  note "python3 is not on PATH. Install Python 3.11 or newer. node-up creates lab/.venv from it."
else
  py_ok=0
  py_ver="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
  if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'; then
    note "python3 is ${py_ver:-unknown}. Install Python 3.11 or newer so node-up can build lab/.venv (dilithium-py)."
  else
    py_ok=1
  fi
  if [[ "${py_ok}" -eq 1 ]]; then
    venv_probe="$(mktemp -d)"
    if ! python3 -m venv "${venv_probe}" >/dev/null 2>&1; then
      note "python3 -m venv failed. On Debian/Ubuntu install the python3-venv package for this Python."
    fi
    rm -rf "${venv_probe}"
  fi
fi

if [[ "${failed}" -ne 0 ]]; then
  exit 1
fi

echo "Host check passed."
