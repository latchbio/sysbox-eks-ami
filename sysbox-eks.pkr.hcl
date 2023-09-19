source "amazon-ebs" "ubuntu-eks" {
  ami_name        = "${var.img_name}/sysbox-eks_${var.sysbox_version}/k8s_${var.k8s_version}/ubuntu-${var.ubuntu_version}-${var.architecture}-server/${var.img_version}"
  ami_description = "Sysbox EKS Node (k8s_${var.k8s_version}), on Ubuntu ${var.ubuntu_version} (${var.architecture}) Maintained by Plural."

  region        = "us-east-2"
  instance_type = local.instance_type
  ami_regions   = var.aws_target_regions

  tags = {
    Linux         = "Ubuntu"
    UbuntuRelease = split("-", var.ubuntu_version)[0]
    UbuntuVersion = split("-", var.ubuntu_version)[1]
    Arch          = "${var.architecture}"
    K8sVersion    = var.k8s_version
    SysboxVersion = var.sysbox_version

    BaseImageID      = "{{ .SourceAMI }}"
    BaseImageOwnerID = "{{ .SourceAMIOwner }}"

    BaseImageOwnerName = "{{ .SourceAMIOwnerName }}"
    BaseImageName      = "{{ .SourceAMIName }}"
  }

  source_ami_filter {
    filters = {
      name = "ubuntu-eks/k8s_${var.k8s_version}/images/hvm-ssd/ubuntu-${var.ubuntu_version}-${var.architecture}-server-*"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  ssh_username          = "ubuntu"
  ami_groups            = ["all"]
  force_deregister      = true
  force_delete_snapshot = true
}

locals {
  instance_type = var.architecture == "amd64" ? "t3.micro" : "t4g.micro"
}
