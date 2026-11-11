# Engineering Log

Reverse-chronological record of physical hardware provisioning, cluster state transitions, operational debugging, and verification outputs.

---

## 2026-11-05

### Overview

Executed automated infrastructure and cluster provisioning drills across OpenTofu, Ansible, and k3s. Refactored OpenTofu virtual machine declarations into declarative loops with dual-key SSH access, reorganized LXC utility containers on `pve-01`, and automated Kubernetes worker role labeling from the control plane. Resolved template machine-ID DHCP lease collisions, Kubernetes admission controller self-labeling constraints, and Cilium Helm schema typecast errors.

### Target Scope

* **Virtual Machines:** `k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`
* **Containers (LXC):** `ansible`, `tailscale`, `nginx`, `pihole`
* **Provisioning & Automation:** `infra/`, `ansible/`, `bootstrap/`

### Key Changes

* Refactored OpenTofu VM definitions into declarative `for_each` loops with dual SSH key pairs (`admin_ssh_public_key` and `ansible_ssh_public_key`).
* Reorganized LXC utility container addressing, placing `ansible`, `tailscale`, `nginx`, and `pihole` on `pve-01`.
* Automated worker node role classification (`telemetry`, `app`) directly from the control plane via Ansible Play 3 using `kubectl label node`.
* Added `/dev/net/tun` cgroup passthrough rules to `tailscale` LXC configuration on `pve-01`.
* Standardized Cilium CNI deployment to target `workload=telemetry` for Hubble components.

### Incidents & Root Cause Analysis

#### 1. Cloud-Init Golden Image Machine-ID Collision (Virtualization Layer)

* **Symptom:** Cloned Kubernetes virtual machines (`k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`) received the identical dynamic DHCP IP lease from the local router.
* **Root Cause:** Systemd-networkd generates DHCP client identifiers (DUID) directly from `/etc/machine-id`. Because golden template 9000 was created without truncating `/etc/machine-id`, all cloned VMs sent the identical DUID in their DHCP solicitations.
* **Resolution:** Truncated `/etc/machine-id` using `virt-customize -a noble-server-cloudimg-amd64.img --install qemu-guest-agent --truncate /etc/machine-id` during the golden template creation workflow, and regenerated unique IDs on active VMs via `systemd-machine-id-setup`.

#### 2. Kubernetes NodeRestriction Admission Plugin Enforcement (Cluster Security Layer)

* **Symptom:** Worker nodes joined the cluster with `<none>` roles, ignoring self-assigned `--node-labels node-role.kubernetes.io/<role>=true` flags passed to the k3s agent join script.
* **Root Cause:** The Kubernetes `NodeRestriction` admission controller strictly prohibits kubelets from self-assigning or modifying labels within the `node-role.kubernetes.io/` namespace during join.
* **Resolution:** Removed `--node-role` and label flags from `bootstrap/02-k3s-agent.sh` (preserving it as a pure join mechanism), and added Play 3 to `ansible/playbooks/04-bootstrap-cluster.yml` to apply node roles directly from `k8s-cp-01` via `kubectl label node`.

#### 3. Cilium Helm / Kubernetes API Schema Typecast Collision (Platform/CNI Layer)

* **Symptom:** `cilium install` failed during rollout with `Deployment in version "v1" cannot be handled as a Deployment: json: cannot unmarshal bool into Go struct field PodSpec.spec.template.spec.nodeSelector of type string`.
* **Root Cause:** Passing `--set "hubble.relay.nodeSelector.node-role\.kubernetes\.io/telemetry=true"` caused Helm to type-cast `true` into a YAML boolean instead of a string, violating the Kubernetes API schema for `PodSpec.nodeSelector` (`map[string]string`).
* **Resolution:** Refactored the selector in `bootstrap/03-cni-cilium.sh` to `workload=telemetry`, providing a string value that bypasses Helm boolean type coercion and aligns with the cluster workload profile convention.

### Verification

