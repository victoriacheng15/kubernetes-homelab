variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL (e.g. https://<PROXMOX_HOST_IP>:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in USER@REALM!TOKENID=UUID format"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Allow self-signed certificates on Proxmox API"
  type        = bool
  default     = true
}

variable "pihole_ipv4_address" {
  description = "IPv4 address with CIDR for Pi-hole container"
  type        = string
  default     = "dhcp"
}

variable "pihole_ipv4_gateway" {
  description = "IPv4 default gateway for Pi-hole container"
  type        = string
  default     = null
}

variable "template_vm_id" {
  description = "VM ID of the Ubuntu 24.04 Server cloud-init template"
  type        = number
  default     = 9000
}

variable "admin_ssh_public_key" {
  description = "Public SSH key for human admin access (k8s-homelab-admin)"
  type        = string
}

variable "ansible_ssh_public_key" {
  description = "Public SSH key for Ansible controller CT 300 (ansible)"
  type        = string
}

variable "container_template_file_id" {
  description = "File ID of the container template in Proxmox storage"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
}

variable "sandbox_vms" {
  description = "Dynamic map of ephemeral sandbox VMs (900-series, static IPs 10.0.0.9x)"
  type = map(object({
    node_name    = optional(string, "pve-01")
    vm_id        = number
    template_id  = number
    ipv4_address = string
    ipv4_gateway = optional(string, "10.0.0.1")
    username     = optional(string, "ubuntu")
    cores        = optional(number, 2)
    memory       = optional(number, 4096)
    disk_size    = optional(number, 30)
    tags         = optional(list(string), ["sandbox"])
  }))
  default = {}
}

variable "sandbox_containers" {
  description = "Dynamic map of ephemeral sandbox LXC containers (800-series, static IPs 10.0.0.8x)"
  type = map(object({
    node_name        = optional(string, "pve-01")
    vm_id            = number
    template_file_id = optional(string)
    ipv4_address     = string
    ipv4_gateway     = optional(string, "10.0.0.1")
    cores            = optional(number, 1)
    memory           = optional(number, 512)
    swap             = optional(number, 512)
    disk_size        = optional(number, 8)
    datastore_id     = optional(string, "local-lvm")
    tags             = optional(list(string), ["sandbox"])
  }))
  default = {}
}
