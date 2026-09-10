

variable "gitlab_vm_name" {
  type    = string
  default = "gitlab-lab-ubuntu-24-04"
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory" {
  type    = number
  default = 8192
}

variable "disk_size" {
  type    = number
  default = 51200
}

variable "headless" {
  type    = bool
  default = true
}

variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "ssh_password" {
  type      = string
  default   = "packer"
  sensitive = true
}

variable "external_url" {
  type    = string
  default = "http://localhost:8080"
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/noble/ubuntu-24.04.3-live-server-amd64.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b"
}

variable "ssh_private_key_file" {
  type    = string
  default = "~/.ssh/id_ed25519_packer_gitlab"
}
