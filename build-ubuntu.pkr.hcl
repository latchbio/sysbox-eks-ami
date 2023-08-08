build {
  name = "sysbox-eks"
  sources = [
    "source.amazon-ebs.ubuntu-eks"

  ]

  # Can be used to gen the current bootstrap.sh to update the patch
#   provisioner "file" {
#     source      = "/usr/local/share/eks/bootstrap.sh"
#     destination = "current_bootstrap.sh"
#     direction   = "download"
#   }

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
      "sudo apt-get install --yes --no-install-recommends cri-o cri-o-runc cri-tools",

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
  #     "echo >>> Installing prebuilt patched CRI-O",
  #     "sudo mv crio /usr/bin/crio",
  #
  #     "echo Setting permissions",
  #     "sudo chmod u+x /usr/bin/crio"
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
      "sudo apt-get install --yes --no-install-recommends golang-go libgpgme-dev",

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

      # Disable selinux for now.
	    "sudo dasel put bool --parser toml --file /etc/crio/crio.conf 'crio.runtime.selinux' false",

      # overlayfs with metacopy=on improves startup time of CRI-O rootless containers significantly
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf 'crio.storage_driver' 'overlay'",
	    "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.storage_option.[]' 'overlay.mountopt=metacopy=on'",

      #
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' CHOWN",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' DAC_OVERRIDE",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' FSETID",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' FOWNER",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' SETUID",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' SETGID",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' SETPCAP",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' SETFCAP",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' NET_BIND_SERVICE",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' KILL",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' AUDIT_WRITE",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' NET_RAW",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' SYS_CHROOT",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.runtime.default_capabilities.[]' MKNOD",
      #
      "sudo dasel put int --parser toml --file /etc/crio/crio.conf 'crio.runtime.pids_limit' 16384",

      # Create 'crio.image' table (required for 'pause_image' settings).
	    "sudo dasel put document --parser toml --file /etc/crio/crio.conf '.crio.image'",

	    # Create 'crio.network' table (required for 'network_dir' settings).
	    "sudo dasel put document --parser toml --file /etc/crio/crio.conf '.crio.network'",

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
      "sudo dasel put object --parser toml -m 'crio.runtime.runtimes.sysbox-runc' --file /etc/crio/crio.conf --type string 'runtime_path=/usr/bin/sysbox-runc' --type string 'runtime_type=oci'",
      "sudo dasel put string --parser toml -m 'crio.runtime.runtimes.sysbox-runc.allowed_annotations.[0]' --file /etc/crio/crio.conf 'io.kubernetes.cri-o.userns-mode'",
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
}
