# 2026-11-02: Layer 2 DNS Sinkhole & Gateway Automation

## Overview

Automated standalone Layer 2 network utility containers (Pi-hole DNS sinkhole and Nginx reverse proxy gateway) using Ansible, enabling internal hostname resolution for homelab services and Kubernetes NodePorts. Hardened Ansible playbooks against upcoming fact deprecations, added Ansible dependency collections to CI, extended OpenTofu with IP output queries, and formalized platform architecture across ADR 004 and ADR 005.

## Target Scope

* **Containers (LXC):** `pihole` on `pve-02`, `nginx` on `pve-01`
* **Automation:** `ansible/playbooks/setup-pihole.yml`, `ansible/playbooks/setup-nginx.yml`, `ansible/playbooks/setup-vms.yml`, `ansible/requirements.yml`, `.github/workflows/ci.yaml`
* **Architecture & Documentation:** `docs/adr/004-three-tier-platform-lifecycle.md`, `docs/adr/005-external-reverse-proxy-gateway.md`, `docs/provisioning.md`, `infra/99-outputs.tf`

## Key Changes

* Automated unattended Pi-hole DNS sinkhole provisioning and wildcard resolution (`*.homelab.local`) to the Nginx gateway via `ansible/playbooks/setup-pihole.yml`.
* Automated Nginx reverse proxy virtual host routing for ArgoCD (`argocd.homelab.local`), Hubble UI (`hubble.homelab.local`), and Pi-hole admin console (`pihole.homelab.local`).
* Migrated playbook variable syntax to `ansible_facts['<fact>']` across all playbooks, eliminating `INJECT_FACTS_AS_VARS` deprecation warnings.
* Added `ansible/requirements.yml` declaring `community.general` and `ansible.posix`, and updated `.github/workflows/ci.yaml` to install requirements before running syntax validation.
* Added `infra/99-outputs.tf` to expose container and VM static IP assignments directly from OpenTofu without requiring in-guest QEMU agent polling.
* Adopted ADR 004 (Three-Tier Platform Lifecycle: OpenTofu, Ansible, ArgoCD) and ADR 005 (External Reverse Proxy Gateway).

## Incidents & Root Cause Analysis

### 1. Pi-hole v6 FTL Configuration Decoupling

* **Symptom:** Wildcard DNS queries for `*.homelab.local` failed with `NXDOMAIN` despite placing configuration in `/etc/dnsmasq.d/02-homelab.conf`.
* **Root Cause:** Pi-hole v6 migrated its core configuration engine to `/etc/pihole/pihole.toml` and disables reading `/etc/dnsmasq.d/` by default.
* **Resolution:** Configured `pihole-FTL --config misc.etc_dnsmasq_d true` in `setup-pihole.yml` prior to restarting `pihole-FTL.service`.

### 2. Linux RFC 6762 mDNS Multicast Trap for `.local` Domains

* **Symptom:** Client workstation failed to resolve `argocd.homelab.local` via Pi-hole (`Server failure`), while public internet domain queries resolved normally.
* **Root Cause:** RFC 6762 designates `.local` exclusively for link-local multicast DNS (mDNS). `systemd-resolved` intercepted `.local` queries and broadcasted on mDNS `224.0.0.251:5353` instead of forwarding unicast DNS requests to the upstream Pi-hole server.
* **Resolution:** Configured an explicit routing domain (`~homelab.local`) on the client network interface to force unicast forwarding to the homelab DNS server.
