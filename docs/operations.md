# Operations & GitOps

## Overview

This guide covers the operational lifecycle of the homelab from bare hypervisor initialization to declarative GitOps workload reconciliation. Operations are structured into three distinct phases:

- **Infrastructure Provisioning:** Configures Proxmox host clustering, Corosync quorum with an external QDevice, Ubuntu Cloud-Init templates, and automated OpenTofu provisioning for VMs and LXCs.
- **Cluster Bootstrap:** Initializes the lightweight Kubernetes control plane (`k3s`), deploys the Cilium eBPF CNI with Hubble observability, and attaches worker nodes across physical hypervisors.
- **GitOps & Workloads:** Deploys the ArgoCD continuous delivery engine using the App-of-Apps architectural pattern, enabling Git-driven reconciliation for platform services and demo applications.

## Infrastructure Provisioning

### Cluster & Quorum Setup

Physical hosts must be joined into a cluster with an external QDevice tiebreaker to maintain odd quorum ($N=3$):

```bash
# On primary node (pve-01)
pvecm create homelab-cluster

# On secondary node (pve-02)
pvecm add <PRIMARY_NODE_IP>

# On primary node, attach QDevice tiebreaker (e.g. Raspberry Pi running corosync-qnetd)
pvecm qdevice setup <QDEVICE_IP>
pvecm status
```

### Cloud-Init Template (VM 9000)

Create the Ubuntu 24.04 Server template on local hypervisor storage:

1. Download the official cloud image.
2. Initialize VM 9000 and import disk to `local-lvm`.
3. Configure Cloud-Init drive, serial socket, and guest agent.
4. Convert to permanent template.

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
qm create 9000 --name "ubuntu-2404-server-template" --memory 2048 --cores 2 --cpu host --net0 virtio,bridge=vmbr0
qm disk import 9000 noble-server-cloudimg-amd64.img local-lvm
qm set 9000 --scsihw virtio-scsi-single --scsi0 local-lvm:vm-9000-disk-0,discard=on,ssd=1
qm set 9000 --ide2 local-lvm:cloudinit --boot order=scsi0 --serial0 socket --vga serial0 --agent enabled=1
qm template 9000
rm -f noble-server-cloudimg-amd64.img
```

### OpenTofu Deployment

1. Generate an API token in the Proxmox Web GUI (`Datacenter -> Permissions -> API Tokens -> Add`) for user `root@pam` with Token ID `tofu`.
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

## Cluster Bootstrap

### Node OS Prerequisites

### Control Plane Provisioning (k3s Server)

### CNI Deployment (Cilium eBPF)

### Agent & Worker Joins

## GitOps & Workloads

### ArgoCD App-of-Apps Engine

### Secrets Management

### Application Deployments
