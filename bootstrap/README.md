# Cluster Bootstrap Automation Suite

A collection of idempotent shell scripts to audit, tune, and provision bare-metal and Proxmox virtual machines into an isolated, high-performance Kubernetes cluster powered by k3s and Cilium (eBPF).

---

## Script Execution Matrix

Not every script runs on every virtual machine. The table below outlines where each script must be executed:

| Script | Purpose | `k8s-cp-01` (Control Plane) | `k8s-telemetry-01` (Worker) | `k8s-app-01` (Worker) |
| :--- | :--- | :---: | :---: | :---: |
| [`00-preflight.sh`](./00-preflight.sh) | Hardware, network, and Ansible OS baseline audit | **Yes** | **Yes** | **Yes** |
| [`01-k3s-server.sh`](./01-k3s-server.sh) | k3s server bootstrap (embedded etcd) | **Yes** | No | No |
| [`02-k3s-agent.sh`](./02-k3s-agent.sh) | Worker node join and role labeling | No | **Yes** | **Yes** |
| [`03-cni-cilium.sh`](./03-cni-cilium.sh) | Cilium CNI and Hubble observability across cluster | **Yes** | No | No |

---

## Detailed Script Overview

### 1. `00-preflight.sh` (Read-Only Audit)

Performs non-destructive environment checks on any target VM prior to configuration:

- Inspects primary IPv4 address, network interface, and default gateway reachability.
- Audits system resources against minimum profiles (vCPUs >= 2, RAM >= 4 GB, root disk space).
- Checks Linux kernel version for Cilium eBPF compatibility (kernel >= 5.10).
- Verifies required Kubernetes ports are free (`6443`, `8472`, `10250`).
- Validates that Ansible OS baseline configuration is active (UTC timezone, swap disabled, `overlay` and `br_netfilter` modules, sysctl IP forwarding, and core packages).

```bash
./bootstrap/00-preflight.sh
# Or test with dry-run mode:
./bootstrap/00-preflight.sh --dry-run
```

---

### 2. `01-k3s-server.sh` (Control Plane Bootstrap)

Initializes the Kubernetes control plane on `k8s-cp-01`:

- Disables default Flannel CNI, Traefik ingress, and ServiceLB.
- Configures dedicated cluster CIDR (`10.244.0.0/16`) and service CIDR (`10.96.0.0/12`).
- Applies control plane taint: `node-role.kubernetes.io/control-plane:NoSchedule`.
- Generates kubeconfig in `~/.kube/config`.
- Outputs cluster join token from `/var/lib/rancher/k3s/server/node-token`.

```bash
./bootstrap/01-k3s-server.sh
```

---

### 3. `02-k3s-agent.sh` (Worker Node Join)

Joins worker nodes into the cluster with automated role and workload labeling.

#### Retrieving the Join Token

Before joining a worker node, retrieve the join token from the control plane (`k8s-cp-01`):

```bash
# On k8s-cp-01:
cat /var/lib/rancher/k3s/server/node-token
```

#### Joining Worker Nodes

Execute the join script on the worker VM using the token from `k8s-cp-01`:

```bash
# Join Telemetry Node (run on k8s-telemetry-01):
./bootstrap/02-k3s-agent.sh \
  --server-url "https://<k8s-cp-01-ip>:6443" \
  --token "<join-token>" \
  --node-role telemetry

# Join Application Node (run on k8s-app-01):
./bootstrap/02-k3s-agent.sh \
  --server-url "https://<k8s-cp-01-ip>:6443" \
  --token "<join-token>" \
  --node-role app
```

---

### 4. `03-cni-cilium.sh` (Cilium CNI & Hubble)

Deploys Cilium across all joined nodes in isolated VXLAN overlay mode:

- Explicitly configures cluster pool IPv4 CIDR (`10.244.0.0/16`) to prevent overlap with physical LAN subnets.
- Enables `bpf.hostLegacyRouting` to safeguard host-destined traffic (SSH and ICMP) on virtualized interfaces.
- Replaces kube-proxy using in-kernel eBPF (`kubeProxyReplacement: true`) pointing directly to the control plane API server.
- Deploys Hubble Relay and Hubble UI across available worker nodes for L3/L4/L7 flow observability.

```bash
./bootstrap/03-cni-cilium.sh
```

---

## Dry-Run Validation

All scripts support a `--dry-run` flag to test commands, directory creation, and manifest generation without making system changes.

Validate the entire suite using the repository Makefile target:

```bash
make bootstrap-dry-run
```
