# Kubernetes Homelab Documentation

Technical specifications, design decisions, and operational runbooks for a bare-metal Kubernetes cluster operating across dual-node Proxmox VE hardware and an external Raspberry Pi quorum witness.

---

## Why This Exists

Built to expand beyond single-machine experiments and disposable cloud setups, evolving the foundations of [observability-hub](https://github.com/victoriacheng15/observability-hub) across distributed physical infrastructure:

* **From Single-Node to Distributed Topology:** Scales the single-machine GitOps and Cilium foundations into a multi-node bare-metal environment, confronting real node failure domains and quorum management.
* **Control Plane Isolation:** Centralized control plane with strict `NoSchedule` taints to preserve API stability.
* **Kernel Datapath & In-Cluster Routing:** Cilium eBPF in isolated VXLAN overlay mode, avoiding host routing table modifications or physical LAN disruption.
* **Zero-Drift GitOps:** ArgoCD as the authoritative reconciler for all cluster services, observability daemons, and security tools.
* **Resilience Under Constraints:** Asymmetric physical hardware (Mini PC + Laptop) with external Raspberry Pi Corosync quorum (`corosync-qnetd`) to prevent split-brain states.

---

## Physical Hardware Baseline

![Physical Topology](./assets/physical-topology.png)

| Host | Hardware Type | CPU / Threads | Memory | Storage | Primary Cluster Roles |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`pve-01`** | Mini PC | 8C / 16T | 32 GB | 1 TB NVMe | `k8s-cp-01` (Control Plane), `k8s-telemetry-01`, LXC Utilities |
| **`pve-02`** | Laptop | 4C / 8T | 8 GB | 256 GB SSD | `k8s-app-01` (Worker), `pihole` (CT 300) |
| **`rpi-01`** | Raspberry Pi 3B | 4C / 4T (1.2 GHz) | 1 GB | MicroSD | Corosync QNet QDevice (Vote 3), Local Chrony NTP (UTC) |

---

## Architecture Topology

![Kubernetes Homelab Architecture](./assets/architecture.png)

### Key Architectural Pillars

* **Control Plane Isolation:** Dedicated control plane VM (`k8s-cp-01`) enforcing `NoSchedule` taints to protect etcd and the Kubernetes API server from resource contention.
* **Kernel-Level Networking (Cilium eBPF):** Cross-node container traffic encapsulates in standard VXLAN UDP packets on port 8472, bypassing iptables and avoiding route conflicts with the physical home LAN.
* **Dedicated Observability Node:** `k8s-telemetry-01` hosts Hubble Relay, Hubble UI, and monitoring daemons, keeping `k8s-app-01` dedicated to workloads.
* **Asymmetric Hardware Resilience:** The Raspberry Pi (`rpi-01`) serves as the Corosync QDevice tiebreaker to provide an odd 3-vote quorum across the two Proxmox hosts (`pve-01` and `pve-02`), preventing split-brain conditions.
* **Declarative GitOps Reconciliation:** ArgoCD acts as the single source of truth for platform manifests and tenant applications, eliminating manual cluster drift.
