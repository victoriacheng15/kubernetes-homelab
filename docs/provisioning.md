# Platform Provisioning

## Overview

This guide covers the three sequential provisioning layers that build the homelab platform from bare-metal hardware to declarative workload delivery:

![Platform Architecture Layers](assets/platform-layers.png)

- **Layer 1: Infrastructure Provisioning:** Uses OpenTofu and Proxmox VE to configure physical hypervisor clustering, odd 3-vote quorum tiebreaking, authoritative local time synchronization via Chrony, base OS templates, and automated VM and LXC creation.
- **Layer 2: Node OS Baseline Provisioning:** Uses Ansible from the dedicated controller container (`CT 303`) to tune kernel modules, swap, sysctl networking parameters, and core utilities across all virtual machines.
- **Layer 3: Declarative GitOps & Cluster Provisioning:** Uses k3s and ArgoCD to bootstrap the lightweight Kubernetes control plane, deploy the Cilium eBPF network fabric, and initialize the App-of-Apps continuous delivery engine.

---

## Layer 1: Infrastructure Provisioning

### Cluster & Quorum Setup

Physical hosts must be joined into a cluster with an external QDevice tiebreaker to maintain an odd 3-vote quorum:

- **Initialize Cluster on Primary Node (`pve-01`):**

  ```bash
  pvecm create k8s-homelab
  ```

- **Join Secondary Node (`pve-02`):**

  ```bash
  pvecm add <PRIMARY_NODE_IP>
  ```

- **Install QNetd on Raspberry Pi (`rpi-01`):**

  ```bash
  sudo apt update && sudo apt install -y corosync-qnetd
  ```

- **Install QDevice on Proxmox Hosts (`pve-01`, `pve-02`):**

  ```bash
  apt update && apt install -y corosync-qdevice
  ```

- **Attach QDevice & Verify Quorum from Primary Node (`pve-01`):**

  ```bash
  pvecm qdevice setup <QDEVICE_IP>
  pvecm status
  ```

??? note "Screenshot: Proxmox Cluster & QDevice Quorum"
    ![Proxmox Cluster Quorum Status](assets/screenshots/proxmox-cluster-quorum.png)

### Time Synchronization

Distributed consensus engines (etcd in k3s and Corosync in Proxmox) require sub-second clock synchronization:

- **Configure Local Chrony NTP Server on Raspberry Pi (`rpi-01`):**

  ```bash
  sudo timedatectl set-timezone UTC
  sudo apt update && sudo apt install -y chrony
  echo -e "server time.cloudflare.com iburst\nallow 192.168.0.0/16\nallow 10.0.0.0/8" | sudo tee -a /etc/chrony/chrony.conf
  sudo systemctl restart chrony
  ```

- **Synchronize Proxmox Hosts (`pve-01`, `pve-02`) Against `rpi-01`:**

  ```bash
  echo "server <RPI_IP> iburst prefer" | sudo tee -a /etc/chrony/chrony.conf
  sudo systemctl restart chrony && chronyc sources -v
  ```

### Cloud-Init Template

Create the Ubuntu 24.04 Server template (VM 9000) on local hypervisor storage:

- **Download Ubuntu 24.04 Cloud Image:**

  ```bash
  wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
  ```

- **Create Template VM and Import Virtual Disk:**

  ```bash
  qm create 9000 --name "ubuntu-2404-server-template" --memory 2048 --cores 2 --cpu host --net0 virtio,bridge=vmbr0
  qm disk import 9000 noble-server-cloudimg-amd64.img local-lvm
  ```

- **Configure Cloud-Init Hardware & Convert to Template:**

  ```bash
  qm set 9000 --scsihw virtio-scsi-single --scsi0 local-lvm:vm-9000-disk-0,discard=on,ssd=1
  qm set 9000 --ide2 local-lvm:cloudinit --boot order=scsi0 --serial0 socket --vga serial0
  qm template 9000
  rm -f noble-server-cloudimg-amd64.img
  ```

### OpenTofu Deployment

Deploy virtual machines and utility containers:

