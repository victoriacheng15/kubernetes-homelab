# Engineering Log

Reverse-chronological record of physical hardware provisioning, cluster state transitions, operational debugging, and verification outputs.

---

## 2026-10-27

**Summary:** Bootstrapped the Layer 3 Kubernetes platform across three virtual machines (`k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`) using k3s and Cilium eBPF CNI in VXLAN overlay mode. Refactored the bootstrap automation suite to enforce clear separation of concerns with Ansible OS baselines, resolved host networking lockout and API server connectivity issues caused by Cilium IPAM and eBPF bypass, and bypassed Kubernetes NodeRestriction admission rejections during worker onboarding.

**Target Nodes & Scope:**

* **Virtual Machines:** `k8s-cp-01` (VM 100), `k8s-telemetry-01` (VM 101), `k8s-app-01` (VM 200)
* **Automation & Scripts:** `bootstrap/00-preflight.sh`, `bootstrap/01-k3s-server.sh`, `bootstrap/02-k3s-agent.sh`, `bootstrap/03-cni-cilium.sh`, `Makefile`
* **Documentation:** `docs/provisioning.md`, `docs/adr/003-cilium-ebpf-in-vxlan-overlay-mode.md`, `bootstrap/README.md`

**Actions Executed:**

* Removed redundant `bootstrap/01-prerequisites.sh` to enforce exclusive OS baseline management via Ansible (`playbooks/setup-vms.yml`).
* Added Section 5 (Ansible OS Baseline Verification) to `bootstrap/00-preflight.sh` to validate timezone, swap disablement, kernel modules (`overlay`, `br_netfilter`), and sysctl IP forwarding prior to Kubernetes installation.
* Configured dedicated Pod CIDR `10.244.0.0/16` and mask size 24 via Cilium Helm values (`ipam.operator.clusterPoolIPv4PodCIDRList` and `ipv4NativeRoutingCIDR`), completely preventing collisions with the physical `10.0.0.0/24` host network.
* Enabled `bpf.hostLegacyRouting=true` in Cilium deployment parameters to safeguard host SSH and ICMP management traffic on virtualized KVM interfaces.
* Dynamically resolved the node primary IP (`<CONTROL_PLANE_IP>`) for Cilium `k8sServiceHost` to maintain reliable in-pod API server connectivity for metrics-server and core addons.

**Incidents, Root Causes & Fixes:**

* **Issue 1: Cilium IPAM Host Subnet Collision and SSH Lockout on `k8s-cp-01`**
  * **Symptom:** Host `k8s-cp-01` lost SSH connectivity and stopped responding to ICMP ping from the local network following Cilium installation.
  * **Root Cause:** Without an explicit cluster pool CIDR, Cilium defaulted to `10.0.0.0/8`, which subsumed the home physical subnet (`10.0.0.0/24`). Cilium assigned an IP within the home subnet to `cilium_host` and routed all `10.0.0.0/24` traffic into the `cilium_host` interface, blackholing inbound and outbound host traffic. Furthermore, eBPF host routing bypassed the Linux kernel routing stack on `eth0`.
  * **Fix:** Accessed `k8s-cp-01` out-of-band via Proxmox VNC console, deleted the conflicting `10.0.0.0/24` route on `cilium_host`, and fully uninstalled Cilium. Purged all lingering Cilium CRDs, `/etc/cni/net.d/05-cilium.conflist`, `/var/run/cilium` cgroup mounts, and `/sys/fs/bpf/cilium` maps. Updated `bootstrap/03-cni-cilium.sh` to hardcode `POD_CIDR="10.244.0.0/16"` and set `bpf.hostLegacyRouting=true`.

* **Issue 2: Worker Node Join Crash on Kubernetes NodeRestriction Admission**
  * **Symptom:** `k3s-agent.service` failed to start on `k8s-telemetry-01` with `Error: failed to validate kubelet flags: unknown 'kubernetes.io' or 'k8s.io' labels specified with --node-labels: [node-role.kubernetes.io/telemetry]`.
  * **Root Cause:** The Kubernetes `NodeRestriction` admission controller prohibits worker kubelet agents from self-assigning labels in the reserved `node-role.kubernetes.io/*` namespace for cluster security isolation.
  * **Fix:** Updated `bootstrap/02-k3s-agent.sh` to only configure the custom `workload=<role>` label in agent `/etc/rancher/k3s/config.yaml`. Applied formal role labels (`node-role.kubernetes.io/<role>=true`) from the control plane using `kubectl label node`.

**Verification & Terminal Outputs:**

* **Cluster Nodes State (`kubectl get nodes -o wide`):**

