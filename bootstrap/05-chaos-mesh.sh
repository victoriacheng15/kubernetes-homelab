#!/usr/bin/env bash
# ==============================================================================
# Script: 05-chaos-mesh.sh
# Purpose: Deploys Chaos Mesh resilience platform pinned to the application worker node
#          (k8s-app-01) with containerd socket integration and NodePort dashboard.
# Usage: ./05-chaos-mesh.sh [--dry-run | -d] [--help | -h]
# ==============================================================================

set -euo pipefail

DRY_RUN=false
CHAOS_MESH_VERSION=""
CHAOS_NAMESPACE="chaos-mesh"
CONTAINERD_SOCKET="/run/k3s/containerd/containerd.sock"
DASHBOARD_NODEPORT=31333

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Installs Chaos Mesh into the '${CHAOS_NAMESPACE}' namespace, configuring the containerd
runtime socket for k3s and pinning workloads to 'workload=app'.

Options:
  -d, --dry-run               Simulate execution without modifying the cluster.
  -v, --version               Display the detected latest Chaos Mesh version and exit.
  -h, --help                  Show this help message.

EOF
  exit 0
}

get_latest_version() {
  local version
  version=$(curl -sSL --connect-timeout 5 https://api.github.com/repos/chaos-mesh/chaos-mesh/releases/latest 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "${version}" ]]; then
    echo "Error: Failed to detect latest Chaos Mesh version from GitHub." >&2
    exit 1
  fi
  echo "${version}"
}

# Parse command line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--version)
      echo "Chaos Mesh version: $(get_latest_version)"
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
log_step "Detecting latest stable Chaos Mesh release..."
CHAOS_MESH_VERSION=$(get_latest_version)
log_info "Detected latest Chaos Mesh release: ${CHAOS_MESH_VERSION}"

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
# 2. Ensure Helm Tooling (via mise if missing)
# ------------------------------------------------------------------------------
log_step "Checking Helm CLI availability..."

# Export mise shims and local bin to PATH if present
export PATH="${HOME}/.local/share/mise/shims:/usr/local/bin:${PATH}"

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would check if 'helm' exists in PATH"
  log_dry "If missing, would install 'mise' and use mise to manage Helm"
else
  if ! command -v helm &>/dev/null; then
    log_info "Helm CLI not found in PATH. Checking mise tool manager..."
    if ! command -v mise &>/dev/null; then
      log_info "Installing mise..."
      curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh
    fi
    log_info "Installing Helm via mise..."
    mise use -g helm@latest
    eval "$(mise activate bash)"
  fi
  log_info "Helm CLI available: $(helm version --short 2>/dev/null || echo 'installed')"
fi

# ------------------------------------------------------------------------------
# 3. Check Existing Installation or Deploy Chaos Mesh
# ------------------------------------------------------------------------------
if [[ "${DRY_RUN}" == "false" ]] && kubectl get deployment chaos-controller-manager -n "${CHAOS_NAMESPACE}" >/dev/null 2>&1 && kubectl rollout status deployment/chaos-controller-manager -n "${CHAOS_NAMESPACE}" --timeout=5s >/dev/null 2>&1; then
  log_info "Chaos Mesh is already installed and operational in '${CHAOS_NAMESPACE}'. Skipping installation."
else
  log_step "Ensuring '${CHAOS_NAMESPACE}' namespace exists..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "Would create namespace '${CHAOS_NAMESPACE}' if not already present"
  else
    if ! kubectl get namespace "${CHAOS_NAMESPACE}" >/dev/null 2>&1; then
      kubectl create namespace "${CHAOS_NAMESPACE}"
      log_info "Namespace '${CHAOS_NAMESPACE}' created."
    else
      log_info "Namespace '${CHAOS_NAMESPACE}' already exists."
    fi
  fi

  # ----------------------------------------------------------------------------
  # 4. Configure Helm Repository
  # ----------------------------------------------------------------------------
  log_step "Configuring Chaos Mesh Helm repository..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "Would execute: helm repo add chaos-mesh https://charts.chaos-mesh.org"
    log_dry "Would execute: helm repo update chaos-mesh"
  else
    helm repo add chaos-mesh https://charts.chaos-mesh.org
    helm repo update chaos-mesh
    log_info "Chaos Mesh Helm repository updated."
  fi

  # ----------------------------------------------------------------------------
  # 5. Deploy Chaos Mesh via Helm
  # ----------------------------------------------------------------------------
  log_step "Deploying Chaos Mesh (version: ${CHAOS_MESH_VERSION}) to '${CHAOS_NAMESPACE}'..."

  HELM_DEPLOY_CMD=(
    helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh
    --namespace "${CHAOS_NAMESPACE}"
    --version "${CHAOS_MESH_VERSION}"
    --set chaosDaemon.runtime=containerd
    --set "chaosDaemon.socketPath=${CONTAINERD_SOCKET}"
    --set "chaosDaemon.nodeSelector.workload=app"
    --set "controllerManager.nodeSelector.workload=app"
    --set "dashboard.nodeSelector.workload=app"
    --set dashboard.service.type=NodePort
    --set "dashboard.service.nodePort=${DASHBOARD_NODEPORT}"
  )

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "Would execute Helm deployment with parameters:"
    echo "  ${HELM_DEPLOY_CMD[*]}"
  else
    "${HELM_DEPLOY_CMD[@]}"
    log_info "Chaos Mesh Helm release deployed."

    log_step "Waiting for Chaos Mesh controller manager readiness..."
    kubectl rollout status deployment/chaos-controller-manager -n "${CHAOS_NAMESPACE}" --timeout=180s
    log_info "Chaos Mesh controller manager is operational."
  fi
fi

echo ""
if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Dry-run verification completed successfully. Chaos Mesh installation validated."
else
  log_info "Chaos Mesh installation successfully completed."
fi
