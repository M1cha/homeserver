#!/bin/sh

set -euo pipefail

script=$(readlink -f "$0")
scriptdir=$(dirname "$script")

cleanup() {
	rm -rf "$tmp"
}

error() {
	echo "$SCRIPT: $1" >&2
}

makefile() {
	OWNER="$1"
	PERMS="$2"
	FILENAME="$3"
	cat > "$FILENAME"
	chown "$OWNER" "$FILENAME"
	chmod "$PERMS" "$FILENAME"
}

rc_add() {
	mkdir -p "$tmp"/etc/runlevels/"$2"
	ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

tmp="$(mktemp -d)"
trap cleanup EXIT
chmod 0755 "$tmp"

arch="$(apk --print-arch)"
repositories_file=/etc/apk/repositories
keys_dir=/etc/apk/keys
hostname=alpine
initfs_features=""
rootfs_extension=""

while getopts "a:r:k:o:h:F:x:" opt; do
	case $opt in
	a) arch="$OPTARG";;
	r) repositories_file="$OPTARG";;
	k) keys_dir="$OPTARG";;
	o) out_dir="$OPTARG";;
	h) hostname="$OPTARG";;
	F) initfs_features="$OPTARG";;
	x) rootfs_extension="$OPTARG";;
	esac
done
shift $(( $OPTIND - 1))

if [ -z "$out_dir" ]; then
	error "missing out_dir"
	exit 1
fi

pkgs="$@"

# use util-linux mount so we can use PARTLABEL in the root cmdline
mkdir -p "$tmp"/etc/mkinitfs/features.d
makefile root:root 0644 "$tmp"/etc/mkinitfs/features.d/homeserver-mount.files <<EOF
/bin/mount
EOF

mkdir -p "$tmp"/etc/mkinitfs
makefile root:root 0644 "$tmp"/etc/mkinitfs/mkinitfs.conf <<EOF
features="$initfs_features"
EOF

${APK:-apk} add --keys-dir "$keys_dir" --no-cache \
	--repositories-file "$repositories_file" \
	--root "$tmp" --initdb --arch "$arch" \
	$pkgs

makefile root:root 0644 "$tmp"/etc/hostname <<EOF
$hostname
EOF

mkdir -p "$tmp"/etc/modules-load.d
makefile root:root 0644 "$tmp"/etc/modules-load.d/lxd.conf <<EOF
# this is needed for starting containers with bridge filtering
br_netfilter
EOF

makefile root:root 0644 "$tmp"/etc/sysctl.d/99-swappiness.conf << EOF
vm.swappiness=1
EOF

# DEVICE_SPECIFIC: You have to change the public key for your own setup ;)
mkdir -p "$tmp"/root/.ssh
makefile root:root 0644 "$tmp"/root/.ssh/authorized_keys << EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDxjs3KQQ3P9HMStT1Xr1CJKZ4LSFVOStOmW5rHq9VzxH5gQaAmqJgCkdGSHDB7+3vD6uU5tm1i6Nl+jtkYGZtDhQthpaXgxIDARrv2Rg/8uWk+Tk/O3biseK5m00D0yB3BG7BMM0iTOHjAYBEK/QQ2gIogrIltZdFlKz0XfGFQivVdyzhbBUHhtn2TU0PoUTRmRupPo2iAJ4K55hBKweirMQPtTU47CZscXjwy1suwn1dSSvlEfE0k5y1m96lJQE0K7lRcRzr7nKaYeBvkcUK4gSalwnZd6m9sP/kRRkeD0McOFBaIsQDmH1gOK3V4brDkJ8y2tYI5ALsm3q1XarYAI9RCa5qg53CNP2hdgTxGb7XGtyc2mtwa81TVkJF7tvFfD/o1KL4f30r6oNbceJQ7gVv7ZaLPtoYbkVYLhhLpxqtbc6MQLbZ0sy5sHkl65C0MRcyErED+2HQrxH1+0Ox1IPW4UiWrqMBE5aC3boORMPa28a13ZNeIPreIrFm79Yk= m1cha@m1chalaptop
EOF

mkdir -p "$tmp"/etc/lxc
makefile root:root 0644 "$tmp"/etc/lxc/default.conf <<EOF
lxc.net.0.type = empty