```text
NAME               STATUS   ROLES           AGE     VERSION        INTERNAL-IP       EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION              CONTAINER-RUNTIME
k8s-app-01         Ready    app             3m27s   v1.36.5+k3s1   <APP_NODE_IP>     <none>        Ubuntu 24.04.5 LTS   6.8.0-147-generic (amd64)   containerd://2.3.4-k3s1.36
k8s-cp-01          Ready    control-plane   132m    v1.36.5+k3s1   <CP_NODE_IP>      <none>        Ubuntu 24.04.5 LTS   6.8.0-147-generic (amd64)   containerd://2.3.4-k3s1.36
k8s-telemetry-01   Ready    telemetry       6m23s   v1.36.5+k3s1   <TELEM_NODE_IP>   <none>        Ubuntu 24.04.5 LTS   6.8.0-147-generic (amd64)   containerd://2.3.4-k3s1.36
```

* **Core Pods & Cilium Infrastructure (`kubectl get pods -A`):**

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

---

## 2026-10-26

**Summary:** Established strict separation of concerns across the platform hierarchy (OpenTofu IaaS -> Ansible OS Configuration -> ArgoCD GitOps). Resolved OpenTofu HTTP connection pool starvation caused by in-guest agent polling, protected imported utility containers from accidental recreation via lifecycle ignore rules, and restructured architectural diagrams into three discrete visual models with a unified Slate design system.

**Target Nodes & Scope:**

* **Virtual Machines:** `k8s-cp-01` (VM 100), `k8s-telemetry-01` (VM 101), `k8s-app-01` (VM 200)
* **Containers (LXC):** `pihole` (CT 300), `tailscale` (CT 301), `nginx` (CT 302), `ansible` (CT 303)
* **Automation & Docs:** `infra/`, `ansible/`, `scripts/generate_diagram.py`, `docs/assets/`

**Actions Executed:**

* Removed in-guest `agent` polling blocks from all VM definitions in `infra/02-vms.tf` to eliminate API timeout deadlocks.
* Configured `lifecycle { ignore_changes = [operating_system[0].template_file_id, unprivileged] }` in `infra/03-containers.tf` to safeguard pre-existing imported containers.
* Standardized VM and container tags to a strict two-tag taxonomy (`k8s`, `dns`, `vpn`, `proxy`, `automation`, `utility`).
* Added `container_template_file_id` variable defaulting to `local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst`.
* Refactored `scripts/generate_diagram.py` to generate three distinct diagrams in logical order:
  1. `Platform Architecture Layers` (`docs/assets/platform-layers.png`): Nested 3-tier wrapper stack.
  2. `Kubernetes Homelab Architecture` (`docs/assets/architecture.png`): Physical bare-metal topology.
  3. `GitOps Flow` (`docs/assets/gitops.png`): Declarative delivery reconciliation.
* Applied a unified design system across diagrams: minimum font size 16px, Slate palette (`#f8fafc` canvas, `#f1f5f9` outer cluster, `#e2e8f0` inner cluster), and zero pure white.

**Incidents, Root Causes & Fixes:**

* **Issue 1: OpenTofu API Timeouts on Container Status (`context deadline exceeded`)**
  * **Symptom:** OpenTofu returned: `error retrieving container status: failed to perform HTTP GET request (path: nodes/pve-01/lxc/301/status/current) - Reason: context deadline exceeded`.
  * **Root Cause:** Virtual machine configurations included `agent { enabled = true }` with a 15-minute polling timeout. Because freshly cloned VMs do not have active guest agents running prior to OS configuration, OpenTofu held HTTP connections open, starving the Proxmox API connection pool.
  * **Fix:** Removed the `agent` block entirely from VM configurations in `infra/02-vms.tf`. Established the operational rule that OpenTofu handles hypervisor-level provisioning exclusively, while in-guest agent activation is delegated to Ansible.

* **Issue 2: OpenTofu Plan Drift Flagging Imported Containers for Destruction**
  * **Symptom:** `tofu plan` attempted to destroy and recreate `pihole` (CT 300) and `tailscale` (CT 301) due to missing template file IDs and unprivileged flag mismatches in state.
  * **Root Cause:** Imported containers were originally created manually without template metadata, causing OpenTofu to detect a diff against required configuration parameters.
  * **Fix:** Added `lifecycle { ignore_changes = [operating_system[0].template_file_id, unprivileged] }` in `infra/03-containers.tf`, ensuring in-place management without destructive recreation.

---

## 2026-10-25

**Summary:** Initialized the physical dual-node Proxmox VE cluster (`k8s-homelab`) with an external Raspberry Pi Corosync QDevice tiebreaker, achieving an odd 3-vote quorum. Configured Stratum 2 Chrony NTP on `rpi-01`, aligned existing utility containers, and automated VM and LXC deployment using OpenTofu.

**Target Nodes & Scope:**

