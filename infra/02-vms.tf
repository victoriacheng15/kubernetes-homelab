# ==============================================================================
# Kubernetes Cluster Virtual Machines (bpg/proxmox)
# ==============================================================================

locals {
  vms = {
    k8s-cp-01 = {
      node_name   = "pve-01"
      vm_id       = 100
      description = "Kubernetes Control Plane Node (k3s server, embedded etcd)"
      tags        = ["k8s", "control-plane"]
      memory      = 4096
      disk_size   = 50
    }
    k8s-telemetry-01 = {
      node_name   = "pve-01"
      vm_id       = 101
      description = "Kubernetes Observability & GitOps Node"
      tags        = ["k8s", "telemetry"]
      memory      = 8192
      disk_size   = 100
    }
    k8s-app-01 = {
      node_name   = "pve-02"
      vm_id       = 200
      description = "Kubernetes General Application Node"
      tags        = ["k8s", "app"]
      memory      = 6144
      disk_size   = 50
    }
  }
}

resource "proxmox_virtual_environment_vm" "vms" {
  for_each    = local.vms
  node_name   = each.value.node_name
  vm_id       = each.value.vm_id
  name        = each.key
  description = each.value.description
  tags        = each.value.tags

  agent {
    enabled = true
  }

  clone {
    vm_id     = var.template_vm_id
    node_name = "pve-01"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.admin_ssh_public_key, var.ansible_ssh_public_key]
    }
  }

  cpu {
    cores = try(each.value.cores, 2)
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    datastore_id = try(each.value.datastore_id, "local-lvm")
    size         = each.value.disk_size
    interface    = "scsi0"
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  scsi_hardware = "virtio-scsi-single"
}
