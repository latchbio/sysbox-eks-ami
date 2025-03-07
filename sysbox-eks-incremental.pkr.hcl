variable "ubuntu_version" {

  default = "jammy-22.04"

  validation {
    condition     = can(regex("^\\w+-\\d+\\.\\d+$", var.ubuntu_version))
    error_message = "Invalid Ubuntu version: expected '{name}-{major}.{minor}'."
  }
}

variable "sysbox_version" {
  type    = string
  default = "0.6.5"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.sysbox_version))
    error_message = "Invalid Sysbox version: expected '{major}.{minor}.{patch}'."
  }
}

variable "k8s_version" {
  type    = string
  default = "1.29"

  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.k8s_version))
    error_message = "Invalid K8s version: expected '{major}.{minor}'."
  }
}

variable "cuda_driver_version" {
  type    = string
  default = "560.35.05"
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
  expression = "latch-bio/sysbox-eks_0.6.5/k8s_1.29/jammy-22.04-amd64-server/nvidia-560.35.05/kvm-support-ccf4"
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
      name = "latch-bio/sysbox-eks_0.6.5/k8s_1.29/ubuntu-jammy-22.04-amd64-server/nvidia-560.35.05/latch-92cf-aidan-latest-gpu-drivers"
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

      "echo '>>> Configuring KVM support'",
      "sudo modprobe kvm",

      "echo 'kvm' | sudo tee -a /etc/modules",

      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/kvm",

      "sudo systemctl restart crio"

      # configure /dev/kvm perms to allow containers to r/w to it
      "echo 'KERNEL==\"kvm\", MODE=\"0666\"' | sudo tee /etc/udev/rules.d/99-kvm-permissions.rules > /dev/null",
      "sudo udevadm control --reload-rules",
      "sudo udevadm trigger"
    ]
  }
}
