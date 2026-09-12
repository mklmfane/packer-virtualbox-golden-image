# Validation

Passed in the authoring environment:

- Four Packer HCL files parsed with python-hcl2 (syntax only).
- Representative answer-file XML rendered and parsed, including an escaped image name.
- Python prepare helper syntax parsed.
- Both workload YAML files parsed.
- Source configuration checked for HTTPS/NTLM and no build-time Swarm initialization.
- Preparation tested with temporary dummy files: matching hashes, payload manifest, private file permissions, refusal to overwrite existing generated files.

Not executed: Packer plugin validation/build, Windows installation, PowerShell parsing or execution, VirtualBox boot, Docker installation/runtime, Windows 11 nested Hyper-V, Sysprep, clone identity, Compose workloads, or multi-node Swarm networking. No ready-made VM image or production support claim is included.

Use real, vendor-verified payloads with prepare.py, run packer validate, and build Server 2022 first. Do not interpret successful syntax checks as proof of a successful Windows build.
