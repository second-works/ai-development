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

ipv6_port="$((20000 + RANDOM % 1000))"
cat > "$health_project/ipv6_health_server.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import socket
import sys

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
    def log_message(self, format_string, *args):
        return

class IPv6HTTPServer(HTTPServer):
    address_family = socket.AF_INET6

IPv6HTTPServer(("::1", int(sys.argv[1])), Handler).serve_forever()
PY
python3 "$health_project/ipv6_health_server.py" "$ipv6_port" >/dev/null 2>&1 &
ipv6_server_pid=$!
trap 'kill "$server_pid" "$ipv6_server_pid" >/dev/null 2>&1 || true; rm -rf "$WORK_DIR"' EXIT
for _ in {1..20}; do
  if curl --noproxy '*' --silent --fail "http://[::1]:${ipv6_port}/health" >/dev/null; then
    break
  fi
  sleep 0.1
done
(
  cd "$health_project"
  APP_PORT="$ipv6_port" \
  APP_HEALTHCHECK_URL="http://[::1]:${ipv6_port}/health" \
  APP_HEALTHCHECK_REQUIRED=1 \
  APP_EXPECT_RUNNING=1 \
  ./bin/doctor
)
kill "$ipv6_server_pid" >/dev/null 2>&1 || true
ipv6_server_pid=""

secret_output="$WORK_DIR/secret-output.log"
(
  cd "$health_project"
  APP_PORT="$health_port" \
  APP_HEALTHCHECK_URL="http://user:secret@127.0.0.1:${health_port}/health?token=secret-token" \
  APP_HEALTHCHECK_REQUIRED=1 \
  APP_EXPECT_RUNNING=0 \
  ./bin/doctor
) >"$secret_output" 2>&1 || true
if grep -Fq 'secret' "$secret_output" || grep -Fq 'secret-token' "$secret_output"; then
  exit 1
fi

malformed_output="$WORK_DIR/malformed-output.log"
(
  cd "$health_project"
  APP_HEALTHCHECK_URL='http://user:topsecret@[bad/health?token=querysecret' \
  APP_HEALTHCHECK_REQUIRED=1 \
  ./bin/doctor
) >"$malformed_output" 2>&1 || true
if grep -Fq 'topsecret' "$malformed_output" || grep -Fq 'querysecret' "$malformed_output"; then
  exit 1
fi

if (
  cd "$health_project"
  APP_PORT="$((health_port + 1))" \
  APP_HEALTHCHECK_URL="http://127.0.0.1:${health_port}/health" \
  APP_HEALTHCHECK_REQUIRED=1 \
  APP_EXPECT_RUNNING=1 \
  ./bin/doctor
); then
  exit 1
fi

for invalid_value in true 2; do
  if (
    cd "$health_project"
    APP_PORT="$health_port" \
    APP_HEALTHCHECK_URL="http://127.0.0.1:${health_port}/health" \
    APP_HEALTHCHECK_REQUIRED="$invalid_value" \
    APP_EXPECT_RUNNING=0 \
    ./bin/doctor
  ); then
    exit 1
  fi
done

for empty_flag in APP_HEALTHCHECK_REQUIRED APP_EXPECT_RUNNING; do
  if (
    cd "$health_project"
    env \
      APP_PORT="$health_port" \
      APP_HEALTHCHECK_URL="http://127.0.0.1:${health_port}/health" \
      APP_HEALTHCHECK_REQUIRED=1 \
      APP_EXPECT_RUNNING=0 \
      "$empty_flag"= \
      ./bin/doctor
  ); then
    exit 1
  fi
done

printf 'app setup/doctor template samples passed\n'
