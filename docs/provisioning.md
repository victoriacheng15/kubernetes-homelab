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

1. **Initialize Cluster on Primary Node (`pve-01`):**

   ```bash
   pvecm create k8s-homelab
   ```

2. **Join Secondary Node (`pve-02`):**

   ```bash
   pvecm add <PRIMARY_NODE_IP>
   ```

3. **Configure Quorum Tiebreaker (Raspberry Pi `rpi-01`):**

   ```bash
   # On Raspberry Pi (rpi-01):
   sudo apt update && sudo apt install -y corosync-qnetd

   # On Proxmox hosts (pve-01 and pve-02):
   apt update && apt install -y corosync-qdevice

   # On primary node (pve-01), attach the QDevice:
   pvecm qdevice setup <QDEVICE_IP>
   pvecm status
   ```

### Time Synchronization

Distributed consensus engines (etcd in k3s and Corosync in Proxmox) require sub-second clock synchronization. The Raspberry Pi (`rpi-01`) acts as the authoritative local Stratum 2 time server using Chrony NTP.

1. **Server Setup on Raspberry Pi (`rpi-01`):**

   ```bash
   # Set timezone to UTC
   sudo timedatectl set-timezone UTC

   # Install chrony
   sudo apt update && sudo apt install -y chrony
   ```

2. **Configure `/etc/chrony/chrony.conf` on `rpi-01`:**

   ```text
   server time.cloudflare.com iburst
   server time.google.com iburst
   server 0.debian.pool.ntp.org iburst

   driftfile /var/lib/chrony/chrony.drift
   makestep 1.0 3
   local stratum 10

   # Allow local homelab subnets to query time
   allow 192.168.0.0/16
   allow 10.0.0.0/8
   ```

3. **Restart and Verify on `rpi-01`:**

   ```bash
   sudo systemctl restart chrony
   sudo systemctl enable chrony
   chronyc sources -v
   chronyc tracking
   ```

4. **Hypervisor Configuration (`pve-01` and `pve-02`):**
   Add `rpi-01` as the preferred time server at the top of `/etc/chrony/chrony.conf` on both Proxmox hosts:

   ```bash
   # Add to /etc/chrony/chrony.conf on pve-01 and pve-02:
   server <RPI_IP> iburst prefer

   # Restart and verify sync
   systemctl restart chrony
   chronyc sources -v
   ```

### Cloud-Init Template

Create the Ubuntu 24.04 Server template (VM 9000) on local hypervisor storage:

