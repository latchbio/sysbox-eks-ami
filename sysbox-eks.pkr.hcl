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
  default = "1.20"

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
  ami_name        = "latch-bio/sysbox-eks/k8s_${var.k8s_version}/images/hvm-ssd/ubuntu-${var.ubuntu_version}-amd64-server"
  ami_description = "Latch Bio, Sysbox EKS Node (k8s_${var.k8s_version}), on Ubuntu ${var.ubuntu_version}, amd64 image"

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
      name = "ubuntu-eks/k8s_${var.k8s_version}/images/hvm-ssd/ubuntu-${var.ubuntu_version}-amd64-server-*"
    }
    most_recent = true
    owners      = ["099720109477"]
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
    inline = [
      "echo Updating apt",
      "sudo apt-get update"
    ]
  }

  provisioner "shell" {
    inline = [
      # https://github.com/nestybox/sysbox/blob/b25fe4a3f9a6501992f8bb3e28d206302de9f33b/docs/user-guide/install-package.md#installing-sysbox
      "echo '>>> Sysbox'",
      "echo Downloading the Sysbox package",
      "wget https://downloads.nestybox.com/sysbox/releases/v${var.sysbox_version}/sysbox-ce_${var.sysbox_version}-0.linux_amd64.deb",

      "echo Installing the Sysbox package",
      "sudo dpkg --install ./sysbox-ce_*.linux_amd64.deb || true", # will fail due to missing dependencies, fixed in the next step

      "echo 'Fixing the Sysbox package (installing dependencies)'",
      "sudo apt-get install --fix-broken --yes --no-install-recommends",

      "echo Cleaning up",
      "rm ./sysbox-ce_*.linux_amd64.deb",
    ]
  }

  provisioner "shell" {
    inline = [
      # https://github.com/nestybox/sysbox/blob/b25fe4a3f9a6501992f8bb3e28d206302de9f33b/docs/user-guide/install-package.md#installing-shiftfs
      "echo '>>> Shiftfs'",

      "echo Installing dependencies",
      "sudo apt-get install --yes --no-install-recommends make dkms",

      "echo Cloning the repository",
      # todo(maximsmol): somehow detect the kernel version instead
      "git clone --branch k5.13 --depth 1 --shallow-submodules https://github.com/toby63/shiftfs-dkms.git shiftfs",
      "cd shiftfs",

      "echo Running the update script",
      "./update1",

      "echo Building and installing",
      "sudo make --file Makefile.dkms",

      "echo Cleaning up",
      "cd ..",
      "rm -rf shiftfs"
    ]
  }

  provisioner "shell" {
    inline = [
      # https://github.com/cri-o/cri-o/blob/a68a72071e5004be78fe2b1b98cb3bfa0e51b74b/install.md#apt-based-operating-systems
      "echo '>>> CRI-O'",

      # fixme(maximsmol): take into account ${ubuntu_version}
      "export OS='xUbuntu_20.04'",
      "export VERSION='${var.k8s_version}'",

      "echo Adding repositories",
      "echo \"deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /\" | sudo dd status=none of=/etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list",
      "echo \"deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /\" | sudo dd status=none of=/etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list",

      "echo Adding keys",
      "mkdir --parents /usr/share/keyrings",
      "curl --location https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/Release.key | sudo gpg --dearmor --output /usr/share/keyrings/libcontainers-archive-keyring.gpg",
      "curl --location https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo gpg --dearmor --output /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg",

      "echo Updating apt",
      "sudo apt-get update",

      "echo Installing CRI-O",
      "sudo apt-get install --yes --no-install-recommends cri-o cri-o-runc cri-tools",

      "echo Enabling CRI-O at startup",
      "sudo systemctl enable crio"
    ]
  }

  provisioner "file" {
    source      = "crio"
    destination = "/home/ubuntu/crio"
    max_retries = 3
  }
  provisioner "shell" {
    inline = [
      "sudo mv crio /usr/bin/crio",
      "sudo chmod +x /usr/bin/crio"
    ]
  }

  # provisioner "shell" {
  #   inline = [
  #     "echo '>>> Sysbox CRI-O patch'",
  #     "echo Adding the Go backports repository",
  #     "sudo apt-get install --yes --no-install-recommends software-properties-common",
  #     "sudo add-apt-repository --yes ppa:longsleep/golang-backports",

  #     "echo Installing Go",
  #     "sudo apt-get update",
  #     # todo(maximsmol): lock the golang version
  #     "sudo apt-get install --yes --no-install-recommends golang-go libgpgme-dev",

  #     "echo Cloning the patched CRI-O repository",
  #     "git clone --branch v1.23-sysbox --depth 1 --shallow-submodules https://github.com/nestybox/cri-o.git cri-o",

  #     "echo Building",
  #     "cd cri-o",
  #     "make binaries",

  #     "echo Installing the patched binary",
  #     "sudo mv bin/crio /usr/bin/crio",

  #     "echo Cleaning up",
  #     "cd ..",
  #     "rm -rf cri-o",

  #     "echo Restarting CRI-O",
  #     "sudo systemctl restart crio"
  #   ]
  # }

  provisioner "shell" {
    inline = [
      # Much of the rest of this is from inside the Sysbox K8s installer image
      "echo '>>> Doing basic CRI-O configuration'",

      "echo Installing Dasel",
      "sudo curl --location \"$(curl --silent --show-error --location https://api.github.com/repos/tomwright/dasel/releases/latest | grep browser_download_url | grep linux_amd64 | cut -d\\\" -f 4)\" --output /usr/local/bin/dasel",
      "sudo chmod +x /usr/local/bin/dasel",

      # todo(maximsmol): do this only when K8s is configured without systemd cgroups (from sysbox todos)
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.cgroup_manager' 'cgroupfs'",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.conmon_cgroup' 'pod'",
      #
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple SETFCAP",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple AUDIT_WRITE",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple NET_RAW",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple SYS_CHROOT",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple MKNOD",
      #
      "sudo dasel put int --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.pids_limit' 16384",
      #
      "echo 'containers:231072:1048576' | sudo tee --append /etc/subuid",
      "echo 'containers:231072:1048576' | sudo tee --append /etc/subgid",

      "echo Configuring Kubelet to use CRI-O",
      "sudo snap stop kubelet-eks",
      "sudo snap set kubelet-eks container-runtime=remote",
      "sudo snap set kubelet-eks container-runtime-endpoint=unix:///var/run/crio/crio.sock",
      # The EKS boot script resets this otherwise:
      "sudo sed --in-place 's/CONTAINER_RUNTIME=\"dockerd\"/CONTAINER_RUNTIME=\"remote\"/' /etc/eks/bootstrap.sh",
      "perl -0777 -i.bkp -p -e 's/echo \"Container runtime \\$\\{CONTAINER_RUNTIME\\} is not supported.\"\\n    exit 1/echo \"Custom container runtime\"/' /etc/eks/bootstrap.sh"
    ]
  }

  provisioner "shell" {
    inline = [
      "echo '>>> Configuring CRI-O for Sysbox'",

      "echo Adding Sysbox to CRI-O runtimes",
      "sudo dasel put object --parser toml --selector 'crio.runtime.runtimes.sysbox-runc' --file /etc/crio/crio.conf --type string 'runtime_path=/usr/bin/sysbox-runc' --type string 'runtime_type=oci'",
      "sudo dasel put string --parser toml --selector 'crio.runtime.runtimes.sysbox-runc.allowed_annotations.[0]' --file /etc/crio/crio.conf 'io.kubernetes.cri-o.userns-mode'",
    ]
  }
}
