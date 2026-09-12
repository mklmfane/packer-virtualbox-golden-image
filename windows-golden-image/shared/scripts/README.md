# Windows Server 2022: WSL 2 + Linux Docker

This add-on runs after deploying the Windows Server VM. It enables the native Windows Containers feature, then installs Docker Engine, Buildx and Compose inside Ubuntu 24.04 on WSL 2. Swarm is built into Docker Engine; the separate swarm phase initializes a single-node manager.

**The WSL Docker engine runs Linux containers.** Enabling the Windows Containers feature does not make that engine run Windows images. Native Windows containers still require a separate Windows runtime, such as the Server runtime supplied in the earlier Packer package. Docker Desktop is not needed for this WSL installation.

## 1. Prepare the VirtualBox VM

Use an updated Server 2022 Desktop Experience installation for the simple WSL installation path below. Server Core 2022 requires Microsoft's manual WSL/distribution installation procedure; the distro automation below is not a validated Core installer.

On the Ubuntu host, shut down the Windows VM cleanly, then expose nested virtualization (replace the VM name if different):

```bash
VBoxManage modifyvm win-manager-01 --nested-hw-virt on --cpus 4 --memory 8192
VBoxManage startvm win-manager-01 --type gui
```

WSL 2 itself runs a virtual machine. In this setup it is nested inside VirtualBox. A successful optional-feature installation does not prove the host CPU/hypervisor can run it. If WSL returns a virtualization error, validate nested virtualization or use a direct Ubuntu VM for the Linux Docker host. Leave sufficient RAM for the Ubuntu host as well as Windows and WSL.

Extract this folder on the Windows VM as `C:\WindowsLab\wsl-docker`, preserving the files together. Use an elevated PowerShell console under the Windows account that will own/use the WSL distribution, not SYSTEM or the temporary Packer account.

## 2. Enable Windows features and reboot

```powershell
Set-ExecutionPolicy -Scope Process Bypass
C:\WindowsLab\wsl-docker\Enable-WslHost.ps1
Restart-Computer
```

The script enables Containers, Microsoft-Windows-Subsystem-Linux, and VirtualMachinePlatform without forcing a reboot itself. Check Windows Update and reboot any pending servicing changes first.

## 3. Install Ubuntu on WSL 2

After reboot, open elevated PowerShell under the same account:

```powershell
wsl --install -d Ubuntu-24.04
```

Complete any reboot requested by WSL. Launch Ubuntu and create its Linux username/password when prompted. If Ubuntu was already installed, reuse it instead of reinstalling it.

```powershell
wsl --update
wsl --set-default-version 2
wsl --set-version Ubuntu-24.04 2
wsl --version
wsl --list --verbose
wsl -d Ubuntu-24.04
```

The distribution must show VERSION 2. Use a current WSL release; systemd support requires WSL >= 0.67.6. If `wsl --version` is unsupported, update the WSL package rather than proceeding with an older inbox runtime. Microsoft's manual installation guide covers systems where the simple installer is unavailable. Do not interpret `--set-default-version 2` as proof an existing distribution was converted.

## 4. Enable systemd in Ubuntu

Inside Ubuntu:

```bash
sudo bash /mnt/c/WindowsLab/wsl-docker/docker-wsl.sh systemd
exit
```

The script preserves existing INI settings in `/etc/wsl.conf`, backs up the original file, and enables `[boot] systemd=true`. Stop only the target distribution from PowerShell (finish any other work in it first):

```powershell
wsl --terminate Ubuntu-24.04
wsl -d Ubuntu-24.04
```

Back in Ubuntu, confirm `ps -p 1 -o comm=` prints `systemd`.

## 5. Install Linux Docker and Compose

Inside Ubuntu:

```bash
sudo bash /mnt/c/WindowsLab/wsl-docker/docker-wsl.sh install
sudo docker version
sudo docker compose version
sudo docker info --format '{{.OSType}}'
sudo docker run --rm hello-world
```

