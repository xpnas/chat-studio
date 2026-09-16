#!/usr/bin/env bash
# Reproducible disposable Studio, never an existing server/profile/database.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STUDIO="$(cd "${1:?Usage: bash scripts/studio-contract.sh /path/to/pinned-studio}" && pwd)"
EXPECTED=b44c74318fe5a0a1f3aed29d5095393964fc3d62
[[ "$(git -C "$STUDIO" rev-parse HEAD)" == "$EXPECTED" ]] || { echo 'Wrong Studio revision' >&2; exit 1; }
[[ -d "$STUDIO/node_modules" ]] || { echo 'Run npm ci in Studio first' >&2; exit 1; }
# Fail before bootstrap if either port belongs to another process.
node --input-type=module - <<'JS'
import net from 'node:net';
for (const port of [18647, 18648]) {
  await new Promise((resolve, reject) => {
    const s = net.createServer(); s.once('error', reject);
    s.listen(port, '127.0.0.1', () => s.close(resolve));
  });
}
JS
umask 077
STATE="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/chatstudio-contract.XXXXXXXX")"
STUDIO_PID='' FIXTURE_PID=''
cleanup() {
  local code=$?
  trap - EXIT
  for pid in "$STUDIO_PID" "$FIXTURE_PID"; do
    if [[ -n "$pid" ]]; then kill -- "-$pid" 2>/dev/null || true; fi
  done
  # Bound cleanup even if a runtime child ignores graceful shutdown.
  sleep 1
  for pid in "$STUDIO_PID" "$FIXTURE_PID"; do
    if [[ -n "$pid" ]]; then kill -KILL -- "-$pid" 2>/dev/null || true; fi
  done
  # setsid gives each service a group, including runtime children.
  for pid in "$STUDIO_PID" "$FIXTURE_PID"; do
    if [[ -n "$pid" ]]; then wait "$pid" 2>/dev/null || true; fi
  done
  if [[ "${CHATSTUDIO_KEEP_CONTRACT_STATE:-0}" == 1 ]]; then
    printf 'Private diagnostic state retained at %s (do not upload)\n' "$STATE"
  else
    rm -rf -- "$STATE"
  fi
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export CHATSTUDIO_TEST_MEDIA=1 CHATSTUDIO_TEST_SERVER=http://127.0.0.1:18647
export CHATSTUDIO_TEST_PASSWORD
CHATSTUDIO_TEST_PASSWORD="$(openssl rand -hex 24)"
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then echo "::add-mask::$CHATSTUDIO_TEST_PASSWORD"; fi
export WORKSPACE_BASE="$STATE/workspace"
mkdir -p "$WORKSPACE_BASE"
export HERMES_HOME="$STATE/hermes" HERMES_WEB_UI_HOME="$STATE/studio"
export HERMES_WEBUI_STATE_DIR="$HERMES_WEB_UI_HOME"
export NODE_ENV=test HERMES_WEB_UI_TEST_DB_DIR="$STATE/database"
export HERMES_RUNTIME_SOURCE=none PORT=18647 BIND_HOST=127.0.0.1
export HERMES_LAN_DISCOVERY_ENABLED=false HERMES_WEB_UI_DISABLE_GATEWAY_AUTOSTART=1
export HERMES_WEB_UI_DISABLE_MCP_AUTOINJECT=1
export TS_NODE_PROJECT=packages/server/tsconfig.json TS_NODE_TRANSPILE_ONLY=true
export TS_NODE_COMPILER_OPTIONS='{"rootDir":"../../"}'
mkdir -p "$HERMES_HOME" "$HERMES_WEB_UI_HOME"
cp "$ROOT/tools/mock-provider/config.yaml" "$HERMES_HOME/config.yaml"
# Isolate HOME only for Studio: preserve the caller's Flutter SDK/pub caches.
mkdir -p "$STATE/home"
cd "$ROOT"
setsid node tools/mock-provider/server.mjs > "$STATE/provider.log" 2>&1 &
FIXTURE_PID=$!
(cd "$STUDIO" && HOME="$STATE/home" exec setsid node -r ts-node/register packages/server/src/index.ts) > "$STATE/studio.log" 2>&1 &
STUDIO_PID=$!
node tools/mock-provider/bootstrap.mjs
flutter test test/live_contract_test.dart --reporter expanded