- **Generate SSH Key Pairs for Fleet Access:**

  Create the administrator key for interactive SSH access:

  ```bash
  ssh-keygen -t ed25519 -C "k8s-homelab-admin"
  ```

  Create the dedicated automation key for the Ansible controller (`CT 303`):

  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/ansible -C "ansible"
  ```

- **Configure Environment Variables:**

  Generate a Proxmox API token (`root@pam!tofu`) with Privilege Separation unchecked under `Datacenter -> Permissions -> API Tokens`.
  Populate `infra/terraform.tfvars` from `infra/terraform.tfvars.example`, supplying your public keys (`~/.ssh/id_ed25519.pub` and `~/.ssh/ansible.pub`) alongside your host endpoints, credentials, and static network leases.

- **Provision Infrastructure Resources:**

  ```bash
  tofu -chdir=infra init
  tofu -chdir=infra plan
  tofu -chdir=infra apply
  ```

### Standalone Utility Containers

Alongside the Kubernetes virtual machines, OpenTofu provisions unprivileged Debian LXC utility containers:

| Container | ID | Host | IP Mode | Operational Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **`pihole`** | `CT 300` | `pve-02` | Static / DHCP | Local DNS sinkhole and wildcard domain resolver (`*.homelab.local`) |
| **`tailscale`** | `CT 301` | `pve-01` | DHCP | Encrypted mesh VPN subnet router gateway (`homelab_subnet`) |
| **`nginx`** | `CT 302` | `pve-01` | DHCP | Local reverse proxy and SSL gateway for cluster dashboards |
| **`ansible`** | `CT 303` | `pve-01` | DHCP | Dedicated automation controller node running playbooks across the fleet |

---

## Layer 2: Node OS Baseline & Utility Services Provisioning

Before bootstrapping Kubernetes, all VM nodes must have active swap disabled, kernel networking modules loaded, and sysctl packet forwarding rules applied. Additionally, foundational utility containers (Pi-hole DNS and Tailscale VPN) are provisioned.

This baseline tuning and utility automation is orchestrated using Ansible from the dedicated controller container (`CT 303` on `pve-01`):

- **Access the Controller Container (`pve-01`):**

  ```bash
  pct enter 303
  ```

- **Bootstrap Ansible Tooling:**

  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  source $HOME/.local/bin/env
  uv tool install ansible-core
  ```

- **Clone Repository & Install Collection Dependencies:**

  ```bash
  git clone https://github.com/victoriacheng15/kubernetes-homelab.git
  cd kubernetes-homelab/ansible
  ansible-galaxy collection install -r requirements.yml
  ```

- **Configure Inventory & Test Fleet Reachability:**

  ```bash
  cp inventory.example.ini inventory.ini
  ansible -i inventory.ini nodes -m ping
  ```

### VM Node Baseline Hardening (`01-setup-vms.yml`)

Execute the baseline playbook across all virtual machine nodes (`k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`):

```bash
ansible-playbook -i inventory.ini playbooks/01-setup-vms.yml
```

The baseline playbook enforces the following system configurations across all nodes:

- **Timezone:** Locks system clock to UTC.
- **Swap:** Disables active swap (`swapoff -a`) and permanently comments out swap mounts in `/etc/fstab`.
- **Kernel Modules:** Loads `overlay` and `br_netfilter`, persisting them in `/etc/modules-load.d/k8s.conf`.
- **Sysctl Parameters:** Enables IP packet forwarding (`net.ipv4.ip_forward = 1`) and bridge netfilter calls.
- **Core Packages:** Installs essential troubleshooting utilities (`curl`, `git`, `jq`, `tcpdump`, `socat`, `htop`, `tar`).

### Utility Containers Provisioning

Standalone Debian LXC utility containers are configured with auxiliary services:

- **Local Wildcard DNS Sinkhole (`02-setup-pihole.yml`):**

  ```bash
  ansible-playbook -i inventory.ini playbooks/02-setup-pihole.yml
  ```

  Verify Pi-hole status on `CT 300`:

  ```bash
  pihole status
  ```

- **Encrypted Mesh Subnet Router (`03-setup-tailscale.yml`):**

  ```bash
  ansible-playbook -i inventory.ini playbooks/03-setup-tailscale.yml
  ```

  Verify Tailscale status on `CT 301`:

  ```bash
  tailscale status
  ```

---

## Layer 3: Declarative GitOps & Cluster Provisioning

Once the physical hypervisors are clustered (Layer 1) and all virtual machine OS baselines and utility services are hardened (Layer 2), the final tier provisions the Kubernetes platform and declarative GitOps delivery engine.

