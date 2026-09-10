# One Ubuntu golden image, multiple VirtualBox VMs

Build Ubuntu once with Packer in `ubuntu2404-golden-image/`. The `k8s/`, `ubuntu/`
and `gitlab/` Packer projects import its OVF and provision separate live VMs.
Only the golden-image project installs from an ISO. The other projects retain
registered VMs and skip export: these are role instances, not templates to clone
again after Kubernetes or GitLab has initialized its state.

## Start with Kubernetes

Requirements on your Linux VirtualBox host: working VBoxManage, Packer >=1.9.0,
Python 3, OpenSSH and Internet access. Builds pin VirtualBox plugin 1.1.5.
The three Kubernetes VMs allocate 8 GiB RAM total plus host overhead.
GitLab adds 8 GiB, Ubuntu 2 GiB; run those later if host memory is limited.

From the repository root:

```bash
cp -n lab.example.json lab.local.json
```

Review `lab.local.json`. Its SSH user and key must match the golden image. The
defaults are `ubuntu` and `~/.ssh/kubespray-lab`. If you already built the golden
image successfully with this key, keep it. For a new setup, run:

```bash
bash ubuntu2404-golden-image/configure.sh
```

That script creates the dedicated key if missing. If it reports an existing
values file, preserve it and check your existing key settings instead.
`lab.py` uses the shared configuration and does not load the old per-role
`*.pkrvars.hcl` files. Golden build CPU, RAM, disk and ISO defaults live in
`ubuntu2404-golden-image/variables.pkr.hcl`. To alter those when using `lab.py`,
use standard `PKR_VAR_...` environment variables, for example
`PKR_VAR_disk_size=65536 python3 scripts/lab.py golden`.

Build the template:

```bash
python3 scripts/lab.py golden
```

Then build/start one control plane and two workers:

```bash
python3 scripts/lab.py up k8s
```

Each invocation runs `packer init`, `packer validate`, then `packer build` for
new VMs. It configures host-only networking, installs matched stable Kubernetes
and CRI-O minor versions, starts the control plane, applies Calico, joins workers
over SSH, and waits for node readiness. No HTTP join server or admin kubeconfig
is exposed to workers. This uses the repository's kubeadm approach, not Kubespray.
It does not install the obsolete Dashboard configuration.

| VM | Host-only IP | vCPU | RAM |
| --- | --- | --- | --- |
| k8s-controlplane-01 | 192.168.56.10 | 2 | 4096 MiB |
| k8s-worker-01 | 192.168.56.11 | 2 | 2048 MiB |
| k8s-worker-02 | 192.168.56.12 | 2 | 2048 MiB |
| ubuntu-lab | 192.168.56.20 | 2 | 2048 MiB |
| gitlab-lab | 192.168.56.30 | 4 | 8192 MiB |

The default Kubernetes minor remains 1.34. CRI-O comes from its matching stable
1.34 stream, rather than prerelease/main. Calico is pinned to 3.31.0. Package
patch versions resolve from those repositories at installation and are recorded
in `/etc/k8s-package-versions.txt`; rebuilds are not byte-for-byte reproducible.
Pod and service CIDRs are corrected to canonical `172.16.0.0/16` and
`172.17.0.0/18`. Review host, VPN and container network routes for overlaps.

NIC 1 remains NAT for downloads. NIC 2 is host-only (`enp0s8`) with a static IP.
Default host interface: vboxnet0 at 192.168.56.1/24. The script creates it if
absent and refuses to alter an existing interface with different settings or
use addresses overlapping its enabled DHCP pool. When creating an interface,
VirtualBox may choose another name; follow the reported name and update the
config. Check guest firewalls if node-to-node traffic is blocked.

## Existing golden image

You may skip `golden` when the complete successful export already exists here:

```text
ubuntu2404-golden-image/output-ubuntu2404/ubuntu-2404-k8s-template.ovf
ubuntu2404-golden-image/output-ubuntu2404/ubuntu-2404-k8s-template-disk001.vmdk
```

Keep the OVF and referenced disks together. Role templates hash the local OVF
at build time; this is not an independently stored integrity check for its disks.
New golden builds explicitly export OVF 2.0 and allocate a 64 GiB virtual disk
for reuse by GitLab. Existing 32 GiB exports can serve Kubernetes/Ubuntu, but the
GitLab preflight requires at least 50 GiB on `/` and will stop before installation.

The golden builder refuses to overwrite output. To rebuild deliberately, first
move the complete output directory into a backup outside this repository; then
run `python3 scripts/lab.py golden`. Existing role VMs keep their own disks.

## Connect and verify

```bash
ssh -i "$HOME/.ssh/kubespray-lab" ubuntu@192.168.56.10
kubectl get nodes -o wide
kubectl get pods -A
```

On each node, `cat /etc/machine-id` and
`sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` should differ between nodes
and remain stable across reboots. The sealed template regenerates identities;
role instances must not run the golden sealing script again.

The host records SSH host keys in ignored `.lab/known_hosts` using accept-new.
Changed keys are rejected. After deliberately recreating a VM, independently
verify its console fingerprint before removing that specific known_hosts entry.

## Ubuntu and GitLab later

```bash
python3 scripts/lab.py up ubuntu
python3 scripts/lab.py up gitlab
```

Ubuntu receives the shared SSH/network/hostname configuration. GitLab imports
the same template, then runs its GitLab CE, Runner and Docker provisioning scripts.
Access its UI at http://192.168.56.30:8080 and Git SSH at 192.168.56.30:22.
Runner registration remains manual: use this reachable host-only URL (not
localhost) and a token obtained from your GitLab instance. Keep credentials out
of Git and the shared golden image. No runners are registered automatically.

## Re-running and existing VMs

`up` reuses matching project-tagged VMs and starts them if powered off. It checks
that provisioning completed and stored identity/network/Kubernetes settings match.
It never replaces a VM just because its name exists. It never resets Kubernetes,
deletes VM disks or changes existing network interfaces automatically. A partial
Packer build without the completion marker requires inspection of its console and
build output; the script will stop rather than treat it as ready.

The old `ubuntu2404-test` is unrelated to the new node names and does not need to
be deleted to run this workflow. Stop it if you need its RAM. Old per-role ISO
seeds, variable files and Kubernetes HTTP bootstrap services are removed from the
tracked tree. Local ignored exports and variable files remain on your computer;
use `lab.local.json` for this workflow.

## Validation

HCL parsing, shell syntax, Python compilation and host-orchestration unit tests
are checked without starting a VM. Full Packer/plugin validation and VirtualBox
build/boot tests must run on your host; VM runtime behavior has not been tested
in the authoring environment.

```bash
python3 -m unittest discover -s tests -v
```

References:
- https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/ovf
- https://github.com/cri-o/packaging
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
