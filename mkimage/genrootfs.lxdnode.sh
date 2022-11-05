cat >> "$tmp"/etc/fstab << EOF
PARTLABEL=var /var ext4 rw,relatime 0 1
PARTLABEL=boot /boot vfat defaults,ro 0 0
PARTLABEL=config /media/config ext4 defaults,ro 0 0
EOF

# give physical eth0 another mac so we can reuse it for eth0_host
mkdir -p "$tmp"/etc/udev/rules.d
makefile root:root 0644 "$tmp"/etc/udev/rules.d/90-network.rules << EOF
SUBSYSTEM=="net", ACTION=="add", KERNEL=="eth0", RUN+="/bin/sh -c \"cat /sys/class/net/\$name/address > /tmp/\$name.address\"", RUN+="/sbin/ip link set dev \$name address 42:42:42:42:42:42"
EOF

makefile root:root 0644 "$tmp"/etc/udev/rules.d/99-restic-hdd.rules << EOF
SUBSYSTEM=="block", ACTION=="add", ENV{PARTNAME}=="restic-backup", RUN+="/usr/bin/lxc start restic-backup-2"
SUBSYSTEM=="block", ACTION=="remove", ENV{PARTNAME}=="restic-backup", RUN+="/usr/bin/lxc stop -f restic-backup-2"
EOF

makefile root:root 0644 "$tmp"/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual

auto eth0_host
iface eth0_host inet dhcp
	pre-up ip link add link eth0 name eth0_host type macvlan mode bridge

	# use physical mac
	pre-up sh -c "ip link set dev eth0_host address \$(cat /tmp/eth0.address)"

	# the macvlan bridge is only up if there are at least two devices on it.
	# to be able to communicate with the LXD host without any LXD containers
	# running we need to add a second, unused port.
	pre-up ip link add link eth0 name eth0_dummy type macvlan mode bridge
	pre-up sysctl -w net.ipv6.conf.eth0_dummy.autoconf=0
	pre-up sysctl -w net.ipv6.conf.eth0_dummy.disable_ipv6=1
	pre-up ip link set dev eth0_dummy up
EOF

# We never want anybody to communicate with the host interface because the host
# is not reachable for the VMs through it.
# We cannot disable or remove it's MAC though so simply remove all addresses.
makefile root:root 0644 "$tmp"/etc/sysctl.d/99-eth0.conf << EOF
net.ipv6.conf.eth0.autoconf=0
net.ipv6.conf.eth0.disable_ipv6=1
EOF

makefile root:root 0755 "$tmp"/etc/nftables.nft << EOF
#!/usr/bin/nft -f

define if_lan_lower = "eth0"
define if_lan_dummy = "eth0_dummy"
define if_lan = "eth0_host"
define if_lxd = "lxdbr0"

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

		log flags all prefix "dropped input: "
	}

	chain forward {
		type filter hook forward priority 0; policy drop;

		iifname { \$if_lan_lower, \$if_lan_dummy } drop;
		oifname { \$if_lan_lower, \$if_lan_dummy } drop;

		# internet access for LXD containers on the default bridge
		iifname \$if_lxd oifname \$if_lan accept
		iifname \$if_lan oifname \$if_lxd ct state related,established accept

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

mkdir "$tmp"/boot/boot_x
mv "$tmp"/boot/*-rpi4 "$tmp"/boot/boot_x/

makefile root:root 0644 "$tmp"/boot/cmdline.txt << EOF
root=PARTLABEL=rootfs0 overlaytmpfs lsm=integrity,apparmor,bpf
EOF

makefile root:root 0644 "$tmp"/boot/config.txt << EOF
[pi4]
enable_gic=1
kernel=boot_0/vmlinuz-rpi4
initramfs boot_0/initramfs-rpi4
[all]
arm_64bit=1
include usercfg.txt
EOF

makefile root:root 0755 "$tmp"/boot/install << EOF
#!/bin/sh

set -euo pipefail

targz="\$1"

error() {
        echo "\$@" >&2
}

current_slot=\$(cat /proc/cmdline | tr ' ' '\n' | grep -m1 '^root=PARTLABEL=rootfs' | sed 's|^root=PARTLABEL=rootfs||')
case \$current_slot in
        0)
                next_slot=1
                ;;
        1)
                next_slot=0
                ;;
        *)
                error "invalid slot: \$current_slot"
                exit 1
                ;;
esac

next_part=\$(lsblk -o PATH,PARTLABEL | awk "{ if (\\\$2 == \\"rootfs\$next_slot\\") { print \\\$1 } }")

echo "\$current_slot -> \$next_slot"

error "mount boot partition rw"
mount -o rw,remount /boot

boot_dir="/boot/boot_\${next_slot}"
if [ -d "\$boot_dir" ];then
        error "delete old boot dir"
        rm -r "\$boot_dir"
fi

error "extract new boot dir"
tar --strip-components=2 -C /boot -xf "\$targz" ./boot/boot_x
mv /boot/boot_x "\$boot_dir"

error "extract new rootfs"
tar -O  -xf "\$targz" ./root.squashfs | dd bs=10M of="\${next_part}"

error "update config.txt"
sed -i "s|boot_[01]/\\\\(.*\\\\)|boot_\${next_slot}/\1|g" /boot/config.txt

error "update cmdline.txt"
sed -i "s|^\\\\(root=PARTLABEL=rootfs\\\\)[01]|\1\${next_slot}|g" /boot/cmdline.txt

error "done"
EOF

echo "rpoweroff:x:1000:1000:remote poweroff,,,:/home/rpoweroff:/home/rpoweroff/loginaction" >> "$tmp"/etc/passwd
echo "rpoweroff:*:19222:0:99999:7:::" >> "$tmp"/etc/shadow
echo "rpoweroff:x:1000:" >> "$tmp"/etc/group

mkdir -p "$tmp"/home/rpoweroff/.ssh
makefile root:root 0644 "$tmp"/home/rpoweroff/.ssh/authorized_keys <<EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDK5CQ0guL4cJGYJTijwKy4P/PPk1InTEiL6NqgorHw5FYNmrEs2X1hCAQvlXA1FyThPtEuT/hvGMxM59W9RPt5wdQ3DUEFLy+vM/8kmwAxgZM1hvSHgPMQopJ/CFPxUeZen0TaSmPk94vryeUle6Pv2rjKAyulwT+ftyWP9bOMxHzOsAHb8mww6i6ji6E2LEr32IHDZnOpf3AjcHE6eTshxB6KilQTzvzA1phLtfrXTEd4CLMd+uFGoZteBGbibR+h5pcJcaZLMBpVxl4JTCRVEUsnflxOL4sadtDuJ+no+CESxFRMK3FmiRjkPn72ux+qb1jbK1PCSj3aVMJd+DnYmGlgTerbVcsrItQZNOtVMwyC1JXJ3KabqgDEC+nJbBPsfeBgD7HKhZ/YYXDj/vnLYEakevqaH1eZRnlHIdFdvrjMI27TD0yxJIR6kzhaFVrrn47v8k4EOJ15WL3HaZ2XvVqIej0Shf6RhPxgwq36E6c4K198nmKsr05xLKYOEcs= root@homeassistant
EOF

makefile root:root 0644 "$tmp"/etc/sudoers.d/rpoweroff <<EOF
rpoweroff ALL=NOPASSWD:/sbin/poweroff
EOF

makefile root:root 0755 "$tmp"/home/rpoweroff/loginaction <<EOF
#!/bin/sh
exec sudo /sbin/poweroff
EOF
