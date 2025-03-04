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

variable "cuda_version" {
  type    = string
  default = "12.6.3"
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
  expression = "latch-bio/sysbox-eks_${var.sysbox_version}/k8s_${var.k8s_version}/ubuntu-${var.ubuntu_version}-arm64-server/latch-${local.git_branch}"
}

source "amazon-ebs" "ubuntu-eks" {
  ami_name        = local.ami_name
  ami_description = "Latch Bio, Sysbox EKS Node (k8s_${var.k8s_version}) on Ubuntu ${var.ubuntu_version}, arm64 image."

  tags = {
    Linux         = "Ubuntu"
    UbuntuRelease = split("-", var.ubuntu_version)[0]
    UbuntuVersion = split("-", var.ubuntu_version)[1]
    Arch          = "arm64"
    K8sVersion    = var.k8s_version
    SysboxVersion = var.sysbox_version

    BaseImageID      = "{{ .SourceAMI }}"
    BaseImageOwnerID = "{{ .SourceAMIOwner }}"

    BaseImageOwnerName = "{{ .SourceAMIOwnerName }}"
    BaseImageName      = "{{ .SourceAMIName }}"
  }

  source_ami_filter {
    filters = {
      name = "ubuntu-eks/k8s_${var.k8s_version}/images/hvm-ssd/ubuntu-${var.ubuntu_version}-arm64-server-20241204"
    }
    owners = ["099720109477"]
  }

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 30
    volume_type = "gp3"
    delete_on_termination = true
  }

  region        = "us-west-2"
  instance_type = "c6g.large"
  ssh_username  = "ubuntu"
  temporary_key_pair_type = "ed25519"
  ssh_handshake_attempts = 100
}

