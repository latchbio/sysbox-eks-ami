variable "ubuntu_version" {

  default = "focal-20.04"

  validation {
    condition     = can(regex("^\\w+-\\d+\\.\\d+$", var.ubuntu_version))
    error_message = "Invalid Ubuntu version: expected '{name}-{major}.{minor}'."
  }
}

variable "sysbox_version" {
  type    = string
  default = "0.6.7"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.sysbox_version))
    error_message = "Invalid Sysbox version: expected '{major}.{minor}.{patch}'."
  }
}

variable "k8s_version" {
  type    = string
  default = "1.28"

  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.k8s_version))
    error_message = "Invalid K8s version: expected '{major}.{minor}'."
  }
}

variable "cuda_driver_version" {
  type    = string
  default = "530.30.02"
}

packer {
  required_plugins {
    amazon = {
      version = "= 1.0.9"
      source  = "github.com/hashicorp/amazon"
    }
    git = {
      version = ">= 0.5.0"
      source  = "github.com/ethanmdavidson/git"
    }

  }
}

data "git-commit" "current" {}

local "git_branch" {
  expression = "${substr(data.git-commit.current.hash, 0, 4)}-${replace(element(data.git-commit.current.branches, 0), "/", "-")}"
}

local "ami_name" {
  expression = "latch-bio/sysbox-eks_0.6.7/1.28/focal-20.04-amd64-server/nvidia-530.30.02-0ubuntu1"
}

source "amazon-ebs" "ubuntu-eks" {
  ami_name        = local.ami_name
  ami_description = "Latch Bio, Sysbox EKS Node (k8s_${var.k8s_version}) with NVIDIA GPU support, on Ubuntu ${var.ubuntu_version}, amd64 image."

  tags = {
    Linux         = "Ubuntu"
    UbuntuRelease = split("-", var.ubuntu_version)[0]
    UbuntuVersion = split("-", var.ubuntu_version)[1]
    Arch          = "amd64"
    K8sVersion    = var.k8s_version
    SysboxVersion = var.sysbox_version

    BaseImageID      = "{{ .SourceAMI }}"
    BaseImageOwnerID = "{{ .SourceAMIOwner }}"

    BaseImageOwnerName = "{{ .SourceAMIOwnerName }}"
    BaseImageName      = "{{ .SourceAMIName }}"
  }

  source_ami_filter {
    filters = {
      name = "latch-bio/sysbox-eks_0.6.4/k8s_1.28/ubuntu-focal-20.04-amd64-server/nvidia-530.30.02-0ubuntu1/latch-69cb-maximsmol-swap"
    }
    owners = ["812206152185"]
  }

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 30
    volume_type = "gp3"
    delete_on_termination = true
  }

  region        = "us-west-2"
  instance_type = "t2.micro"
  ssh_username  = "ubuntu"
  temporary_key_pair_type = "ed25519"
  ssh_handshake_attempts = 100
}

build {
  name = "sysbox-eks-incremental"
  sources = [
    "source.amazon-ebs.ubuntu-eks",
  ]

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",
      "export DEBIAN_FRONTEND=noninteractive",

      # https://github.com/nestybox/sysbox/blob/b25fe4a3f9a6501992f8bb3e28d206302de9f33b/docs/user-guide/install-package.md#installing-sysbox
      "echo '>>> Sysbox'",
      "echo Downloading the Sysbox package",
      "wget https://downloads.nestybox.com/sysbox/releases/v${var.sysbox_version}/sysbox-ce_${var.sysbox_version}-0.linux_amd64.deb",

      "echo Installing Sysbox package dependencies",

      "sudo apt-get install rsync -y",

      "echo Installing the Sysbox package",
      "sudo dpkg --install ./sysbox-ce_*.linux_amd64.deb || true", # will fail due to missing dependencies, fixed in the next step

      "echo 'Fixing the Sysbox package (installing dependencies)'",

      "sudo --preserve-env=DEBIAN_FRONTEND apt-get install --fix-broken --yes --no-install-recommends",

      "echo Cleaning up",
      "rm ./sysbox-ce_*.linux_amd64.deb",
    ]
  }

  provisioner "file" {
    source      = "cloud-init-local.service.d/10-wait-for-net-device.conf"
    destination = "/home/ubuntu/10-wait-for-net-device.conf"
  }

  provisioner "file" {
    source      = "udev/10-ec2imds.rules"
    destination = "/home/ubuntu/10-ec2imds.rules"
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",
      "",
      "echo '>>> Installing cloud-init network device wait configuration'",
      "sudo mkdir -p /etc/systemd/system/cloud-init-local.service.d",
      "sudo mv /home/ubuntu/10-wait-for-net-device.conf /etc/systemd/system/cloud-init-local.service.d/",
      "",
      "sudo mkdir -p /etc/udev/rules.d",
      "sudo mv /home/ubuntu/10-ec2imds.rules /etc/udev/rules.d/",
      "",
      "sudo systemctl daemon-reload"
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Configuring KVM support'",
      "sudo modprobe kvm",

      "echo 'kvm' | sudo tee -a /etc/modules",

      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/kvm",

      "sudo systemctl restart crio",

      # configure /dev/kvm perms to allow containers to r/w to it
      "echo 'KERNEL==\"kvm\", MODE=\"0666\"' | sudo tee /etc/udev/rules.d/99-kvm-permissions.rules > /dev/null",
      "sudo udevadm control --reload-rules",
      "sudo udevadm trigger"
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Configuring IPv6 prioritization'",
      "echo 'label ::/0          100' | sudo tee -a /etc/gai.conf"
    ]
  }
}
