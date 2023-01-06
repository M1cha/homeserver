# homeserver

This is my full homeserver setup.

## Hardware

- ROCK 4 Model A+ (4GB RAM, 32GB EMMC) - [allnet](https://shop.allnetchina.cn/collections/frontpage/products/rock-pi-4-model-b-board-only-2-4-5ghz-wlan-bluetooth-5-0?variant=39284740653158) - [radxa wiki](https://wiki.radxa.com/Rock4/hardware/rock4)
- [M.2 extension board](https://shop.allnetchina.cn/products/rock-pi-4x-m-2-extension-board-v1-6)
- [Samsung SSD 980 M.2 1TB](https://www.samsung.com/de/memory-storage/nvme-ssd/980-1tb-nvme-pcie-gen-3-mz-v8v1t0bw/)
- [SDSQXA2-064G-GN6MA](https://www.westerndigital.com/en-ap/products/memory-cards/sandisk-extreme-uhs-i-microsd-160-mbps#SDSQXA2-064G-GN6MA)
- [Heatsink](https://shop.allnetchina.cn/products/heatsink-for-rock-pi-4?variant=15798546858086)
- [RTC battery](https://shop.allnetchina.cn/p¸roducts/rtc-battery-for-rock-pi-4?variant=15416681529446)

### Backup HDD

This setup allows powering down both 12V and 5V lines of the HDD using a single
smart plug. Both The 5V and the 12V power supplies are connected to it.

- WD Red WD40EFRX 4TB
- [benon multi-socket](https://www.amazon.de/gp/product/B0888PK57K)
- [1m deleyCON USB 3.0 extension](https://www.deleycon.de/deleycon-usb-3-0-verlaengerungskabel-usb-stecker-zu-usb-buchse/) (cut open to disconnect 5V and power it through a USB charger)
- Samsung USB charger (as the 5V power source, soldered to the cable above)
- [TRÅDFRI smart plug](https://www.ikea.com/de/de/p/tradfri-steckdose-funkgesteuert-smart-00377314/)
- [EasyULT USB3 to SATA adapter](https://www.amazon.de/gp/product/B07L5DK7C5)
- Cheap 12V DC power adapter

### Smart Home

- [deleyCON 4 Port USB 3.0 HUB](https://www.deleycon.de/deleycon-3-port-usb-3-0-hub-mit-kartenleser-sdhc-micro-sd-windows-mac-3x-usb3-0-port/) (connected through a USB2 extension cable to prevent 2.4GHz interference)
- CC2652P USB dongle

## Operating system

### Firmware

I'm using the internal MMC just for the firmware because:

- mainline linux had IO errors with the MMC
- The reserved partition of CoreOS is too small for rk3399

Installation:

- compile u-boot with `rock-pi-4-rk3399_defconfig`
- boot into any OS from the microSD so we can write to the MMC
- `dd if=u-boot-rockchip.bin of=/dev/mmcblk0 seek=64`

### CoreOS

Convert ignition config

```bash
podman run --interactive --rm quay.io/coreos/butane:release --pretty --strict < coreos/homeserver.bu > coreos/homeserver.ign
```

Download current OS image:

```bash
podman run --privileged --rm -v .:/data -w /data quay.io/coreos/coreos-installer:release download --architecture aarch64
```

Write to micro SD:

```bash
sudo podman run --privileged --rm -v /dev:/dev -v /run/udev:/run/udev -v .:/data -w /data quay.io/coreos/coreos-installer:release install --offline --image-file fedora-coreos-37.20221106.3.0-metal.aarch64.raw.xz --ignition-file coreos/homeserver.ign /dev/mmcblk0
```

### Install additional packages

```bash
sudo rpm-ostree install htop inotify-tools python3
```

- htop: it's just very useful
- inotify-tools: required for my syncthing rsyncd setup
- python3: for ansible

### Network setup

These could be done with ansible but I found them a little too specific to my
setup so I did them manually.

Ignore router DNS to prevent adding the search-domain to containers `/etc/hosts`:

```bash
nmcli con mod 'Wired connection 1' ipv4.ignore-auto-dns yes
nmcli con mod 'Wired connection 1' ipv6.ignore-auto-dns yes
```

Use the routers DNS server instead of pihole:

`/etc/systemd/resolved.conf`

```ini
[Resolve]
DNS=192.168.43.1
```

### Trust my own CA

The gotify client needs this.

```bash
create /etc/pki/ca-trust/source/anchors/m1cha-main.pem
run update-ca-trust
```

## ansible

### Build dependencies
arp-reply:

```bash
git clone tools/arp-reply
sh -c 'cd tools/arp-reply && cross build --release --target aarch64-unknown-linux-gnu'
```

std2pipe:

```bash
./tools/std2pipe/build_release.sh linux/arm64
```

### Run/Update

```bash
ansible-playbook main.yml
```
