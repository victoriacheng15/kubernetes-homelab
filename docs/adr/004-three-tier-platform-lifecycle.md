# ADR 004: Three-Tier Platform Lifecycle

- **Status:** Accepted
- **Date:** 2026-11-02
- **Author:** Victoria Cheng

## Context and Problem Statement

Operating a declarative homelab environment requires orchestrating multiple infrastructure layers: bare-metal Proxmox hypervisor virtualization, Linux operating system configurations, standalone utility services, and Kubernetes application delivery.

Attempting to manage all tiers with a single tool leads to architectural coupling, brittle state management, and configuration drift:

1. **Cloud-Init Overextension:** Cloud-Init excels at Day-0 instance bootstrapping (hostname, network, user creation), but lacks idempotent Day-2 orchestration capabilities across multiple nodes.
2. **Kubernetes API Scope:** Kubernetes controllers cannot manage bare hypervisors, kernel modules, swap state, or out-of-cluster helper containers.
3. **Tool Sprawl without Boundaries:** Embedding shell scripts inside infrastructure declarations or using configuration management tools to apply application manifests creates conflicting sources of truth.

How should lifecycle management and configuration state be separated across the homelab infrastructure stack?

## Decision Outcome

Establish a strict three-tier platform lifecycle model separating infrastructure provisioning, host configuration management, and declarative workload delivery:

### Layer 1: Virtualization and Hardware (OpenTofu)

- **Scope:** Declarative state for Proxmox VE resources (QEMU VMs, LXC containers, virtual CPU cores, memory limits, network bridges, static MAC and IP allocations).
- **Boundary:** OpenTofu executes via the Proxmox API. Its responsibility terminates once VM and container resources are provisioned and powered on. It does not configure in-guest application software.

### Layer 2: Operating System Baseline and Standalone Services (Ansible)

- **Scope:** Host-level configuration management and idempotent Day-2 operations. Configures OS sysctl parameters, kernel modules (overlay, br_netfilter), container runtimes (containerd), swap disabling, Kubernetes package baselines (kubeadm, kubelet, kubectl), and standalone utility LXCs (Pi-hole DNS, Nginx Gateway).
- **Boundary:** Ansible accesses hosts via agentless SSH using centralized inventories. Its responsibility terminates at the Kubernetes node boundary. It does not manage in-cluster Kubernetes applications or Deployments.

### Layer 3: Workload Delivery and In-Cluster Lifecycle (ArgoCD)

- **Scope:** Declarative GitOps inside the Kubernetes cluster. Synchronizes cluster networking (Cilium CNI, Hubble), storage provisioners (Local Path Provisioner), metrics pipelines (Prometheus, Grafana, OpenTelemetry), and application workloads directly from the Git repository.
- **Boundary:** ArgoCD operates purely within the Kubernetes API plane. It has no access to the Proxmox hypervisor API or host operating system shells.

## Consequences

### Positive

- **Deterministic Blast Radius:** A failure in Kubernetes or ArgoCD does not affect host-level networking, hypervisor resources, or external DNS and reverse proxy utilities.
- **Idempotent Day-2 Operations:** Kernel updates, package patches, and configuration tuning across all virtual machines are applied reproducibly through Ansible playbooks without rebuilding virtual machines.
- **Single Source of Truth per Layer:** Each tool operates within its optimal abstraction layer, eliminating overlapping automation scripts and configuration collisions.

### Negative

- **Cross-Layer Sequencing:** Provisioning a new service requires sequential execution across boundaries (OpenTofu provision, Ansible configure, ArgoCD deploy).
- **Multiple Toolchains:** Maintaining OpenTofu state, Ansible inventories, and Kubernetes manifests requires multi-domain tooling and workflow disciplines.

## Verification

- [x] Provisioned cluster VMs and LXC utility containers cleanly via OpenTofu.
- [x] Executed Ansible playbooks (`setup-vms.yml`, `setup-pihole.yml`, `setup-nginx.yml`) to configure host runtimes, sysctl parameters, and standalone services.
- [x] Verified ArgoCD synchronized in-cluster platform applications (Cilium, Local Path Provisioner) without host-level intervention.