By orchestrating the underlying bootstrap scripts inside numbered Ansible playbooks, cluster provisioning is repeatable, automated, and decoupled from manual execution on individual nodes.

### Preflight Hardware & Network Audit

Before initializing the cluster, execute `bootstrap/00-preflight.sh` as a standalone read-only sanity check. This audits target node IPs, CPU virtualization flags, kernel eBPF support, memory allocations, and open ports on target Kubernetes VMs (`k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`).

Execute from the controller container (`CT 303`) or your workstation over SSH (eliminating the need to clone the repository onto target VMs):

```bash
# From CT 303 or workstation against any target VM:
ssh ubuntu@<TARGET_NODE_IP> 'bash -s' < bootstrap/00-preflight.sh
```

Alternatively, if logged directly into a target node:

```bash
# Directly on target node (k8s-cp-01, k8s-telemetry-01, k8s-app-01):
./bootstrap/00-preflight.sh
```

### Cluster Nodes Bootstrap (`04-bootstrap-cluster.yml`)

The cluster nodes playbook orchestrates the initialization of the control plane and automated joining of worker nodes without manual token copying:

```bash
# From ansible/ directory:
ansible-playbook -i inventory.ini playbooks/04-bootstrap-cluster.yml
```

This playbook runs across two sequential plays:

- **Control Plane Initialization (`k8s-cp-01`):**
  - Executes `bootstrap/01-k3s-server.sh` via `ansible.builtin.script` with Flannel and Traefik disabled.
  - Captures the cluster join token from `/var/lib/rancher/k3s/server/node-token` and registers it in memory.

- **Worker Node Joining (`k8s-telemetry-01`, `k8s-app-01`):**
  - Executes `bootstrap/02-k3s-agent.sh` on worker targets, automatically injecting the join endpoint, token, and node workload roles (`workload=telemetry`, `workload=app`).
  - Labels node roles formally from the control plane in compliance with the Kubernetes NodeRestriction admission controller.

Verify node status from the control plane:

```bash
kubectl get nodes -o wide
```

### In-Cluster Platform & Network Services (`05-setup-cluster-services.yml`)

With nodes joined, deploy core networking, GitOps, and platform resilience tools to `k8s-cp-01`:

```bash
# From ansible/ directory:
ansible-playbook -i inventory.ini playbooks/05-setup-cluster-services.yml
```

This playbook injects `KUBECONFIG: /etc/rancher/k3s/k3s.yaml` and deploys three platform tiers:

- **Cilium eBPF CNI & Hubble Observability (`bootstrap/03-cni-cilium.sh`):**
  - Deploys Cilium in VXLAN overlay mode (`10.244.0.0/16` Pod CIDR).
  - Replaces `kube-proxy` with socket-based in-kernel load balancing.
  - Enables Hubble relay and Hubble UI (NodePort `31235`).
  - Includes status verification checks to skip installation safely if already operational.

- **ArgoCD GitOps Continuous Delivery Engine (`bootstrap/04-gitops-argocd.sh`):**
  - Installs upstream ArgoCD manifests into the `argocd` namespace.
  - Exposes `argocd-server` via NodePort (`HTTP 30080`, `HTTPS 30443`).
  - Waits for controller readiness rollouts.

- **Chaos Mesh Resilience Platform (`bootstrap/05-chaos-mesh.sh`):**
  - Configures the Chaos Mesh Helm repository.
  - Deploys Chaos Mesh pinned to `k8s-app-01` (`workload=app`) using the k3s containerd socket (`/run/k3s/containerd/containerd.sock`).
  - Exposes the Chaos Mesh dashboard via NodePort (`31333`).

Key parameters configured across cluster services:

| Parameter | Value | Purpose |
| :--- | :--- | :--- |
| **Pod CIDR** | `10.244.0.0/16` | Eliminates subnet collisions with the physical LAN |
| **Host Routing** | `bpf.hostLegacyRouting=true` | Protects host-level SSH and management traffic |
| **Kube-Proxy** | In-kernel eBPF | High-performance socket-based load balancing |
| **Hubble** | Relay & UI enabled | Real-time L3/L4/L7 flow observability |
| **ArgoCD Ingress** | NodePort `30080` / `30443` | Reverse proxy entrypoint for GitOps UI and API |
| **Chaos Mesh Ingress** | NodePort `31333` | Reverse proxy entrypoint for Chaos Dashboard |

