section_homeserver() {
	build_section homeserver
}

build_homeserver() {
	local _script=$(readlink -f "$HOME/.mkimage/genrootfs-homeserver.sh")

	(cd "$OUTDIR"; sh "$_script" -k "$APKROOT"/etc/apk/keys \
		-r "$APKROOT"/etc/apk/repositories \
		-o "$DESTDIR" \
		-a "$ARCH" \
		-h "$hostname" \
		$rootfs_apks)
}

profile_homeserver() {
while IFS= read -r name; do
	name=$(echo "$name" | sed 's/^\s*#.*$//g' | xargs)

	if [ -z "$name" ]; then
		continue;
	fi

	rootfs_apks="$rootfs_apks $name"
done <<	EOF
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

	title="homeserver"
	desc="m1chas homeserver image"
	image_ext="tar.gz"
	arch="aarch64"
	hostname="lxd"
}
