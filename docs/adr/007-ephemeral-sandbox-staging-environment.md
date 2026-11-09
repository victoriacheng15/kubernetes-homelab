# ADR 007: Ephemeral Sandbox Staging Environment

- **Status:** Accepted
- **Date:** 2026-11-08
- **Author:** Victoria Cheng

## Context and Problem Statement

When developing OpenTofu definitions, testing cloud-init configurations, or iterating on Ansible playbooks, running untested changes directly against production Kubernetes nodes (`k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`) unnecessarily pollutes node state with test packages or configuration churn.

Furthermore, testing hypervisor provisioning and cloud-init rendering locally on a developer workstation does not accurately match how VMs boot on Proxmox.

A dedicated sandbox VM provides an ephemeral testbed to validate provisioning and playbooks without modifying or affecting the production cluster nodes.

## Decision Outcome

We will introduce a declarative, dynamic sandbox staging mechanism directly within the OpenTofu and Ansible codebases using the following architecture:

1. **Dynamic Sandbox Variable Map (`var.sandbox_vms`):**
   - Define a dynamic map in `infra/01-variables.tf` defaulting to an empty map (`{}`).
   - In production runs, zero sandbox resources exist by default, preventing resource consumption on the Proxmox hosts.
   - Operators can declare one or more ephemeral sandbox instances in `infra/terraform.tfvars` when testing.

2. **Dedicated 900-Series VM ID & IP Reservation:**
   - Reserve VM IDs `900` through `909` exclusively for ephemeral sandboxes to prevent ID collisions with production VMs (100-series) and utility containers (300-series).
   - Reserve static IP allocations `10.0.0.90/24` through `10.0.0.99/24` to ensure deterministic addressing and avoid DHCP lease drift.

3. **Ansible Staging Isolation:**
   - Add a dedicated `[sandbox]` inventory group in `ansible/inventory.ini`.
   - Testing is executed strictly using targeted host limits (`ansible-playbook -i inventory.ini --limit sandbox playbook.yml`), guaranteeing that production cluster nodes are never targeted during experiments.

## Consequences

### Positive

- **Production Cluster Protection:** Prevents configuration drift, accidental package pollution, and service disruption on production Kubernetes nodes during automation development.
- **True Hypervisor Fidelity:** Validates cloud-init drive generation, Proxmox API interactions, and static networking on actual Proxmox hardware rather than an idealized local container.
- **Zero-Footprint Default:** Setting `default = {}` ensures that standard `tofu apply` executions incur zero memory, disk, or CPU overhead when sandboxes are not in use.
- **Fast Teardown:** Entire sandbox environments can be spun up, tested, and destroyed via `tofu destroy -target=proxmox_virtual_environment_vm.sandbox` in seconds.

### Negative

- **Host Resource Allocation:** Consumes physical host CPU, RAM, and storage on `pve-01` while active until destroyed.

## Verification

- [x] **Manual Check:** Run `tofu plan` with `sandbox_vms` defined; verify planned VM ID is in the 900 range.
- [x] **Manual Check:** Spin up `sandbox-01` and verify SSH connectivity via Ansible (`ansible -i inventory.ini -m ping sandbox`).
- [x] **Automated Tests:** Run `tofu fmt -check` and `tofu validate` across `infra/` to confirm syntax validity.
