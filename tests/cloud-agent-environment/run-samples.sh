#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
environment_install="$(python3 -c 'import json, pathlib, sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["install"])' "$ROOT/.cursor/environment.json")"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/project/scripts"
cp "$ROOT/scripts/collect-github-state.py" "$ROOT/scripts/render-status-report.py" "$fixture/project/scripts/"

# pyenv/asdf/Volta等のshimは隔離PATHで動作しないため、実体を先に取得する。
resolve_runtime() {
  case "$1" in
    python3) python3 -c 'import sys; print(sys.executable)' ;;
    node) node -p 'process.execPath' ;;
  esac
}
for tool in python3 node; do
  ln -s "$(resolve_runtime "$tool")" "$fixture/bin/$tool"
done

# 外部commandへ依存するshimを経由しても同じ実体へ解決することを検証。
mkdir "$fixture/shims"
cat > "$fixture/shims/python3" <<'SH'
#!/bin/sh
set -e
printf shim | grep shim | sed s/shim/shim/ | tr a-z a-z >/dev/null
case "$0" in
  */python3) exec "$CLOUD_AGENT_REAL_PYTHON" "$@" ;;
  */node) exec "$CLOUD_AGENT_REAL_NODE" "$@" ;;
esac
SH
cp "$fixture/shims/python3" "$fixture/shims/node"
chmod +x "$fixture/shims/python3" "$fixture/shims/node"
CLOUD_AGENT_REAL_PYTHON="$(resolve_runtime python3)"
CLOUD_AGENT_REAL_NODE="$(resolve_runtime node)"
export CLOUD_AGENT_REAL_PYTHON CLOUD_AGENT_REAL_NODE
[[ "$(PATH="$fixture/shims:$PATH" resolve_runtime python3)" == "$CLOUD_AGENT_REAL_PYTHON" ]]
[[ "$(PATH="$fixture/shims:$PATH" resolve_runtime node)" == "$CLOUD_AGENT_REAL_NODE" ]]

# 実設定を隔離projectへ適用する。実repoや共有cacheへbytecodeを残さない。
run_install() {
  (cd "$fixture/project" && PATH="$fixture/bin" PYTHONPYCACHEPREFIX="$fixture/cache" /bin/sh -c "$environment_install") >"$fixture/output" 2>&1
}

# 旧Harnessの2異常系を保持し、終了codeと後続compile停止も確認する。
if run_install; then
  printf 'Cloud Agent install must fail when bash is unavailable\n' >&2
  exit 1
fi
[[ ! -d "$fixture/cache" ]] || { printf 'install continued after missing bash\n' >&2; exit 1; }
cat > "$fixture/bin/bash" <<'SH'
#!/bin/sh
exit 42
SH
chmod +x "$fixture/bin/bash"
status=0
run_install || status=$?
[[ "$status" == 42 ]] || { printf 'bash version failure was not propagated: %s\n' "$status" >&2; exit 1; }
[[ ! -d "$fixture/cache" ]] || { printf 'install continued after bash failure\n' >&2; exit 1; }

# 正常時は実際のPython compilerが両scriptを検証する。
rm "$fixture/bin/bash"
ln -s "$(command -v bash)" "$fixture/bin/bash"
run_install || { cat "$fixture/output" >&2; exit 1; }
python3 - "$fixture" <<'PY'
from pathlib import Path
import sys
fixture = Path(sys.argv[1])
for name in ('collect-github-state', 'render-status-report'):
    assert list((fixture / 'cache').rglob(f'{name}.*.pyc')), name
assert not list((fixture / 'project').rglob('__pycache__'))
PY

# compile失敗を成功扱いせず、設定の末尾まで到達することを確認する。
printf 'invalid python syntax !\n' > "$fixture/project/scripts/render-status-report.py"
if run_install; then
  printf 'Cloud Agent install must propagate Python compile failure\n' >&2
  exit 1
fi
printf 'Cloud Agent environment execution regression: PASS\n'
