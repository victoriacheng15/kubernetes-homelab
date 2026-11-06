# The Platform Journey: From Manual Clicks to Codified Architecture

A retrospective narrative on environmental constraints, operational toil, and evolutionary platform design.

---

## The Evolution at a Glance

```text
  ┌────────────────────────────────────────────────────────┐
  │                 Proxmox VE Web GUI                     │
  │     Initial manual discovery and hardware learning     │
  └──────────────────────────┬─────────────────────────────┘
                             │
                             ▼  Friction: Repeating the creation wizard 10 times for 10 VMs
  ┌────────────────────────────────────────────────────────┐
  │                 Layer 1: OpenTofu                      │
  │     Declarative virtual hardware and container state   │
  └──────────────────────────┬─────────────────────────────┘
                             │
                             ▼  Friction: SSHing into 5+ nodes to patch & tune OS
  ┌────────────────────────────────────────────────────────┐
  │                 Layer 2: Ansible                       │
  │     Idempotent OS baselines and standalone utilities   │
  └──────────────────────────┬─────────────────────────────┘
                             │
                             ▼  Friction: Manual manifest delivery & drift
  ┌────────────────────────────────────────────────────────┐
  │                 Layer 3: ArgoCD                        │
  │     Declarative in-cluster GitOps workload delivery    │
  └──────────────────────────┬─────────────────────────────┘
                             │
                             ▼  Reflection: Locking in separation of concerns
  ┌────────────────────────────────────────────────────────┐
  │                 ADR Codification                       │
  │     Formalized architectural boundaries (ADR 001-005)  │
  └──────────────────────────┬─────────────────────────────┘
                             │
                             ▼  Mastery: Zero-touch disaster recovery
  ┌────────────────────────────────────────────────────────┐
  │              Act 6: The Phoenix Rebuild                │
  │     Zero-touch orchestration via site.yml (ADR 006)    │
  └────────────────────────────────────────────────────────┘
```

---

## Act 1: The Bare Metal Reality

Every homelab begins with hardware constraints. Instead of an enterprise datacenter with uniform rack-mount servers, this cluster was assembled from available physical machines:

* **`pve-01` (Mini PC):** The primary computing workhorse.
* **`pve-02` (Laptop):** An energy-efficient secondary node with built-in battery backup.
* **`rpi-01` (Raspberry Pi 3B):** A low-power single-board computer acting as the quorum tiebreaker ([ADR 001](adr/001-two-node-cluster-topology.md)).

Logging into Proxmox VE for the first time provided an intuitive graphical playground. Clicking through the Web UI made it easy to inspect local storage pools, create Linux network bridges (`vmbr0`), and boot an initial Ubuntu cloud image.

However, the graphical interface soon revealed its fundamental operational ceiling.

---

## Act 2: The First Wall of Toil (Why OpenTofu?)

!!! quote "The Realization"
    Clicking through the VM creation wizard once was fine to learn how KVM parameters work.
    Thinking about having to repeat that entire wizard 10 times to build 10 VMs was the moment manual work became unsustainable.

Manually clicking through the Proxmox GUI introduced immediate operational friction:

* **Inconsistent Configuration:** Forgetting to toggle a disk cache setting or misallocating memory between hosts.
* **Rebuild Friction:** If a node crashed or needed a fresh hypervisor reinstall, recreating the virtual machines required another hour of repetitive manual clicking.

This friction justified introducing **Layer 1: OpenTofu**.

By declaring the cluster infrastructure in OpenTofu manifests, virtual machines and utility containers became reproducible with a single command:

```bash
tofu apply
```

---

## Act 3: The Second Wall of Toil (Why Ansible?)

Provisioning virtual hardware solved the creation problem, but exposed the host configuration problem.

Once the virtual machines booted, they were bare operating system shells. Preparing them for Kubernetes required:

