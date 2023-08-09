#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset


#
# Subid default values.
#
# Sysbox supports up 4K sys contaienrs per K8s node, each with 64K subids.
#
# Historical note: prior to Docker's acquisition of Nesytbox, Sysbox-CE was
# limited to 16-pods-per-node via variable subid_alloc_min_range below, whereas
# Sysbox-EE was limited to 4K-pods-per-node. After Docker's acquisition of
# Nestybox (05/22) Sysbox-EE is no longer being offered and therefore Docker has
# decided to lift the Sysbox-CE limit to encourage adoption of Sysbox on K8s
# clusters (the limit will now be 4K-pods-per-node as it was in Sysbox-EE).
#
subid_alloc_min_start=100000
subid_alloc_min_range=268435456
subid_alloc_max_end=4294967295

# We use CRI-O's default user "containers" for the sub-id range (rather than
# user "sysbox").
subid_user="containers"
subid_def_file="/etc/login.defs"
subuid_file="/etc/subuid"
subgid_file="/etc/subgid"

function get_subid_limits() {

	# Get subid defaults from /etc/login.defs

	subuid_min=$subid_alloc_min_start
	subuid_max=$subid_alloc_max_end
	subgid_min=$subid_alloc_min_start
	subgid_max=$subid_alloc_max_end

	if [ ! -f $subid_def_file ]; then
		return
	fi

	set +e
	res=$(grep "^SUB_UID_MIN" $subid_def_file >/dev/null 2>&1)
	if [ $? -eq 0 ]; then
		subuid_min=$(echo $res | cut -d " " -f2)
	fi

	res=$(grep "^SUB_UID_MAX" $subid_def_file >/dev/null 2>&1)
	if [ $? -eq 0 ]; then
		subuid_max=$(echo $res | cut -d " " -f2)
	fi

	res=$(grep "^SUB_GID_MIN" $subid_def_file >/dev/null 2>&1)
	if [ $? -eq 0 ]; then
		subgid_min=$(echo $res | cut -d " " -f2)
	fi

	res=$(grep "^SUB_GID_MAX" $subid_def_file >/dev/null 2>&1)
	if [ $? -eq 0 ]; then
		subgid_max=$(echo $res | cut -d " " -f2)
	fi
	set -e
}

function config_subid_range() {
	local subid_file=$1
	local subid_size=$2
	local subid_min=$3
	local subid_max=$4

	if [ ! -f $subid_file ] || [ ! -s $subid_file ]; then
		echo "$subid_user:$subid_min:$subid_size" >"${subid_file}"
		return
	fi

	readarray -t subid_entries <"${subid_file}"

	# if a large enough subid config already exists for user $subid_user, there
	# is nothing to do.

	for entry in "${subid_entries[@]}"; do
		user=$(echo $entry | cut -d ":" -f1)
		start=$(echo $entry | cut -d ":" -f2)
		size=$(echo $entry | cut -d ":" -f3)

		if [[ "$user" == "$subid_user" ]] && [ "$size" -ge "$subid_size" ]; then
			return
		fi
	done

	# Sort subid entries by start range
	declare -a sorted_subids
	if [ ${#subid_entries[@]} -gt 0 ]; then
		readarray -t sorted_subids < <(echo "${subid_entries[@]}" | tr " " "\n" | tr ":" " " | sort -n -k 2)
	fi

	# allocate a range of subid_alloc_range size
	hole_start=$subid_min

	for entry in "${sorted_subids[@]}"; do
		start=$(echo $entry | cut -d " " -f2)
		size=$(echo $entry | cut -d " " -f3)

		hole_end=$start

		if [ $hole_end -ge $hole_start ] && [ $((hole_end - hole_start)) -ge $subid_size ]; then
			echo "$subid_user:$hole_start:$subid_size" >>$subid_file
			return
		fi

		hole_start=$((start + size))
	done

	hole_end=$subid_max
	if [ $((hole_end - hole_start)) -lt $subid_size ]; then
		echo "failed to allocate $subid_size sub ids in range $subid_min:$subid_max"
		return
	else
		echo "$subid_user:$hole_start:$subid_size" >>$subid_file
		return
	fi
}

function main() {
    sudo su -
    get_subid_limits
	config_subid_range "$subuid_file" "$subid_alloc_min_range" "$subuid_min" "$subuid_max"
	config_subid_range "$subgid_file" "$subid_alloc_min_range" "$subgid_min" "$subgid_max"
}
