#!/usr/bin/env bash
# ==============================================================================
# Script: 01-k3s-server.sh
# Purpose: Bootstraps the primary k3s control plane with embedded etcd.
#          Disables default Flannel, Traefik, and ServiceLB in preparation for Cilium.
# Usage: ./01-k3s-server.sh [--dry-run | -d] [--help | -h]
# ==============================================================================

set -euo pipefail

DRY_RUN=false
CLUSTER_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
K3S_CONFIG_DIR="/etc/rancher/k3s"
K3S_CONFIG_FILE="${K3S_CONFIG_DIR}/config.yaml"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Bootstraps the k3s control plane on k8s-cp-01 with embedded etcd and sets up
the node with control plane isolation taints.

Options:
  -d, --dry-run             Simulate execution without installing k3s or changing system state.
  --cluster-cidr <cidr>     Pod network CIDR (default: 10.244.0.0/16).
  --service-cidr <cidr>     Service network CIDR (default: 10.96.0.0/12).
  -h, --help                Show this help message.

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
    --cluster-cidr)
      CLUSTER_CIDR="$2"
      shift 2
      ;;
    --service-cidr)
      SERVICE_CIDR="$2"
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

# Check root privilege unless running in dry-run mode
if [[ "${DRY_RUN}" == "false" && "$EUID" -ne 0 ]]; then
  echo "Error: This script must be run as root (or via sudo)." >&2
  exit 1
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Dry-run mode active. No packages will be installed or services started."
fi

# ------------------------------------------------------------------------------
# 1. Generate Declarative k3s Configuration
# ------------------------------------------------------------------------------
log_step "Generating declarative k3s server configuration (${K3S_CONFIG_FILE})..."

read -r -d '' CONFIG_CONTENT <<EOF || true
# k3s server configuration optimized for Cilium CNI and control plane isolation
cluster-cidr: "${CLUSTER_CIDR}"
service-cidr: "${SERVICE_CIDR}"
flannel-backend: "none"
disable-network-policy: true
disable:
  - traefik
  - servicelb
node-taint:
  - "node-role.kubernetes.io/control-plane:NoSchedule"
write-kubeconfig-mode: "0644"
EOF

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would create directory: ${K3S_CONFIG_DIR}"
  log_dry "Would write configuration to ${K3S_CONFIG_FILE}:"
  echo "${CONFIG_CONTENT}"
else
  mkdir -p "${K3S_CONFIG_DIR}"
  echo "${CONFIG_CONTENT}" > "${K3S_CONFIG_FILE}"
  log_info "k3s configuration file generated."
fi

# ------------------------------------------------------------------------------
# 2. Install k3s Server Binary & Systemd Service
# ------------------------------------------------------------------------------
log_step "Installing k3s control plane server..."

INSTALL_CMD="curl -sfL https://get.k3s.io | sh -s - server"

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would execute: ${INSTALL_CMD}"
  log_dry "Would wait for k3s systemd service to become active"
else
  eval "${INSTALL_CMD}"
  systemctl enable --now k3s
  log_info "k3s service started."

  log_step "Waiting for k3s API server readiness..."
  until kubectl get nodes >/dev/null 2>&1; do
    echo -n "."
    sleep 2
  done
  echo ""
  log_info "k3s control plane is active."
fi

# ------------------------------------------------------------------------------
# 3. Configure Local User Kubeconfig
# ------------------------------------------------------------------------------
log_step "Configuring user kubeconfig..."

TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
KUBE_DIR="${USER_HOME}/.kube"

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would create user directory: ${KUBE_DIR}"
  log_dry "Would copy /etc/rancher/k3s/k3s.yaml to ${KUBE_DIR}/config"
  log_dry "Would chown ${TARGET_USER}:${TARGET_USER} on ${KUBE_DIR}/config"
else
  mkdir -p "${KUBE_DIR}"
  cp /etc/rancher/k3s/k3s.yaml "${KUBE_DIR}/config"
  chown -R "${TARGET_USER}:${TARGET_USER}" "${KUBE_DIR}"
  log_info "Kubeconfig successfully configured at ${KUBE_DIR}/config"
fi

# ------------------------------------------------------------------------------
# 4. Display Cluster Join Information
# ------------------------------------------------------------------------------
log_step "Extracting cluster join credentials for worker nodes..."

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would read node token from: /var/lib/rancher/k3s/server/node-token"
  log_dry "Would display K3S_URL and K3S_TOKEN join command instructions"
else
  NODE_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
  NODE_IP=$(hostname -I | awk '{print $1}')

  echo ""
  echo "================================================================================"
  echo -e "\033[1;32mk3s Control Plane Successfully Initialized!\033[0m"
  echo "================================================================================"
  echo "Control Plane Endpoint: https://${NODE_IP}:6443"
  echo "Cluster Join Token:     ${NODE_TOKEN}"
  echo ""
  echo "Worker Node Join Command (save for 02-k3s-agent.sh):"
  echo "  export K3S_URL=\"https://${NODE_IP}:6443\""
  echo "  export K3S_TOKEN=\"${NODE_TOKEN}\""
  echo "================================================================================"
fi

echo ""
if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Dry-run verification completed successfully. Control plane bootstrap validated."
else
  log_info "Control plane bootstrap complete. Proceed with 03-cni-cilium.sh to initialize networking."
fi
