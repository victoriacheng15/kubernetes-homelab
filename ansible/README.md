# Ansible VM Configuration Runbook

This directory contains the Ansible automation playbooks and configuration to tune freshly provisioned Ubuntu 24.04 VMs immediately after OpenTofu creates them.

---

## Prerequisites

- Target VMs created by OpenTofu and running.
- SSH access working via user `ubuntu` with your public SSH key.
- Ansible installed on your workstation or running inside the `ansible` LXC container (`CT 303`).

---

## Quickstart

1. **Configure Inventory:**

   ```bash
   cp inventory.example.ini inventory.ini
   ```

   Edit `inventory.ini` and supply the IP addresses or local DNS hostnames of your three nodes.

2. **Verify Connectivity:**
   Test SSH authentication and Python availability across all nodes:

   ```bash
   ansible nodes -m ping
   ```

3. **Execute the Setup Playbook:**

   ```bash
   ansible-playbook playbooks/setup-vms.yml
   ```

---

## What the Playbook Configures

- **Timezone:** Locks system timezone to UTC.
- **Swap:** Disables active swap (`swapoff -a`) and permanently comments out swap entries in `/etc/fstab`.
- **Kernel Modules:** Loads `overlay` and `br_netfilter` immediately and persists them across reboots in `/etc/modules-load.d/k8s.conf`.
- **Sysctl Parameters:** Enables packet forwarding (`net.ipv4.ip_forward = 1`) and bridge netfilter calls in `/etc/sysctl.d/99-kubernetes.conf`.
- **Core Packages:** Installs `curl`, `git`, `jq`, `tcpdump`, `socat`, `chrony`, `htop`, and `tar`.
