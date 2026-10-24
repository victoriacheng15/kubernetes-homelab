# ==============================================================================
# pve-01 (Mini PC)
# - k8s-cp-01 (VM 100): Control Plane (API Server, embedded etcd)
# - k8s-telemetry-01 (VM 101): Observability & GitOps
# ==============================================================================

resource "proxmox_virtual_environment_vm" "k8s_cp_01" {
  node_name   = "pve-01"
  vm_id       = 100
  name        = "k8s-cp-01"
  description = "Kubernetes Control Plane Node (k3s server, embedded etcd)"
  tags        = ["k8s", "control-plane", "k3s"]

  clone {
    vm_id = var.template_vm_id
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    datastore_id = "local-lvm"
    size         = 50
    interface    = "scsi0"
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  scsi_hardware = "virtio-scsi-single"
}

resource "proxmox_virtual_environment_vm" "k8s_telemetry_01" {
  node_name   = "pve-01"
  vm_id       = 101
  name        = "k8s-telemetry-01"
  description = "Kubernetes Observability & GitOps Node"
  tags        = ["k8s", "Observability", "gitops"]

  clone {
    vm_id = var.template_vm_id
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    datastore_id = "local-lvm"
    size         = 100
    interface    = "scsi0"
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  scsi_hardware = "virtio-scsi-single"
}

# ==============================================================================
# pve-02 (Laptop)
# - k8s-app-01 (VM 200): General Applications
# ==============================================================================

resource "proxmox_virtual_environment_vm" "k8s_app_01" {
  node_name   = "pve-02"
  vm_id       = 200
  name        = "k8s-app-01"
  description = "Kubernetes General Application Node"
  tags        = ["k8s", "worker", "apps"]

  clone {
    vm_id = var.template_vm_id
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 6144
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    datastore_id = "local-lvm"
    size         = 50
    interface    = "scsi0"
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  scsi_hardware = "virtio-scsi-single"
}