??? note "Cluster Nodes & Role Verification (`kubectl get nodes`)"
    ```text
    NAME               STATUS   ROLES           AGE   VERSION
    k8s-app-01         Ready    app             60m   v1.37.2+k3s1
    k8s-cp-01          Ready    control-plane   60m   v1.37.2+k3s1
    k8s-telemetry-01   Ready    telemetry       60m   v1.37.2+k3s1
    ```

??? note "Core Platform Services Pods Status (`kubectl get pods -A`)"
    ```text
    NAMESPACE     NAME                                                    READY   STATUS    RESTARTS   AGE
    argocd        argocd-application-controller-0                         1/1     Running   0          8m
    argocd        argocd-applicationset-controller-b764968bf-jlgtx        1/1     Running   0          8m
    argocd        argocd-dex-server-5d7f54495d-jxsdn                      1/1     Running   0          2m
    argocd        argocd-notifications-controller-79766d8cbf-4xxhg        1/1     Running   0          8m
    argocd        argocd-redis-9bfb7b976-xjs8n                            1/1     Running   0          8m
    argocd        argocd-repo-server-555f8b597f-6kc64                     1/1     Running   0          8m
    argocd        argocd-server-76c54c4c57-wgsrb                          1/1     Running   0          8m
    chaos-mesh    chaos-controller-manager-54cb7bfdbc-4qffx               1/1     Running   0          7m
    chaos-mesh    chaos-daemon-htpgj                                      1/1     Running   0          7m
    chaos-mesh    chaos-dashboard-75747bb9d6-w5x59                        1/1     Running   0          7m
    kube-system   cilium-72m5c                                            1/1     Running   0          11m
    kube-system   cilium-operator-6698c97cf4-wxh7l                        1/1     Running   0          11m
    ```

---

## 2026-11-03

### Overview

Deployed Wave 0 (Infrastructure) GitOps tier via ArgoCD, establishing baseline security, certificate management, and kernel runtime observability across the cluster using cert-manager, Kyverno, and Falco. Hardened GitOps CI pipelines with automated Kustomize compilation and Kubeconform schema validation. Resolved kernel eBPF driver initialization, container runtime socket routing, and Kyverno policy admission exemptions for Falco. Established local workstation cluster administration via an isolated remote kubeconfig, eliminating SSH copy-paste toil.

### Target Scope

* **Cluster Workloads (Wave 0):** `cert-manager` (v1.21.3), `kyverno` (v1.19.2), `falco` (v0.45.2)
* **GitOps & Bootstrapping:** `gitops/bootstrap/00-infrastructure.yaml`, `gitops/infrastructure/`
* **Continuous Integration:** `.github/workflows/ci.yaml`
* **Workstation Tooling:** `~/.kube/homelab.yaml`, `z-local/03-DNS-RESOLUTION.md`, `z-local/04-NGINX-TLS-DASHBOARDS.md`

### Key Changes

* Provisioned `cert-manager` v1.21.3 with a local three-stage PKI hierarchy (`selfsigned-issuer`, `homelab-root-ca`, and `homelab-ca-issuer`) pinned to `k8s-telemetry-01` via RFC 6902 JSON patches.
* Deployed `kyverno` v1.19.2 with a baseline `disallow-privileged-containers` ClusterPolicy pinned to `k8s-telemetry-01` via RFC 6902 JSON patches.
* Deployed `falco` v0.45.2 DaemonSet across all nodes using the modern eBPF driver (`engine.kind: modern_ebpf`), host kernel BTF mounts, and K3s containerd socket paths.
* Enhanced `.github/workflows/ci.yaml` with a dedicated `validate-gitops` job, implementing Tier 2 (Kustomize compilation) and Tier 3 (Kubeconform OpenAPI schema validation) gates for all GitOps pull requests.
* Enabled `SkipDryRunOnMissingResource=true` in `gitops/bootstrap/00-infrastructure.yaml` to unblock ArgoCD pre-flight dry-run evaluation on dynamically introduced CRDs.
* Exported K3s cluster credentials to `~/.kube/homelab.yaml` with the `k-home` alias, enabling the local workstation to communicate directly with the remote Kubernetes API server.

