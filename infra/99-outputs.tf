# ==============================================================================
# OpenTofu Outputs
# ==============================================================================

output "container_ips" {
  description = "IPv4 addresses for standalone utility containers"
  value = {
    for name, ct in proxmox_virtual_environment_container.containers :
    name => try(ct.ipv4["eth0"], "dhcp")
  }
}

output "sandbox_container_ips" {
  description = "IPv4 addresses for ephemeral sandbox containers"
  value = {
    for name, ct in proxmox_virtual_environment_container.sandbox :
    name => try(ct.ipv4["eth0"], "static")
  }
}

output "vm_ips" {
  description = "IPv4 addresses for Kubernetes virtual machines"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vms :
    name => try([for ip in flatten(vm.ipv4_addresses) : ip if !startswith(ip, "127.")][0], "dhcp")
  }
}

output "sandbox_vm_ips" {
  description = "IPv4 addresses for ephemeral sandbox VMs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.sandbox :
    name => try([for ip in flatten(vm.ipv4_addresses) : ip if !startswith(ip, "127.")][0], "static")
  }
}
