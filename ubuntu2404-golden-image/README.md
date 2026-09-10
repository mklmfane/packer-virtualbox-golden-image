# Shared Ubuntu 24.04 golden image

For the shared Kubernetes, Ubuntu and GitLab workflow, follow [the repository README](../README.md). New builds default to a 64 GiB disk. The standalone instructions below describe only building and inspecting the base image.

This package prepares one reusable Ubuntu Server image using Packer and VirtualBox.
It contains source files, not an already-built OVF or disk image.

The workflow is: build the base image; import separate VMs; give each VM its own
identity and cluster-network address.
The image has SSH, Python 3, passwordless sudo for the configured account, swap
disabled, IPv4 forwarding and bridge modules.

## Repository placement


You can use this image project in a sibling directory, or copy this directory
into `packer/ubuntu2404-golden-image/` in the checkout pointing your local branch . No remote
change is required to build locally. To publish your customizations, use your own
repository or fork; an upstream origin does not grant permission to push there.


## Host prerequisites

- Linux x86-64 host with working VirtualBox and hardware virtualization.
- Packer >= 1.9.0, VBoxManage, ssh-keygen, Python 3 and unzip.
- Internet access for the ISO, Packer plugin and Ubuntu package repositories.
- Enough free disk for the ISO, build disk, exported disk and subsequent clones.
- A build allowance of 2 vCPUs and 4 GiB RAM; both are configurable.

Run Packer as your regular VirtualBox user. The installer uses VirtualBox's
default NAT adapter. Its `10.0.2.2` address reaches the host; the host firewall
must permit the VM to reach Packer's temporary HTTP server on TCP 8800–8899.
The HTTP server binds all host interfaces for this local lab build. The seed
contains a public key and optionally a password hash, never the private key.

## Build

Extract the archive and run:

```bash
cd ubuntu2404-golden-image
bash configure.sh
packer init .
packer fmt .
packer validate -var-file=values.pkrvars.hcl .
packer build -var-file=values.pkrvars.hcl .
```

The final `.` is required: it selects the directory containing the `.pkr.hcl`
files. `packer { ... }` belongs in the HCL file, not on the build command line.

`configure.sh` creates or reuses `~/.ssh/kubernetes-packer-lab`, confirms its public key
matches, and writes `values.pkrvars.hcl`. It never overwrites an existing values
file or key. A dedicated unencrypted SSH key enables unattended builds; protect
that private key on the host. Only its public key is baked into this lab image.
To use a different existing unencrypted key:

```bash
bash configure.sh /absolute/path/to/private-key
```

Alternatively, copy `values.pkrvars.hcl.example` to `values.pkrvars.hcl` and edit
both absolute key paths. The password is locked by default. If console login is
needed, generate a hash with `openssl passwd -6` and set `password_hash` to that
hash in the values file. SSH password login remains disabled.

Ubuntu 24.04.5 is retained from the supplied configuration. Its SHA-256 is pinned
from Ubuntu's published SHA256SUMS. If using another point-release ISO, override
both `iso_url` and `iso_checksum` together. If a pinned ISO is moved, supply its
verified local file path or an official mirror URL with the same checksum.
Security updates during autoinstall mean successive builds are not byte-identical.
The image records `/etc/image-build-info` and `/etc/image-package-manifest.txt`.

Expected output:

```text
output-ubuntu2404/ubuntu-2404-k8s-template.ovf
output-ubuntu2404/*.vmdk
```

Keep the entire output directory together. The OVF describes the VM and references
the disk file; copying the OVF alone is insufficient. This export is not a Vagrant
`.box` file. A Vagrant box requires a separate packaging step.

Packer normally refuses to reuse an existing output directory. Preserve the
previous artifact before changing the output directory or intentionally rebuilding.

## Why node deployment is separate

The original shell-local post-processor called `deploy-3nodes.sh` after export.
That sequencing is suitable for accessing an exported artifact, but it also
makes every image build create cluster VMs. The script was not provided and is
not included here. This first stage finishes with the golden-image export.

Before integrating your deployment script, ensure it:

1. Imports the OVF separately for each node with fresh VirtualBox MAC addresses.
2. Keeps NIC 1 as NAT for Internet access and adds NIC 2 on a shared host-only
   network, such as 192.168.56.0/24, after checking for host/VPN route conflicts.
3. Assigns distinct hostnames and host-only IPs, for example node1/.11,
   node2/.12 and node3/.13. The host may use 192.168.56.1.
4. Configures the second NIC in netplan with no default route; NAT remains the
   default route. Verify actual interface names with `ip -br link`.


Cloud-init is cleaned before export. A clone generates a new machine ID and SSH
host keys on boot. For NoCloud personalization, attach a separate `cidata` seed
per clone with a unique `instance-id` and `local-hostname`; user-data can set its
hostname. Cloud-init networking is explicitly disabled so it does not overwrite
netplan: configure host-only networking separately, or deliberately remove that
setting if your deployment workflow uses cloud-init network-config.

## Smoke-test the exported image

Import a disposable VM using a unique unused VM name and host TCP port:

```bash
VBoxManage import output-ubuntu2404/ubuntu-2404-k8s-template.ovf \
  --vsys 0 --vmname ubuntu2404-image-test
VBoxManage modifyvm ubuntu2404-image-test \
  --natpf1 'smoke-ssh,tcp,127.0.0.1,2301,,22'
VBoxManage startvm ubuntu2404-image-test --type headless
```

After boot, connect using the key configured for this build:

```bash
ssh -i "$HOME/.ssh/kuberntes-packer-lab" -p 2301 ubuntu@127.0.0.1
sudo -n true
python3 --version
cat /etc/image-build-info
cat /etc/machine-id
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
swapon --show
sysctl net.ipv4.ip_forward
systemctl status golden-image-ssh-keys.service --no-pager
sudo cloud-init status --wait
```

Expect empty swap output, forwarding equal to 1, working sudo/Python/SSH and a
successful key-generation service. Import a second disposable VM with another
name and port to confirm the machine ID and SSH host-key fingerprint differ.
Reboot the first test VM and confirm its identity remains stable. Importing with
fresh MACs is also necessary; guest cleanup does not change VirtualBox MACs.

## Troubleshooting

- Installer stays at GRUB: build with
  `packer build -var-file=values.pkrvars.hcl -var='headless=false' .` and observe
  the console. The supplied sequence assumes BIOS GRUB and this Ubuntu ISO;
  boot timing may need adjustment on the host.
- Installer asks questions: inspect its seed HTTP requests and
  `/var/log/installer` in the live installer. Confirm the escaped semicolon and
  trailing slash in the NoCloud URL and that the VM can reach 10.0.2.2.
- SSH timeout: inspect the installation console, key paths and NAT forwarding.
  `configure.sh` checks key correspondence. The initial install may download
  security updates and take time.
- Sudo failure: ensure autoinstall late-commands succeeded. The image depends on
  the validated `/etc/sudoers.d/90-packer` entry.
- Cloud-init wait reports an error: inspect `sudo cloud-init status --long` and
  its logs. The build intentionally stops instead of exporting an uncertain VM.

## Validation status

Shell scripts were checked with `bash -n`; a representative rendered autoinstall
document was parsed as YAML. Packer and VirtualBox are unavailable in the authoring
environment, so `packer validate`, installer boot, export and clone smoke tests
must be run on your VirtualBox host. These source files do not imply a successful
image build.

## References

- https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/iso
- https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html
- https://docs.cloud-init.io/en/latest/reference/cli.html
- https://releases.ubuntu.com/noble/SHA256SUMS

