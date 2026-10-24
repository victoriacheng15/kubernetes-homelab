# ==============================================================================
# Standalone Utility LXC Containers (bpg/proxmox)
# ==============================================================================

locals {
  containers = {
    pihole = {
      node_name    = "pve-02"
      vm_id        = 300
      description  = "Local DNS Server and Ad-blocking Sinkhole"
      tags         = ["dns", "utility", "pihole"]
      ipv4_address = var.pihole_ipv4_address
      ipv4_gateway = var.pihole_ipv4_gateway
    }
    tailscale = {
      node_name    = "pve-01"
      vm_id        = 301
      description  = "Encrypted Tailscale Subnet Router Gateway"
      tags         = ["vpn", "utility", "tailscale"]
      ipv4_address = "dhcp"
    }
    nginx = {
      node_name    = "pve-01"
      vm_id        = 302
      description  = "Local Reverse Proxy & Domain Router (*.home.arpa)"
      tags         = ["proxy", "utility", "nginx"]
      ipv4_address = "dhcp"
    }
    ansible = {
      node_name    = "pve-01"
      vm_id        = 303
      description  = "Ansible Automation Control Node"
      tags         = ["automation", "utility", "ansible"]
      ipv4_address = "dhcp"
    }
  }
}

resource "proxmox_virtual_environment_container" "containers" {
  for_each     = local.containers
  node_name    = each.value.node_name
  vm_id        = each.value.vm_id
  unprivileged = true
  description  = each.value.description
  tags         = each.value.tags

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.ipv4_address
        gateway = try(each.value.ipv4_gateway, null)
      }
    }
  }

  cpu {
    cores = try(each.value.cores, 1)
  }

  memory {
    dedicated = try(each.value.memory, 512)
    swap      = try(each.value.swap, 512)
  }

  disk {
    datastore_id = try(each.value.datastore_id, "local-lvm")
    size         = try(each.value.disk_size, 8)
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  features {
    nesting = true
  }
}
