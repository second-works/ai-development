#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
environment_install="$(python3 -c 'import json, pathlib, sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["install"])' "$ROOT/.cursor/environment.json")"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/project/scripts"
cp "$ROOT/scripts/collect-github-state.py" "$ROOT/scripts/render-status-report.py" "$fixture/project/scripts/"
for tool in python3 node head; do
  ln -s "$(command -v "$tool")" "$fixture/bin/$tool"
done

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
