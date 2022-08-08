#!/bin/sh

set -euo pipefail

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

while getopts "a:r:k:o:h:" opt; do
	case $opt in
	a) arch="$OPTARG";;
	r) repositories_file="$OPTARG";;
	k) keys_dir="$OPTARG";;
	o) out_dir="$OPTARG";;
	h) hostname="$OPTARG";;
	esac
done
shift $(( $OPTIND - 1))

if [ -z "$out_dir" ]; then
	error "missing out_dir"
	exit 1
fi

pkgs="$@"

mkdir -p "$tmp"/etc/mkinitfs
makefile root:root 0644 "$tmp"/etc/mkinitfs/mkinitfs.conf <<EOF
features="base mmc nanopi-r4s squashfs"
EOF

# those are needed to load the sdcard driver
mkdir -p "$tmp"/etc/mkinitfs/features.d
makefile root:root 0644 "$tmp"/etc/mkinitfs/features.d/nanopi-r4s.modules <<EOF
kernel/drivers/clk/clk-rk808.ko*
kernel/drivers/gpio/gpio-rockchip.ko*
kernel/drivers/i2c/busses/i2c-rk3x.ko*
kernel/drivers/mfd/rk808.ko*
kernel/drivers/pwm/pwm-rockchip.ko*
kernel/drivers/regulator/fixed.ko*
kernel/drivers/regulator/rk808-regulator.ko*
kernel/drivers/rtc/rtc-rk808.ko*
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

makefile root:root 0644 "$tmp"/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto lan0
iface lan0 inet manual

auto lan0_host
iface lan0_host inet static
	address 192.168.43.2/24
	gateway 192.168.43.1
	pre-up ip link add link lan0 name lan0_host type macvlan mode bridge

	# the macvlan bridge is only up if there are at least two devices on it.
	# to be able to communicate with the LXD host without any LXD containers
	# running we need to add a second, unused port.
	pre-up ip link add link lan0 name lan0_dummy type macvlan mode bridge
	pre-up sysctl -w net.ipv6.conf.lan0_dummy.autoconf=0
	pre-up sysctl -w net.ipv6.conf.lan0_dummy.disable_ipv6=1
	pre-up ip link set dev lan0_dummy up
EOF

makefile root:root 0644 "$tmp"/etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 192.168.43.1
EOF

# We never want anybody to communicate with the host interface because the host
# is not reachable for the VMs through it.
# We cannot disable or remove it's MAC though so simply remove all addresses.
makefile root:root 0644 "$tmp"/etc/sysctl.d/99-lan0.conf << EOF
net.ipv6.conf.lan0.autoconf=0
net.ipv6.conf.lan0.disable_ipv6=1
EOF

makefile root:root 0644 "$tmp"/etc/sysctl.d/99-swappiness.conf << EOF
vm.swappiness=1
EOF

# This serves two purposes:
# 1) give the lan and wan ports generic names so we don't have to device
#    specific names or MACs anywhere else.
# 2) swap WAN and LAN ports because R4S' LAN port uses a pretty bad realtek NIC
#    that can't handle the macvlan setup.
#
# DEVICE_SPECIFIC: You have to adjust the MAC address for your own setup
mkdir -p "$tmp"/etc/udev/rules.d
makefile root:root 0644 "$tmp"/etc/udev/rules.d/90-network.rules << EOF
# give our interfaces proper names
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="68:27:19:ac:db:26", RUN+="/sbin/ip link set dev \$name address 42:42:42:42:42:42", NAME="lan0"
SUBSYSTEM=="net", ACTION=="add", NAME=="enp1s0", RUN+="/sbin/ip link set dev \$name address 68:27:19:ac:db:26", NAME="wan0"
EOF

makefile root:root 0755 "$tmp"/etc/nftables.nft << EOF
#!/usr/bin/nft -f

define if_lan_lower = "lan0"
define if_lan_dummy = "lan0_dummy"
define if_lan = "lan0_host"
define if_lxd = "lxdbr0"
define if_lxdpriv = "lxdpriv0"

