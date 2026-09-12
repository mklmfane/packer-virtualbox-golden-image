variable "iso_url" {
  type    = string
  default = "https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US"
}
variable "iso_checksum" {
  type    = string
  default = "sha256:3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325"
}
variable "image_name" { type = string }
variable "admin_password" {
  type      = string
  sensitive = true
  validation {
    condition     = can(regex("^[A-Za-z0-9!@#%_+-]{16,64}$", var.admin_password))
    error_message = "Use prepare.py to generate a compatible password."
  }
}
variable "headless" { default = false }
variable "cpus" { default = 4 }
variable "memory" { default = 8192 }
variable "disk_size" { default = 102400 }
variable "initialize_swarm" {
  type        = bool
  default     = false
  description = "After final-user WSL installation, optionally initialize an independent single-node Linux Swarm."
}
