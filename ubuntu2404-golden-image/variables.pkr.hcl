variable "ssh_username" {
  type    = string
  default = "ubuntu"
  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.ssh_username))
    error_message = "Use a valid Linux username containing only lowercase letters, digits, underscore or hyphen."
  }
}

variable "ssh_public_key_file" {
  type = string
}

variable "ssh_private_key_file" {
  type = string
}

variable "password_hash" {
  type        = string
  sensitive   = true
  default     = "!"
  description = "Locked password by default. Optionally supply an SHA-512 crypt hash for console login; SSH passwords remain disabled."
}

variable "vm_hostname" {
  type    = string
  default = "ubuntu-2404-k8s-template"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.vm_hostname))
    error_message = "Use a valid single-label lowercase hostname, at most 63 characters."
  }
}

variable "headless" {
  type    = bool
  default = true
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 4096
}

variable "disk_size" {
  type    = number
  default = 65536
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/24.04.5/ubuntu-24.04.5-live-server-amd64.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:97f3d7ffb032c3eb3b23d2c8be9cc76e60c2c1f2c0146ba5ba9fe01cafae0fd8"
}

