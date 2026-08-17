#!/usr/bin/env bash

# 以本機 mock 驗證 escrow 的五種狀態轉移，以及 put-parameter race、SSM type
# 與 AWS 錯誤分類三條例外分支；不連線 AWS 或 Cluster，也不使用實際
# credential。測試資料只存在 test process 的暫存目錄。
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_under_test="${repository_root}/scripts/escrow-argocd-initial-admin-password.sh"
test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT

fixture_password="test-initial-admin-password"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# 斷言失敗訊息只印 label，不印被比對的字串，避免 fixture password 進入 CI log。
assert_contains() {
  local file="$1"
  local expected="$2"
  local label="$3"
  grep -Fq -- "${expected}" "${file}" || fail "${label}: expected content is missing"
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  local label="$3"
  if grep -Fq -- "${unexpected}" "${file}"; then
    fail "${label}: prohibited content is present"
  fi
}

make_mocks() {
  local case_directory="$1"
  mkdir -p "${case_directory}/bin" "${case_directory}/runner-temp"

  cat >"${case_directory}/bin/aws" <<'MOCK_AWS'
#!/usr/bin/env bash
set -euo pipefail
printf 'aws' >>"${MOCK_CALL_LOG}"
printf ' %q' "$@" >>"${MOCK_CALL_LOG}"
printf '\n' >>"${MOCK_CALL_LOG}"

operation="${1:-} ${2:-}"
case "${operation}" in
  "ssm get-parameter")
    if [[ "$(<"${MOCK_SSM_STATE_FILE}")" == "present" ]]; then
      if [[ " $* " == *" Parameter.Type "* ]]; then
        printf '%s\n' "$(<"${MOCK_SSM_TYPE_FILE}")"
      else
        jq -Rs . "${MOCK_SSM_VALUE_FILE}"
      fi
      exit 0
    fi
    # 預設是 ParameterNotFound；其他值用來驗證錯誤分類不會誤判為「不存在」。
    printf '%s\n' "$(<"${MOCK_SSM_GET_ERROR_FILE}")" >&2
    exit 254
    ;;
  "ssm put-parameter")
    value_argument=""
    while (($#)); do
      if [[ "$1" == "--value" ]]; then
        shift
        value_argument="${1:-}"
        break
      fi
      shift
    done
    [[ "${value_argument}" == file://* ]] || exit 90
    if [[ "$(<"${MOCK_PUT_MODE_FILE}")" == "conflict" ]]; then
      # 模擬另一個執行在本次 read 與 put 之間搶先建立同名 parameter。
      cp -- "${MOCK_PUT_CONFLICT_VALUE_FILE}" "${MOCK_SSM_VALUE_FILE}"
      printf 'SecureString' >"${MOCK_SSM_TYPE_FILE}"
      printf 'present' >"${MOCK_SSM_STATE_FILE}"
      printf 'ParameterAlreadyExists\n' >&2
      exit 254
    fi
    cp -- "${value_argument#file://}" "${MOCK_SSM_VALUE_FILE}"
    printf 'SecureString' >"${MOCK_SSM_TYPE_FILE}"
    printf 'present' >"${MOCK_SSM_STATE_FILE}"
    printf '{"Version":1}\n'
    ;;
  *)
    exit 91
    ;;
esac
MOCK_AWS

  cat >"${case_directory}/bin/kubectl" <<'MOCK_KUBECTL'
#!/usr/bin/env bash
set -euo pipefail
printf 'kubectl' >>"${MOCK_CALL_LOG}"
printf ' %q' "$@" >>"${MOCK_CALL_LOG}"
printf '\n' >>"${MOCK_CALL_LOG}"

arguments=" $* "
if [[ "${arguments}" == *" get secret "* ]]; then
  if [[ "$(<"${MOCK_SECRET_STATE_FILE}")" != "present" ]]; then
    exit 0
  fi
  if [[ "${arguments}" == *" --output=name "* ]]; then
    printf 'secret/argocd-initial-admin-secret\n'
  else
    printf '%s' "${MOCK_SECRET_VALUE}" | base64 | tr -d '\n'
  fi
  exit 0
fi
if [[ "${arguments}" == *" delete secret "* ]]; then
  [[ "$(<"${MOCK_SECRET_STATE_FILE}")" == "present" ]] || exit 1
  printf 'absent' >"${MOCK_SECRET_STATE_FILE}"
  printf 'secret deleted\n'
  exit 0
fi
exit 92
MOCK_KUBECTL

  cat >"${case_directory}/bin/sleep" <<'MOCK_SLEEP'
#!/usr/bin/env bash
set -euo pipefail
printf 'sleep %q\n' "${1:-}" >>"${MOCK_CALL_LOG}"
MOCK_SLEEP

  chmod 755 "${case_directory}/bin/aws" "${case_directory}/bin/kubectl" "${case_directory}/bin/sleep"
  : >"${case_directory}/calls.log"
  : >"${case_directory}/kubeconfig"
}

# run_case <name> <secret_state> <ssm_state> <ssm_value> <expected_exit>
#          [ssm_type] [put_mode] [put_conflict_value] [get_error]
run_case() {
  local name="$1"
  local secret_state="$2"
  local ssm_state="$3"
  local ssm_value="$4"
  local expected_exit="$5"
  local ssm_type="${6:-SecureString}"
  local put_mode="${7:-succeed}"
  local put_conflict_value="${8:-}"
  local get_error="${9:-ParameterNotFound}"
  local case_directory="${test_root}/${name}"
  local actual_exit=0

  make_mocks "${case_directory}"
  printf '%s' "${secret_state}" >"${case_directory}/secret-state"
  printf '%s' "${ssm_state}" >"${case_directory}/ssm-state"
  printf '%s' "${ssm_value}" >"${case_directory}/ssm-value"
  printf '%s' "${ssm_type}" >"${case_directory}/ssm-type"
  printf '%s' "${put_mode}" >"${case_directory}/put-mode"
  printf '%s' "${put_conflict_value}" >"${case_directory}/put-conflict-value"
  printf '%s' "${get_error}" >"${case_directory}/get-error"

  # 子程序 stdout 會重導至一般檔案，不是 GitHub workflow command channel；
  # 明確隔離 Runner 環境，避免 add-mask command 改變 state machine 測試語意。
  set +e
  PATH="${case_directory}/bin:${PATH}" \
    RUNNER_TEMP="${case_directory}/runner-temp" \
    KUBECONFIG="${case_directory}/kubeconfig" \
    GITHUB_ACTIONS=false \
    ARGOCD_ADMIN_PASSWORD_PARAMETER_NAME="/gitops/dev/platform/argocd/ADMIN_PASSWORD" \
    ARGOCD_ADMIN_SECRET_POLL_ATTEMPTS=2 \
    ARGOCD_ADMIN_SECRET_POLL_INTERVAL_SECONDS=0 \
    MOCK_CALL_LOG="${case_directory}/calls.log" \
    MOCK_SECRET_STATE_FILE="${case_directory}/secret-state" \
    MOCK_SECRET_VALUE="${fixture_password}" \
    MOCK_SSM_STATE_FILE="${case_directory}/ssm-state" \
    MOCK_SSM_VALUE_FILE="${case_directory}/ssm-value" \
    MOCK_SSM_TYPE_FILE="${case_directory}/ssm-type" \
    MOCK_SSM_GET_ERROR_FILE="${case_directory}/get-error" \
    MOCK_PUT_MODE_FILE="${case_directory}/put-mode" \
    MOCK_PUT_CONFLICT_VALUE_FILE="${case_directory}/put-conflict-value" \
    bash "${script_under_test}" >"${case_directory}/output.log" 2>&1
  actual_exit=$?
  set -e

  [[ "${actual_exit}" -eq "${expected_exit}" ]] || {
    sed "s/${fixture_password}/[REDACTED]/g" "${case_directory}/output.log" >&2
    fail "${name} exited ${actual_exit}; expected ${expected_exit}"
  }
  assert_not_contains "${case_directory}/output.log" "${fixture_password}" \
    "${name}: fixture password must not reach stdout or stderr"
  if find "${case_directory}/runner-temp" -mindepth 1 -print -quit | grep -q .; then
    fail "${name} left sensitive temporary files behind"
  fi

  CASE_DIRECTORY="${case_directory}"
}

# ── 狀態矩陣的五個分支 ────────────────────────────────────────────────────────

run_case "secret-present-ssm-absent" present absent "" 0
assert_contains "${CASE_DIRECTORY}/calls.log" "ssm put-parameter" \
  "secret-present-ssm-absent: parameter must be created"
assert_contains "${CASE_DIRECTORY}/calls.log" "--type SecureString" \
  "secret-present-ssm-absent: parameter must be a SecureString"
assert_contains "${CASE_DIRECTORY}/calls.log" "--value file://" \
  "secret-present-ssm-absent: value must be passed through a file"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "--overwrite" \
  "secret-present-ssm-absent: overwrite must never be requested"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "${fixture_password}" \
  "secret-present-ssm-absent: fixture password must not reach a CLI argument"
assert_contains "${CASE_DIRECTORY}/calls.log" "delete secret" \
  "secret-present-ssm-absent: initial Secret must be deleted"
[[ "$(<"${CASE_DIRECTORY}/secret-state")" == "absent" ]] || fail "created escrow did not delete Secret"
[[ "$(<"${CASE_DIRECTORY}/ssm-state")" == "present" ]] || fail "created escrow did not create SSM parameter"

run_case "secret-present-ssm-same" present present "${fixture_password}" 0
assert_not_contains "${CASE_DIRECTORY}/calls.log" "ssm put-parameter" \
  "secret-present-ssm-same: existing parameter must not be rewritten"
assert_contains "${CASE_DIRECTORY}/calls.log" "delete secret" \
  "secret-present-ssm-same: initial Secret must be deleted"
[[ "$(<"${CASE_DIRECTORY}/secret-state")" == "absent" ]] || fail "same-value escrow did not delete Secret"

run_case "secret-present-ssm-different" present present "different-password" 1
assert_not_contains "${CASE_DIRECTORY}/calls.log" "ssm put-parameter" \
  "secret-present-ssm-different: parameter must not be overwritten"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "delete secret" \
  "secret-present-ssm-different: initial Secret must be preserved"
[[ "$(<"${CASE_DIRECTORY}/secret-state")" == "present" ]] || fail "different-value escrow deleted Secret"
[[ "$(<"${CASE_DIRECTORY}/ssm-value")" == "different-password" ]] || fail "different-value escrow overwrote SSM"

run_case "secret-present-ssm-trailing-newline" present present $'test-initial-admin-password\n' 1
assert_not_contains "${CASE_DIRECTORY}/calls.log" "ssm put-parameter" \
  "secret-present-ssm-trailing-newline: parameter must not be overwritten"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "delete secret" \
  "secret-present-ssm-trailing-newline: initial Secret must be preserved"
[[ "$(<"${CASE_DIRECTORY}/secret-state")" == "present" ]] || fail "newline-different escrow deleted Secret"

run_case "secret-absent-ssm-present" absent present "previously-escrowed-password" 0
assert_not_contains "${CASE_DIRECTORY}/calls.log" "ssm put-parameter" \
  "secret-absent-ssm-present: completed escrow must not rotate the parameter"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "delete secret" \
  "secret-absent-ssm-present: nothing left to delete"

run_case "secret-absent-ssm-absent" absent absent "" 1
assert_contains "${CASE_DIRECTORY}/calls.log" "sleep 0" \
  "secret-absent-ssm-absent: bounded polling must run"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "ssm put-parameter" \
  "secret-absent-ssm-absent: nothing may be escrowed"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "delete secret" \
  "secret-absent-ssm-absent: nothing may be deleted"

# ── put-parameter race（TOCTOU）與錯誤分類分支 ────────────────────────────────

# 另一個執行在 read 與 put 之間建立了相同值的 parameter：不得視為失敗，
# 且必須沿用既有 parameter 後刪除 initial Secret。
run_case "race-put-conflict-same" present absent "" 0 \
  SecureString conflict "${fixture_password}"
assert_contains "${CASE_DIRECTORY}/calls.log" "ssm put-parameter" \
  "race-put-conflict-same: creation must have been attempted"
assert_contains "${CASE_DIRECTORY}/calls.log" "delete secret" \
  "race-put-conflict-same: initial Secret must be deleted"
[[ "$(<"${CASE_DIRECTORY}/secret-state")" == "absent" ]] || fail "race same-value escrow did not delete Secret"
[[ "$(<"${CASE_DIRECTORY}/ssm-value")" == "${fixture_password}" ]] || fail "race same-value escrow changed SSM"

# 搶先建立的值不同：必須 fail closed，不刪 Secret 也不動 parameter。
run_case "race-put-conflict-different" present absent "" 1 \
  SecureString conflict "racer-password"
assert_contains "${CASE_DIRECTORY}/calls.log" "ssm put-parameter" \
  "race-put-conflict-different: creation must have been attempted"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "delete secret" \
  "race-put-conflict-different: initial Secret must be preserved"
[[ "$(<"${CASE_DIRECTORY}/secret-state")" == "present" ]] || fail "race different-value escrow deleted Secret"
[[ "$(<"${CASE_DIRECTORY}/ssm-value")" == "racer-password" ]] || fail "race different-value escrow overwrote SSM"

# Parameter 存在但不是 SecureString：拒絕使用，且不得建立或刪除任何一方。
run_case "ssm-wrong-type" present present "${fixture_password}" 2 String
assert_not_contains "${CASE_DIRECTORY}/calls.log" "ssm put-parameter" \
  "ssm-wrong-type: nothing may be written"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "delete secret" \
  "ssm-wrong-type: initial Secret must be preserved"
[[ "$(<"${CASE_DIRECTORY}/secret-state")" == "present" ]] || fail "wrong-type escrow deleted Secret"

# 非 ParameterNotFound 的 AWS 錯誤不得被誤判為「parameter 不存在」。
run_case "ssm-access-denied" present absent "" 2 \
  SecureString succeed "" \
  "An error occurred (AccessDeniedException) when calling the GetParameter operation"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "ssm put-parameter" \
  "ssm-access-denied: a read failure must not trigger creation"
assert_not_contains "${CASE_DIRECTORY}/calls.log" "delete secret" \
  "ssm-access-denied: initial Secret must be preserved"
[[ "$(<"${CASE_DIRECTORY}/secret-state")" == "present" ]] || fail "access-denied escrow deleted Secret"

echo "PASS: Dev ArgoCD admin password escrow state matrix"
