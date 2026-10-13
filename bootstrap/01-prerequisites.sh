#!/usr/bin/env bash
# ==============================================================================
# Script: 01-prerequisites.sh
# Purpose: Prepares base Linux OS nodes for k3s and Cilium deployment.
# Usage: ./01-prerequisites.sh [--dry-run | -d] [--help | -h]
# ==============================================================================

set -euo pipefail

DRY_RUN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Prepares Ubuntu/Debian host OS with required kernel modules, sysctl configs,
swap deactivation, and baseline packages for Kubernetes.

Options:
  -d, --dry-run    Simulate execution without modifying system state or files.
  -h, --help       Show this help message.

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
  log_dry "Dry-run mode active. No system changes will be made."
fi

# ------------------------------------------------------------------------------
# 1. Kernel Modules Configuration
# ------------------------------------------------------------------------------
log_step "Configuring required kernel modules (overlay, br_netfilter)..."

MODULES_CONF="/etc/modules-load.d/k8s.conf"
MODULES_CONTENT="# Kubernetes and Cilium required modules
overlay
br_netfilter"

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would write kernel modules to ${MODULES_CONF}:"
  echo "${MODULES_CONTENT}"
  log_dry "Would execute: modprobe overlay && modprobe br_netfilter"
else
  echo "${MODULES_CONTENT}" > "${MODULES_CONF}"
  modprobe overlay
  modprobe br_netfilter
  log_info "Kernel modules overlay and br_netfilter loaded."
fi

# ------------------------------------------------------------------------------
# 2. Sysctl Network Parameters
# ------------------------------------------------------------------------------
log_step "Configuring sysctl parameters for container networking..."

SYSCTL_CONF="/etc/sysctl.d/99-kubernetes-cri.conf"
SYSCTL_CONTENT="# Kubernetes networking and packet forwarding
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1"

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would write sysctl parameters to ${SYSCTL_CONF}:"
  echo "${SYSCTL_CONTENT}"
  log_dry "Would execute: sysctl --system"
else
  echo "${SYSCTL_CONTENT}" > "${SYSCTL_CONF}"
  sysctl --system > /dev/null
  log_info "Sysctl network parameters applied."
fi

# ------------------------------------------------------------------------------
# 3. Disable Swap Memory
# ------------------------------------------------------------------------------
log_step "Disabling swap memory..."

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would execute: swapoff -a"
  log_dry "Would comment out swap entries in /etc/fstab"
else
  swapoff -a
  sed -i.bak -r 's/(.+swap.+)/# \1/' /etc/fstab
  log_info "Swap disabled and commented out in /etc/fstab."
fi

# ------------------------------------------------------------------------------
# 4. Install Baseline Packages
# ------------------------------------------------------------------------------
log_step "Installing baseline utilities (curl, jq, tar, iptables, open-iscsi)..."

PKGS=(curl jq tar iptables open-iscsi ca-certificates)

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would execute: apt-get update -y && apt-get install -y ${PKGS[*]}"
else
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y > /dev/null
  apt-get install -y --no-install-recommends "${PKGS[@]}" > /dev/null
  log_info "Baseline packages installed successfully."
fi

# ------------------------------------------------------------------------------
# 5. Local Storage Mount Directory Preparation
# ------------------------------------------------------------------------------
log_step "Preparing local storage persistence directories..."

STORAGE_DIR="/opt/local-path-provisioner"

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would execute: mkdir -p ${STORAGE_DIR} && chmod 750 ${STORAGE_DIR}"
else
  mkdir -p "${STORAGE_DIR}"
  chmod 750 "${STORAGE_DIR}"
  log_info "Storage path ${STORAGE_DIR} ready."
fi

echo ""
if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Dry-run verification completed successfully. All prerequisites validated."
else
  log_info "Node prerequisites successfully configured. Ready for k3s bootstrap."
fi
