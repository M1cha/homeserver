#!/bin/bash

set -euo pipefail

tmp2sys() {
	local path="$1"
	shift

	if [ -d "$path" ]; then
		rsync "$@" -a "$path/" "/$path/"
	else
		rsync "$@" -a "$path" "/$path"
	fi
}

cleanup_systemd() {
	find /etc/systemd/system -mindepth 1 -maxdepth 1 -print0 |
	while IFS= read -rd '' path_etc; do
		path_usr="/usr$path_etc"

		if [ -L "$path_usr" ] || [ -e "$path_usr" ]; then
			continue
		fi
		if [ -d "$path_etc" ] && [[ "$path_etc" != *service.d ]]; then
			continue
		fi

		echo "WARNING: delete $path_etc"
		rm -r "$path_etc"
	done
}

install() {
	cd "$HOME/tmp_config"

	chmod -R go= etc/NetworkManager/system-connections/*

	tmp2sys etc/hostname
	tmp2sys etc/sysctl.d/99-m1cha.conf
	tmp2sys etc/subuid
	tmp2sys etc/subgid
	tmp2sys etc/containers/networks --delete
	tmp2sys etc/containers/containers.conf
	tmp2sys etc/NetworkManager/system-connections --delete
	tmp2sys etc/containers/systemd --delete
	tmp2sys etc/systemd/resolved.conf
	tmp2sys etc/systemd/system
	tmp2sys etc/pki/ca-trust/source/anchors --delete
	tmp2sys usr/local/bin --delete
	tmp2sys usr/local/lib --delete
	tmp2sys usr/local/share --delete

	# This is needed for forwarding devices to containers.
	setsebool -P container_use_devices=true

	systemctl daemon-reload
	nmcli connection reload
	systemctl enable --now \
		container-image-builder@homeserver-universal.timer \
		gitmirror.timer \
		hdparm.service \
		podman-auto-update.timer \
		netavark-dhcp-proxy.socket \
		nftables.service \
		rclone-backup.timer \
		restic-autobackup.timer \
		syncthing-rsync.path \
		syncthing-rsync-watch.service \
		syncthing-rsync.timer

	systemctl reload nftables.service
	/usr/bin/flock -x -w 1 /tmp/update-bridge-rules.lock /usr/local/bin/update-bridge-rules
}

cleanup_systemd
install
