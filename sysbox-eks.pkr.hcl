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

variable "nvidia_driver_version" {
  type    = string
  default = "530.30.02-0ubuntu1"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+-.*$", var.nvidia_driver_version))
    error_message = "Invalid NVIDIA driver version: expected '{major}.{minor}.{patch}-{build}'."
  }
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
  expression = "latch-bio/sysbox-eks_${var.sysbox_version}/k8s_${var.k8s_version}/ubuntu-${var.ubuntu_version}-amd64-server/nvidia-${var.nvidia_driver_version}/latch-${local.git_branch}"
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
      name = "ubuntu-eks/k8s_${var.k8s_version}/images/hvm-ssd/ubuntu-${var.ubuntu_version}-amd64-server-20240411"
    }
    owners = ["099720109477"]
  }

  region        = "us-west-2"
  instance_type = "t2.micro"
  ssh_username  = "ubuntu"
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
      "sudo apt-get update -y",
    ]
  }


  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Installing latch'",
      "curl --location --fail --remote-name https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Linux-x86_64.sh",
      "sudo bash Mambaforge-Linux-x86_64.sh -b -p /opt/mamba -u",
      "rm Mambaforge-Linux-x86_64.sh",

      "sudo /opt/mamba/bin/mamba create --copy -y -p /opt/latch-env python=3.11",
      "sudo /opt/latch-env/bin/pip install --upgrade latch"
    ]
  }

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

      # https://github.com/nestybox/sysbox/blob/b25fe4a3f9a6501992f8bb3e28d206302de9f33b/docs/user-guide/install-package.md#installing-shiftfs
      "echo '>>> Shiftfs'",

      "echo Installing dependencies",
      "sudo apt-get update",
      "sudo apt-get install --yes --no-install-recommends make dkms git",

      "echo Detecting kernel version to determine the correct branch",
      "export kernel_version=\"$(uname -r | sed --regexp-extended 's/([0-9]+\\.[0-9]+).*/\\1/g')\"",
      "echo \"$kernel_version\"",
      "declare -A kernel_to_branch=( [5.17]=k5.17 [5.16]=k5.16 [5.15]=k5.16 [5.14]=k5.13 [5.13]=k5.13 [5.10]=k5.10 [5.8]=k5.10 [5.4]=k5.4 )",
      "export branch=\"$(echo $${kernel_to_branch[$kernel_version]})\"",

      "echo Cloning the repository branch: $branch",
      "git clone --branch $branch --depth 1 --shallow-submodules https://github.com/toby63/shiftfs-dkms.git shiftfs",
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
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

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
      "sudo apt-get install --yes --no-install-recommends cri-o cri-o-runc",

      "export CRICTL_VERSION='v${var.k8s_version}.0'",
      "wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-amd64.tar.gz",
      "sudo tar zxvf crictl-$CRICTL_VERSION-linux-amd64.tar.gz -C /usr/local/bin",
      "rm --force crictl-$CRICTL_VERSION-linux-amd64.tar.gz",

      "echo Enabling CRI-O at startup",
      "sudo systemctl enable crio"
    ]
  }


  ## Uncomment this section to install from a patched CRI-O binary
  # provisioner "file" {
  #   source      = "crio"
  #   destination = "/home/ubuntu/crio"
  #   max_retries = 3
  # }

  # provisioner "shell" {
  #   inline = [
  #     "echo '>>> Installing prebuilt patched CRI-O'",
  #     "sudo mv crio /usr/bin/crio",

  #     "echo Setting permissions",
  #     "sudo chmod u+x /usr/bin/crio"

  #     # "echo Restarting CRI-O",
  #     # "sudo systemctl restart crio"
  #   ]
  # }

  ## Comment this section to install from a patched CRI-O binary
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
      # todo(maximsmol): lock the golang version
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

  provisioner "file" {
    # reference: https://github.com/awslabs/amazon-eks-ami/blob/main/templates/al2/runtime/bootstrap.sh
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

      # Much of the rest of this is from inside the Sysbox K8s installer image
      "echo '>>> Doing basic CRI-O configuration'",

      "echo Installing Dasel",
      "sudo curl --location https://github.com/TomWright/dasel/releases/download/v1.24.3/dasel_linux_amd64 --output /usr/local/bin/dasel",
      "sudo chmod u+x /usr/local/bin/dasel",

      # todo(maximsmol): do this only when K8s is configured without systemd cgroups (from sysbox todos)
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.cgroup_manager' 'cgroupfs'",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.conmon_cgroup' 'pod'",

      # use containerd/Docker's default capabilities: https://github.com/moby/moby/blob/faf84d7f0a1f2e6badff6f720a3e1e559c356fff/oci/caps/defaults.go
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
      #
      "sudo dasel put int --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.pids_limit' 16384",
      #
      "echo 'containers:231072:1048576' | sudo tee --append /etc/subuid",
      "echo 'containers:231072:1048576' | sudo tee --append /etc/subgid",
      # /usr/local/share/eks/bootstrap.sh is symlinked to /etc/eks/boostrap.sh
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
      "export DEBIAN_FRONTEND=noninteractive",

      "wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb",
      "sudo dpkg -i cuda-keyring_1.0-1_all.deb",
      "rm cuda-keyring_1.0-1_all.deb",

      "sudo apt-get update",
      "sudo --preserve-env=DEBIAN_FRONTEND apt-get --yes --no-install-recommends install libnvidia-common-530=${var.nvidia_driver_version} libnvidia-gl-530=${var.nvidia_driver_version} nvidia-kernel-common-530=${var.nvidia_driver_version} nvidia-dkms-530=${var.nvidia_driver_version} nvidia-kernel-source-530=${var.nvidia_driver_version} libnvidia-compute-530=${var.nvidia_driver_version} libnvidia-extra-530=${var.nvidia_driver_version} nvidia-compute-utils-530=${var.nvidia_driver_version} libnvidia-decode-530=${var.nvidia_driver_version} libnvidia-encode-530=${var.nvidia_driver_version} nvidia-utils-530=${var.nvidia_driver_version} xserver-xorg-video-nvidia-530=${var.nvidia_driver_version} libnvidia-cfg1-530=${var.nvidia_driver_version} libnvidia-fbc1-530=${var.nvidia_driver_version} nvidia-driver-530=${var.nvidia_driver_version} nvidia-container-toolkit",
      "sudo apt-mark hold libnvidia-common-530 libnvidia-gl-530 nvidia-kernel-common-530 nvidia-dkms-530 nvidia-kernel-source-530 libnvidia-compute-530 libnvidia-extra-530 nvidia-compute-utils-530 libnvidia-decode-530 libnvidia-encode-530 nvidia-utils-530 xserver-xorg-video-nvidia-530 libnvidia-cfg1-530 libnvidia-fbc1-530 nvidia-driver-530",

      # enable mounting FUSE device inside of containers
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/fuse",

      # enable mounting NVIDIA devices inside of containers
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/card0",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/card1",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/card2",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/card3",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/card4",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/card5",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/card6",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/card7",

      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/renderD128",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/renderD129",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/renderD130",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/renderD131",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/renderD132",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/renderD133",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/renderD134",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/dri/renderD135",

      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia0",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia1",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia2",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia3",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia4",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia5",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia6",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia7",

      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidiactl",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia-modeset",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia-uvm",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/nvidia-uvm-tools",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf --selector 'crio.runtime.allowed_devices.[]' --multiple /dev/vga_arbiter",

      "sudo dasel put string --parser toml --selector 'crio.runtime.default_runtime' --file /etc/crio/crio.conf 'nvidia'",
      "sudo dasel put object --parser toml --selector 'crio.runtime.runtimes.nvidia' --file /etc/crio/crio.conf --type string 'runtime_path=/usr/bin/nvidia-container-runtime'",
      "sudo dasel delete --parser toml --selector 'nvidia-container-runtime.runtimes' --file /etc/nvidia-container-runtime/config.toml",
      "sudo dasel put string --parser toml --selector 'nvidia-container-runtime.runtimes.[]' --file /etc/nvidia-container-runtime/config.toml 'runc'"
    ]
  }

  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Patching kubelet config'",
      "sudo dasel put bool --parser json --file /etc/kubernetes/kubelet/kubelet-config.json --selector 'failSwapOn' false",
      "sudo dasel put bool --parser json --file /etc/kubernetes/kubelet/kubelet-config.json --selector 'featureGates.NodeSwap' true",
      "sudo dasel put string --parser json --file /etc/kubernetes/kubelet/kubelet-config.json --selector 'memorySwap.swapBehavior' 'UnlimitedSwap'",
    ]
  }
}
