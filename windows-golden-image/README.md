# Server 2022: Guest Additions + automatic WSL post-deployment

Apply this overlay to the existing `windows-golden-image` project. Back up the corresponding files before replacing them. Preserve your `prepare.py`, generated values, `shared/Autounattend.xml.pkrtpl` and `Bootstrap-WinRM.ps1`.

Replace BOTH `server2022/windows.pkr.hcl` and `server2022/variables.pkr.hcl`, and copy the included shared scripts to `shared/scripts/`. Do not leave duplicate variables/source blocks in another `.pkr.hcl` file in the same folder.

## What changes

1. Packer retrieves the Guest Additions ISO matching the HOST VirtualBox version and uploads it to Windows.
2. The PowerShell installer mounts it, checks the Oracle installer signature, installs Guest Additions silently, then Packer reboots.
3. VBoxService and VBoxControl checks must succeed before continuing.
4. Windows Containers, WSL and Virtual Machine Platform are enabled once. Another reboot and Guest Additions/feature check follows.
5. A scheduled task is registered for the first post-deployment administrator logon.
6. Sysprep generalizes and shuts down the image for export.
7. After import, OOBE and final administrator sign-in, the task automatically installs the Microsoft-signed WSL MSI, imports checksum-verified Canonical Ubuntu 24.04, enables systemd, and installs Linux Docker Engine, Buildx and Compose from Docker's repository.
8. Optional single-node Swarm initialization runs only AFTER deployment. Swarm commands are part of Docker Engine regardless of this option.

The obsolete native `Install-ServerRuntime.ps1` and duplicate `Enable-Features.ps1` calls were removed from the build. Older scripts may remain in your shared directory, but the new template does not invoke them.

## Guest Additions versus VirtualBox

Install VirtualBox itself on the outer Ubuntu host. Install VirtualBox **Guest Additions** inside Windows. These are different products. Installing the host hypervisor package inside Windows is not how to obtain guest display, mouse, shared-folder or integration drivers.

The template uses VBoxSVGA, 128 MiB video memory, and disabled 3D acceleration. The hardware RTC remains UTC; Windows is set to `GTB Standard Time` (Bucharest, automatic EET/EEST) and Ubuntu to `Europe/Bucharest`. If your answer file currently says UTC, change its `<TimeZone>` to `GTB Standard Time` too.

Matching Guest Additions and reboot checks reduce configuration errors; they cannot guarantee that your CPU/host VirtualBox version can run nested WSL 2. A screenshot or exact stop code is required to diagnose the existing unbootable VM. This package builds a fresh image; it does not repair that VM or remove its disks.

## Disk and RAM

Defaults are 4 vCPU, 8 GiB RAM and a 100 GiB disk. Your former 30 GiB disk is too constrained for Server 2022 plus a WSL virtual disk, updates and container images. Values in generated/values.pkrvars.hcl, if present for memory/disk_size/cpus, override these defaults. Change those too if needed. A new disk_size affects new builds only, not an existing export.

## Build

From the existing project root, after applying the overlay:

```bash
cd server2022
packer init . &&
packer fmt . &&
packer validate -var-file=generated/values.pkrvars.hcl . &&
packer build -var-file=generated/values.pkrvars.hcl .
```

Move an existing `output-server2022` directory to a backup before rebuilding. Preserve the failed VM separately for diagnosis.

For automatic independent SINGLE-NODE Swarm initialization in each deployed VM, add:

```hcl
initialize_swarm = true
```

to generated/values.pkrvars.hcl before building. It defaults to false so clones do not accidentally create separate clusters when you intended a shared manager/worker cluster. Linux Swarm tooling is installed automatically in either case.

## Exactly when automatic setup runs

WSL distributions are registered per Windows user. For that reason, the image does not register Ubuntu under the temporary `packer` account that sealing disables.

Import the OVF, finish normal Windows OOBE and sign in with your intended final LOCAL administrator account. The task `WindowsLab-PostDeploy` runs automatically with that account's highest privileges. There is no need to type the manual `-Stage Ubuntu`, `Docker` or `Verify` commands.

This is automatic **first-administrator-logon** provisioning, not pre-login SYSTEM provisioning. The task explicitly ignores SYSTEM and the temporary `packer` user. It binds to the first final administrator SID so a second administrator does not accidentally install a second distro. Do not use the temporary account as the final user.

If the WSL MSI requires a reboot, Windows schedules one in 60 seconds; sign in with the SAME account afterward and installation resumes automatically. No password or auto-login credential is stored. The task retries failures up to three times, five minutes apart, and retries again on a later sign-in. It marks completion only after Docker verification passes and then disables itself.

An active network connection and working DNS/TLS are required. Runtime/rootfs URLs resolve stable/current downloads at execution time, not fixed versions; the runtime MSI signature and rootfs checksum are checked. Installed Docker package versions are recorded inside Ubuntu. For reproducible production builds, use a managed, pinned artifact source.

## Progress and verification

On Windows, PowerShell:

```powershell
Get-ScheduledTask -TaskName WindowsLab-PostDeploy
Get-ScheduledTaskInfo -TaskName WindowsLab-PostDeploy
Get-ChildItem C:\ProgramData\WindowsLab\logs
Get-Content C:\ProgramData\WindowsLab\last-error.txt -ErrorAction SilentlyContinue
Get-Content C:\ProgramData\WindowsLab\complete.json -ErrorAction SilentlyContinue
```

Logs are `C:\ProgramData\WindowsLab\logs\postdeploy-*.log`. This directory is limited to administrators and SYSTEM. If Swarm initialization is enabled, Docker's ordinary initialization output includes a join token; treat logs as sensitive.

After completion, under the owning Windows account:

```powershell
wsl --list --verbose
wsl -d Ubuntu-24.04 -u root -- docker version
wsl -d Ubuntu-24.04 -u root -- docker compose version
wsl -d Ubuntu-24.04 -u root -- docker info
```

The engine OS must be `linux`. Windows Containers is an OS feature; native Windows containers require a separate Windows engine. This setup intentionally installs the requested engine inside WSL.

WSL does not necessarily start at Windows boot or stay running after its owning user logs out. The installation task is not a persistent workload supervisor. WSL NAT addresses also require separate network design for multi-VM Swarm; TCP portproxy alone cannot carry Swarm's UDP overlay traffic.

## Existing boot failure

Do not delete the unbootable VM or its disk. Record whether you installed the full Windows VirtualBox host installer or VBoxWindowsAdditions.exe, capture the exact boot message/Windows stop code, and identify whether failure began before or after enabling WSL/Virtual Machine Platform. Recovery differs for graphics drivers, storage drivers, and nested-hypervisor failures.

## Validation limits

HCL parsing, embedded Bash syntax and structural workflow checks were performed. Windows/PowerShell execution, real Guest Additions installation, Sysprep, final-user scheduled-task behavior and nested WSL boot still require host testing. Packer runtime checks will stop a build that fails its reboot/service gates; they are not a guarantee of future hardware compatibility.

Primary references:

- https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/iso
- https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/guestadditions.html
- https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal
- https://learn.microsoft.com/en-us/windows/wsl/install