build {
  name = "sysbox-eks"
  sources = [
    "source.amazon-ebs.ubuntu-eks",
  ]

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Use cgroup2'",
      "sudo sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty1 console=ttyS0 nvme_core.io_timeout=4294967295\"/GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty1 console=ttyS0 nvme_core.io_timeout=4294967295 systemd.unified_cgroup_hierarchy=1\"/g' /etc/default/grub.d/50-cloudimg-settings.cfg",
      "sudo update-grub",
      "sudo systemctl reboot"
    ]

    expect_disconnect = true
    skip_clean        = true
    pause_after       = "10s"
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo Updating apt",
      "sudo apt update --yes",
      "sudo apt-get update --yes",
      "sudo apt-get install --yes build-essential git",
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Installing latch'",
      "curl --location --fail --remote-name https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-aarch64.sh",
      "sudo bash Miniforge3-Linux-aarch64.sh -b -p /opt/miniforge -u",
      "rm Miniforge3-Linux-aarch64.sh",

      "sudo /opt/miniforge/bin/conda create --copy -y -p /opt/latch-env python=3.11",
      "sudo /opt/latch-env/bin/pip install --upgrade latch"
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",
      "export DEBIAN_FRONTEND=noninteractive",

      "echo '>>> Sysbox'",
      "echo Downloading the Sysbox package",
      "wget https://downloads.nestybox.com/sysbox/releases/v${var.sysbox_version}/sysbox-ce_${var.sysbox_version}-0.linux_arm64.deb",

      "echo Installing Sysbox package dependencies",
      "sudo apt-get install rsync -y",

      "echo Installing the Sysbox package",
      "sudo dpkg --install ./sysbox-ce_*.linux_arm64.deb || true",

      "echo 'Fixing the Sysbox package (installing dependencies)'",
      "sudo --preserve-env=DEBIAN_FRONTEND apt-get install --fix-broken --yes --no-install-recommends",

      "echo Cleaning up",
      "rm ./sysbox-ce_*.linux_arm64.deb",
    ]
  }

  provisioner "file" {
    source      = "systemd"
    destination = "/home/ubuntu"
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "echo '>>> Configuring Systemd for Sysbox'",
      "sudo mv /home/ubuntu/systemd/system/sysbox-mgr.service /lib/systemd/system/sysbox-mgr.service",
      "sudo mv /home/ubuntu/systemd/system/sysbox-fs.service /lib/systemd/system/sysbox-fs.service",
      "sudo mv /home/ubuntu/systemd/system/sysbox.service /lib/systemd/system/sysbox.service",
      "sudo mkdir /var/log/sysbox"
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> CRI-O'",
      "export PROJECT_PATH='prerelease:/main'",
      "export VERSION='v${var.k8s_version}'",

      "echo Adding keys and repositories",
      "mkdir --parents /etc/apt/keyrings",

      "curl -fsSL https://pkgs.k8s.io/core:/stable:/$VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg",
      "echo \"deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$VERSION/deb/ /\" | sudo tee /etc/apt/sources.list.d/kubernetes.list",

      "curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/$PROJECT_PATH/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg",
      "echo \"deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/$PROJECT_PATH/deb/ /\" | sudo tee /etc/apt/sources.list.d/cri-o.list",

      "echo Updating apt",
      "sudo apt-get update",

      "echo Installing CRI-O",
      "sudo apt-get install --yes --no-install-recommends cri-o",

      "export CRICTL_VERSION='v${var.k8s_version}.0'",
      "wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-arm64.tar.gz",
      "sudo tar zxvf crictl-$CRICTL_VERSION-linux-arm64.tar.gz -C /usr/local/bin",
      "rm --force crictl-$CRICTL_VERSION-linux-arm64.tar.gz",

      "echo Enabling CRI-O at startup",
      "sudo systemctl enable crio"
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Sysbox CRI-O patch'",
      "echo Adding the Go backports repository",
      "sudo apt-get install --yes --no-install-recommends software-properties-common",
      "sudo add-apt-repository --yes ppa:longsleep/golang-backports",

      "echo Installing Go",
      "sudo apt-get update",
      "sudo apt-get install --yes --no-install-recommends golang-go libgpgme-dev pkg-config libseccomp-dev",

      "echo Cloning the patched CRI-O repository",
      "git clone --branch v${var.k8s_version}-sysbox --depth 1 --shallow-submodules https://github.com/nestybox/cri-o.git cri-o",

      "echo Building",
      "cd cri-o",
      "make binaries",

      "echo Installing the patched binary",
      "sudo mv bin/crio /usr/bin/crio",
      "sudo chmod u+x /usr/bin/crio",

      "echo Cleaning up",
      "cd ..",
      "rm -rf cri-o",

      "echo Restarting CRI-O",
      "sudo systemctl restart crio"
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "echo '>>> Conmon Install'",
      "sudo apt-get install --yes --no-install-recommends libc6-dev libglib2.0-dev runc",
      "git clone https://github.com/containers/conmon.git",
      "cd conmon",
      "make",
      "sudo make install",
      "cd ..",
      "sudo rm -rf conmon"
    ]
  }

  provisioner "file" {
    source      = "bootstrap.sh.patch"
    destination = "/home/ubuntu/bootstrap.sh.patch"
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "sudo mv /home/ubuntu/bootstrap.sh.patch /usr/local/share/eks/bootstrap.sh.patch",
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Doing basic CRI-O configuration'",

      "echo Installing Dasel",
      "sudo curl --location https://github.com/TomWright/dasel/releases/download/v1.24.3/dasel_linux_arm64 --output /usr/local/bin/dasel",
      "sudo chmod u+x /usr/local/bin/dasel",

      "sudo touch /etc/crio/crio.conf",

      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.cgroup_manager' 'cgroupfs'",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.conmon_cgroup' 'pod'",

      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple CHOWN",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple DAC_OVERRIDE",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple FSETID",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple FOWNER",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple MKNOD",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple NET_RAW",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple SETGID",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple SETUID",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple SETFCAP",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple SETPCAP",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple NET_BIND_SERVICE",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple SYS_CHROOT",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple KILL",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple AUDIT_WRITE",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.default_capabilities.[]' --multiple LINUX_IMMUTABLE",

      "sudo dasel put int --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.pids_limit' 16384",

      "echo 'containers:231072:1048576' | sudo tee --append /etc/subuid",
      "echo 'containers:231072:1048576' | sudo tee --append /etc/subgid",

      "sudo patch --backup /usr/local/share/eks/bootstrap.sh /usr/local/share/eks/bootstrap.sh.patch"
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Configuring CRI-O for Sysbox'",

      "echo Adding Sysbox to CRI-O runtimes",
      "sudo dasel put object --parser toml --selector 'crio.runtime.runtimes.sysbox-runc' --file /etc/crio/crio.conf --type string 'runtime_path=/usr/bin/sysbox-runc' --type string 'runtime_type=oci'",
      "sudo dasel put string --parser toml --selector 'crio.runtime.runtimes.sysbox-runc.allowed_annotations.[0]' --file /etc/crio/crio.conf 'io.kubernetes.cri-o.userns-mode'",
      "sudo dasel put string --parser toml --selector 'crio.runtime.runtimes.sysbox-runc.allowed_annotations.[1]' --file /etc/crio/crio.conf 'io.kubernetes.cri-o.Devices'",
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Removing /etc/cni/net.d'",
      "sudo rm -r /etc/cni/net.d/",
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Patching kubelet config'",
      "sudo dasel put bool --parser json --file /etc/kubernetes/kubelet/kubelet-config.json --selector 'failSwapOn' false",
      "sudo dasel put boolean --parser json --file /etc/kubernetes/kubelet/kubelet-config.json --selector 'featureGates.NodeSwap' true",
      "sudo dasel put string --parser json --file /etc/kubernetes/kubelet/kubelet-config.json --selector 'memorySwap.swapBehavior' 'UnlimitedSwap'",
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
      "sudo modprobe kvm_intel",
      "sudo modprobe kvm_amd",

      "echo 'kvm' | sudo tee -a /etc/modules",
      "echo 'kvm_intel' | sudo tee -a /etc/modules",
      "echo 'kvm_amd' | sudo tee -a /etc/modules",

      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/kvm",

      "sudo systemctl restart crio"
    ]
  }
}
