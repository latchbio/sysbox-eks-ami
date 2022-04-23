# Sysbox EKS AMI

Packer script for building an AMI with pre-installed Sysbox based on an Ubuntu EKS AMI.

## Usage

1. Install [HashiCorp Packer](https://www.packer.io/downloads)
1. Run `packer init .`
1. Ensure you have a patched CRI-O binary (for the Linux kernel 5.13)
   [The packer definition](./sysbox-eks.pkr.hcl) contains commented-out instructions on building the patched binary as part of the packer build. This is a very slow process so by default it copies the file instead. You could run the same commands on any Ubuntu 20.04 system and `scp` the binary to use it here.
1. Run `packer build sysbox-eks.pkr.hcl`

## Differences from the Ubuntu EKS AMI

- Installs Sysbox
- Installs `shiftfs`
- Installs CRI-O + patches the binary using the Sysbox fork
- Configures CRI-O as the Sysbox Kubernetes installer would
- Configures CRI-O to work with Sysbox
- Sets `kubelet-eks` to use CRI-O by default
- Adds Sysbox to the list of CRI-O runtimes

## License/Copying

**Intent:** dedicated to the public domain. To comply with legal precedent and ease adoption in corporate environments, multi-licensed under well-known terms.

**Preferred:** [CC0](https://creativecommons.org/publicdomain/zero/1.0/)

**Alternatives:**

- [BSD0](./licenses/BSD0)
- [MIT](./licenses/MIT)
