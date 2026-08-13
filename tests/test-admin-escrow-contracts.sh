#!/usr/bin/env bash

# 驗證template、environment contract、workflow順序與敏感資料邊界；只讀取
# repository檔案，不連線外部系統。
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dev_template="${repository_root}/argocd/bootstrap/argocd-app-dev.yaml.tftpl"
prod_template="${repository_root}/argocd/bootstrap/argocd-app-prod.yaml.tftpl"
apply_stage="${repository_root}/.github/workflows/terraform-apply-stage.yml"
dev_workflow="${repository_root}/.github/workflows/terraform-apply-dev.yml"
prod_workflow="${repository_root}/.github/workflows/terraform-apply-prod.yml"
escrow_script="${repository_root}/scripts/escrow-argocd-initial-admin-password.sh"
loader_action="${repository_root}/.github/actions/load-environment-config/action.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for account in dev-readonly dev-operator prod-readonly prod-operator; do
  if grep -Fq -- "${account}" "${dev_template}" "${prod_template}"; then
    fail "removed local account remains in an active template: ${account}"
  fi
done
if grep -Eq 'argocd-rbac-cm|policy\.csv|role:(dev|prod)-(readonly|operator)' \
  "${dev_template}" "${prod_template}"; then
  fail "custom local-account RBAC remains in an active template"
fi
for template in "${dev_template}" "${prod_template}"; do
  grep -Fq 'path: /data/url' "${template}" || fail "canonical URL patch is missing"
  grep -Fq 'value: https://${argocd_internal_fqdn}' "${template}" || \
    fail "dynamic canonical URL placeholder is missing"
done

command -v jq >/dev/null || fail "jq is required for contract tests"
jq -e '.admin_password_parameter_name == "/gitops/dev/platform/argocd/ADMIN_PASSWORD"' \
  "${repository_root}/terraform/argocd/environments/dev.json" >/dev/null || \
  fail "Dev admin password parameter contract is invalid"
jq -e 'has("admin_password_parameter_name") | not' \
  "${repository_root}/terraform/argocd/environments/prod.json" >/dev/null || \
  fail "Prod environment must not define an admin password parameter"
grep -Fq 'admin_password_parameter=${ADMIN_PASSWORD_PARAMETER}' "${loader_action}" || \
  fail "environment loader does not emit the non-secret Dev parameter path"

# dev.json 是 canonical source，但 loader 與 escrow script 各自保有一份 allowlist
# 作為 poisoned-config 防護。三處必須同步，否則只改 dev.json 會通過全部 CI
# checks，卻在 install job 執行 escrow 時才失敗。
canonical_parameter="$(jq -er '.admin_password_parameter_name' \
  "${repository_root}/terraform/argocd/environments/dev.json")"
grep -Fq "\"${canonical_parameter}\"" "${loader_action}" || \
  fail "environment loader allowlist does not match dev.json: ${canonical_parameter}"
grep -Fq "[[ \"\${parameter_name}\" == \"${canonical_parameter}\" ]]" "${escrow_script}" || \
  fail "escrow script allowlist does not match dev.json: ${canonical_parameter}"

