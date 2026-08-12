#!/usr/bin/env bash

# 將 Dev 首次安裝產生的 ArgoCD initial admin password 複製至 SSM
# SecureString；確認保存內容相同後才刪除 initial Secret。此腳本不輪替
# password，也不管理 argocd-secret 中由 ArgoCD 維護的 bcrypt hash。
set -euo pipefail

namespace="argocd"
secret_name="argocd-initial-admin-secret"
secret_key="password"
parameter_name="${ARGOCD_ADMIN_PASSWORD_PARAMETER_NAME:-}"
poll_attempts="${ARGOCD_ADMIN_SECRET_POLL_ATTEMPTS:-12}"
poll_interval_seconds="${ARGOCD_ADMIN_SECRET_POLL_INTERVAL_SECONDS:-5}"

[[ -n "${RUNNER_TEMP:-}" && -d "${RUNNER_TEMP}" ]] || {
  echo "RUNNER_TEMP must be an existing directory" >&2
  exit 2
}
[[ -n "${KUBECONFIG:-}" && -f "${KUBECONFIG}" && ! -L "${KUBECONFIG}" ]] || {
  echo "A regular temporary kubeconfig file is required" >&2
  exit 2
}
[[ "${parameter_name}" == "/gitops/dev/platform/argocd/ADMIN_PASSWORD" ]] || {
  echo "The admin password escrow parameter does not match the approved Dev contract" >&2
  exit 2
}
[[ "${parameter_name}" != *[[:space:]]* ]] || {
  echo "The admin password escrow parameter name contains whitespace" >&2
  exit 2
}
[[ "${poll_attempts}" =~ ^[1-9][0-9]*$ ]] || {
  echo "ARGOCD_ADMIN_SECRET_POLL_ATTEMPTS must be a positive integer" >&2
  exit 2
}
[[ "${poll_interval_seconds}" =~ ^[0-9]+$ ]] || {
  echo "ARGOCD_ADMIN_SECRET_POLL_INTERVAL_SECONDS must be a non-negative integer" >&2
  exit 2
}
command -v aws >/dev/null
command -v kubectl >/dev/null
command -v base64 >/dev/null
command -v cmp >/dev/null
command -v jq >/dev/null
command -v wc >/dev/null

umask 077
temp_directory="$(mktemp -d "${RUNNER_TEMP%/}/argocd-admin-escrow.XXXXXX")"
secret_presence_file="${temp_directory}/secret-presence"
secret_base64_file="${temp_directory}/secret-password.base64"
admin_password_file="${temp_directory}/admin-password"
ssm_value_file="${temp_directory}/ssm-value"
ssm_raw_value_file="${temp_directory}/ssm-raw-value"
ssm_type_file="${temp_directory}/ssm-type"
command_error_file="${temp_directory}/command-error"
command_output_file="${temp_directory}/command-output"

cleanup() {
  rm -f -- \
    "${secret_presence_file}" \
    "${secret_base64_file}" \
    "${admin_password_file}" \
    "${ssm_value_file}" \
    "${ssm_raw_value_file}" \
    "${ssm_type_file}" \
    "${command_error_file}" \
    "${command_output_file}"
  rmdir -- "${temp_directory}" 2>/dev/null || true
}
# 正常結束由 EXIT trap 清理；收到終止 signal 時，清理後必須停止執行。
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

touch \
  "${secret_presence_file}" \
  "${secret_base64_file}" \
  "${admin_password_file}" \
  "${ssm_value_file}" \
  "${ssm_raw_value_file}" \
  "${ssm_type_file}" \
  "${command_error_file}" \
  "${command_output_file}"
