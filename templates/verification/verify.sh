#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

stage_count=0

skip_stage() {
  local stage="$1"
  local reason="$2"
  printf '[verify] stage=%s skipped reason=%s\n' "${stage}" "${reason}"
}

run_stage() {
  local stage="$1"
  shift
  stage_count=$((stage_count + 1))
  printf '[verify] stage=%s started\n' "${stage}"
  if "$@"; then
    printf '[verify] stage=%s passed\n' "${stage}"
  else
    local status=$?
    printf '[verify] stage=%s failed exit=%s\n' "${stage}" "${status}" >&2
    exit "${status}"
  fi
}

has_npm_script() {
  node -e '
    const fs = require("fs");
    const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8"));
    const scriptName = process.argv[1];
    process.exit(typeof packageJson.scripts?.[scriptName] === "string" ? 0 : 1);
  ' "$1" >/dev/null 2>&1
}

has_python_tests() {
  [[ -d tests ]] && [[ -n "$(find tests -type f \( -name 'test_*.py' -o -name '*_test.py' \) -print -quit)" ]]
}

has_ruff_config() {
  [[ -f ruff.toml || -f .ruff.toml ]] || {
    [[ -f pyproject.toml ]] && grep -qE '^\[tool\.ruff([.]|\])' pyproject.toml
  }
}

has_mypy_config() {
  [[ -f mypy.ini || -f .mypy.ini ]] || {
    [[ -f pyproject.toml ]] && grep -qE '^\[tool\.mypy\]' pyproject.toml
  } || {
    [[ -f setup.cfg ]] && grep -qE '^\[mypy\]' setup.cfg
  }
}

has_python_build_config() {
  [[ -f pyproject.toml ]] && grep -qE '^\[build-system\]' pyproject.toml
}

run_node_stages() {
  if has_npm_script lint; then
    run_stage lint npm run lint
  else
    skip_stage lint 'package.json has no scripts.lint'
  fi

  if has_npm_script typecheck; then
    run_stage 'type check' npm run typecheck
  else
    skip_stage 'type check' 'package.json has no scripts.typecheck'
  fi

  if has_npm_script test; then
    run_stage test npm test
  else
    skip_stage test 'package.json has no scripts.test'
  fi

  if has_npm_script build; then
    run_stage build npm run build
  else
    skip_stage build 'package.json has no scripts.build'
  fi
}

run_python_stages() {
  if has_ruff_config; then
    run_stage lint ruff check .
  else
    skip_stage lint 'no Ruff configuration found'
  fi

  if has_mypy_config; then
    run_stage 'type check' mypy .
  else
    skip_stage 'type check' 'no mypy configuration found'
  fi

  if has_python_tests; then
    run_stage test pytest -q
  else
    skip_stage test 'no Python test files found'
  fi

  if has_python_build_config; then
    run_stage build python -m build
  else
    skip_stage build 'no PEP 517 build configuration found'
  fi
}

run_generic_stages() {
  local stage
  local script
  local ran_stage=0
  for stage in lint typecheck test build; do
    script="${ROOT_DIR}/scripts/${stage}.sh"
    if [[ -x "${script}" ]]; then
      run_stage "${stage}" "${script}"
      ran_stage=1
    else
      skip_stage "${stage}" "${script} is not executable"
    fi
  done

  if ((ran_stage == 0)) && [[ -x "${ROOT_DIR}/scripts/ci.sh" ]]; then
    run_stage generic-ci "${ROOT_DIR}/scripts/ci.sh"
  fi
}

stack="${VERIFY_STACK:-auto}"
if [[ "${stack}" == auto ]]; then
  if [[ -f package.json ]]; then
    stack=node
  elif [[ -f pyproject.toml || -f requirements.txt || -f setup.py ]]; then
    stack=python
  else
    stack=generic
  fi
fi

case "${stack}" in
  node)
    [[ -f package.json ]] || { printf '[verify] stack=node requires package.json\n' >&2; exit 2; }
    run_node_stages
    ;;
  python)
    [[ -f pyproject.toml || -f requirements.txt || -f setup.py ]] || {
      printf '[verify] stack=python requires pyproject.toml, requirements.txt, or setup.py\n' >&2
      exit 2
    }
    run_python_stages
    ;;
  generic)
    run_generic_stages
    ;;
  *)
    printf '[verify] unsupported VERIFY_STACK=%s\n' "${stack}" >&2
    exit 2
    ;;
esac

printf '[verify] completed stack=%s applicable_stages=%s\n' "${stack}" "${stage_count}"
