# Architectural Decision Records (ADR)

This directory contains the architectural decisions made during the evolution of the project.

| ID | Title | Description | Status |
| :--- | :--- | :--- | :--- |
| 001 | [Two-Node Cluster Topology](./001-two-node-cluster-topology.md) | Asymmetric physical topology with centralized control plane and external Raspberry Pi quorum tiebreaker. | Proposed |
| 002 | [Local Storage with Retain Policy](./002-local-storage-with-retain-policy.md) | Local disk mapping via local-path provisioner with strict retention policy, rejecting 2-node distributed storage. | Proposed |
| 003 | [Cilium eBPF in VXLAN Overlay Mode](./003-cilium-ebpf-in-vxlan-overlay-mode.md) | In-kernel eBPF datapath with VXLAN packet encapsulation for home LAN isolation, kube-proxy replacement, and Hubble telemetry. | Proposed |
