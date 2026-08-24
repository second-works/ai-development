#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_SOURCE="${ROOT_DIR}/templates/verification/verify.sh"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

make_stage() {
  local project_dir="$1"
  local stage="$2"
  local exit_status="$3"
  cat > "${project_dir}/scripts/${stage}.sh" <<EOF
#!/usr/bin/env bash
printf '%s\\n' '${stage}' >> "\${VERIFY_MARKER_FILE}"
exit ${exit_status}
EOF
  chmod +x "${project_dir}/scripts/${stage}.sh"
}

success_project="${WORK_DIR}/success-project"
mkdir -p "${success_project}/scripts"
cp "${VERIFY_SOURCE}" "${success_project}/scripts/verify.sh"
chmod +x "${success_project}/scripts/verify.sh"
for stage in lint typecheck test build; do
  make_stage "${success_project}" "${stage}" 0
done
success_markers="${success_project}/markers.txt"
(cd "${success_project}" && VERIFY_STACK=generic VERIFY_MARKER_FILE="${success_markers}" ./scripts/verify.sh)
expected_markers=$'lint\ntypecheck\ntest\nbuild'
[[ "$(<"${success_markers}")" == "${expected_markers}" ]] || {
  printf 'success sample executed stages in an unexpected order\n' >&2
  exit 1
}

failure_project="${WORK_DIR}/failure-project"
mkdir -p "${failure_project}/scripts"
cp "${VERIFY_SOURCE}" "${failure_project}/scripts/verify.sh"
chmod +x "${failure_project}/scripts/verify.sh"
make_stage "${failure_project}" lint 17
for stage in typecheck test build; do
  make_stage "${failure_project}" "${stage}" 0
done
failure_markers="${failure_project}/markers.txt"
set +e
failure_output="$(cd "${failure_project}" && VERIFY_STACK=generic VERIFY_MARKER_FILE="${failure_markers}" ./scripts/verify.sh 2>&1)"
failure_status=$?
set -e
[[ "${failure_status}" -eq 17 ]] || {
  printf 'lint failure did not preserve its exit status\n' >&2
  exit 1
}
[[ "${failure_output}" == *'stage=lint failed'* ]] || {
  printf 'lint failure was not identified in the log\n' >&2
  exit 1
}
[[ "$(<"${failure_markers}")" == lint ]] || {
  printf 'verification continued after lint failure\n' >&2
  exit 1
}

printf 'template verification samples passed\n'
