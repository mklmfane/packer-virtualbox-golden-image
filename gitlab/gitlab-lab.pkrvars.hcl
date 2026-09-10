vm_name  = "gitlab-lab-ubuntu-24-04"
cpus     = 4
memory   = 8192
disk_size = 51200
headless = true

ssh_username = "packer"
ssh_password = "packer"

external_url = "http://localhost:8080"

iso_url      = "https://releases.ubuntu.com/noble/ubuntu-24.04.3-live-server-amd64.iso"
iso_checksum = "sha256:c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b"

ssh_private_key_file = "~/.ssh/id_ed25519_packer_gitlab"
