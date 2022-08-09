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

profile_homeserver_base() {
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
	lsblk
	lxcfs
	lxd-feature
	mount
	nftables
	prometheus-node-exporter
	prometheus-node-exporter-openrc
	qemu
	qemu-img
	qemu-system-aarch64
	tcpdump
	xtables-addons
	zfs
	zfs-udev
EOF
)
	image_ext="tar.gz"
	arch="aarch64"
	hostname="lxd"
	initfs_features="base homeserver-mount mmc squashfs"
	rootfs_extension="homeserver"
}

profile_rpilxdnode() {
	profile_homeserver_base

	rootfs_pks="$rootfs_pkgs raspberrypi-bootloader raspberrypi-bootloader-common"
	title="RPI LXD node"
	desc="m1chas RPI LXD node image"
	rootfs_kernel_flavor="rpi4"
	rootfs_kernel_addons="zfs"
	rootfs_extension="lxdnode"
}

profile_homeserver() {
	profile_homeserver_base

	rootfs_pks="$rootfs_pkgs linux-firmware-rtl_nic u-boot-tools"
	title="homeserver"
	desc="m1chas homeserver image"
	initfs_features="$initfs_features nanopi-r4s"
	rootfs_kernel_flavor="lts"
	rootfs_kernel_addons="xtables-addons zfs"
	rootfs_extension="homeserver"
}