### Incidents & Root Cause Analysis

#### 1. Falco Modern eBPF & Image Plugin Architecture

* **Symptom:** Falco DaemonSet crashed repeatedly on startup with `Error: Option 'cri' does not exist`, followed by `Plugin requirement not satisfied, must load one of: container (>= 0.4.0)`.
* **Root Cause:** Falco removed legacy `--cri` command-line flags in v0.39 and transitioned container metadata enrichment to modular plugins (`libcontainer.so`) in v0.41. Mounting a custom ConfigMap directly over `/etc/falco/falco.yaml` wiped out the base image's plugin declarations and rule files. Furthermore, manually redefining the plugin in a drop-in conflicted with the image's pre-existing `/etc/falco/config.d/falco.container_plugin.yaml`.
* **Resolution:** Preserved the upstream image's default `/etc/falco/falco.yaml` and modular configurations intact. Created a minimal drop-in at `/etc/falco/config.d/homelab.yaml` declaring only `engine.kind: modern_ebpf`. Mounted the host K3s socket (`/run/k3s/containerd/containerd.sock`) to the container's standard path (`/run/containerd/containerd.sock`), enabling Falco's native container plugin to connect automatically.

#### 2. Kyverno Privileged Container Admission Policy Exemption

* **Symptom:** ArgoCD surfaced policy violation alerts on the Falco DaemonSet: `rule privileged-containers failed at path /spec/containers/0/securityContext/privileged/`.
* **Root Cause:** The `disallow-privileged-containers` ClusterPolicy excluded system namespaces (`kube-system`, `argocd`, `cilium`, `infrastructure`), but omitted `falco`. Because Falco requires `securityContext.privileged: true` to attach eBPF probes to kernel tracepoints, Kyverno flagged the daemon.
* **Resolution:** Added `- falco` to `exclude.any.resources.namespaces` in `gitops/infrastructure/kyverno/cluster-policies.yaml`, allowing Falco to run with necessary kernel tracing capabilities.

#### 3. ArgoCD CRD Pre-Flight Dry Run Blocker

* **Symptom:** ArgoCD sync failed with `Resource not found in cluster: cert-manager.io/v1/Certificate:homelab-root-ca` and `kyverno.io/v1/ClusterPolicy:disallow-privileged-containers`.
* **Root Cause:** ArgoCD runs a dry-run schema validation against the Kubernetes API server before applying manifests. Because the CRDs and Custom Resources were deployed within the same application, the API server had not registered the schemas when the pre-flight check executed.
* **Resolution:** Added `SkipDryRunOnMissingResource=true` to `syncOptions` in `gitops/bootstrap/00-infrastructure.yaml`, instructing ArgoCD to bypass dry-run checks for Custom Resources whose CRDs are installed during the sync.

#### 4. Workflow Friction: Remote Cluster Administration via Workstation Kubeconfig

* **Symptom:** Debugging cluster workloads required a slow, multi-minute feedback loop (edit locally, push to git, open PR, merge, wait for ArgoCD poll, SSH to control plane VM, inspect logs).
* **Root Cause:** The local development environment was not configured with a remote kubeconfig, treating the cluster as an isolated black box reachable only through SSH or GitOps commits.
* **Resolution:** Copied `/etc/rancher/k3s/k3s.yaml` from `k8s-cp-01` (`<CONTROL_PLANE_IP>`) to an isolated local file `~/.kube/homelab.yaml` and mapped it to a `k-home` shell alias, enabling the local workstation to communicate directly with the remote Kubernetes API server.

### Verification