# not flushing all the rules prevents flushing LXDs bridge filter rules on reload
# disabled because they fail if the tables don't exist
# delete table inet filter
# delete table ip nat

flush ruleset

table inet filter {
	chain inbound_lan {
		tcp dport 22 accept

		# for debug purposes
		icmp type echo-request limit rate 5/second accept
	}

	chain inbound_lxd {
		# LXD provides dnsmasq to containers
		ip protocol { tcp, udp } th dport 53 accept comment "DNS"
		udp dport { 67, 547 } accept comment "DHCP"
	}

 	chain inbound_lxdpriv {
		# LXD provides dnsmasq to containers
		ip protocol { tcp, udp } th dport 53 accept comment "DNS"
		udp dport { 67, 547 } accept comment "DHCP"
	}

	chain input {
		type filter hook input priority 0; policy drop;

		iifname { \$if_lan_lower, \$if_lan_dummy } drop;

		ct state invalid drop
		ct state { established, related } accept

		# SLAAC
		icmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept

		iifname lo accept
		iifname \$if_lan jump inbound_lan
		iifname \$if_lxd jump inbound_lxd
		iifname \$if_lxdpriv jump inbound_lxdpriv

		log flags all prefix "dropped input: "
	}

	chain forward {
		type filter hook forward priority 0; policy drop;

		iifname { \$if_lan_lower, \$if_lan_dummy } drop;
		oifname { \$if_lan_lower, \$if_lan_dummy } drop;

		# internet access for LXD containers on the default bridge
		iifname \$if_lxd oifname \$if_lan accept
		iifname \$if_lan oifname \$if_lxd ct state related,established accept

		# allow devices on the private bridge to communicate
		# NOTE: this works on top of LXDs port isolation meaning they
		#       still won't be able to communicate if they're supposed
		#       to be isolated
		iifname "lxdpriv0" oifname "lxdpriv0" accept

		log flags all prefix "dropped forward: "
	}

	chain output {
		type filter hook output priority 0; policy accept;

		oifname { \$if_lan_lower, \$if_lan_dummy } drop;
	}
}

table ip nat {
	chain prerouting {
		type nat hook prerouting priority 0; policy accept;
	}

	chain postrouting {
		type nat hook postrouting priority 100; policy accept;

		oifname \$if_lan masquerade
	}
}
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

# DEVICE_SPECIFIC: change the UUIDs
cat >> "$tmp"/etc/fstab << EOF
UUID=20337b56-0ad1-403a-8e9c-f59655509c93 /var ext4 rw,relatime 0 1
UUID=d436b29f-3f13-4508-9f20-3ae9f54271f3 none swap sw 0 0
/dev/mmcblk1p1 /boot vfat defaults 0 0
/dev/mmcblk1p5 /media/config ext4 defaults,ro 0 0
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

# add bridge `lxdpriv0`
makefile root:root 0755 "$tmp/etc/init.d/homeserver-bridge" <<EOF
#!/sbin/openrc-run

depend()
{
	before networking
	after modules
}

start() {
	brctl addbr lxdpriv0
	sysctl -w net.ipv6.conf.lxdpriv0.autoconf=0
	sysctl -w net.ipv6.conf.lxdpriv0.disable_ipv6=1
	ip link set dev lxdpriv0 up

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

# r4s uses a faster default console speed
cat >> "$tmp/etc/inittab" <<EOF

console::respawn:/sbin/getty -L console 1500000 vt100
EOF

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
rc_add homeserver-bridge boot
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

mkdir -p "$out_dir/boot"
mv "$tmp/boot/"* "$out_dir/boot/"

# mkinitfs' trigger installs a symlink that causes issues
rm "$out_dir/boot/boot"

outfile="$out_dir/root.squashfs"
rm -f "$outfile"
mksquashfs "$tmp" "$outfile"
