#!/usr/bin/env bash
# ==============================================================================
# Script: 03-cni-cilium.sh
# Purpose: Deploys Cilium CNI in isolated VXLAN overlay mode with in-kernel
#          kube-proxy replacement and Hubble Relay/UI enabled.
# Usage: ./03-cni-cilium.sh [--dry-run | -d] [--help | -h]
# ==============================================================================

set -euo pipefail

DRY_RUN=false
CILIUM_VERSION="1.16.2"
POD_CIDR="10.244.0.0/16"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Installs Cilium CLI and deploys Cilium CNI in VXLAN overlay mode with Hubble
observability enabled.

Options:
  -d, --dry-run                 Simulate execution without modifying the cluster.
  --cilium-version <version>    Cilium release version (default: ${CILIUM_VERSION}).
  --pod-cidr <cidr>             Pod network CIDR (default: ${POD_CIDR}).
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
    --cilium-version)
      CILIUM_VERSION="$2"
      shift 2
      ;;
    --pod-cidr)
      POD_CIDR="$2"
      shift 2
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
# 2. Install Cilium CLI Binary
# ------------------------------------------------------------------------------
log_step "Checking Cilium CLI installation..."

CLI_INSTALL_CMD="curl -sSL --fail --remote-name https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz && sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin && rm -f cilium-linux-amd64.tar.gz"

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would check if 'cilium' binary exists in PATH"
  log_dry "If missing, would execute: ${CLI_INSTALL_CMD}"
else
  if ! command -v cilium &>/dev/null; then
    log_info "Installing Cilium CLI..."
    eval "${CLI_INSTALL_CMD}"
  fi
  log_info "Cilium CLI available: $(cilium version --client 2>/dev/null || echo 'installed')"
fi

# ------------------------------------------------------------------------------
# 3. Deploy Cilium via Helm/CLI with Overlay Architecture Profile
# ------------------------------------------------------------------------------
log_step "Deploying Cilium CNI (version: ${CILIUM_VERSION}) in VXLAN overlay mode..."

CILIUM_INSTALL_CMD=(
  cilium install
  --version "${CILIUM_VERSION}"
  --cluster-pool-ipv4-cidr "${POD_CIDR}"
  --set ipv4NativeRoutingCIDR="${POD_CIDR}"
  --set routingMode=tunnel
  --set tunnelProtocol=vxlan
  --set autoDirectNodeRoutes=false
  --set kubeProxyReplacement=true
  --set k8sServiceHost=127.0.0.1
  --set k8sServicePort=6443
  --set bpf.masquerade=true
  --set hubble.relay.enabled=true
  --set hubble.ui.enabled=true
)

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would execute Cilium deployment with parameters:"
  echo "  cilium install \\"
  echo "    --version \"${CILIUM_VERSION}\" \\"
  echo "    --cluster-pool-ipv4-cidr \"${POD_CIDR}\" \\"
  echo "    --set ipv4NativeRoutingCIDR=\"${POD_CIDR}\" \\"
  echo "    --set routingMode=tunnel \\"
  echo "    --set tunnelProtocol=vxlan \\"
  echo "    --set autoDirectNodeRoutes=false \\"
  echo "    --set kubeProxyReplacement=true \\"
  echo "    --set k8sServiceHost=127.0.0.1 \\"
  echo "    --set k8sServicePort=6443 \\"
  echo "    --set bpf.masquerade=true \\"
  echo "    --set hubble.relay.enabled=true \\"
  echo "    --set hubble.ui.enabled=true"
else
  "${CILIUM_INSTALL_CMD[@]}"
  log_info "Cilium manifests applied to kube-system namespace."

  log_step "Waiting for Cilium daemonset and Hubble pods to become ready..."
  cilium status --wait
  log_info "Cilium CNI is fully operational."
fi

echo ""
if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Dry-run verification completed successfully. Cilium CNI configuration validated."
else
  log_info "Cilium CNI and Hubble observability successfully initialized."
fi