??? note "Wave 0 Infrastructure Workloads State (`cert-manager`, `falco`, `kyverno`)"
    ```text
    NAMESPACE      NAME                                                READY   STATUS    RESTARTS   AGE
    cert-manager   cert-manager-6857c5fb9b-c782x                       1/1     Running   0          155m
    cert-manager   cert-manager-cainjector-5548dd9c6c-jxkl6            1/1     Running   0          155m
    cert-manager   cert-manager-webhook-db4b6c44b-x4tfh                1/1     Running   0          155m
    falco          falco-d6w6g                                         1/1     Running   0          2m15s
    falco          falco-mrdtz                                         1/1     Running   0          2m15s
    falco          falco-n2wz7                                         1/1     Running   0          2m15s
    kyverno        kyverno-admission-controller-7648cb8849-jf4vz       1/1     Running   0          155m
    kyverno        kyverno-background-controller-5468bb579-xbjhk       1/1     Running   0          155m
    kyverno        kyverno-cleanup-controller-7596c46688-7fkpq         1/1     Running   0          155m
    kyverno        kyverno-reports-controller-57c7bc78dc-7mfxv         1/1     Running   0          155m
    ```

??? note "Falco Modern eBPF Engine Initialization Logs"
    ```text
    Loading rules from:
       /etc/falco/falco_rules.yaml | schema validation: ok
    Enabled event sources: syscall
    Opening 'syscall' source with modern BPF probe.
    One ring buffer every '2' CPUs.
    Starting health webserver with threadiness 2, listening on 0.0.0.0:8765
    ```

---

## 2026-11-02

### Overview

Automated standalone Layer 2 network utility containers (Pi-hole DNS sinkhole and Nginx reverse proxy gateway) using Ansible, enabling internal hostname resolution for homelab services and Kubernetes NodePorts. Hardened Ansible playbooks against upcoming fact deprecations, added Ansible dependency collections to CI, extended OpenTofu with IP output queries, and formalized platform architecture across ADR 004 and ADR 005.

### Target Scope

* **Containers (LXC):** `pihole` on `pve-02`, `nginx` on `pve-01`
* **Automation:** `ansible/playbooks/setup-pihole.yml`, `ansible/playbooks/setup-nginx.yml`, `ansible/playbooks/setup-vms.yml`, `ansible/requirements.yml`, `.github/workflows/ci.yaml`
* **Architecture & Documentation:** `docs/adr/004-three-tier-platform-lifecycle.md`, `docs/adr/005-external-reverse-proxy-gateway.md`, `docs/provisioning.md`, `infra/99-outputs.tf`

### Key Changes

* Automated unattended Pi-hole DNS sinkhole provisioning and wildcard resolution (`*.homelab.local`) to the Nginx gateway via `ansible/playbooks/setup-pihole.yml`.
* Automated Nginx reverse proxy virtual host routing for ArgoCD (`argocd.homelab.local`), Hubble UI (`hubble.homelab.local`), and Pi-hole admin console (`pihole.homelab.local`).
* Migrated playbook variable syntax to `ansible_facts['<fact>']` across all playbooks, eliminating `INJECT_FACTS_AS_VARS` deprecation warnings.
* Added `ansible/requirements.yml` declaring `community.general` and `ansible.posix`, and updated `.github/workflows/ci.yaml` to install requirements before running syntax validation.
* Added `infra/99-outputs.tf` to expose container and VM static IP assignments directly from OpenTofu without requiring in-guest QEMU agent polling.
* Adopted ADR 004 (Three-Tier Platform Lifecycle: OpenTofu, Ansible, ArgoCD) and ADR 005 (External Reverse Proxy Gateway).

### Incidents & Root Cause Analysis

#### 1. Pi-hole v6 FTL Configuration Decoupling

* **Symptom:** Wildcard DNS queries for `*.homelab.local` failed with `NXDOMAIN` despite placing configuration in `/etc/dnsmasq.d/02-homelab.conf`.
* **Root Cause:** Pi-hole v6 migrated its core configuration engine to `/etc/pihole/pihole.toml` and disables reading `/etc/dnsmasq.d/` by default.
* **Resolution:** Configured `pihole-FTL --config misc.etc_dnsmasq_d true` in `setup-pihole.yml` prior to restarting `pihole-FTL.service`.

