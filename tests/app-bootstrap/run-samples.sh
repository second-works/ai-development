#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TEMPLATE="$ROOT/templates/app-bootstrap"
WORK="$(mktemp -d)"
SERVER_PID=""
trap 'if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; fi; rm -rf "$WORK"' EXIT

APP="$WORK/app"
cp -R "$TEMPLATE" "$APP"
chmod +x "$APP/bin/setup" "$APP/bin/setup.app" "$APP/bin/doctor"

"$APP/bin/setup" >"$WORK/setup-first.log"
grep -Fq 'PASS setup: .env created from .env.example' "$WORK/setup-first.log"
grep -Fq 'PASS setup: application hook completed' "$WORK/setup-first.log"

printf 'local-setting=preserved\n' >>"$APP/.env"
before="$(shasum -a 256 "$APP/.env" | awk '{print $1}')"
"$APP/bin/setup" >"$WORK/setup-second.log"
after="$(shasum -a 256 "$APP/.env" | awk '{print $1}')"
[[ "$before" == "$after" ]]
grep -Fq 'PASS setup: existing .env preserved' "$WORK/setup-second.log"

"$APP/bin/doctor" >"$WORK/doctor-warning.log"
grep -Fq 'PASS doctor: required command: git' "$WORK/doctor-warning.log"
grep -Fq 'PASS doctor: required file: .env' "$WORK/doctor-warning.log"
grep -Fq 'WARN doctor: APP_HEALTHCHECK_URL is not configured' "$WORK/doctor-warning.log"
grep -Fq 'PASS doctor: completed with warnings' "$WORK/doctor-warning.log"

PORT_FILE="$WORK/port"
python3 - "$PORT_FILE" <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
    def log_message(self, format, *args):
        pass

server = HTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w", encoding="utf-8") as output:
    output.write(str(server.server_port))
server.serve_forever()
PY
SERVER_PID="$!"
for _ in $(seq 1 50); do
  [[ -s "$PORT_FILE" ]] && break
  sleep 0.1
done
[[ -s "$PORT_FILE" ]]
PORT="$(cat "$PORT_FILE")"
printf 'APP_HEALTHCHECK_URL=http://127.0.0.1:%s/health\n' "$PORT" >>"$APP/.env"
"$APP/bin/doctor" >"$WORK/doctor-health.log"
grep -Fq 'PASS doctor: local health endpoint' "$WORK/doctor-health.log"
grep -Fq 'PASS doctor: completed' "$WORK/doctor-health.log"

kill "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""
if "$APP/bin/doctor" >"$WORK/doctor-down.log" 2>&1; then
  exit 1
fi
grep -Fq 'FAIL doctor: local health endpoint is unavailable' "$WORK/doctor-down.log"

sed -i.bak 's#^APP_HEALTHCHECK_URL=.*#APP_HEALTHCHECK_URL=#' "$APP/.env"
grep -Fq 'local-setting=preserved' "$APP/.env"
printf 'APP_REQUIRED_COMMANDS=definitely-missing-command\n' >>"$APP/.env"
if "$APP/bin/doctor" >"$WORK/doctor-missing-command.log" 2>&1; then
  exit 1
fi
grep -Fq 'FAIL doctor: required command is unavailable: definitely-missing-command' "$WORK/doctor-missing-command.log"

printf 'app-bootstrap samples: ok\n'
