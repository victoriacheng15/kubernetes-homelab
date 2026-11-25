# 2026-10-27: Layer 3 Kubernetes Bootstrap & Cilium eBPF

## Overview

Bootstrapped the Layer 3 Kubernetes platform across three virtual machines (`k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`) using k3s and Cilium eBPF CNI in VXLAN overlay mode. Refactored the bootstrap automation suite to enforce clear separation of concerns with Ansible OS baselines, resolved host networking lockout and API server connectivity issues caused by Cilium IPAM and eBPF bypass, and bypassed Kubernetes NodeRestriction admission rejections during worker onboarding.

## Target Scope

* **Virtual Machines:** `k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`
* **Automation & Scripts:** `bootstrap/00-preflight.sh`, `bootstrap/01-k3s-server.sh`, `bootstrap/02-k3s-agent.sh`, `bootstrap/03-cni-cilium.sh`, `Makefile`
* **Documentation:** `docs/provisioning.md`, `docs/adr/003-cilium-ebpf-in-vxlan-overlay-mode.md`, `bootstrap/README.md`

## Key Changes

* Removed redundant `bootstrap/01-prerequisites.sh` to enforce exclusive OS baseline management via Ansible (`playbooks/setup-vms.yml`).
* Added Section 5 (Ansible OS Baseline Verification) to `bootstrap/00-preflight.sh` to validate timezone, swap disablement, kernel modules (`overlay`, `br_netfilter`), and sysctl IP forwarding prior to Kubernetes installation.
* Configured dedicated Pod CIDR `10.244.0.0/16` and mask size 24 via Cilium Helm values (`ipam.operator.clusterPoolIPv4PodCIDRList` and `ipv4NativeRoutingCIDR`), completely preventing collisions with the physical `10.0.0.0/24` host network.
* Enabled `bpf.hostLegacyRouting=true` in Cilium deployment parameters to safeguard host SSH and ICMP management traffic on virtualized KVM interfaces.
* Dynamically resolved the node primary IP (`<CONTROL_PLANE_IP>`) for Cilium `k8sServiceHost` to maintain reliable in-pod API server connectivity for metrics-server and core addons.

## Incidents & Root Cause Analysis

### 1. Cilium IPAM Host Subnet Collision and SSH Lockout (`k8s-cp-01`)

* **Symptom:** Host `k8s-cp-01` lost SSH connectivity and stopped responding to ICMP ping from the local network following Cilium installation.
* **Root Cause:** Without an explicit cluster pool CIDR, Cilium defaulted to `10.0.0.0/8`, which subsumed the home physical subnet (`10.0.0.0/24`). Cilium assigned an IP within the home subnet to `cilium_host` and routed all `10.0.0.0/24` traffic into the `cilium_host` interface, blackholing inbound and outbound host traffic. Furthermore, eBPF host routing bypassed the Linux kernel routing stack on `eth0`.
* **Resolution:** Accessed `k8s-cp-01` out-of-band via Proxmox VNC console, deleted the conflicting `10.0.0.0/24` route on `cilium_host`, and fully uninstalled Cilium. Purged all lingering Cilium CRDs, `/etc/cni/net.d/05-cilium.conflist`, `/var/run/cilium` cgroup mounts, and `/sys/fs/bpf/cilium` maps. Updated `bootstrap/03-cni-cilium.sh` to explicitly define `POD_CIDR="10.244.0.0/16"` and set `bpf.hostLegacyRouting=true`.

### 2. Worker Node Join Crash on Kubernetes NodeRestriction Admission (`k8s-telemetry-01`)

* **Symptom:** `k3s-agent.service` failed to start on `k8s-telemetry-01` with `Error: failed to validate kubelet flags: unknown 'kubernetes.io' or 'k8s.io' labels specified with --node-labels: [node-role.kubernetes.io/telemetry]`.
* **Root Cause:** The Kubernetes `NodeRestriction` admission controller prohibits worker kubelet agents from self-assigning labels in the reserved `node-role.kubernetes.io/*` namespace for cluster security isolation.
* **Resolution:** Updated `bootstrap/02-k3s-agent.sh` to only configure the custom `workload=<role>` label in agent `/etc/rancher/k3s/config.yaml`. Applied formal role labels (`node-role.kubernetes.io/<role>=true`) from the control plane using `kubectl label node`.

## Verification

??? note "Cluster Nodes State (`kubectl get nodes -o wide`)"
    ```text
    NAME               STATUS   ROLES           AGE     VERSION        INTERNAL-IP       EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION              CONTAINER-RUNTIME
    k8s-app-01         Ready    app             3m27s   v1.36.5+k3s1   <APP_NODE_IP>     <none>        Ubuntu 24.04.5 LTS   6.8.0-147-generic (amd64)   containerd://2.3.4-k3s1.36
    k8s-cp-01          Ready    control-plane   132m    v1.36.5+k3s1   <CP_NODE_IP>      <none>        Ubuntu 24.04.5 LTS   6.8.0-147-generic (amd64)   containerd://2.3.4-k3s1.36
    k8s-telemetry-01   Ready    telemetry       6m23s   v1.36.5+k3s1   <TELEM_NODE_IP>   <none>        Ubuntu 24.04.5 LTS   6.8.0-147-generic (amd64)   containerd://2.3.4-k3s1.36
    ```

??? note "Core Pods & Cilium Infrastructure (`kubectl get pods -A`)"
    ```text
    NAMESPACE     NAME                                      READY   STATUS    RESTARTS      AGE
    kube-system   cilium-7xxtz                              1/1     Running   0             92s
    kube-system   cilium-bjzjc                              1/1     Running   0             92s
    kube-system   cilium-envoy-2nb7q                        1/1     Running   0             92s
    kube-system   cilium-envoy-5sbt8                        1/1     Running   0             92s
    kube-system   cilium-envoy-tnnpt                        1/1     Running   0             92s
    kube-system   cilium-hs7jt                              1/1     Running   0             92s
    kube-system   cilium-operator-68d47884c4-hr2gt          1/1     Running   0             92s
    kube-system   coredns-7cfb7bc9c7-95x62                  1/1     Running   0             80s
    kube-system   hubble-relay-6d4d7c44-mdpbb               1/1     Running   0             92s
    kube-system   hubble-ui-6645694df9-67sh4                2/2     Running   0             92s
    kube-system   local-path-provisioner-77b9867795-snbbq   1/1     Running   4 (20m ago)   132m
    kube-system   metrics-server-6dc596dfb8-cwd75           1/1     Running   1 (21m ago)   59m
    ```