#### 2. Linux RFC 6762 mDNS Multicast Trap for `.local` Domains

* **Symptom:** Client workstation failed to resolve `argocd.homelab.local` via Pi-hole (`Server failure`), while public internet domain queries resolved normally.
* **Root Cause:** RFC 6762 designates `.local` exclusively for link-local multicast DNS (mDNS). `systemd-resolved` intercepted `.local` queries and broadcasted on mDNS `224.0.0.251:5353` instead of forwarding unicast DNS requests to the upstream Pi-hole server.
* **Resolution:** Configured an explicit routing domain (`~homelab.local`) on the client network interface to force unicast forwarding to the homelab DNS server.

---

## 2026-10-27

### Overview

Bootstrapped the Layer 3 Kubernetes platform across three virtual machines (`k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`) using k3s and Cilium eBPF CNI in VXLAN overlay mode. Refactored the bootstrap automation suite to enforce clear separation of concerns with Ansible OS baselines, resolved host networking lockout and API server connectivity issues caused by Cilium IPAM and eBPF bypass, and bypassed Kubernetes NodeRestriction admission rejections during worker onboarding.

### Target Scope

* **Virtual Machines:** `k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`
* **Automation & Scripts:** `bootstrap/00-preflight.sh`, `bootstrap/01-k3s-server.sh`, `bootstrap/02-k3s-agent.sh`, `bootstrap/03-cni-cilium.sh`, `Makefile`
* **Documentation:** `docs/provisioning.md`, `docs/adr/003-cilium-ebpf-in-vxlan-overlay-mode.md`, `bootstrap/README.md`

### Key Changes

* Removed redundant `bootstrap/01-prerequisites.sh` to enforce exclusive OS baseline management via Ansible (`playbooks/setup-vms.yml`).
* Added Section 5 (Ansible OS Baseline Verification) to `bootstrap/00-preflight.sh` to validate timezone, swap disablement, kernel modules (`overlay`, `br_netfilter`), and sysctl IP forwarding prior to Kubernetes installation.
* Configured dedicated Pod CIDR `10.244.0.0/16` and mask size 24 via Cilium Helm values (`ipam.operator.clusterPoolIPv4PodCIDRList` and `ipv4NativeRoutingCIDR`), completely preventing collisions with the physical `10.0.0.0/24` host network.
* Enabled `bpf.hostLegacyRouting=true` in Cilium deployment parameters to safeguard host SSH and ICMP management traffic on virtualized KVM interfaces.
* Dynamically resolved the node primary IP (`<CONTROL_PLANE_IP>`) for Cilium `k8sServiceHost` to maintain reliable in-pod API server connectivity for metrics-server and core addons.

### Incidents & Root Cause Analysis

#### 1. Cilium IPAM Host Subnet Collision and SSH Lockout (`k8s-cp-01`)

* **Symptom:** Host `k8s-cp-01` lost SSH connectivity and stopped responding to ICMP ping from the local network following Cilium installation.
* **Root Cause:** Without an explicit cluster pool CIDR, Cilium defaulted to `10.0.0.0/8`, which subsumed the home physical subnet (`10.0.0.0/24`). Cilium assigned an IP within the home subnet to `cilium_host` and routed all `10.0.0.0/24` traffic into the `cilium_host` interface, blackholing inbound and outbound host traffic. Furthermore, eBPF host routing bypassed the Linux kernel routing stack on `eth0`.
* **Resolution:** Accessed `k8s-cp-01` out-of-band via Proxmox VNC console, deleted the conflicting `10.0.0.0/24` route on `cilium_host`, and fully uninstalled Cilium. Purged all lingering Cilium CRDs, `/etc/cni/net.d/05-cilium.conflist`, `/var/run/cilium` cgroup mounts, and `/sys/fs/bpf/cilium` maps. Updated `bootstrap/03-cni-cilium.sh` to explicitly define `POD_CIDR="10.244.0.0/16"` and set `bpf.hostLegacyRouting=true`.

