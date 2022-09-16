cat >> "$tmp"/etc/fstab << EOF
PARTLABEL=var /var ext4 rw,relatime 0 1
# NOTE: busyboxs swapon doesn't support partlabel and \`util-linux-misc\`
#       is quite big
/dev/disk/by-partlabel/swap none swap sw 0 0
PARTLABEL=boot /boot vfat defaults,ro 0 0
PARTLABEL=config /media/config ext4 defaults,ro 0 0
EOF

makefile root:root 0644 "$tmp"/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto brlan0
iface brlan0 inet static
	bridge-ports lan0
	bridge-stp 0

	address 192.168.43.2/24
	gateway 192.168.43.1
EOF

makefile root:root 0644 "$tmp"/etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 192.168.43.1
EOF

# addresses on a bridged interface don't make any sense
makefile root:root 0644 "$tmp"/etc/sysctl.d/99-lan0.conf << EOF
net.ipv6.conf.lan0.autoconf=0
net.ipv6.conf.lan0.disable_ipv6=1
EOF

# This serves two purposes:
# 1) give the lan and wan ports generic names so we don't have to use device
#    specific names or MACs anywhere else.
# 2) swap WAN and LAN ports because R4S' LAN port uses a pretty bad realtek NIC
#    that can't handle the macvlan setup.
#
# DEVICE_SPECIFIC: You have to adjust the MAC address for your own setup
mkdir -p "$tmp"/etc/udev/rules.d
makefile root:root 0644 "$tmp"/etc/udev/rules.d/90-network.rules << EOF
# give our interfaces proper names
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="68:27:19:ac:db:26", NAME="wan0"
SUBSYSTEM=="net", ACTION=="add", NAME=="enp1s0", RUN+="/sbin/ip link set dev \$name address 6a:27:19:ac:db:26", NAME="lan0"
EOF

makefile root:root 0755 "$tmp"/etc/nftables.nft << EOF
#!/usr/bin/nft -f

define if_lan = "brlan0"
define if_lxd = "lxdbr0"
define if_lxdpriv = "lxdpriv0"
define if_prometheus = "prometheus"

# not flushing all the rules prevents flushing LXDs bridge filter rules on reload
# disabled because they fail if the tables don't exist
# delete table inet filter
# delete table ip nat

flush ruleset

table inet filter {
	chain lxd_dns {
		ip protocol { tcp, udp } th dport 53 accept comment "DNS"
	}

	chain lxd_dhcp {
		udp dport { 67, 547 } accept comment "DHCP"
	}

	chain inbound_lan {
		tcp dport 22 accept

		# for debug purposes
		icmp type echo-request limit rate 5/second accept
	}

	chain inbound_lxd {
		jump lxd_dns
		jump lxd_dhcp
	}

	chain inbound_lxdpriv {
		jump lxd_dns
		jump lxd_dhcp
	}

	chain inbound_prometheus {
		jump lxd_dhcp
		tcp dport { 9100, 9101 } accept comment "prometheus node exporter"
	}

	chain input {
		type filter hook input priority 0; policy drop;

		ct state invalid drop
		ct state { established, related } accept

		# SLAAC
		icmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept

		iifname lo accept
		iifname \$if_lan jump inbound_lan
		iifname \$if_lxd jump inbound_lxd
		iifname \$if_lxdpriv jump inbound_lxdpriv
		iifname \$if_prometheus jump inbound_prometheus

		log flags all prefix "dropped input: "
	}

	chain forward {
		type filter hook forward priority 0; policy drop;

		# internet access for LXD containers on the default bridge
		iifname \$if_lxd oifname \$if_lan accept
		iifname \$if_lan oifname \$if_lxd ct state related,established accept

		# allow devices on the private bridge to communicate
		# NOTE: this works on top of LXDs port isolation meaning they
		#       still won't be able to communicate if they're supposed
		#       to be isolated
		iifname "lxdpriv0" oifname "lxdpriv0" accept

		iifname "brlan0" oifname "brlan0" accept

		log flags all prefix "dropped forward: "
	}

	chain output {
		type filter hook output priority 0; policy accept;
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

# r4s uses a faster default console speed
cat >> "$tmp/etc/inittab" <<EOF

console::respawn:/sbin/getty -L console 1500000 vt100
EOF

makefile root:root 0755 "$tmp/usr/bin/lxdmetrics" <<EOF
#!/bin/sh

set -euo pipefail

read msg

data=\$(curl -s --unix-socket /var/lib/lxd/unix.socket http://lxd/1.0/metrics)

echo -ne "HTTP/1.1 200 OK\r\n"
echo -ne "Content-Length: \${#data}\r\n"
echo -ne "\r\n"

echo -n "\$data"
EOF

makefile root:root 0755 "$tmp/etc/init.d/lxdmetrics" <<EOF
#!/sbin/openrc-run
supervisor=supervise-daemon

command="/usr/bin/socat"
command_args="tcp-listen:9101,reuseaddr,fork system:/usr/bin/lxdmetrics"
command_background="yes"
group="lxd"
user="root"

pidfile="/var/run/\${SVCNAME}.pid"
start_stop_daemon_args="--user \$user --group \$group"

depend() {
        need net
        after firewall
}
EOF

rc_add homeserver-bridge boot
rc_add lxdmetrics default
