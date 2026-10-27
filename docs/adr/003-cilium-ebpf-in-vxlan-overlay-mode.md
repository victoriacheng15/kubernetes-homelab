# ADR 003: Cilium eBPF in VXLAN Overlay Mode

- **Status:** Accepted
- **Date:** 2026-10-11
- **Author:** Victoria Cheng

## Context and Problem Statement

Kubernetes pods running across separate physical machines (`pve-01` and `pve-02`) require reliable network communication.

Operating cluster networking across consumer hardware presents specific architectural hurdles:

1. **Consumer Router Routing Limitations:** Physical home routers do not support dynamic BGP routing or static pod CIDR route injection, causing packets destined for internal pod IPs (e.g., `10.244.0.0/16`) to be dropped on the wire.
2. **Home LAN Isolation Requirements:** Pods must not expose internal cluster IP addresses directly to the home network, avoiding ARP noise, IP address exhaustion, and potential conflicts with household consumer devices.
3. **Legacy `kube-proxy` Overhead:** Traditional Kubernetes relies on `kube-proxy` to generate thousands of sequential `iptables` firewall rules, resulting in higher packet latency and difficult debugging.
4. **Network Telemetry Visibility Gap:** Standard network plugins (such as default Flannel) provide no visibility into service-to-service traffic, HTTP status codes, DNS resolution failures, or packet drop reasons.

How should cluster networking and service routing be architected to enable cross-node communication without reconfiguring the home network, while providing real-time network observability?

## Decision Outcome

Deploy Cilium CNI in standard VXLAN encapsulation overlay mode, leveraging in-kernel eBPF for data path routing and Hubble for network observability:

1. **VXLAN Overlay Encapsulation:**
   - Configure Cilium to encapsulate cross-node pod traffic in standard UDP packets on port 8472.
   - Decouple all pod networking from the physical home LAN, allowing cluster communication to run transparently across existing switches.

2. **`kube-proxy` Replacement with eBPF:**
   - Run k3s with `--disable-kube-proxy` and `--flannel-backend=none`.
   - Utilize Cilium's in-kernel eBPF maps for cluster service load balancing, eliminating `iptables` rule chain traversal.

3. **Integrated Network Observability via Hubble:**
   - Deploy Hubble Relay and Hubble UI on `k8s-telemetry-01` to capture and stream real-time flow logs, L7 HTTP metrics, and drop diagnostics directly to Prometheus and Grafana.

## Consequences

### Positive

- **Zero Home Router Modifications:** Pod traffic travels as regular UDP packets between the two physical servers, eliminating any need for BGP, static routes, or router changes.
- **Deep Network Observability:** Hubble exposes live DNS lookups, TCP connection states, HTTP status codes, and packet drop reasons via CLI and dashboard interfaces.
- **High Data Path Performance:** Replacing `iptables` with eBPF socket routing reduces packet processing latency and CPU overhead.
- **Identity-Aware Security:** Supports L3/L4 and L7 `CiliumNetworkPolicy` resources to enforce zero-trust service communication based on Kubernetes labels rather than brittle IP addresses.

### Negative

- **Encapsulation Header Overhead:** The 50-byte VXLAN header (Outer IP + UDP + VXLAN) reduces the effective maximum transmission unit (MTU) from 1500 to 1450 bytes.
- **Host Kernel Compatibility Dependency:** Cilium requires modern Linux kernel eBPF capabilities and kernel headers on the underlying VM templates.
- **Operational Learning Curve:** Troubleshooting eBPF maps requires learning `cilium` and `hubble` CLI tooling instead of standard Linux `iptables` or `route` commands.

## Verification

- [x] Deploy test pod on `k8s-app-01`, executing network and DNS queries across the overlay to verify cluster connectivity.
- [x] Run `cilium status` and confirm BPF data path is active and `kube-proxy` replacement is enabled.
- [x] Confirm Hubble Relay and Hubble UI pods are running across worker nodes.
