# 2026-11-24: Remote Tailscale Subnet Routing

## Overview

Resolved remote OpenTofu (`tofu plan`) connection timeouts when administering the homelab from outside the home network via the `rpi-01` Tailscale gateway. Enabled RFC 1918 subnet routing alongside exit-node functionality so remote workstations can reach internal `<HOME_LAN_CIDR>` homelab devices (`pve-01` Proxmox API and SSH) over the encrypted Tailscale mesh.

## Target Scope

* **Gateway Node:** `rpi-01` (Tailscale exit node and subnet router)
* **Infrastructure & Tooling:** `infra/00-main.tf`, local workstation Tailscale client

## Key Changes

* Configured `rpi-01` to advertise the home LAN CIDR (`--advertise-routes=<HOME_LAN_CIDR>`) in addition to `--advertise-exit-node`.
* Approved the `<HOME_LAN_CIDR>` subnet route in the Tailscale Admin Console and enabled `--accept-routes` on the remote client workstation.

## Incidents & Root Cause Analysis

### 1. Remote `tofu plan` Timeout Over Tailscale Exit Node

* **Symptom:** Running `tofu plan` from a remote network timed out while connecting to the Proxmox API (`:8006`). Public internet traffic routed successfully through `rpi-01` as an exit node, and `ip route get <PROXMOX_HOST_IP>` on the workstation confirmed packets entered `dev tailscale0`, yet both HTTPS (`curl -k -I --connect-timeout 5 https://<PROXMOX_HOST_IP>:8006/`) and SSH (`/dev/tcp/<PROXMOX_HOST_IP>/22`) failed to reach `pve-01`.
* **Root Cause:** In Tailscale, `--advertise-exit-node` only routes default internet traffic (`0.0.0.0/0`) and does not automatically expose or forward traffic to private RFC 1918 LAN subnets (`<HOME_LAN_CIDR>`). Additionally, Linux Tailscale clients do not accept advertised subnet routes unless `--accept-routes` is explicitly set.
* **Resolution:** Advertised the home LAN subnet on `rpi-01` (`sudo tailscale set --advertise-exit-node --advertise-routes=<HOME_LAN_CIDR>`), approved the route in the Tailscale Admin Console, and enabled route acceptance on the client (`sudo tailscale set --accept-routes`). Verified `tofu plan` and direct LAN connectivity to `pve-01` succeeded immediately afterward.

## Verification

??? note "Proxmox API Reachability Over Tailscale (`curl -k -I --connect-timeout 5 https://<PROXMOX_HOST_IP>:8006/`)"
    ```text
    HTTP/1.1 501 method 'HEAD' not available
    ```

??? note "Proxmox SSH Port Reachability Over Tailscale (`timeout 5 bash -c \"</dev/tcp/<PROXMOX_HOST_IP>/22\" && echo \"22 open\" || echo \"22 unreachable\"`)"
    ```text
    22 open
    ```

??? note "Remote OpenTofu State Refresh (`tofu -chdir=infra plan`)"
    ```text
    No changes. Your infrastructure matches the configuration.
    ```