lxc.idmap = u 0 100000 1000000000
lxc.idmap = g 0 100000 1000000000
EOF

makefile root:root 0644 "$tmp"/etc/subgid <<EOF
root:100000:1000000000
EOF

makefile root:root 0644 "$tmp"/etc/subuid <<EOF
root:100000:1000000000
EOF

cat >> "$tmp"/etc/rc.conf <<EOF

rc_cgroup_mode="unified"
rc_logger="YES"
rc_parallel="YES"
EOF

mkdir -p "$tmp"/etc/apk/protected_paths.d
makefile root:root 0644 "$tmp"/etc/apk/protected_paths.d/lbu.list << EOF
+root/.ssh/authorized_keys
EOF

cat >> "$tmp"/etc/conf.d/lxd <<EOF

error_log="/var/log/lxd.log"
EOF

# LXD uses this scope to verify if `memory.swap` is available
mkdir -p "$tmp/etc/local.d"
makefile root:root 0755 "$tmp/etc/local.d/cgroup-initscope.start" <<EOF
#!/bin/sh
mkdir -m 0755 -p /sys/fs/cgroup/init.scope
EOF

# copy private, readonly per-device data from the config partition
makefile root:root 0755 "$tmp/etc/init.d/homeserver-config" <<EOF
#!/sbin/openrc-run

depend()
{
	before zfs-import
	after localmount
}

start() {
	cp /media/config/zpool.cache /etc/zfs/zpool.cache
	cp /media/config/ssh_host_* /etc/ssh/
	return 0
}
EOF

# persistent LXC config for the root user
mkdir -p "$tmp/root/.config"
ln -s /media/config/root-lxc "$tmp"/root/.config/lxc

cat >> "$tmp"/etc/chrony/chrony.conf <<EOF
makestep 1 -1
EOF

# workaround for: https://github.com/lxc/lxd/issues/10724
cp "$tmp/bin/busybox" "$tmp/bin/gzip"

# make sure root login is disabled
sed -i -e 's/^root::/root:*:/' "$tmp"/etc/shadow

branch=edge
VERSION_ID=$(awk -F= '$1=="VERSION_ID" {print $2}'  "$tmp"/etc/os-release)
case $VERSION_ID in
*_alpha*|*_beta*) branch=edge;;
*.*.*) branch=v${VERSION_ID%.*};;
esac

makefile root:root 0644 "$tmp"/etc/apk/repositories <<EOF
https://dl-cdn.alpinelinux.org/alpine/$branch/main
https://dl-cdn.alpinelinux.org/alpine/$branch/community
https://dl-cdn.alpinelinux.org/alpine/$branch/testing
EOF

mkdir -p "$tmp"/etc/apk
echo -n "" | makefile root:root 0644 "$tmp"/etc/apk/world
for pkg in $pkgs; do
	echo "$pkg" >> "$tmp"/etc/apk/world
done

rc_add devfs sysinit
rc_add dmesg sysinit
rc_add homeserver-config sysinit
rc_add hwdrivers sysinit
rc_add localmount sysinit
rc_add udev sysinit
rc_add udev-trigger sysinit
rc_add udev-settle sysinit
rc_add zfs-import sysinit
rc_add zfs-mount sysinit

rc_add bootmisc boot
rc_add cgroups boot
rc_add dbus boot
rc_add hostname boot
rc_add hwclock boot
rc_add irqbalance boot
rc_add local boot
rc_add modules boot
rc_add networking boot
rc_add nftables boot
rc_add sysctl boot
rc_add syslog boot
rc_add urandom boot

rc_add chronyd default
rc_add crond default
rc_add lxcfs default
rc_add lxd default
rc_add node-exporter default
rc_add sshd default
rc_add swap default
rc_add udev-postmount default

rc_add killprocs shutdown
rc_add mount-ro shutdown
rc_add savecache shutdown

if [ -n "$rootfs_extension" ]; then
	source "$scriptdir/genrootfs.$rootfs_extension.sh"
fi

mkdir -p "$out_dir/boot"
mv "$tmp/boot/"* "$out_dir/boot/"

# mkinitfs' trigger installs a symlink that causes issues
rm "$out_dir/boot/boot"

outfile="$out_dir/root.squashfs"
rm -f "$outfile"
mksquashfs "$tmp" "$outfile"
