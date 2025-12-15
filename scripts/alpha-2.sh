#!/usr/bin/env bash
# Alpha-2 demo harness (missionctl): discovers alpha2 pytest steps and runs them with narration.
set -euo pipefail

resolve_root() {
  local src="${BASH_SOURCE[0]}"
  while [ -L "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")/.." && pwd
}

ROOT_DIR="$(resolve_root)"
STATE_POINTER="${HOME}/.symbia-seed-current"
STATE_DIR="${SYMBIA_STATE_DIR:-}"
API_BASE="${SYMBIA_API_BASE:-}"
TOKEN_FILE="${SYMBIA_DEMO_TOKEN_FILE:-}"
PY_BIN="${PY_BIN:-}"
PYTEST_BIN=()
PYTEST_VERSION="${PYTEST_VERSION:-7.4.4}"

usage() {
  cat <<EOF
Usage: $(basename "$0") missionctl
Commands:
  missionctl   Guided Alpha-2 demo runner (requires seed.sh boot dev already running)
EOF
}

# Ensure pytest is available; bootstrap a local .venv if needed.
bootstrap_pytest() {
  local venv_dir="$ROOT_DIR/.venv"
  local venv_python="$venv_dir/bin/python"
  if [[ ! -x "$venv_python" ]]; then
    "$PY_BIN" -m venv "$venv_dir"
  fi
  "$venv_python" -m pip install --upgrade pip >/dev/null 2>&1 || true
  "$venv_python" -m pip install "pytest==${PYTEST_VERSION}"
}

