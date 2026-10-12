#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASK_TEMP="$(mktemp -d /tmp/nessa-sync-verification.XXXXXX)"
TASK_PEER_PID=""
cleanup() {
  if [[ -n "$TASK_PEER_PID" ]]; then
    kill "$TASK_PEER_PID" 2>/dev/null || true
    wait "$TASK_PEER_PID" 2>/dev/null || true
  fi
  rm -rf "$TASK_TEMP"
}
trap cleanup EXIT
if [[ -n "${NESSA_VERIFICATION_PYTHON:-}" ]]; then
  TASK_PYTHON="$NESSA_VERIFICATION_PYTHON"
else
  python3 -m venv "$TASK_TEMP/venv"
  "$TASK_TEMP/venv/bin/pip" install -q -r "$TASK_ROOT/verification/sync/requirements.txt"
  TASK_PYTHON="$TASK_TEMP/venv/bin/python"
fi
"$TASK_PYTHON" "$TASK_ROOT/verification/sync/feed_peer.py" "$TASK_TEMP/port" > "$TASK_TEMP/peer.log" 2>&1 &
TASK_PEER_PID=$!
for _ in {1..200}; do
  if [[ -s "$TASK_TEMP/port" ]]; then break; fi
  if ! kill -0 "$TASK_PEER_PID" 2>/dev/null; then cat "$TASK_TEMP/peer.log"; exit 1; fi
  sleep 0.05
done
[[ -s "$TASK_TEMP/port" ]]
swift build --package-path "$TASK_ROOT" --product PhoneSyncVerification
"$TASK_PYTHON" - "$TASK_ROOT/.build/debug/PhoneSyncVerification" "ws://127.0.0.1:$(cat "$TASK_TEMP/port")/session" "$TASK_TEMP" <<'PY'
import subprocess
import sys

try:
    subprocess.run(sys.argv[1:], check=True, timeout=75)
except subprocess.TimeoutExpired:
    print("FAIL: lifecycle verification exceeded 75 seconds", flush=True)
    sys.exit(1)
except subprocess.CalledProcessError as failure:
    sys.exit(failure.returncode)
PY
