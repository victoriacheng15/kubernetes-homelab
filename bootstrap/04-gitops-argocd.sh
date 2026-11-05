#!/usr/bin/env bash
# ==============================================================================
# Script: 04-gitops-argocd.sh
# Purpose: Deploys ArgoCD continuous delivery engine, configures NodePort
#          ingress routing, and verifies controller rollout.
# Usage: ./04-gitops-argocd.sh [--dry-run | -d] [--help | -h]
# ==============================================================================

set -euo pipefail

DRY_RUN=false
ARGOCD_VERSION=""
ARGOCD_NAMESPACE="argocd"
ARGOCD_MANIFEST_URL=""

get_latest_version() {
  local version
  version=$(curl -sSL --connect-timeout 5 https://api.github.com/repos/argoproj/argo-cd/releases/latest 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "${version}" ]]; then
    echo "Error: Failed to detect latest ArgoCD version from GitHub." >&2
    exit 1
  fi
  echo "${version}"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Installs the ArgoCD continuous delivery engine into the '${ARGOCD_NAMESPACE}' namespace,
exposes the argocd-server service via NodePort (HTTP: 30080, HTTPS: 30443), and verifies
workload readiness.

Options:
  -d, --dry-run                 Simulate execution without modifying the cluster.
  -v, --version                 Display the detected latest ArgoCD version and exit.
  -h, --help                    Show this help message.

EOF
  exit 0
}

# Parse command line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--version)
      echo "ArgoCD version: $(get_latest_version)"
      exit 0
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

log_info() {
  echo -e "\033[1;34m[INFO]\033[0m $*"
}

log_step() {
  echo -e "\033[1;32m[STEP]\033[0m $*"
}

log_dry() {
  echo -e "\033[1;33m[DRY-RUN]\033[0m $*"
}

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Dry-run mode active. No cluster resources will be deployed."
fi

# Detect latest stable release
log_step "Detecting latest stable ArgoCD release..."
ARGOCD_VERSION=$(get_latest_version)
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/v${ARGOCD_VERSION}/manifests/install.yaml"
log_info "Detected latest ArgoCD release: v${ARGOCD_VERSION}"

# ------------------------------------------------------------------------------
# 1. Verify Cluster Connectivity (Kubectl)
# ------------------------------------------------------------------------------
log_step "Verifying Kubernetes cluster connectivity..."

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would verify kubectl connectivity via: kubectl cluster-info"
else
  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "Error: Unable to connect to Kubernetes cluster. Ensure KUBECONFIG is set." >&2
    exit 1
  fi
  log_info "Cluster connection verified."
fi

# ------------------------------------------------------------------------------
# 2. Check Existing Installation or Deploy ArgoCD
# ------------------------------------------------------------------------------
if [[ "${DRY_RUN}" == "false" ]] && kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1 && kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=5s >/dev/null 2>&1; then
  log_info "ArgoCD is already installed in '${ARGOCD_NAMESPACE}'. Skipping manifest application."
else
  log_step "Ensuring '${ARGOCD_NAMESPACE}' namespace exists..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "Would create namespace '${ARGOCD_NAMESPACE}' if not already present"
  else
    if ! kubectl get namespace "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
      kubectl create namespace "${ARGOCD_NAMESPACE}"
      log_info "Namespace '${ARGOCD_NAMESPACE}' created."
    else
      log_info "Namespace '${ARGOCD_NAMESPACE}' already exists."
    fi
  fi

  # ----------------------------------------------------------------------------
  # 3. Deploy Upstream ArgoCD Manifests
  # ----------------------------------------------------------------------------
  log_step "Applying upstream ArgoCD manifests (${ARGOCD_VERSION})..."
  APPLY_CMD="kubectl apply --server-side -n ${ARGOCD_NAMESPACE} -f ${ARGOCD_MANIFEST_URL}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "Would execute: ${APPLY_CMD}"
  else
    eval "${APPLY_CMD}"
    log_info "ArgoCD manifests successfully applied."
  fi
fi

# ------------------------------------------------------------------------------
# 4. Pin ArgoCD Workloads to Telemetry Node
# ------------------------------------------------------------------------------
log_step "Pinning ArgoCD workloads to telemetry node (node-role.kubernetes.io/telemetry=true)..."
NODE_SELECTOR_PATCH='{"spec":{"template":{"spec":{"nodeSelector":{"node-role.kubernetes.io/telemetry":"true"}}}}}'

ARGOCD_WORKLOADS=(
  "deployment/argocd-server"
  "deployment/argocd-repo-server"
  "deployment/argocd-applicationset-controller"
  "deployment/argocd-notifications-controller"
  "deployment/argocd-redis"
  "statefulset/argocd-application-controller"
)

for workload in "${ARGOCD_WORKLOADS[@]}"; do
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "Would execute: kubectl patch ${workload} -n ${ARGOCD_NAMESPACE} -p '${NODE_SELECTOR_PATCH}'"
  else
    if kubectl get "${workload}" -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
      kubectl patch "${workload}" -n "${ARGOCD_NAMESPACE}" -p "${NODE_SELECTOR_PATCH}" >/dev/null
      log_info "Patched ${workload} to run on telemetry node."
    fi
  fi
done

# ------------------------------------------------------------------------------
# 5. Expose ArgoCD Server via NodePort
# ------------------------------------------------------------------------------
log_step "Exposing argocd-server via NodePort (HTTP: 30080, HTTPS: 30443)..."
PATCH_PAYLOAD='{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 8080, "nodePort": 30080}, {"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30443}]}}'

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would execute: kubectl patch svc argocd-server -n ${ARGOCD_NAMESPACE} -p '${PATCH_PAYLOAD}'"
else
  kubectl patch svc argocd-server -n "${ARGOCD_NAMESPACE}" -p "${PATCH_PAYLOAD}"
  log_info "argocd-server patched to NodePort."
fi

# ------------------------------------------------------------------------------
# 6. Wait for Deployment Rollout Readiness
# ------------------------------------------------------------------------------
log_step "Waiting for argocd-server deployment readiness..."

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would execute: kubectl rollout status deployment/argocd-server -n ${ARGOCD_NAMESPACE} --timeout=180s"
else
  kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=180s
  log_info "argocd-server is operational."
fi

echo ""
if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Dry-run verification completed successfully. ArgoCD installation validated."
else
  log_info "ArgoCD installation successfully completed."
fi
