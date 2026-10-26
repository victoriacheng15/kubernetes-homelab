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

variable "ssh_public_key" {
  description = "Public SSH key injected into the default ubuntu user"
  type        = string
}

variable "container_template_file_id" {
  description = "File ID of the container template in Proxmox storage"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
}
