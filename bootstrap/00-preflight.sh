#!/usr/bin/env bash
# ==============================================================================
# Script: 00-preflight.sh
# Purpose: Inspects and audits VM hardware, network (IP, DNS, Gateway),
#          kernel version, and port availability before running bootstrap scripts.
# Usage: ./00-preflight.sh [--dry-run | -d] [--help | -h]
# ==============================================================================

set -euo pipefail

DRY_RUN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Audits VM readiness (IP address, DNS, gateway, vCPUs, RAM, disk, kernel version,
and required ports) for the Kubernetes homelab setup.

Options:
  -d, --dry-run    Runs read-only audit (preflight is inherently read-only).
  -h, --help       Show this help message.

EOF
  exit 0
}

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

# Color helpers
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BLUE="\033[1;34m"
RESET="\033[0m"

log_pass() { echo -e "  [${GREEN}PASS${RESET}] $*"; }
log_warn() { echo -e "  [${YELLOW}WARN${RESET}] $*"; }
log_fail() { echo -e "  [${RED}FAIL${RESET}] $*"; }
log_info() { echo -e "  [${BLUE}INFO${RESET}] $*"; }

echo "================================================================================"
echo -e "${BLUE}Kubernetes VM Environment Preflight Audit${RESET}"
echo "================================================================================"

# ------------------------------------------------------------------------------
# 1. Host Identification & OS
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}1. System & Virtualization Profile${RESET}"
HOSTNAME_VAL=$(hostname)
ARCH_VAL=$(uname -m)
KERNEL_VAL=$(uname -r)
VIRT_VAL=$(systemd-detect-virt 2>/dev/null || echo "unknown")

log_info "Hostname:       ${HOSTNAME_VAL}"
log_info "Architecture:   ${ARCH_VAL}"
log_info "Kernel Release: ${KERNEL_VAL}"
log_info "Hypervisor:     ${VIRT_VAL}"

if [[ "${ARCH_VAL}" == "x86_64" ]]; then
  log_pass "Architecture is x86_64."
else
  log_warn "Non-x86_64 architecture detected (${ARCH_VAL})."
fi

# Kernel version check (Cilium eBPF recommends >= 5.10)
KERNEL_MAJOR=$(echo "${KERNEL_VAL}" | cut -d. -f1)
KERNEL_MINOR=$(echo "${KERNEL_VAL}" | cut -d. -f2)
if [[ "${KERNEL_MAJOR}" -gt 5 || ("${KERNEL_MAJOR}" -eq 5 && "${KERNEL_MINOR}" -ge 10) ]]; then
  log_pass "Linux kernel >= 5.10 (fully supports Cilium eBPF features)."
else
  log_warn "Linux kernel is older than 5.10 (${KERNEL_VAL}). Some eBPF features may be restricted."
fi

# ------------------------------------------------------------------------------
# 2. Network Discovery (IP, Gateway, DNS, Internet)
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}2. Network & Connectivity Discovery${RESET}"

# Primary IPv4 and default interface
PRIMARY_IFACE=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1 || true)
PRIMARY_IP=$(ip -4 addr show dev "${PRIMARY_IFACE:-lo}" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || true)
DEFAULT_GW=$(ip route show default 2>/dev/null | awk '{print $3}' | head -n1 || true)

if [[ -n "${PRIMARY_IP}" ]]; then
  log_pass "Primary IPv4 Address: ${PRIMARY_IP} (interface: ${PRIMARY_IFACE:-unknown})"
else
  log_fail "No active IPv4 address found on default interface."
fi

if [[ -n "${DEFAULT_GW}" ]]; then
  log_pass "Default Gateway:      ${DEFAULT_GW}"
else
  log_warn "No default gateway detected."
fi

# Gateway Ping
if [[ -n "${DEFAULT_GW}" ]] && ping -c 1 -W 2 "${DEFAULT_GW}" >/dev/null 2>&1; then
  log_pass "Default gateway is reachable."
else
  log_warn "Could not ping default gateway (${DEFAULT_GW:-none})."
fi

# DNS Resolution
if getent hosts github.com >/dev/null 2>&1; then
  log_pass "DNS resolution is functional (resolved github.com)."
else
  log_fail "DNS resolution failed for github.com. Check /etc/resolv.conf."
fi

# ------------------------------------------------------------------------------
# 3. Hardware Resources (vCPU, RAM, Disk)
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}3. Hardware Resource Allocation${RESET}"

# vCPUs
VCPU_COUNT=$(nproc)
if [[ "${VCPU_COUNT}" -ge 2 ]]; then
  log_pass "vCPUs: ${VCPU_COUNT} available (minimum required: 2)."
else
  log_fail "vCPUs: ${VCPU_COUNT} detected. Kubernetes requires at least 2 vCPUs."
fi

# Memory (MB)
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_RAM_GB=$(awk "BEGIN {printf \"%.1f\", ${TOTAL_RAM_MB}/1024}")

if [[ "${TOTAL_RAM_MB}" -ge 3500 ]]; then
  log_pass "RAM: ${TOTAL_RAM_GB} GB available (meets minimum 4 GB profile)."
else
  log_warn "RAM: ${TOTAL_RAM_GB} GB detected. Less than 4 GB may constrain telemetry/app nodes."
fi

# Swap
SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
if [[ "${SWAP_TOTAL}" -eq 0 ]]; then
  log_pass "Swap is completely disabled (ideal for Kubernetes)."
else
  log_warn "Swap is currently enabled (${SWAP_TOTAL} MB). 01-prerequisites.sh will disable it."
fi

# Root Disk Space
DISK_AVAIL_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
if [[ "${DISK_AVAIL_GB}" -ge 15 ]]; then
  log_pass "Disk Space: ${DISK_AVAIL_GB} GB free on '/' (recommended: >= 15 GB)."
else
  log_warn "Disk Space: only ${DISK_AVAIL_GB} GB free on '/'. May fill up during container pulls."
fi

# ------------------------------------------------------------------------------
# 4. Port Availability Audit
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}4. Required Ports Availability${RESET}"

PORTS_TO_CHECK=(
  "6443:Kubernetes API Server"
  "8472:Cilium VXLAN Overlay"
  "10250:Kubelet API"
)

for ENTRY in "${PORTS_TO_CHECK[@]}"; do
  PORT="${ENTRY%%:*}"
  DESC="${ENTRY#*:}"

  if command -v ss &>/dev/null; then
    if ss -tuln | grep -q ":${PORT} "; then
      log_warn "Port ${PORT} (${DESC}) is currently IN USE."
    else
      log_pass "Port ${PORT} (${DESC}) is available."
    fi
  else
    log_info "Port ${PORT} (${DESC}) check skipped ('ss' command not installed)."
  fi
done

echo ""
echo "================================================================================"
echo -e "${GREEN}Preflight inspection complete.${RESET}"
echo "Use the primary IP (${PRIMARY_IP:-<node-ip>}) when configuring DHCP reservations and node tokens."
echo "================================================================================"
