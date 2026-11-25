# 2026-10-26: Platform Hierarchy & OpenTofu Hardening

## Overview

Established strict separation of concerns across the platform hierarchy (OpenTofu IaaS -> Ansible OS Configuration -> ArgoCD GitOps). Resolved OpenTofu HTTP connection pool starvation caused by in-guest agent polling, protected imported utility containers from accidental recreation via lifecycle ignore rules, and restructured architectural diagrams into discrete visual models with a unified Slate design system.

## Target Scope

* **Virtual Machines:** `k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`
* **Containers (LXC):** `pihole`, `tailscale`, `nginx`, `ansible`
* **Automation & Docs:** `infra/`, `ansible/`, `scripts/generate_diagram.py`, `docs/assets/`

## Key Changes

* Removed in-guest `agent` polling blocks from all VM definitions in `infra/02-vms.tf` to eliminate API timeout deadlocks.
* Configured `lifecycle { ignore_changes = [operating_system[0].template_file_id, unprivileged] }` in `infra/03-containers.tf` to safeguard pre-existing imported containers.
* Standardized VM and container tags to a strict two-tag taxonomy (`k8s`, `dns`, `vpn`, `proxy`, `automation`, `utility`).
* Added `container_template_file_id` variable defaulting to `local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst`.
* Refactored `scripts/generate_diagram.py` to generate diagrams using a unified Slate design token system.

## Incidents & Root Cause Analysis

### 1. OpenTofu API Timeouts on Container Status (`context deadline exceeded`)

* **Symptom:** OpenTofu returned: `error retrieving container status: failed to perform HTTP GET request (path: nodes/pve-01/lxc/301/status/current) - Reason: context deadline exceeded`.
* **Root Cause:** Virtual machine configurations included `agent { enabled = true }` with a 15-minute polling timeout. Because freshly cloned VMs do not have active guest agents running prior to OS configuration, OpenTofu held HTTP connections open, starving the Proxmox API connection pool.
* **Resolution:** Removed the `agent` block entirely from VM configurations in `infra/02-vms.tf`. Established the operational rule that OpenTofu handles hypervisor-level provisioning exclusively, while in-guest agent activation is delegated to Ansible.

### 2. OpenTofu Plan Drift Flagging Imported Containers for Destruction

* **Symptom:** `tofu plan` attempted to destroy and recreate `pihole` and `tailscale` due to missing template file IDs and unprivileged flag mismatches in state.
* **Root Cause:** Imported containers were originally created manually without template metadata, causing OpenTofu to detect a diff against required configuration parameters.
* **Resolution:** Added `lifecycle { ignore_changes = [operating_system[0].template_file_id, unprivileged] }` in `infra/03-containers.tf`, ensuring in-place management without destructive recreation.
