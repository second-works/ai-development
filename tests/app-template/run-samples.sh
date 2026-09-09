#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

copy_template() {
  local project_dir="$1"
  mkdir -p "$project_dir/bin"
  cp "$ROOT_DIR/templates/app/bin/setup" "$project_dir/bin/setup"
  cp "$ROOT_DIR/templates/app/bin/doctor" "$project_dir/bin/doctor"
  cp "$ROOT_DIR/templates/app/.env.example" "$project_dir/.env.example"
  cp "$ROOT_DIR/templates/app/README.md" "$project_dir/README.md"
  chmod +x "$project_dir/bin/setup" "$project_dir/bin/doctor"
}

project_dir="$WORK_DIR/sample-app"
copy_template "$project_dir"

(
  cd "$project_dir"
  ./bin/setup
  cp .env .env.before
  ./bin/setup >/dev/null
  cmp -s .env .env.before
  ./bin/doctor
)

health_project="$WORK_DIR/health-app"
copy_template "$health_project"
(
  cd "$health_project"
  ./bin/setup >/dev/null
)
health_port="$((18000 + RANDOM % 1000))"
cat > "$health_project/health_server.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format_string, *args):
        return

HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY
python3 "$health_project/health_server.py" "$health_port" >/dev/null 2>&1 &
server_pid=$!
cleanup_server() {
  kill "$server_pid" >/dev/null 2>&1 || true
}
trap 'cleanup_server; rm -rf "$WORK_DIR"' EXIT
for _ in {1..20}; do
  if curl --silent --fail "http://127.0.0.1:${health_port}/health" >/dev/null; then
    break
  fi
  sleep 0.1
done
(
  cd "$health_project"
  APP_PORT="$health_port" \
  APP_HEALTHCHECK_URL="http://127.0.0.1:${health_port}/health" \
  APP_HEALTHCHECK_REQUIRED=1 \
  APP_EXPECT_RUNNING=1 \
  ./bin/doctor
)

printf 'app setup/doctor template samples passed\n'
