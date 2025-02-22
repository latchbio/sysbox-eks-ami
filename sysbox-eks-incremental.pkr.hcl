variable "ubuntu_version" {

  default = "focal-20.04"

  validation {
    condition     = can(regex("^\\w+-\\d+\\.\\d+$", var.ubuntu_version))
    error_message = "Invalid Ubuntu version: expected '{name}-{major}.{minor}'."
  }
}

variable "sysbox_version" {
  type    = string
  default = "0.6.4"

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
  expression = "latch-bio/sysbox-eks_0.6.4/1.28/focal-20.04-amd64-server/nvidia-530.30.02-0ubuntu1/latch-69cb-maximsmol-swap/gai-patch"
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

      "echo '>>> Configuring IPv6 prioritization'",
      "echo 'label ::/0          100' | sudo tee -a /etc/gai.conf"
    ]
  }
}