??? note "Screenshot: Cluster Nodes & Cilium Datapath Status"
    ![Proxmox Console Cilium and Node Status](assets/screenshots/proxmox-pve-cilium-status.png)

### ArgoCD App-of-Apps Declarative Workload Reconciliation

Once ArgoCD is running, initialize declarative GitOps workload delivery:

- Retrieve the initial auto-generated administrator password:

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
  ```

- Apply the root orchestrator manifest:

  ```bash
  kubectl apply -f gitops/root-application.yaml
  ```

The root application automatically watches `gitops/bootstrap/` and reconciles workloads across dedicated node roles and phases:

| Application | Target Path | Target Node / Namespace | Operational Role |
| :--- | :--- | :--- | :--- |
| **`root-app`** | `gitops/bootstrap` | `argocd` | Watches Git for child application manifests |
| **`infrastructure`** | `gitops/infrastructure` | `local-path-storage` / `infrastructure` | Wave 0 foundational platform tier (StorageClass, Cert-Manager, Kyverno, Falco) |
| **`telemetry`** | `gitops/telemetry` | `k8s-telemetry-01` / `telemetry` | Wave 1 observability stack (Hubble, Prometheus, Grafana, OpenTelemetry) |
| **`apps`** | `gitops/apps` | `k8s-app-01` / `apps` | Wave 2 tenant applications (Podinfo, Juice Shop) |

Verify application reconciliation status using CLI:

```bash
kubectl get applications -n argocd
kubectl get pods -A
```

??? note "Screenshot: ArgoCD Dashboard & Application Tree"
      ![ArgoCD App-of-Apps Dashboard](assets/screenshots/argocd-app-of-apps.png)

### Ingress Gateway & Reverse Proxy Setup (`06-setup-nginx.yml`)

Deploy the Nginx gateway configuration to `CT 302` to establish reverse proxy routes for all platform dashboards:

```bash
# From ansible/ directory:
ansible-playbook -i inventory.ini playbooks/06-setup-nginx.yml
```

Verify Nginx status and virtual host routes on `CT 302`:

```bash
# On Nginx container (CT 302): verify service status and syntax
systemctl status nginx
nginx -t
ls -la /etc/nginx/conf.d/
```

Access all homelab dashboards in your browser via the managed reverse proxy routes:

| Subdomain | Target Service | Operational Purpose |
| :--- | :--- | :--- |
| `argocd.homelab.local` | `argocd-server:30443` | GitOps continuous delivery management dashboard |
| `hubble.homelab.local` | `hubble-ui:31235` | Real-time eBPF network flow map and traffic inspection |
| `pihole.homelab.local` | `pihole-FTL:80` | Network-wide DNS sinkhole and ad-blocking administration |
| `grafana.homelab.local` | `grafana:30300` | Cluster resource metrics and telemetry visualization |
| `podinfo.homelab.local` | `podinfo:30098` | Reference microservice interface and canary routing testbed |
| `juiceshop.homelab.local` | `juice-shop:30081` | Vulnerable web application generating attack traffic for Falco |
| `chaos.homelab.local` | `chaos-dashboard:31333` | Visual experiment designer for fault injection and stress tests |

---

## Master Pipeline Orchestration (`site.yml`)

For zero-touch full-fleet provisioning and disaster recovery drills ("The Phoenix Rebuild"), the entire platform from bare virtual machines to reverse proxy ingress can be executed sequentially using the master orchestrator playbook:

```bash
# From ansible/ directory:
ansible-playbook -i inventory.ini site.yml
```

This master orchestrator runs all six numbered playbooks in strict dependency order:

- `playbooks/01-setup-vms.yml`: Base OS hardening, swap disabling, kernel networking modules, and sysctl rules.
- `playbooks/02-setup-pihole.yml`: Local DNS sinkhole and wildcard domain routing (`*.homelab.local`).
- `playbooks/03-setup-tailscale.yml`: Encrypted mesh VPN subnet router gateway.
- `playbooks/04-bootstrap-cluster.yml`: k3s control plane initialization, token capture, and worker node joining.
- `playbooks/05-setup-cluster-services.yml`: In-cluster Cilium eBPF CNI, ArgoCD GitOps engine, and Chaos Mesh platform.
- `playbooks/06-setup-nginx.yml`: Ingress gateway virtual host routing for all 7 platform dashboards.