#### 2. Worker Node Join Crash on Kubernetes NodeRestriction Admission (`k8s-telemetry-01`)

* **Symptom:** `k3s-agent.service` failed to start on `k8s-telemetry-01` with `Error: failed to validate kubelet flags: unknown 'kubernetes.io' or 'k8s.io' labels specified with --node-labels: [node-role.kubernetes.io/telemetry]`.
* **Root Cause:** The Kubernetes `NodeRestriction` admission controller prohibits worker kubelet agents from self-assigning labels in the reserved `node-role.kubernetes.io/*` namespace for cluster security isolation.
* **Resolution:** Updated `bootstrap/02-k3s-agent.sh` to only configure the custom `workload=<role>` label in agent `/etc/rancher/k3s/config.yaml`. Applied formal role labels (`node-role.kubernetes.io/<role>=true`) from the control plane using `kubectl label node`.

### Verification

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

---

## 2026-10-26

### Overview

Established strict separation of concerns across the platform hierarchy (OpenTofu IaaS -> Ansible OS Configuration -> ArgoCD GitOps). Resolved OpenTofu HTTP connection pool starvation caused by in-guest agent polling, protected imported utility containers from accidental recreation via lifecycle ignore rules, and restructured architectural diagrams into discrete visual models with a unified Slate design system.

### Target Scope

* **Virtual Machines:** `k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`
* **Containers (LXC):** `pihole`, `tailscale`, `nginx`, `ansible`
* **Automation & Docs:** `infra/`, `ansible/`, `scripts/generate_diagram.py`, `docs/assets/`

### Key Changes

* Removed in-guest `agent` polling blocks from all VM definitions in `infra/02-vms.tf` to eliminate API timeout deadlocks.
* Configured `lifecycle { ignore_changes = [operating_system[0].template_file_id, unprivileged] }` in `infra/03-containers.tf` to safeguard pre-existing imported containers.
* Standardized VM and container tags to a strict two-tag taxonomy (`k8s`, `dns`, `vpn`, `proxy`, `automation`, `utility`).
* Added `container_template_file_id` variable defaulting to `local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst`.
* Refactored `scripts/generate_diagram.py` to generate diagrams using a unified Slate design token system.

### Incidents & Root Cause Analysis

#### 1. OpenTofu API Timeouts on Container Status (`context deadline exceeded`)

* **Symptom:** OpenTofu returned: `error retrieving container status: failed to perform HTTP GET request (path: nodes/pve-01/lxc/301/status/current) - Reason: context deadline exceeded`.
* **Root Cause:** Virtual machine configurations included `agent { enabled = true }` with a 15-minute polling timeout. Because freshly cloned VMs do not have active guest agents running prior to OS configuration, OpenTofu held HTTP connections open, starving the Proxmox API connection pool.
* **Resolution:** Removed the `agent` block entirely from VM configurations in `infra/02-vms.tf`. Established the operational rule that OpenTofu handles hypervisor-level provisioning exclusively, while in-guest agent activation is delegated to Ansible.

#### 2. OpenTofu Plan Drift Flagging Imported Containers for Destruction

* **Symptom:** `tofu plan` attempted to destroy and recreate `pihole` and `tailscale` due to missing template file IDs and unprivileged flag mismatches in state.
* **Root Cause:** Imported containers were originally created manually without template metadata, causing OpenTofu to detect a diff against required configuration parameters.
* **Resolution:** Added `lifecycle { ignore_changes = [operating_system[0].template_file_id, unprivileged] }` in `infra/03-containers.tf`, ensuring in-place management without destructive recreation.

---

## 2026-10-25

### Overview

Initialized the physical dual-node Proxmox VE cluster (`k8s-homelab`) with an external Raspberry Pi Corosync QDevice tiebreaker, achieving an odd 3-vote quorum. Configured Stratum 2 Chrony NTP on `rpi-01`, aligned existing utility containers, and automated VM and LXC deployment using OpenTofu.