The engine OS must be `linux`. The installer uses Docker's signed Ubuntu APT repository and installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`. It fails rather than silently removing conflicting runtimes. It uses the current stable package versions available when run; installed versions are recorded in `/var/log/windowslab-docker-versions.txt`. It does not expose the Docker daemon on TCP or add your user to the root-equivalent `docker` group.

No Windows `docker.zip`, Windows Compose executable, or Docker Desktop installer is needed for the WSL engine. Those files were inputs to the separate native Windows runtime Packer workflow.

## 6. Initialize a single-node Swarm

Inside Ubuntu, after Docker is healthy:

```bash
sudo bash /mnt/c/WindowsLab/wsl-docker/docker-wsl.sh swarm
sudo docker node ls
```

The script selects the WSL interface source IP and uses it for the manager's advertised/data-path address. An optional second argument after `swarm` can specify an IPv4 address already assigned inside WSL. Existing Swarm membership is preserved, not reset. Initialization prints a join token through Docker's normal output; treat it as a cluster credential.

WSL's default networking is NAT. The WSL Linux IP differs from the Windows VM's `192.168.56.x` address and may change after restart. Do not advertise the Windows host-only IP from inside WSL unless you have explicitly implemented routable networking for it. A TCP-only `netsh portproxy` does not solve Swarm UDP overlay connectivity. This package does not configure cross-VM Swarm networking, IP persistence, or Windows firewall rules for remote workers.

For a three-node Swarm across your VirtualBox lab, directly networked Ubuntu VMs are a more straightforward extension of your current golden-image workflow. Keep this WSL Swarm as a single-node development lab unless you deliberately design and verify the nested network.

## 7. Linux workload examples

Inside Ubuntu, copy the examples into the Linux filesystem:

```bash
mkdir -p ~/wsl-docker-demo
cp /mnt/c/WindowsLab/wsl-docker/compose.yaml /mnt/c/WindowsLab/wsl-docker/stack.yaml ~/wsl-docker-demo/
cd ~/wsl-docker-demo
sudo docker compose up -d
curl http://localhost:8080/
sudo docker stack deploy -c stack.yaml wsldemo
sudo docker service ls
sudo docker service ps wsldemo_web
curl http://localhost:8081/
```

The examples use Linux nginx images and separate ports so they can coexist. Tags are mutable; pin image digests when reproducibility matters. `docker compose` manages local containers; `docker stack deploy` manages Swarm services.

From the Windows VM, WSL's localhost forwarding may provide access to the application. The outer Ubuntu laptop is another host; access from it requires additional forwarding/routing through Windows, which is not included here.

Cleanup of just these sample workloads:

```bash
sudo docker compose down
sudo docker stack rm wsldemo
```

## Lifecycle and Packer placement

WSL distributions are registered per Windows user. Install the distro and its Docker runtime after importing the golden image, finishing OOBE, and creating the final account. Do not initialize Swarm in a generalized golden image or register the distro under the Packer account that the seal script disables.

You can stage these files in your Packer image and run the feature-enable script before a Packer `windows-restart` provisioner. The actual WSL distribution setup remains a post-deployment operation in the final user's session. These scripts do not rewrite the earlier native-runtime template or its validation steps.

`systemctl enable docker` enables Docker when this WSL distro starts. It does not register a Windows startup task, guarantee WSL stays running after logout, or automatically start the distro when Windows boots. Open `wsl -d Ubuntu-24.04` to start your lab and check `sudo systemctl status docker`. If the WSL IP changed and Swarm is unhealthy, inspect membership and addressing; the scripts intentionally do not destroy/reinitialize your cluster.

## Validation

Bash syntax and sample YAML parsing were checked in the authoring environment. Windows feature installation, PowerShell execution, WSL boot, nested virtualization, APT installation, Docker smoke tests, and Swarm runtime tests have not been run on your VM. This archive contains scripts, not an already-configured VM.

## Primary sources

- https://learn.microsoft.com/en-us/windows/wsl/install-on-server
- https://learn.microsoft.com/en-us/windows/wsl/systemd
- https://learn.microsoft.com/en-us/windows/wsl/networking
- https://docs.docker.com/engine/install/ubuntu/
- https://docs.docker.com/compose/install/linux/
- https://docs.docker.com/engine/swarm/
