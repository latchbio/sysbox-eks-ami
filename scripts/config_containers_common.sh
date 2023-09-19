#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

# The instructions in this function are typically executed as part of the
# containers-common's deb-pkg installation (which is a dependency of the cri-o
# pkg) by creating the default config files required for cri-o operations.
# However, these config files are not part of the cri-o tar file that
# we're relying on in this installation process, so we must explicitly create
# this configuration state as part of the installation process.
function config_containers_common() {

	local config_files="/home/ubuntu/crio/config"
	local containers_dir="/etc/containers"
	mkdir -p "$containers_dir"

	# Create a default system-wide registries.conf file and associated drop-in
	# dir if not already present.
	local reg_file="${containers_dir}/registries.conf"
	if [ ! -f "$reg_file" ]; then
		mv "${config_files}/etc_containers_registries.conf" "${reg_file}"
	fi

	local reg_dropin_dir="${containers_dir}/registries.conf.d"
	mkdir -p "$reg_dropin_dir"

	# Copy registry shortname config
	local shortnames_conf_file="${reg_dropin_dir}/000-shortnames.conf"
	if [ ! -f "$shortnames_conf_file" ]; then
		mv "${config_files}/etc_containers_registries.conf.d_000-shortnames.conf" "${shortnames_conf_file}"
	fi

	# Create a default registry-configuration file if not already present.
	local reg_dir="${containers_dir}/registries.d"
	mkdir -p "$reg_dir"

	local reg_def_file="${reg_dir}/default.yaml"
	if [ ! -f "$reg_def_file" ]; then
		mv "${config_files}/etc_containers_registries.d_default.yaml" "${reg_def_file}"
	fi

	# Create a default storage.conf file if not already present.
	local storage_conf_file="${containers_dir}/storage.conf"
	if [ ! -f "$storage_conf_file" ]; then
		mv "${config_files}/etc_containers_storage.conf" "${storage_conf_file}"
	fi

	# Create a default policy.json file if not already present.
	local policy_file="${containers_dir}/policy.json"
	if [ ! -f "$policy_file" ]; then
		mv "${config_files}/etc_containers_policy.json" "${policy_file}"
	fi

	# Copy the default loopback CNI config file
	local cni_dir="/etc/cni/net.d"
	mkdir -p "$cni_dir"

	local lb_file="${cni_dir}/200-loopback.conf"
	if [ ! -f "$lb_file" ]; then
		mv "${config_files}/etc_cni_net.d_200-loopback.conf" "${lb_file}"
	fi
}

config_containers_common