1. Download the official cloud image.
2. Initialize VM 9000 and import disk to `local-lvm`.
3. Configure Cloud-Init drive, serial socket, and display.
4. Convert to permanent template.

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
qm create 9000 --name "ubuntu-2404-server-template" --memory 2048 --cores 2 --cpu host --net0 virtio,bridge=vmbr0
qm disk import 9000 noble-server-cloudimg-amd64.img local-lvm
qm set 9000 --scsihw virtio-scsi-single --scsi0 local-lvm:vm-9000-disk-0,discard=on,ssd=1
qm set 9000 --ide2 local-lvm:cloudinit --boot order=scsi0 --serial0 socket --vga serial0
qm template 9000
rm -f noble-server-cloudimg-amd64.img
```

### OpenTofu Deployment

1. Generate an API token in the Proxmox Web GUI (`Datacenter -> Permissions -> API Tokens -> Add`) for user `root@pam` with Token ID `tofu` (ensure Privilege Separation is unchecked).
2. Configure variables in `infra/terraform.tfvars`:

   ```hcl
   proxmox_endpoint     = "https://<PROXMOX_HOST_IP>:8006/"
   proxmox_api_token    = "root@pam!tofu=<SECRET_UUID>"
   proxmox_insecure     = true
   ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
   template_vm_id       = 9000
   pihole_ipv4_address  = "<STATIC_IP>/24"
   pihole_ipv4_gateway  = "<GATEWAY_IP>"
   ```

3. Initialize, plan, and apply:

   ```bash
   cd infra
   tofu init
   tofu plan
   tofu apply
   ```

---

## Layer 2: Node OS Baseline Provisioning

Before bootstrapping Kubernetes, all VM nodes must have active swap disabled, kernel networking modules loaded, and sysctl packet forwarding rules applied. This baseline tuning is automated using Ansible from the dedicated controller container (`CT 303` on `pve-01`).

### Controller Container Access

From your Proxmox host shell (`pve-01`):

```bash
pct enter 303
```

### Locales & Collection Dependencies

Ensure UTF-8 locales are generated and required collections are installed inside the container:

```bash
# Generate UTF-8 locales permanently
apt update && apt install -y locales
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Install required Ansible collections
ansible-galaxy collection install community.general ansible.posix
```

### Fleet Connectivity Verification

From the repository's `ansible/` directory, verify that all target nodes authenticate and respond:

```bash
cd ~/kubernetes-homelab/ansible
ansible nodes -m ping
```

All three nodes (`k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`) should return `"ping": "pong"` with `SUCCESS`.

### Baseline Playbook Execution

Run the setup playbook:

```bash
ansible-playbook playbooks/setup-vms.yml
```

The playbook enforces the following system baselines across all nodes:

- **Timezone:** Locks system clock to UTC.
- **Swap:** Disables active swap (`swapoff -a`) and permanently comments out swap mounts in `/etc/fstab`.
- **Kernel Modules:** Loads `overlay` and `br_netfilter` immediately and persists them across reboots in `/etc/modules-load.d/k8s.conf`.
- **Sysctl Parameters:** Enables IP packet forwarding (`net.ipv4.ip_forward = 1`) and bridge netfilter calls in `/etc/sysctl.d/99-kubernetes.conf`.
- **Core Packages:** Installs essential troubleshooting utilities (`curl`, `git`, `jq`, `tcpdump`, `socat`, `htop`, `tar`).

---

## Layer 3: Declarative GitOps & Cluster Provisioning

Once the physical hypervisors are clustered (Layer 1) and all virtual machine OS baselines are hardened (Layer 2), the final tier provisions the Kubernetes platform using k3s and ArgoCD as its declarative GitOps delivery engine.

### Preflight Environment Verification

Before running installation scripts, execute `bootstrap/00-preflight.sh` to audit system resources, kernel version, network ports, and verify that the Ansible OS baseline (timezone, swap, kernel modules, sysctl) is active across target nodes:

```bash
./bootstrap/00-preflight.sh
```

### Control Plane Initialization

Bootstrap the isolated control plane on `k8s-cp-01` using `bootstrap/01-k3s-server.sh`. This script configures declarative k3s server settings in `/etc/rancher/k3s/config.yaml`, disables default Flannel and Traefik to prepare for Cilium, and isolates the control plane with a `NoSchedule` taint:

```bash
./bootstrap/01-k3s-server.sh

# Verify local control plane status
kubectl get nodes
```

Upon completion, the script outputs the cluster join endpoint and node token directly to the terminal for worker onboarding.

### Worker Node Onboarding

Execute `bootstrap/02-k3s-agent.sh` on each worker node:

```bash
# On k8s-telemetry-01:
sudo ./bootstrap/02-k3s-agent.sh \
  --server-url "https://<CONTROL_PLANE_IP>:6443" \
  --token "<JOIN_TOKEN>" \
  --node-role telemetry

# On k8s-app-01:
sudo ./bootstrap/02-k3s-agent.sh \
  --server-url "https://<CONTROL_PLANE_IP>:6443" \
  --token "<JOIN_TOKEN>" \
  --node-role app
```

!!! note
    In accordance with the Kubernetes NodeRestriction admission plugin, worker nodes self-assign the `workload=<role>` label. Formal role labels are assigned from the control plane.

Apply formal role labels from `k8s-cp-01`:

```bash
kubectl label node k8s-telemetry-01 node-role.kubernetes.io/telemetry=true
kubectl label node k8s-app-01 node-role.kubernetes.io/app=true
```

### CNI & Network Fabric Deployment

Deploy Cilium eBPF in VXLAN overlay mode using `bootstrap/03-cni-cilium.sh` from `k8s-cp-01`:

```bash
./bootstrap/03-cni-cilium.sh
```

Key parameters configured by the script:

| Parameter | Value | Purpose |
| :--- | :--- | :--- |
| **Pod CIDR** | `10.244.0.0/16` | Eliminates subnet collisions with the physical LAN |
| **Host Routing** | `bpf.hostLegacyRouting=true` | Protects host-level SSH and management traffic |
| **Kube-Proxy** | In-kernel eBPF | High-performance socket-based load balancing |
| **Hubble** | Relay & UI enabled | Real-time L3/L4/L7 flow observability |

Verify cluster health and eBPF data path status:

```bash
cilium status --wait
kubectl get nodes -o wide
kubectl get pods -A
```

### ArgoCD App-of-Apps Initialization

*Placeholder for deploying the ArgoCD GitOps engine to reconcile platform manifests from Git.*