chmod 600 "${temp_directory}"/*

secret_exists() {
  : >"${secret_presence_file}"
  : >"${command_error_file}"
  if ! kubectl --kubeconfig "${KUBECONFIG}" \
    --namespace "${namespace}" \
    get secret "${secret_name}" \
    --ignore-not-found \
    --output=name \
    >"${secret_presence_file}" 2>"${command_error_file}"; then
    echo "Unable to determine whether the ArgoCD initial admin Secret exists" >&2
    return 2
  fi
  if grep -qx "secret/${secret_name}" "${secret_presence_file}"; then
    return 0
  fi
  return 1
}

read_ssm_parameter() {
  : >"${ssm_value_file}"
  : >"${ssm_raw_value_file}"
  : >"${ssm_type_file}"
  : >"${command_error_file}"
  if aws ssm get-parameter \
    --name "${parameter_name}" \
    --query Parameter.Type \
    --output text \
    >"${ssm_type_file}" 2>"${command_error_file}"; then
    if ! grep -qx 'SecureString' "${ssm_type_file}"; then
      echo "The Dev ArgoCD admin password escrow parameter is not a SecureString" >&2
      return 2
    fi
    if ! aws ssm get-parameter \
      --name "${parameter_name}" \
      --with-decryption \
      --query Parameter.Value \
      --output json \
      >"${ssm_raw_value_file}" 2>"${command_error_file}"; then
      echo "Unable to decrypt the Dev ArgoCD admin password escrow parameter" >&2
      return 2
    fi
    if ! jq -j '.' "${ssm_raw_value_file}" >"${ssm_value_file}"; then
      echo "Unable to decode the Dev ArgoCD admin password escrow parameter" >&2
      return 2
    fi
    [[ -s "${ssm_value_file}" ]] || {
      echo "The Dev ArgoCD admin password escrow parameter is empty" >&2
      return 2
    }
    return 0
  fi
  if grep -q "ParameterNotFound" "${command_error_file}"; then
    : >"${ssm_value_file}"
    return 1
  fi
  echo "Unable to read the Dev ArgoCD admin password escrow parameter" >&2
  return 2
}

delete_initial_secret() {
  : >"${command_error_file}"
  if ! kubectl --kubeconfig "${KUBECONFIG}" \
    --namespace "${namespace}" \
    delete secret "${secret_name}" \
    --wait=true \
    >"${command_output_file}" 2>"${command_error_file}"; then
    echo "The password is escrowed, but deleting the ArgoCD initial admin Secret failed" >&2
    return 1
  fi
  echo "Dev ArgoCD initial admin password escrow is complete; the initial Secret was deleted."
}

if secret_exists; then
  secret_state="present"
else
  secret_status=$?
  [[ "${secret_status}" -eq 1 ]] || exit "${secret_status}"
  secret_state="absent"
fi

if read_ssm_parameter; then
  ssm_state="present"
else
  ssm_status=$?
  [[ "${ssm_status}" -eq 1 ]] || exit "${ssm_status}"
  ssm_state="absent"
fi

if [[ "${secret_state}" == "absent" && "${ssm_state}" == "present" ]]; then
  echo "Dev ArgoCD initial admin password escrow is already complete."
  exit 0
fi

attempt=1
while [[ "${secret_state}" == "absent" && "${ssm_state}" == "absent" &&
  "${attempt}" -lt "${poll_attempts}" ]]; do
  # 迴圈進入前已檢查過一次，因此先累加再顯示，讓訊息涵蓋到 ${poll_attempts}。
  attempt=$((attempt + 1))
  echo "等待 ArgoCD initial admin Secret（${attempt}/${poll_attempts}）。"
  sleep "${poll_interval_seconds}"

  if secret_exists; then
    secret_state="present"
  else
    secret_status=$?
    [[ "${secret_status}" -eq 1 ]] || exit "${secret_status}"
  fi

  if read_ssm_parameter; then
    ssm_state="present"
  else
    ssm_status=$?
    [[ "${ssm_status}" -eq 1 ]] || exit "${ssm_status}"
  fi
done

if [[ "${secret_state}" == "absent" && "${ssm_state}" == "present" ]]; then
  echo "Dev ArgoCD initial admin password escrow is already complete."
  exit 0
fi
if [[ "${secret_state}" == "absent" ]]; then
  echo "::error::The ArgoCD initial admin Secret and Dev escrow parameter are both absent" >&2
  exit 1
fi

# Secret value 直接重導至權限受限檔案，不讓 base64 或 plaintext 出現在 stdout。
if ! kubectl --kubeconfig "${KUBECONFIG}" \
  --namespace "${namespace}" \
  get secret "${secret_name}" \
  --output="go-template={{ index .data \"${secret_key}\" }}" \
  >"${secret_base64_file}" 2>"${command_error_file}"; then
  echo "Unable to read the ArgoCD initial admin password" >&2
  exit 1
fi
[[ -s "${secret_base64_file}" ]] || {
  echo "The ArgoCD initial admin password is empty" >&2
  exit 1
}
if ! base64 --decode <"${secret_base64_file}" >"${admin_password_file}"; then
  echo "The ArgoCD initial admin password is not valid base64" >&2
  exit 1
fi
rm -f -- "${secret_base64_file}"
[[ -s "${admin_password_file}" ]] || {
  echo "The decoded ArgoCD initial admin password is empty" >&2
  exit 1
}
if LC_ALL=C grep -q '[[:cntrl:]]' "${admin_password_file}"; then
  echo "The decoded ArgoCD initial admin password contains unsupported control characters" >&2
  exit 1
fi
if [[ "$(wc -l <"${admin_password_file}")" -ne 0 ]]; then
  echo "The decoded ArgoCD initial admin password contains a line break" >&2
  exit 1
fi

# GitHub mask command 是唯一把 plaintext 寫往 workflow command channel 的位置；
# runner 會在後續 log 中遮罩相同值，且此值不寫入 output、summary 或 GITHUB_ENV。
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  IFS= read -r admin_password_mask <"${admin_password_file}" || true
  escaped_admin_password_mask="${admin_password_mask//'%'/'%25'}"
  printf '::add-mask::%s\n' "${escaped_admin_password_mask}"
  unset admin_password_mask escaped_admin_password_mask
fi

# 再讀一次 SSM，讓等待期間或併發建立的 parameter 也走同值比對。
if read_ssm_parameter; then
  if ! cmp -s "${admin_password_file}" "${ssm_value_file}"; then
    echo "::error::The existing Dev escrow parameter differs from the ArgoCD initial admin password" >&2
    exit 1
  fi
  delete_initial_secret
  exit 0
else
  ssm_status=$?
  [[ "${ssm_status}" -eq 1 ]] || exit "${ssm_status}"
fi

: >"${command_error_file}"
if ! aws ssm put-parameter \
  --name "${parameter_name}" \
  --type SecureString \
  --value "file://${admin_password_file}" \
  --description "Temporary Dev ArgoCD initial admin password escrow" \
  >"${command_output_file}" 2>"${command_error_file}"; then
  # 另一個執行若剛建立同名 parameter，只接受值完全相同的結果。
  if ! read_ssm_parameter; then
    echo "Unable to create or confirm the Dev ArgoCD admin password escrow parameter" >&2
    exit 1
  fi
fi

if ! read_ssm_parameter; then
  echo "Unable to confirm the Dev ArgoCD admin password escrow parameter after creation" >&2
  exit 1
fi
if ! cmp -s "${admin_password_file}" "${ssm_value_file}"; then
  echo "::error::The confirmed Dev escrow parameter differs from the ArgoCD initial admin password" >&2
  exit 1
fi

delete_initial_secret
