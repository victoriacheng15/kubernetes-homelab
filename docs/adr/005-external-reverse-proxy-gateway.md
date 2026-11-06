# ADR 005: External Reverse Proxy Gateway

- **Status:** Accepted
- **Date:** 2026-11-02
- **Author:** Victoria Cheng

## Context and Problem Statement

Providing network access to homelab services requires ingress routing from LAN client devices. Typical Kubernetes architectures deploy an in-cluster Ingress Controller (such as Cilium Ingress, Ingress-Nginx, or Traefik) coupled with Layer 2 ARP announcements or BGP routing via MetalLB or Cilium.

In this homelab environment, several constraints and operational challenges arise:

1. **Decoupled Out-of-Cluster Services:** Critical services exist outside the Kubernetes cluster, including the Pi-hole DNS sinkhole and Proxmox VE hypervisor management interfaces. An in-cluster ingress controller cannot proxy traffic when Kubernetes nodes are offline.
2. **Resource Constraints:** In a two-node heterogeneous cluster (`pve-01` Mini PC, `pve-02` Laptop), running in-cluster ingress controller daemonsets, proxy pods, and load balancers consumes CPU and memory that are better reserved for application workloads and observability pipelines.
3. **Consumer Network Limitations:** The home LAN operates on a standard router without native BGP support. Relying on Layer 2 ARP leader election for virtual IPs introduces failover latency and network broadcast overhead.

How should ingress routing and reverse proxying be structured to serve both Kubernetes workloads and out-of-cluster homelab services reliably?

## Decision Outcome

Deploy an external, standalone Nginx reverse proxy inside a dedicated lightweight Proxmox LXC container on `pve-01`:

### Standalone Gateway Architecture

- Host Nginx within a Debian LXC container on `pve-01` bridged directly onto the primary LAN (`vmbr0`).
- Assign a dedicated static IP address within the infrastructure subnet range.
- Pair with the Pi-hole DNS sinkhole where a wildcard DNS entry (`*.homelab.local`) resolves directly to the Nginx gateway IP.

### Unified Routing Hub

- Nginx terminates HTTP traffic for both internal Kubernetes NodePort services (ArgoCD, Hubble UI) and standalone LXC services (Pi-hole web admin).
- Configuration files are managed declaratively using Ansible (`ansible/playbooks/setup-nginx.yml`) with modular virtual host definitions in `/etc/nginx/conf.d/`.

### Lifecycle Independence

- The gateway operates independently of Kubernetes cluster availability. Maintenance, reboots, or failures of Kubernetes worker or control plane nodes do not interrupt DNS routing or access to independent utilities.

## Consequences

### Positive

- **Independent Availability:** Pi-hole, status endpoints, and hypervisor utilities remain accessible through the gateway even during Kubernetes cluster maintenance or downtime.
- **Minimal Resource Footprint:** The Debian LXC container consumes less than 50 MB of RAM, leaving maximum host memory available for Kubernetes workloads.
- **Simplified Networking:** Eliminates the need for BGP routers, complex CNI host-routing configurations, or L2 ARP broadcast failovers on the home LAN.

### Negative

- **Manual Route Management:** New Kubernetes services are not discovered automatically via standard Kubernetes Ingress or Gateway API resources. Routes must be declared in Ansible playbooks and deployed to Nginx.
- **Single Point of Gateway Ingress:** Running a single Nginx LXC instance creates a failure domain on `pve-01`. If `pve-01` fails, external hostname routing drops until restored or migrated.

## Verification

- [x] Configured Nginx virtual hosts in `/etc/nginx/conf.d/` routing `argocd.homelab.local`, `hubble.homelab.local`, and `pihole.homelab.local`.
- [x] Validated configuration syntax via `nginx -t`.
- [x] Verified HTTP resolution from client workstation through Pi-hole wildcard DNS to the Nginx reverse proxy endpoint.
