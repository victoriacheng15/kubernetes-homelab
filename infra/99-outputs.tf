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

output "vm_ips" {
  description = "IPv4 addresses for Kubernetes virtual machines"
  value = {
    "k8s-cp-01"        = try(proxmox_virtual_environment_vm.k8s_cp_01.ipv4_addresses[0][0], "dhcp")
    "k8s-telemetry-01" = try(proxmox_virtual_environment_vm.k8s_telemetry_01.ipv4_addresses[0][0], "dhcp")
    "k8s-app-01"       = try(proxmox_virtual_environment_vm.k8s_app_01.ipv4_addresses[0][0], "dhcp")
  }
}
