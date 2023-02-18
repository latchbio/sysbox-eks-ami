variable "ubuntu_version" {
  type    = string
  default = "focal-20.04"

  validation {
    condition     = can(regex("^\\w+-\\d+\\.\\d+$", var.ubuntu_version))
    error_message = "Invalid Ubuntu version: expected '{name}-{major}.{minor}'."
  }
}

variable "sysbox_version" {
  type    = string
  default = "0.5.0"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.sysbox_version))
    error_message = "Invalid Sysbox version: expected '{major}.{minor}.{patch}'."
  }
}

variable "k8s_version" {
  type    = string
  default = "1.21"

  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.k8s_version))
    error_message = "Invalid K8s version: expected '{major}.{minor}'."
  }
}

packer {
  required_plugins {
    amazon = {
      version = "= 1.0.9"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu-eks" {
  ami_name        = "latch-bio/sysbox-eks-no-net/k8s_${var.k8s_version}/images/hvm-ssd/ubuntu-${var.ubuntu_version}-amd64-server"
  ami_description = "Latch Bio, Sysbox EKS Node w/ Latch Pod Runtime (k8s_${var.k8s_version}), on Ubuntu ${var.ubuntu_version}, amd64 image"

  tags = {
    Linux         = "Ubuntu"
    UbuntuRelease = split("-", var.ubuntu_version)[0]
    UbuntuVersion = split("-", var.ubuntu_version)[1]
    Arch          = "amd64"
    K8sVersion    = var.k8s_version
    SysboxVersion = var.sysbox_version

    BaseImage = "{{ .SourceAMIName }}"
  }

  source_ami_filter {
    filters = {
      name = "latch-bio/sysbox-eks/k8s_${var.k8s_version}/images/hvm-ssd/ubuntu-${var.ubuntu_version}-amd64-server"
    }
    most_recent = true
    owners      = ["812206152185"]
  }

  region        = "us-west-2"
  instance_type = "t2.micro"
  ssh_username  = "ubuntu"
}

build {
  name = "sysbox-eks"
  sources = [
    "source.amazon-ebs.ubuntu-eks"
  ]

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "echo 'Removing /etc/cni/net.d'",
      "sudo rm -r /etc/cni/net.d/",
    ]
  }
}