### Target Scope

* **Physical Hosts:** `pve-01` (Mini PC), `pve-02` (Laptop), `rpi-01` (Raspberry Pi 3B)
* **Virtual Machines:** `k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`, Ubuntu 24.04 Template
* **Containers (LXC):** `pihole` on `pve-02`, `tailscale` on `pve-01`, `nginx` on `pve-01`, `ansible` on `pve-01`

### Key Changes

* Formed the Proxmox cluster `k8s-homelab` on `pve-01` and joined `pve-02`.
* Preserved existing container configs across the `pmxcfs` join and migrated `tailscale` from `pve-02` to `pve-01`.
* Installed `corosync-qnetd` on `rpi-01` and attached it as the external cluster QDevice via `pvecm qdevice setup`.
* Configured Chrony NTP on `rpi-01` as the local network time server and synchronized `pve-01` and `pve-02`.
* Migrated Ubuntu 24.04 Cloud-Init template to `pve-01` local storage.
* Downloaded Debian 13 standard amd64 LXC template on `pve-01`.
* Configured OpenTofu manifests (`infra/`) to provision Kubernetes VMs and manage LXC utility containers.

### Incidents & Root Cause Analysis

#### 1. Proxmox Join Blocked Due to Pre-existing Containers

* **Symptom:** `pvecm add` failed with error: `this host already contains virtual guests`.
* **Root Cause:** Joining a cluster mounts the shared `pmxcfs` cluster filesystem over `/etc/pve`, which would hide local guest configurations if not preserved.
* **Resolution:** Backed up `/etc/pve/local/lxc` to `/root/pve-lxc-backup`, executed `pvecm add <PVE_01_IP> --force`, and restored `.conf` files into `/etc/pve/nodes/pve-02/lxc/`.

#### 2. Proxmox API HTTP 403 Forbidden on VM Clone

* **Symptom:** OpenTofu returned: `error cloning VM: received an HTTP 403 response - Reason: Permission check failed (/vms/9000, VM.Clone)`.
* **Root Cause:** Proxmox Web GUI checks **Privilege Separation** by default when creating API tokens, stripping administrative permissions from `root@pam!tofu`.
* **Resolution:** Recreated the token with **Privilege Separation unchecked**, restoring inherited root permissions.

#### 3. OpenTofu Failed to Locate Template 9000 on `pve-02`

* **Symptom:** OpenTofu returned: `HTTP 500 - unable to find configuration file for VM 9000 on node 'pve-02'`.
* **Root Cause:** Template 9000 resides on `pve-01`. When provisioning `k8s-app-01` on `pve-02`, OpenTofu defaulted to searching for the template on the target node.
* **Resolution:** Added `node_name = "pve-01"` explicitly inside the `clone` block in `infra/02-vms.tf`.

#### 4. QDevice Marked as `NR` for `pve-02`

* **Symptom:** `pvecm nodes` displayed `NR` under the Qdevice column for `pve-02`, causing OpenTofu plan timeouts.
* **Root Cause:** `NR` signifies "Not Registered" with the remote `corosync-qnetd` daemon. After simulated failover testing, `corosync-qdevice.service` was stopped on `pve-02`.
* **Resolution:** Executed `systemctl restart corosync-qdevice` on `pve-02`, successfully reconnecting to port 5403 on `rpi-01`.

### Verification

??? note "Cluster Quorum & QDevice Status (`pvecm status`)"
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

??? note "Authoritative Time Synchronization (`chronyc sources -v`)"
    ```text
    MS Name/IP address         Stratum Poll Reach LastRx Last sample
    ===============================================================================
    ^- time.cloudflare.com           3   6    17     7   +462us[ +462us] +/-   24ms
    ^* time4.google.com              1   6    17     7   +142us[ +676us] +/-   10ms
    ^- archer.fsck.ca                2   6    17     6   -572us[ -572us] +/-   36ms
    ```
