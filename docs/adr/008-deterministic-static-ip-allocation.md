# ADR 008: Deterministic Static IP Allocation

- **Status:** Proposed
- **Date:** 2026-11-24
- **Author:** Victoria Cheng

## Context and Problem Statement

Currently, cluster virtual machines and utility LXC containers rely on the home router's DHCP server to assign IP addresses. Because DHCP assigns addresses dynamically from a pool, it is messy and hard to remember which IP belongs to which device:

- **Unordered Address Space:** DHCP scatters VMs, LXC containers, and physical hosts across random IPs, making it difficult to tell at a glance what kind of device an IP belongs to.
- **Manual Lookups & Lease Drift:** Without predictable, ordered ranges managed in OpenTofu, adding or migrating hosts requires checking router leases and updating `ansible/inventory.ini`, `kubeconfig` endpoints, and Nginx upstreams.

Organizing the address space into ordered static ranges (for example, `.10` to `.29` for VMs and `.30` to `.49` for containers) makes the network immediately readable and easy to manage through OpenTofu and Ansible.

## Decision Outcome

This decision migrates all permanent and ephemeral infrastructure from dynamic DHCP leases to a deterministic static IP allocation schema within `<HOME_LAN_CIDR>`, enforced declaratively in OpenTofu (`infra/02-vms.tf`, `infra/03-containers.tf`) and `ansible/inventory.ini`:

| IP Range (`<HOME_LAN_CIDR>`) | Tier | Scope |
| :--- | :--- | :--- |
| `<SUBNET>.10` - `<SUBNET>.29` | Cluster Virtual Machines | Control plane and worker VMs |
| `<SUBNET>.30` - `<SUBNET>.49` | Utility Containers (LXC) | `ansible`, `pihole`, `nginx`, `storage` |
| `<SUBNET>.50` - `<SUBNET>.59` | Proxmox Hypervisors | `pve-01`, `pve-02` (plus reserved host slots) |
| `<SUBNET>.60` - `<SUBNET>.69` | Non-PVE Hardware | `rpi-01` and external infrastructure devices |
| `<SUBNET>.80` - `<SUBNET>.89` | Ephemeral Sandbox Containers | Disposable `800`-series LXCs |
| `<SUBNET>.90` - `<SUBNET>.99` | Ephemeral Sandbox VMs | Disposable `900`-series VMs |

## Consequences

### Positive

- **Zero Lease Drift & Portable Hardware Migrations:** Node and container IPs are managed declaratively in OpenTofu and stay consistent across hardware migrations or node replacements without requiring manual router DHCP reservation lookups.
- **Clear Operational Boundaries:** Any operator can immediately identify a host's role (hypervisor, cluster VM, utility LXC, or ephemeral sandbox) from its last octet.
- **Simplified Automation:** `ansible/inventory.ini`, Nginx upstreams, and remote `kubeconfig` endpoints stay permanently pinned to known addresses.

### Negative

- **DHCP Pool Exclusion Required:** The home router's DHCP pool must be restricted outside `.10` through `.99` to prevent the router from assigning a static homelab IP to an unrelated LAN device.
- **Rebuild Cutover:** Applying static IP configurations in OpenTofu (`infra/02-vms.tf`, `infra/03-containers.tf`) may recreate or re-initialize existing VMs and containers.

## Verification

- [ ] **Router Boundary:** Confirm home router DHCP range does not overlap with `.10` through `.99`.
- [ ] **Infrastructure Plan:** Run `tofu -chdir=infra plan` and verify static CIDR and gateway assignments for VMs and LXCs.
- [ ] **Connectivity Check:** Run `ansible -i inventory.ini all -m ping` against the updated static inventory after apply.
- [ ] **Syntax Validation:** Run `tofu -chdir=infra fmt -check` and `tofu -chdir=infra validate`.
