# ADR 001: Two-Node Cluster Topology

- **Status:** Accepted
- **Date:** 2026-10-11
- **Author:** Victoria Cheng

## Context and Problem Statement

Operating a Kubernetes cluster across consumer homelab hardware presents fundamental distributed systems challenges:

1. **Quorum Vulnerability:** Distributed consensus protocols require an odd number of voting nodes to maintain quorum. A dual-node physical topology risks split-brain if the interconnect between machines degrades.
2. **Resource and Hardware Heterogeneity:** The physical hardware consists of two machines (`pve-01` Mini PC, `pve-02` Laptop) and a low-power single-board computer (`rpi-01` Raspberry Pi).
3. **Blast Radius and Workload Contention:** Experimental chaos engineering and security drills must not compromise cluster management, API stability, or metrics collection pipelines.

How should the physical node layout, control plane placement, and quorum tiebreaker be structured to ensure reliability and operational safety?

## Decision Outcome

Adopt an asymmetric, segregated two-node physical cluster topology with an external low-power quorum tiebreaker:

1. **Centralized Single Control Plane (`pve-01`):**
   - Run k3s with embedded etcd on a dedicated control plane VM (`k8s-cp-01`) hosted on `pve-01`.
   - Avoid two-node multi-master etcd clustering, which is prone to split-brain locks.

2. **Workload and Blast Radius Segregation:**
   - Host cluster-critical infrastructure on `pve-01`: control plane (`k8s-cp-01`) and continuous delivery/telemetry (`k8s-telemetry-01` running ArgoCD, OpenTelemetry Collector, Prometheus, Grafana, and Hubble).
   - Confine experimental workloads to `pve-02`: application node (`k8s-app-01` running Go OTel application, OWASP Juice Shop, Falco, and Chaos Mesh fault injection).

3. **External Proxmox Quorum Tiebreaker (`rpi-01`):**
   - Deploy `corosync-qnetd` on a bare-metal Raspberry Pi (`rpi-01`) providing a 3rd quorum vote to Proxmox VE.
   - Prevents VM cluster fencing lockouts if one physical Proxmox host reboots.

## Consequences

### Positive

- **Deterministic Consensus:** The external `corosync-qnetd` tiebreaker prevents split-brain and ensures Proxmox quorum across two physical hosts.
- **Protected Control Plane:** Heavy fault injection or kernel stress from Chaos Mesh on `pve-02` cannot starve the Kubernetes API server or Prometheus pipeline on `pve-01`.

### Negative

- **Single Control Plane Node Failure Domain:** If `pve-01` suffers a hardware outage, the Kubernetes API server becomes unavailable until restored. Workloads on `pve-02` remain running but cannot be rescheduled or modified via API.
- **Quorum Tiebreaker Dependency:** Proxmox clustering requires the Raspberry Pi to remain online for quorum arbitration during host maintenance.

## Verification

- [x] Executed `pvecm status` on `pve-01` and confirmed `Expected votes: 3`, `Total votes: 3`, `Quorum: 2`, and `Flags: Quorate Qdevice`.
- [x] Simulated `pve-02` outage by stopping cluster services (`systemctl stop corosync pve-cluster`). Verified on `pve-01` that `pvecm status` retained active quorum (`Total votes: 2`, `Quorum: 2`) with `/etc/pve` remaining read-write. Restored `pve-02` via `systemctl start pve-cluster corosync`.
