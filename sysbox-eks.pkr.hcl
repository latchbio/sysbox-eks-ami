source "amazon-ebs" "ubuntu-eks" {
  ami_name        = "${var.img_name}/sysbox-eks_${var.sysbox_version}/k8s_${var.k8s_version}/images/hvm-ssd/ubuntu-${var.ubuntu_version}-amd64-server"
  ami_description = "Sysbox EKS Node (k8s_${var.k8s_version}), on Ubuntu ${var.ubuntu_version}, amd64 image"

  region        = "us-west-2"
  instance_type = "t2.micro"
  ami_regions   = var.aws_target_regions

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
      name = "ubuntu-eks/k8s_${var.k8s_version}/images/hvm-ssd/ubuntu-${var.ubuntu_version}-amd64-server-*"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  ssh_username          = "ubuntu"
  # ami_groups            = ["all"] # TODO: uncomment when ready to make public
  force_deregister      = true
  force_delete_snapshot = true
}