apply_line="$(grep -n 'name: "Terraform Apply (' "${apply_stage}" | head -n 1 | cut -d: -f1)"
escrow_line="$(grep -n 'name: "Escrow Dev ArgoCD initial admin password"' "${apply_stage}" | cut -d: -f1)"
close_line="$(grep -n 'name: "Close automation VPN tunnel"' "${apply_stage}" | cut -d: -f1)"
[[ -n "${apply_line}" && -n "${escrow_line}" && -n "${close_line}" ]] || \
  fail "required install-stage steps are missing"
((apply_line < escrow_line && escrow_line < close_line)) || \
  fail "escrow must run after install apply and before the tunnel closes"
grep -A 4 '^  register-argocd-application:' "${dev_workflow}" | \
  grep -Fq 'needs: install-argocd' || fail "Dev self-manage does not wait for install and escrow"

# Prod 走的是同一支 reusable workflow，所以只 grep prod workflow 沒有意義：escrow
# 全部邏輯都在 terraform-apply-stage.yml。真正要驗的是每個 escrow step 都帶著
# dev-only guard，以及 prod workflow 只以 environment: prod 呼叫該 workflow。
step_guards() {
  awk '
    function flush() { if (step_name != "") printf "%s\t%s\n", step_name, step_guard }
    /^      - name: / {
      flush()
      step_name = $0
      sub(/^      - name: /, "", step_name)
      gsub(/^"|"$/, "", step_name)
      step_guard = ""
      next
    }
    /^        if: / {
      if (step_name != "" && step_guard == "") {
        step_guard = $0
        sub(/^        if: /, "", step_guard)
      }
      next
    }
    END { flush() }
  ' "$1"
}

dev_guard="inputs.environment == 'dev' && inputs.stage == 'install'"
guard_table="$(step_guards "${apply_stage}")"

assert_step_guard() {
  local step="$1"
  local expected="$2"
  local actual
  actual="$(printf '%s\n' "${guard_table}" | awk -F'\t' -v s="${step}" '$1 == s { print $2 }')"
  [[ -n "${actual}" ]] || fail "escrow step is missing from the apply stage: ${step}"
  [[ "${actual}" == "${expected}" ]] || \
    fail "escrow step guard is wrong for '${step}': ${actual}"
}

assert_step_guard "Install kubectl for Dev admin password escrow" "${dev_guard}"
assert_step_guard "Fetch Dev Management Cluster credentials from SSM" "${dev_guard}"
assert_step_guard "Configure Dev admin escrow AWS credentials" "${dev_guard}"
assert_step_guard "Escrow Dev ArgoCD initial admin password" "${dev_guard}"
assert_step_guard "Clear Dev admin escrow credential environment" "always() && ${dev_guard}"

# 任何提及 escrow／admin password 的 step 都必須帶 dev-only guard，避免日後新增
# step 時漏掉條件。
while IFS=$'\t' read -r step_name step_guard; do
  case "${step_name}" in
    *"admin password escrow"* | *"admin escrow"* | *"Escrow Dev"*) ;;
    *) continue ;;
  esac
  [[ "${step_guard}" == *"${dev_guard}"* ]] || \
    fail "escrow-related step is not restricted to Dev install: ${step_name}"
done <<< "${guard_table}"

# Prod 只能以 environment: prod 呼叫 reusable workflow。
grep -Fq 'environment: prod' "${prod_workflow}" || \
  fail "Prod workflow does not pass environment: prod to the apply stage"
if grep -Fq 'environment: dev' "${prod_workflow}"; then
  fail "Prod workflow passes environment: dev to the apply stage"
fi
if grep -Eiq 'dev-admin-escrow' "${prod_workflow}"; then
  fail "Prod workflow references the Dev admin escrow OIDC role"
fi

for prohibited in upload-artifact --overwrite 'set -x'; do
  if grep -Fq -- "${prohibited}" "${escrow_script}"; then
    fail "escrow script contains prohibited data path or behavior: ${prohibited}"
  fi
done
if grep -Eq '>>.*GITHUB_(ENV|OUTPUT|STEP_SUMMARY)' "${escrow_script}"; then
  fail "escrow script writes to a prohibited GitHub data channel"
fi
grep -Fq -- '--type SecureString' "${escrow_script}" || fail "SecureString type is missing"
grep -Fq -- '--value "file://${admin_password_file}"' "${escrow_script}" || \
  fail "SSM value must be supplied through a restricted file"
grep -Fq -- '::add-mask::%s' "${escrow_script}" || fail "GitHub mask command is missing"
grep -Fq -- 'cmp -s "${admin_password_file}" "${ssm_value_file}"' "${escrow_script}" || \
  fail "same-value confirmation is missing"

echo "PASS: ArgoCD admin escrow static contracts"