* **Physical Hosts:** `pve-01` (Mini PC), `pve-02` (Laptop), `rpi-01` (Raspberry Pi 4)
* **Virtual Machines:** `k8s-cp-01` (VM 100), `k8s-telemetry-01` (VM 101), `k8s-app-01` (VM 200), Ubuntu 24.04 Template (VM 9000)
* **Containers (LXC):** `pihole` (CT 300 on `pve-02`), `tailscale` (CT 301 on `pve-01`), `nginx` (CT 302 on `pve-01`), `ansible` (CT 303 on `pve-01`)

**Actions Executed:**

* Formed the Proxmox cluster `k8s-homelab` on `pve-01` and joined `pve-02`.
* Preserved existing container configs across the `pmxcfs` join and migrated `tailscale` (CT 301) from `pve-02` to `pve-01`.
* Installed `corosync-qnetd` on `rpi-01` and attached it as the external cluster QDevice via `pvecm qdevice setup`.
* Configured Chrony NTP on `rpi-01` as the local network time server and synchronized `pve-01` and `pve-02`.
* Migrated Ubuntu 24.04 Cloud-Init template (VM 9000) to `pve-01` local storage.
* Downloaded Debian 13 standard amd64 LXC template on `pve-01`.
* Configured OpenTofu manifests (`infra/`) to provision Kubernetes VMs and manage LXC utility containers.

**Verification & Terminal Outputs:**

* **Cluster Quorum & QDevice Status (`pvecm status`):**

```text
Cluster information
-------------------
Name:             k8s-homelab
Config Version:   3
Transport:        knet
Secure auth:      on

Quorum information
------------------
Date:             Mon Oct 26 02:13:26 2026
Quorum provider:  corosync_votequorum
Nodes:            2
Node ID:          0x00000001
Ring ID:          1.1b
Quorate:          Yes

Votequorum information
----------------------
Expected votes:   3
Highest expected: 3
Total votes:      3
Quorum:           2  
Flags:            Quorate Qdevice 

Membership information
----------------------
    Nodeid      Votes    Qdevice Name
         1          1    A,V,NMW pve-01 (local)
         2          1    A,V,NMW pve-02
         0          1            Qdevice
```

* **Authoritative Time Synchronization (`chronyc sources -v`):**

```text
MS Name/IP address         Stratum Poll Reach LastRx Last sample               
===============================================================================
^- time.cloudflare.com           3   6    17     7   +462us[ +462us] +/-   24ms
^* time4.google.com              1   6    17     7   +142us[ +676us] +/-   10ms
^- archer.fsck.ca                2   6    17     6   -572us[ -572us] +/-   36ms
```

**Incidents, Root Causes & Fixes:**

* **Issue 1: Proxmox Join Blocked Due to Pre-existing Containers**
  * **Symptom:** `pvecm add` failed with error: `this host already contains virtual guests`.
  * **Root Cause:** Joining a cluster mounts the shared `pmxcfs` cluster filesystem over `/etc/pve`, which would hide local guest configurations if not preserved.
  * **Fix:** Backed up `/etc/pve/local/lxc` to `/root/pve-lxc-backup`, executed `pvecm add <PVE_01_IP> --force`, and restored `.conf` files into `/etc/pve/nodes/pve-02/lxc/`.

* **Issue 2: Proxmox API HTTP 403 Forbidden on VM Clone**
  * **Symptom:** OpenTofu returned: `error cloning VM: received an HTTP 403 response - Reason: Permission check failed (/vms/9000, VM.Clone)`.
  * **Root Cause:** Proxmox Web GUI checks **Privilege Separation** by default when creating API tokens, stripping administrative permissions from `root@pam!tofu`.
  * **Fix:** Recreated the token with **Privilege Separation unchecked**, restoring inherited root permissions.

* **Issue 3: OpenTofu Failed to Locate Template 9000 on `pve-02`**
  * **Symptom:** OpenTofu returned: `HTTP 500 - unable to find configuration file for VM 9000 on node 'pve-02'`.
  * **Root Cause:** Template 9000 resides on `pve-01`. When provisioning `k8s-app-01` on `pve-02`, OpenTofu defaulted to searching for the template on the target node.
  * **Fix:** Added `node_name = "pve-01"` explicitly inside the `clone` block in `infra/02-vms.tf`.

* **Issue 4: QDevice Marked as `NR` for `pve-02`**
  * **Symptom:** `pvecm nodes` displayed `NR` under the Qdevice column for `pve-02`, causing OpenTofu plan timeouts.
  * **Root Cause:** `NR` signifies "Not Registered" with the remote `corosync-qnetd` daemon. After simulated failover testing, `corosync-qdevice.service` was stopped on `pve-02`.
  * **Fix:** Executed `systemctl restart corosync-qdevice` on `pve-02`, successfully reconnecting to port 5403 on `rpi-01`.