* Disabling Linux swap permanently.
* Loading required kernel modules (`overlay`, `br_netfilter`).
* Tuning `sysctl` networking parameters (`net.ipv4.ip_forward = 1`).
* Installing container runtimes (`containerd`) and Kubernetes packages.

Logging into multiple separate machines over SSH and manually pasting terminal commands was tedious and error-prone. One forgotten `sysctl` command on a single worker node could silently break pod-to-pod networking days later.

This justified introducing **Layer 2: Ansible**.

Through centralized inventories and idempotent playbooks (`ansible/playbooks/setup-vms.yml`), node preparation was condensed into an automated, version-controlled operation.

---

## Act 4: The Ingress Mystery (Standalone Gateway and DNS)

With the cluster operational, accessing web services (ArgoCD, Hubble UI, and monitoring dashboards) required memorizing internal IP addresses and high NodePort numbers (`:30443`, `:31235`).

The typical Kubernetes solution is an in-cluster Ingress Controller coupled with MetalLB. However, the homelab presented distinct challenges:

* **Resource Preservation:** Running ingress pods and daemonsets consumes memory on a dual-node cluster that is better reserved for core workloads.
* **The Out-of-Cluster Dilemma:** Independent services (such as the Pi-hole DNS sinkhole and Proxmox management interfaces) exist outside Kubernetes. If the cluster restarts or undergoes maintenance, an in-cluster ingress controller goes down with it.

The solution was deploying an external, lightweight Nginx reverse proxy and Pi-hole as standalone LXC containers.

### Field Note: The Two Protocol Traps

Building the gateway uncovered two real-world operational challenges:

* **Pi-hole v6 FTL Decoupling:** Pi-hole v6 migrated from `/etc/dnsmasq.d/` flat files to `/etc/pihole/pihole.toml`. It silently ignored wildcard configurations until `misc.etc_dnsmasq_d = true` was explicitly enabled in Ansible.
* **Linux RFC 6762 mDNS Trap:** Client workstations failed to query `*.homelab.local` because Linux `systemd-resolved` routes `.local` queries via multicast mDNS by default. Configuring an explicit routing domain (`~homelab.local`) forced unicast resolution to the homelab DNS server.

---

## Act 5: Locking Down Boundaries (The ADRs)

After eliminating the manual toil and stabilizing the network, the final step was architectural reflection: locking in the boundaries so tools would not bleed into each other over time.

This resulted in formal Architectural Decision Records:

* **[ADR 001](adr/001-two-node-cluster-topology.md):** Asymmetric two-node cluster topology with external Raspberry Pi tiebreaker.
* **[ADR 002](adr/002-local-storage-with-retain-policy.md):** Local disk mapping with strict retention policy.
* **[ADR 003](adr/003-cilium-ebpf-in-vxlan-overlay-mode.md):** Cilium eBPF in VXLAN overlay mode.
* **[ADR 004](adr/004-three-tier-platform-lifecycle.md):** Three-tier platform lifecycle (OpenTofu, Ansible, ArgoCD).
* **[ADR 005](adr/005-external-reverse-proxy-gateway.md):** External reverse proxy gateway.

---

## Act 6: The Phoenix Rebuild

With individual components automated, the final friction point emerged: the handoff between layers. Rebuilding the platform from scratch still required a manual relay across multiple terminal tabs to copy join tokens and execute bootstrap scripts sequentially.

This prompted [ADR 006](adr/006-orchestrated-cluster-bootstrap-via-ansible-scripts.md) and the final operational refinements:

* **Master Orchestration (`site.yml`):** Chaining VM baselines, cluster bootstrapping, Cilium CNI, and ArgoCD in strict sequence, passing join tokens in Ansible memory without manual intervention.
* **Golden Image Baking:** Using `virt-customize` on the cloud-init template to pre-bake `qemu-guest-agent` and truncate `/etc/machine-id`, eliminating API timeouts and duplicate DHCP leases.
