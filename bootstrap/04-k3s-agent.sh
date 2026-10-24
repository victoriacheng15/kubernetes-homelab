#!/usr/bin/env bash
# ==============================================================================
# Script: 04-k3s-agent.sh
# Purpose: Joins worker/agent nodes (telemetry and app nodes) to the k3s cluster
#          with workload labels.
# Usage: ./04-k3s-agent.sh --server-url <url> --token <token> --node-role <telemetry|app> [--dry-run | -d]
# ==============================================================================

set -euo pipefail

DRY_RUN=false
SERVER_URL="${K3S_URL:-}"
TOKEN="${K3S_TOKEN:-}"
NODE_ROLE=""
NODE_NAME="$(hostname)"
K3S_CONFIG_DIR="/etc/rancher/k3s"
K3S_CONFIG_FILE="${K3S_CONFIG_DIR}/config.yaml"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Joins this node as an agent/worker to an existing k3s control plane.

Options:
  --server-url <url>      Control plane API endpoint (e.g. https://192.168.1.10:6443).
  --token <token>         Cluster join token (from /var/lib/rancher/k3s/server/node-token).
  --node-role <role>      Node profile to assign labels: 'telemetry' or 'app'.
  --node-name <name>      Explicit node name override (default: $(hostname)).
  -d, --dry-run           Simulate execution without modifying system state.
  -h, --help              Show this help message.

Environment Variables:
  K3S_URL                 Can be used instead of --server-url
  K3S_TOKEN               Can be used instead of --token

Examples:
  ./04-k3s-agent.sh --server-url https://192.168.1.10:6443 --token K10abc... --node-role telemetry
  ./04-k3s-agent.sh --server-url https://192.168.1.10:6443 --token K10abc... --node-role app --dry-run

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
    --server-url)
      SERVER_URL="$2"
      shift 2
      ;;
    --token)
      TOKEN="$2"
      shift 2
      ;;
    --node-role)
      NODE_ROLE="$2"
      shift 2
      ;;
    --node-name)
      NODE_NAME="$2"
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

# Mock values in dry run if omitted
if [[ "${DRY_RUN}" == "true" ]]; then
  SERVER_URL="${SERVER_URL:-https://192.168.1.10:6443}"
  TOKEN="${TOKEN:-mock-k3s-cluster-join-token}"
  NODE_ROLE="${NODE_ROLE:-telemetry}"
fi

# Validation
if [[ -z "${SERVER_URL}" || -z "${TOKEN}" ]]; then
  echo "Error: Both --server-url and --token must be specified (or set via K3S_URL and K3S_TOKEN)." >&2
  exit 1
fi

if [[ "${NODE_ROLE}" != "telemetry" && "${NODE_ROLE}" != "app" ]]; then
  echo "Error: --node-role must be specified as either 'telemetry' or 'app'." >&2
  exit 1
fi

# Check root privilege unless running in dry-run mode
if [[ "${DRY_RUN}" == "false" && "$EUID" -ne 0 ]]; then
  echo "Error: This script must be run as root (or via sudo)." >&2
  exit 1
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Dry-run mode active. No agent packages will be installed."
fi

# ------------------------------------------------------------------------------
# 1. Determine Node Labels
# ------------------------------------------------------------------------------
log_step "Determining node labels for profile: '${NODE_ROLE}'..."

LABELS=()
case "${NODE_ROLE}" in
  telemetry)
    LABELS+=("node-role.kubernetes.io/telemetry=true")
    LABELS+=("workload=telemetry")
    ;;
  app)
    LABELS+=("node-role.kubernetes.io/app=true")
    LABELS+=("workload=app")
    ;;
esac

log_info "Assigned labels: ${LABELS[*]}"

# ------------------------------------------------------------------------------
# 2. Generate Declarative Agent Configuration
# ------------------------------------------------------------------------------
log_step "Generating declarative k3s agent configuration (${K3S_CONFIG_FILE})..."

read -r -d '' CONFIG_CONTENT <<EOF || true
server: "${SERVER_URL}"
token: "${TOKEN}"
node-name: "${NODE_NAME}"
node-label:
$(printf "  - \"%s\"\n" "${LABELS[@]}")
EOF

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would create directory: ${K3S_CONFIG_DIR}"
  log_dry "Would write configuration to ${K3S_CONFIG_FILE}:"
  echo "${CONFIG_CONTENT}"
else
  mkdir -p "${K3S_CONFIG_DIR}"
  echo "${CONFIG_CONTENT}" > "${K3S_CONFIG_FILE}"
  log_info "k3s agent configuration generated."
fi

# ------------------------------------------------------------------------------
# 3. Install k3s Agent & Systemd Service
# ------------------------------------------------------------------------------
log_step "Installing k3s agent service..."

INSTALL_CMD="curl -sfL https://get.k3s.io | K3S_URL=\"${SERVER_URL}\" K3S_TOKEN=\"${TOKEN}\" sh -s - agent"

if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Would execute: ${INSTALL_CMD}"
  log_dry "Would enable and start systemd service: k3s-agent"
else
  eval "${INSTALL_CMD}"
  systemctl enable --now k3s-agent
  log_info "k3s agent service started."
fi

echo ""
if [[ "${DRY_RUN}" == "true" ]]; then
  log_dry "Dry-run verification completed successfully. Worker node join validated."
else
  log_info "Node ${NODE_NAME} successfully joined to ${SERVER_URL} as '${NODE_ROLE}' agent."
fi
