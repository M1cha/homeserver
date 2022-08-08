section_homeserver() {
	build_section homeserver
}

build_homeserver() {
	local _script=$(readlink -f "$HOME/.mkimage/genrootfs.common.sh")
	local _pkgs="$rootfs_pkgs linux-$rootfs_kernel_flavor"

	local _a
	for _a in $rootfs_kernel_addons; do
		_pkgs="$_pkgs $_a-$rootfs_kernel_flavor"
	done

	(cd "$OUTDIR"; sh "$_script" -k "$APKROOT"/etc/apk/keys \
		-r "$APKROOT"/etc/apk/repositories \
		-o "$DESTDIR" \
		-a "$ARCH" \
		-h "$hostname" \
		-F "$initfs_features" \
		-x "$rootfs_extension" \
		$_pkgs)
}

makearray() {
	local arr=""
	while IFS= read -r name; do
		name=$(echo "$name" | sed 's/^\s*#.*$//g' | xargs)

		if [ -z "$name" ]; then
			continue;
		fi

		arr="$arr $name"
	done

	echo "$arr"
}

profile_homeserver() {
rootfs_pkgs=$(makearray << EOF
	# from profile_base
	alpine-base
	busybox
	chrony
	e2fsprogs
	haveged
	ifupdown-ng
	openssh
	openssl
	tzdata
	wget

	# ours
	apparmor
	apparmor-profiles
	apparmor-utils
	btrfs-progs
	btrfs-progs-extra
	dbus
	dbus-openrc
	eudev
	eudev-netifnames
	htop
	irqbalance
	irqbalance-openrc
	linux-firmware-none
	linux-firmware-rtl_nic
	lxcfs
	lxd-feature
	nftables
	prometheus-node-exporter
	prometheus-node-exporter-openrc
	qemu
	qemu-img
	qemu-system-aarch64
	tcpdump
	u-boot-tools
	xtables-addons
	zfs
	zfs-udev
EOF
)

	title="homeserver"
	desc="m1chas homeserver image"
	image_ext="tar.gz"
	arch="aarch64"
	hostname="lxd"
	initfs_features="base mmc nanopi-r4s squashfs"
	rootfs_kernel_flavor="lts"
	rootfs_kernel_addons="xtables-addons zfs"
	rootfs_extension="homeserver"
}
