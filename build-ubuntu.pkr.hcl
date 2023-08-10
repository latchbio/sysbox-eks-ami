build {
  name = "sysbox-eks"
  sources = [
    "source.amazon-ebs.ubuntu-eks"

  ]

  # # Can be used to gen the current bootstrap.sh to update the patch
  # provisioner "file" {
  #   source      = "/usr/local/share/eks/bootstrap.sh"
  #   destination = "current_bootstrap.sh"
  #   direction   = "download"
  # }

  # equivalent to install_package_deps() function
  # TODO: seems like installing fuse removes fuse3. Which is needed by sysbox? According to arch package docs it hase fuse2 as a dependency.
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo Updating apt",
      "sudo apt-get -y install ca-certificates",
      "sudo apt-get update -y",
      "sudo apt-get install -y rsync fuse iptables"
    ]
  }

  ###################
  ## Install CRI-O ##
  ###################


  # equivalent to deploy_crio_installer_service() function
  provisioner "file" {
    sources     = [
      "tmp/crio/${var.architecture}/v${var.k8s_version}/crio-patched",
      "tmp/crio/${var.architecture}/v${var.k8s_version}/cri-o.${var.architecture}.tar.gz",
      "tmp/crio/scripts/crio-extractor.sh",
      "tmp/crio/config/etc_cni_net.d_200-loopback.conf",
      "tmp/crio/config/etc_containers_registries.conf.d_000-shortnames.conf",
      "tmp/crio/config/etc_containers_storage.conf",
      "tmp/crio/config/etc_containers_registries.conf",
      "tmp/crio/config/etc_containers_registries.d_default.yaml",
      "tmp/crio/config/etc_containers_policy.json",
      ]
    destination = "/home/ubuntu/"
    max_retries = 3
  }
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "sudo mv cri-o.${var.architecture}.tar.gz /usr/local/bin/cri-o.${var.architecture}.tar.gz",
      "sudo mv crio-patched /usr/local/bin/crio-patched",
      "sudo chmod +x crio-extractor.sh && sudo mv crio-extractor.sh /usr/local/bin/crio-extractor.sh",

      "mkdir -p crio/config",
      "mv etc_cni_net.d_200-loopback.conf crio/config/etc_cni_net.d_200-loopback.conf",
      "mv etc_containers_registries.conf.d_000-shortnames.conf crio/config/etc_containers_registries.conf.d_000-shortnames.conf",
      "mv etc_containers_storage.conf crio/config/etc_containers_storage.conf",
      "mv etc_containers_registries.conf crio/config/etc_containers_registries.conf",
      "mv etc_containers_registries.d_default.yaml crio/config/etc_containers_registries.d_default.yaml",
      "mv etc_containers_policy.json crio/config/etc_containers_policy.json",
    ]
  }

  # equivalent to config_containers_common() function
  provisioner "shell" {
    script          = "scripts/config_containers_common.sh"
    execute_command = "chmod +x {{ .Path }}; sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  # equivalent to install_crio() function
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      # Extract and install the CRI-O (and related dependencies) binaries
      "pushd '/usr/local/bin'",
      "sudo tar -xvf 'cri-o.${var.architecture}.tar.gz'",
      "sudo rm -r 'cri-o.${var.architecture}.tar.gz'",
	    "pushd cri-o",

      "sudo sh -c  \"/usr/local/bin/crio-extractor.sh install '/usr/local'\"",
      "sudo rm -r /usr/local/bin/cri-o",

      # Replace the stock CRI-O binary with the one that has the uid mapping patch
	    # required by Sysbox.
      "sudo mv /usr/local/bin/crio-patched /usr/local/bin/crio",

      # Remove the CRI-O extractor script since it is no longer needed.
      "sudo rm /usr/local/bin/crio-extractor.sh",

      "sudo systemctl enable crio",
      "sudo systemctl restart crio",
	    "sudo systemctl is-active --quiet crio",
	    "echo 'CRI-O installation done.'",
    ]
  }

  # equivalent to config_crio() function
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      # Much of the rest of this is from inside the Sysbox K8s installer image
      "echo '>>> Doing basic CRI-O configuration'",

      "echo Installing Dasel",
      "sudo curl --location https://github.com/TomWright/dasel/releases/download/v1.24.3/dasel_linux_${var.architecture} --output /usr/local/bin/dasel",
      "sudo chmod u+x /usr/local/bin/dasel",

      # Disable selinux for now.
	    "sudo dasel put bool --parser toml --file /etc/crio/crio.conf 'crio.runtime.selinux' false",

      # # Add user "containers" to the /etc/subuid and /etc/subgid files
      # NOTE: this is done in the next step with config_subid_range.sh

      # Set capabilities to match default caps in containerd/docker
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

      # Create 'crio.image' table (required for 'pause_image' settings).
	    "sudo dasel put document --parser toml --file /etc/crio/crio.conf '.crio.image'",

	    # Create 'crio.network' table (required for 'network_dir' settings).
	    "sudo dasel put document --parser toml --file /etc/crio/crio.conf '.crio.network'",

      # CRI-O puts a default limit of 1024 processes per pod; this is too small for
      # Sysbox pods, since these run sometimes complex software such as Docker,
      # K8s, etc. Thus we increase this to 16K processes per pod. Since the max
      # limit for Linux is 4M (see /proc/sys/kernel/pid_max), this allows up to
      # ~256 Sysbox containers each consuming 16K processes on a given host. It
      # also constraints a malicious container executing a fork bomb to 16K
      # processes, well below the kernel's max pid limit.
      "sudo dasel put int --parser toml --file /etc/crio/crio.conf 'crio.runtime.pids_limit' 16384",
    ]
  }

  # equivalent to get_subid_limits() and config_subid_range() functions
  provisioner "shell" {
    script          = "scripts/config_subid_range.sh"
    execute_command = "chmod +x {{ .Path }}; sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  ####################
  ## Install Sysbox ##
  ####################

  # equivalent to install_shiftfs() function
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
      "rm -rf shiftfs",
      "sudo apt-get remove --yes --purge make dkms git"
    ]
  }

  # equivalent to copy_sysbox_to_host() function
  provisioner "file" {
    source      = "tmp/sysbox/${var.architecture}/bin"
    destination = "/home/ubuntu/"
  }
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Moving Sysbox binaries to /usr/bin'",
      "sudo mv /home/ubuntu/bin/* /usr/bin/",
    ]
  }

  # equivalent to copy_conf_to_host() function
  provisioner "file" {
    sources      = ["tmp/sysbox/systemd/99-sysbox-sysctl.conf", "tmp/sysbox/systemd/50-sysbox-mod.conf"]
    destination = "/home/ubuntu/"
  }
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Moving Sysbox sysctl configs to /lib/sysctl.d/'",
      "sudo mv /home/ubuntu/99-sysbox-sysctl.conf /lib/sysctl.d/99-sysbox-sysctl.conf",
      "sudo mv /home/ubuntu/50-sysbox-mod.conf /lib/sysctl.d/50-sysbox-mod.conf",
    ]
  }

  # equivalent to copy_systemd_units_to_host() function
  provisioner "file" {
    sources      = ["tmp/sysbox/systemd/sysbox.service", "tmp/sysbox/systemd/sysbox-mgr.service", "tmp/sysbox/systemd/sysbox-fs.service"]
    destination = "/home/ubuntu/"
  }
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo '>>> Moving Sysbox systemd units to /lib/systemd/system/'",
      "sudo mv /home/ubuntu/sysbox.service /lib/systemd/system/sysbox.service",
      "sudo mv /home/ubuntu/sysbox-mgr.service /lib/systemd/system/sysbox-mgr.service",
      "sudo mv /home/ubuntu/sysbox-fs.service /lib/systemd/system/sysbox-fs.service",

      "echo '>>> Enabling Sysbox systemd units'",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable sysbox.service",
      "sudo systemctl enable sysbox-mgr.service",
      "sudo systemctl enable sysbox-fs.service",
    ]
  }

  # equivalent to apply_conf()
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "sudo echo 'Configuring host sysctls ...'",
	    "sudo sysctl -p '/lib/sysctl.d/99-sysbox-sysctl.conf'",
    ]
  }

  # equivalent to start_sysbox()
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "sudo echo 'Starting CE ...'",
	    "sudo systemctl restart sysbox",
	    "sudo systemctl is-active --quiet sysbox",
    ]
  }

  # equivalent to config_crio_for_sysbox() function
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "set -o pipefail -o errexit",

      "echo 'Adding Sysbox to CRI-O config ...'",

      # overlayfs with metacopy=on improves startup time of CRI-O rootless containers significantly
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf 'crio.storage_driver' 'overlay'",
	    "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.storage_option.[]' 'overlay.mountopt=metacopy=on'",

      # Add Sysbox to CRI-O's runtime list
      "sudo dasel put object --parser toml -m 'crio.runtime.runtimes.sysbox-runc' --file /etc/crio/crio.conf --type string 'runtime_path=/usr/bin/sysbox-runc' --type string 'runtime_type=oci'",
      "sudo dasel put string --parser toml -m 'crio.runtime.runtimes.sysbox-runc.allowed_annotations.[0]' --file /etc/crio/crio.conf 'io.kubernetes.cri-o.userns-mode'",
    ]
  }

  # equivalent to adjust_crio_config_dependencies() function (from kubelet-config-helpe.sh that usually runs at runtime)
  # see https://github.com/nestybox/sysbox-pkgr/blob/b560194d516b300e9e201274a29348d3626055c1/k8s/scripts/kubelet-config-helper.sh#L861
  # see https://github.com/nestybox/sysbox-pkgr/blob/b560194d516b300e9e201274a29348d3626055c1/k8s/scripts/kubelet-config-helper.sh#L833
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [

      # todo(maximsmol): do this only when K8s is configured without systemd cgroups (from sysbox todos)
      # this is done by the kubelet-config-helper.sh
      # see https://github.com/nestybox/sysbox-pkgr/blob/b560194d516b300e9e201274a29348d3626055c1/k8s/scripts/kubelet-config-helper.sh#L861
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf 'crio.runtime.cgroup_manager' 'cgroupfs'",
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf 'crio.runtime.conmon_cgroup' 'pod'",

      # needed for networking
      # this is done by the kubelet-config-helper.sh
      # see https://github.com/nestybox/sysbox-pkgr/blob/b560194d516b300e9e201274a29348d3626055c1/k8s/scripts/kubelet-config-helper.sh#L833
      "sudo dasel put string --parser toml --file /etc/crio/crio.conf -m 'crio.network.plugin_dirs.[]' '/opt/cni/bin'",
    ]
  }

  # patch the bootstrap.sh to support cri-o and set it as the default
  provisioner "file" {
    source      = "bootstrap.sh.patch"
    destination = "/home/ubuntu/bootstrap.sh.patch"
  }
  provisioner "shell" {
    inline_shebang = "/usr/bin/env bash"
    inline = [
      "sudo mv /home/ubuntu/bootstrap.sh.patch /usr/local/share/eks/bootstrap.sh.patch",
      "sudo patch --backup /usr/local/share/eks/bootstrap.sh /usr/local/share/eks/bootstrap.sh.patch"
    ]
  }
}
