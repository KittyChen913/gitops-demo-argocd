#!/usr/bin/env bash
# ==============================================================================
# ArgoCD 執行階段健康檢查
#
# 檢查範圍：
#   1. 作為執行前提的 Kubernetes API connectivity
#   2. ArgoCD Pod 就緒狀態
#   3. ArgoCD Application sync/health 狀態
#   4. 預期的 Worker Cluster 註冊狀態
#
# Kubernetes node 與 kube-system health 由 gitops-demo-cluster 負責。
# ==============================================================================

set -euo pipefail

ENVIRONMENT="${1:-unknown}"
MGMT_LABEL="${2:-unknown}"
WORKER_LABEL="${3:-unknown}"

if [ -t 1 ] && [ -z "${CI:-}" ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; NC=''
fi

PASS=0; WARN=0; FAIL=0

pass()   { PASS=$((PASS+1)); echo -e "${GREEN}[PASS]${NC} $*"; }
warn()   { WARN=$((WARN+1)); echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()   { FAIL=$((FAIL+1)); echo -e "${RED}[FAIL]${NC} $*"; }
header() { echo ""; echo "=== $* ==="; }

header "ArgoCD Runtime Health — ${ENVIRONMENT} / ${MGMT_LABEL}"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

header "1. Kubernetes API Prerequisite"

if kubectl cluster-info --request-timeout=10s > /dev/null 2>&1; then
  pass "Management-cluster API server is reachable"
else
  fail "Management-cluster API server is unreachable"
fi

header "2. ArgoCD Pods"

if ! kubectl get namespace argocd > /dev/null 2>&1; then
  fail "ArgoCD namespace does not exist"
elif ! ARGOCD_PODS_JSON="$(kubectl get pods -n argocd -o json --request-timeout=15s 2>/dev/null)"; then
  fail "Unable to query ArgoCD pods"
else
  ARGOCD_TOTAL="$(jq '[.items[]] | length' <<< "${ARGOCD_PODS_JSON}")"
  ARGOCD_READY="$(jq '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' \
    <<< "${ARGOCD_PODS_JSON}")"
  ARGOCD_UNREADY=$((ARGOCD_TOTAL - ARGOCD_READY))

  echo "  Total:   ${ARGOCD_TOTAL}"
  echo "  Ready:   ${ARGOCD_READY}"
  echo "  Unready: ${ARGOCD_UNREADY}"

  jq -r '.items[] | [
      .metadata.name,
      (.status.phase // "Unknown"),
      (([.status.containerStatuses[]? | select(.ready == true)] | length) | tostring),
      (((.status.containerStatuses // []) | length) | tostring)
    ] | @tsv' <<< "${ARGOCD_PODS_JSON}" | \
    awk -F '\t' '{printf "  %-50s %-12s %s/%s Ready\n", $1, $2, $3, $4}'

  if [ "${ARGOCD_TOTAL}" -eq 0 ]; then
    fail "No ArgoCD pods were found"
  elif [ "${ARGOCD_READY}" -lt 4 ]; then
    fail "Only ${ARGOCD_READY} ArgoCD pods are Ready (expected at least 4)"
  elif [ "${ARGOCD_UNREADY}" -gt 0 ]; then
    fail "ArgoCD has ${ARGOCD_UNREADY} unready pod(s)"
  else
    pass "ArgoCD pods are healthy (${ARGOCD_READY}/${ARGOCD_TOTAL} Ready)"
  fi
fi

header "3. ArgoCD Applications"

if ! kubectl get crd applications.argoproj.io > /dev/null 2>&1; then
  fail "ArgoCD Application CRD is not installed"
elif ! APPLICATIONS_JSON="$(kubectl get applications -n argocd -o json --request-timeout=15s 2>/dev/null)"; then
  fail "Unable to query ArgoCD Applications"
else
  APP_TOTAL="$(jq '[.items[]] | length' <<< "${APPLICATIONS_JSON}")"
  APP_NOT_SYNCED="$(jq '[.items[] | select((.status.sync.status // "Unknown") != "Synced")] | length' \
    <<< "${APPLICATIONS_JSON}")"
  APP_NOT_HEALTHY="$(jq '[.items[] | select((.status.health.status // "Unknown") != "Healthy")] | length' \
    <<< "${APPLICATIONS_JSON}")"

  echo "  Total:       ${APP_TOTAL}"
  echo "  Not Synced:  ${APP_NOT_SYNCED}"
  echo "  Not Healthy: ${APP_NOT_HEALTHY}"

  if [ "${APP_TOTAL}" -gt 0 ]; then
    jq -r '.items[] | [
        .metadata.name,
        (.status.sync.status // "Unknown"),
        (.status.health.status // "Unknown")
      ] | @tsv' <<< "${APPLICATIONS_JSON}" | \
      awk -F '\t' '{printf "  %-40s %-12s %s\n", $1, $2, $3}'
  fi

  if [ "${APP_TOTAL}" -eq 0 ]; then
    fail "No ArgoCD Applications were found"
  elif [ "${APP_NOT_SYNCED}" -gt 0 ] || [ "${APP_NOT_HEALTHY}" -gt 0 ]; then
    fail "Applications not ready: ${APP_NOT_SYNCED} not Synced, ${APP_NOT_HEALTHY} not Healthy"
  else
    pass "All ${APP_TOTAL} Applications are healthy and Synced"
  fi
fi

header "4. Worker Cluster Registration"

EXPECTED_SECRET="cluster-${WORKER_LABEL}"
if kubectl get secret "${EXPECTED_SECRET}" -n argocd > /dev/null 2>&1; then
  pass "Worker Cluster '${EXPECTED_SECRET}' is registered"
else
  fail "Worker Cluster secret '${EXPECTED_SECRET}' was not found"
  kubectl get secrets -n argocd \
    -l "argocd.argoproj.io/secret-type=cluster" \
    -o custom-columns="NAME:.metadata.name" \
    --no-headers 2>/dev/null || true
fi

echo ""
echo "══════════════════════════════════════════════"
echo " ArgoCD Runtime Health Summary — ${ENVIRONMENT}"
echo "══════════════════════════════════════════════"
printf " PASS: %d  WARN: %d  FAIL: %d\n" "${PASS}" "${WARN}" "${FAIL}"
echo "══════════════════════════════════════════════"

if [ "${FAIL}" -gt 0 ]; then
  echo " ArgoCD runtime health check FAILED"
  exit 1
elif [ "${WARN}" -gt 0 ]; then
  echo " ArgoCD runtime health check PASSED with warnings"
else
  echo " ArgoCD runtime health check PASSED"
fi