# Prefer project venv pytest if available; otherwise bootstrap.
init_bins() {
  local venv_python="$ROOT_DIR/.venv/bin/python"
  local venv_pytest="$ROOT_DIR/.venv/bin/pytest"

  if [[ -n "$PY_BIN" && ! -x "$PY_BIN" ]]; then
    echo "PY_BIN points to a non-executable interpreter: $PY_BIN" >&2
    exit 1
  fi

  if [[ -z "$PY_BIN" ]]; then
    if [[ -x "$venv_python" ]]; then
      PY_BIN="$venv_python"
    else
      PY_BIN="$(command -v python3 || true)"
      if [[ -z "$PY_BIN" ]]; then
        PY_BIN="$(command -v python || true)"
      fi
    fi
  fi

  if [[ -z "$PY_BIN" ]]; then
    echo "Python interpreter not found; checked $venv_python, python3, python on PATH." >&2
    exit 1
  fi

  if [[ -x "$venv_pytest" ]]; then
    PYTEST_BIN=("$venv_pytest")
  else
    if "$PY_BIN" - <<'PYCODE'
try:
    import pytest  # noqa: F401
except Exception:
    raise SystemExit(1)
PYCODE
    then
      PYTEST_BIN=("$PY_BIN" -m pytest)
    else
      echo "pytest not found; bootstrapping local venv with pytest ${PYTEST_VERSION}..."
      bootstrap_pytest
      if [[ -x "$venv_pytest" ]]; then
        PYTEST_BIN=("$venv_pytest")
        PY_BIN="$venv_python"
      else
        echo "Failed to bootstrap pytest into $ROOT_DIR/.venv" >&2
        exit 1
      fi
    fi
  fi

  if [[ ${#PYTEST_BIN[@]} -eq 0 ]]; then
    echo "pytest resolution failed unexpectedly for interpreter: $PY_BIN" >&2
    exit 1
  fi
}

resolve_state_dir() {
  if [[ -n "$STATE_DIR" ]]; then
    STATE_DIR="$(echo "$STATE_DIR" | sed 's#^~#'"$HOME"'#')"
    return
  fi
  if [[ -f "$STATE_POINTER" ]]; then
    local pinned
    pinned="$(cat "$STATE_POINTER" 2>/dev/null || true)"
    if [[ -n "$pinned" ]]; then
      STATE_DIR="$pinned"
      return
    fi
  fi
  STATE_DIR="$HOME/.symbia-seed"
}

init_defaults() {
  resolve_state_dir
  API_BASE="${API_BASE:-http://127.0.0.1:19123}"
  TOKEN_FILE="${TOKEN_FILE:-$STATE_DIR/auth/demo.token}"
  mkdir -p "$STATE_DIR/alpha2"
  STEPS_FILE="$STATE_DIR/alpha2/steps.json"
}

check_prereqs() {
  if [[ ! -f "$TOKEN_FILE" ]]; then
    echo "Note: demo token file not found at $TOKEN_FILE. Run ./scripts/seed.sh boot dev first."
  fi
}

list_steps() {
  local out err_file
  err_file="$(mktemp)"
  if ! out=$(PYTHONPATH="$ROOT_DIR" SYMBIA_RUN_ALPHA2=1 SYMBIA_STATE_DIR="$STATE_DIR" SYMBIA_API_BASE="$API_BASE" SYMBIA_DEMO_TOKEN_FILE="$TOKEN_FILE" \
      "${PYTEST_BIN[@]}" -p tests.alpha2.plugin --alpha2-list-json tests/alpha2 -q 2>"$err_file"); then
    err="$(cat "$err_file" 2>/dev/null || true)"
    echo "Failed to collect alpha2 steps via pytest." >&2
    [[ -n "$err" ]] && echo "$err" >&2
    rm -f "$err_file"
    exit 1
  fi
  rm -f "$err_file"
  local out_file
  out_file="$(mktemp)"
  echo "$out" > "$out_file"
  local json_out
  if ! json_out=$("$PY_BIN" - <<PYCODE
import json, re, sys, pathlib
path = pathlib.Path("$out_file")
text = path.read_text()
m = re.search(r"\[[\s\S]*\]", text)
if not m:
    sys.exit(1)
payload = json.loads(m.group(0))
print(json.dumps(payload, indent=2))
PYCODE
); then
    echo "Failed to parse alpha2 step listing." >&2
    echo "$out" >&2
    rm -f "$out_file"
    exit 1
  fi
  rm -f "$out_file"
  echo "$json_out" > "$STEPS_FILE"
}

print_menu() {
  echo "Alpha-2 demo steps (pytest-discovered):"
  "$PY_BIN" - "$STEPS_FILE" <<'PYCODE'
import json, sys
path = sys.argv[1]
try:
    steps = json.loads(open(path).read())
except Exception:
    print("  (no steps found)")
    sys.exit(0)
for idx, step in enumerate(steps, start=1):
    print(f"  {idx}) {step.get('title','')} [{step.get('id','')}]")
print("  a) run all")
print("  q) quit")
PYCODE
}

load_step_meta() {
  local idx="$1"
  eval "$("$PY_BIN" - "$STEPS_FILE" "$idx" <<'PYCODE'
import json, sys, shlex
path, idx = sys.argv[1], int(sys.argv[2])
steps = json.load(open(path))
if idx < 1 or idx > len(steps):
    sys.exit(1)
s = steps[idx-1]
def emit_scalar(name, val):
    print(f'{name}={shlex.quote(str(val))}')
def emit_array(name, arr):
    safe = [shlex.quote(str(x)) for x in arr]
    print(f'{name}=(' + " ".join(safe) + ")")
emit_scalar("STEP_ID", s.get("id",""))
emit_scalar("STEP_TITLE", s.get("title",""))
emit_scalar("STEP_ANNOUNCE", s.get("announce",""))
emit_scalar("STEP_EXPLAIN", s.get("explain",""))
emit_scalar("STEP_NODEID", s.get("nodeid",""))
emit_array("STEP_AUDIT", s.get("audit_hints", []) or [])
emit_array("STEP_INSPECT", s.get("inspect_hints", []) or [])
PYCODE
)" || return 1
}

print_section() {
  local title="$1"; shift
  echo "$title"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "  - $line"
  done <<<"$*"
}

run_step() {
  local idx="$1"
  load_step_meta "$idx"
  local step_dir="$STATE_DIR/alpha2/$STEP_ID"
  mkdir -p "$step_dir"

  echo ""
  echo "==> [$STEP_ID] $STEP_TITLE"
  echo "What: $STEP_ANNOUNCE"
  echo "Why:  $STEP_EXPLAIN"
  echo "Audit hints:"
  for h in "${STEP_AUDIT[@]}"; do
    [[ -n "$h" ]] && echo "  - $h"
  done
  echo "  - API port: $API_BASE (curl $API_BASE/health)"
  echo "  - Logs: tail -f $STATE_DIR/logs/symbia-seed.api.log"

  echo "Inspect commands:"
  for h in "${STEP_INSPECT[@]}"; do
    [[ -n "$h" ]] && echo "  - $h"
  done
  echo "  - junit: $step_dir/junit.xml"
  echo "  - summary: $step_dir/summary.json"

  local junit="$step_dir/junit.xml"
  local summary="$step_dir/summary.json"
  local start_ts
  start_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  set +e
  PYTHONPATH="$ROOT_DIR" SYMBIA_RUN_ALPHA2=1 SYMBIA_STATE_DIR="$STATE_DIR" SYMBIA_API_BASE="$API_BASE" SYMBIA_DEMO_TOKEN_FILE="$TOKEN_FILE" \
    "${PYTEST_BIN[@]}" -p tests.alpha2.plugin "$STEP_NODEID" --junitxml "$junit" -q
  local status=$?
  set -e
  local result="PASS"
  if [[ "$status" -ne 0 ]]; then
    result="FAIL"
  fi
  local end_ts
  end_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  "$PY_BIN" - "$summary" <<PYCODE
import json, sys
summary_path = sys.argv[1]
data = {
    "id": "${STEP_ID}",
    "title": "${STEP_TITLE}",
    "result": "${result}",
    "started_at": "${start_ts}",
    "ended_at": "${end_ts}",
    "junit": "${junit}",
    "nodeid": "${STEP_NODEID}",
    "api_base": "${API_BASE}",
    "state_dir": "${STATE_DIR}",
}
with open(summary_path, "w") as f:
    json.dump(data, f, indent=2)
PYCODE
  echo "Result: $result (exit $status). Reports in $step_dir"
  return "$status"
}

run_all() {
  local idx=1
  local rc=0
  local total
  total=$("$PY_BIN" - "$STEPS_FILE" <<'PYCODE'
import json, sys
try:
    steps = json.loads(open(sys.argv[1]).read())
    print(len(steps))
except Exception:
    print(0)
PYCODE
  )
  while [[ $idx -le ${total:-0} ]]; do
    if ! run_step "$idx"; then
      rc=$?
      echo "Stopping after failure (step $idx)."
      break
    fi
    idx=$((idx+1))
  done
  return "$rc"
}

missionctl() {
  cd "$ROOT_DIR"
  init_bins
  init_defaults
  check_prereqs
  echo "Waiting for Seed API to be ready at $API_BASE ..."
  local i
  for i in {1..30}; do
    if curl -fsS "$API_BASE/health" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  list_steps
  while true; do
    print_menu
    printf "Select a step (number, a=all, q=quit): "
    read -r choice
    case "$choice" in
      q|Q) exit 0 ;;
      a|A) run_all; exit $? ;;
      '' ) continue ;;
      *)
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
          run_step "$choice" || true
        else
          echo "Invalid choice."
        fi
        ;;
    esac
  done
}

CMD="${1:-missionctl}"
shift || true
case "$CMD" in
  missionctl) missionctl ;;
  *) usage; exit 1 ;;
esac
