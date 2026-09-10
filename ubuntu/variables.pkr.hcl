variable "ssh_username" {
  type    = string
  default = "kube"
}

variable "ssh_private_key_file" {
  type    = string
  default = "${env("HOME")}/.ssh/k8s_kubespray"
}

variable "ssh_pubkey" {
  type = string
}

variable "vm_hostname" {
  type    = string
  default = "ubuntu-k8s-template"
}

# Autoinstall requires a hash even if we lock the account.
variable "password_hash" {
  type    = string
  default = "$6$Qibx35EfIQbiJ5n0$kP/0I1358GyOqdNHPhitv9Z8Ak00RBeTv0HXBs58iR.LPStTPIvApyvnJMM5JCMnI5QMuRP1Hv3RnBDgZMfrg."
}
