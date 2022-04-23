# Sysbox EKS AMI

Packer script for building an AMI with pre-installed Sysbox based on an Ubuntu EKS AMI.

## Usage

1. Install [HashiCorp Packer](https://www.packer.io/downloads)
1. Run `just init`
1. Ensure you have a patched CRI-O binary
1. Run `just build`

## Differences from the Ubuntu EKS AMI

- Installs Sysbox
- Installs `shiftfs`
- Installs CRI-O + patches the binary using the Sysbox fork
- Configures CRI-O as the Sysbox Kubernetes installer would
- Configures CRI-O to work with Sysbox
- Sets `kubelet-eks` to use CRI-O by default
- Adds Sysbox to the list of CRI-O runtimes
