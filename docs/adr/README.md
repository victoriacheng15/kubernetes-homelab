# Architectural Decision Records (ADR)

This directory contains the architectural decisions made during the evolution of the project.

| ID | Title | Description | Status |
| :--- | :--- | :--- | :--- |
| 001 | [Two-Node Cluster Topology](./001-two-node-cluster-topology.md) | Asymmetric physical topology with centralized control plane and external Raspberry Pi quorum tiebreaker. | Accepted |
| 002 | [Local Storage with Retain Policy](./002-local-storage-with-retain-policy.md) | Local disk mapping via local-path provisioner with strict retention policy, rejecting 2-node distributed storage. | Accepted |
| 003 | [Cilium eBPF in VXLAN Overlay Mode](./003-cilium-ebpf-in-vxlan-overlay-mode.md) | In-kernel eBPF datapath with VXLAN packet encapsulation for home LAN isolation, kube-proxy replacement, and Hubble telemetry. | Accepted |
| 004 | [Three-Tier Platform Lifecycle](./004-three-tier-platform-lifecycle.md) | Strict separation of concerns across infrastructure (OpenTofu), OS and host baseline (Ansible), and workload delivery (ArgoCD). | Accepted |
| 005 | [External Reverse Proxy Gateway](./005-external-reverse-proxy-gateway.md) | Decoupled Nginx reverse proxy in a lightweight LXC container for LAN ingress and independent service availability. | Accepted |
