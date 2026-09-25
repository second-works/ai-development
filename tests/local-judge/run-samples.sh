#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
python3 -m unittest discover -s "$ROOT_DIR/tests/local-judge" -p 'test_*.py' -v
