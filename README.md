# homeserver

This is my full homeserver setup.

## Hardware

- [ASUS PRIME B760M-A D4-CSM](https://www.asus.com/motherboards-components/motherboards/prime/prime-b760m-a-d4-csm/)
- [Intel® Core™ i3-12100](https://ark.intel.com/content/www/us/en/ark/products/134584/intel-core-i3-12100-processor-12m-cache-up-to-4-30-ghz.html)
- [CP2K16G4DFRA32A RAM](https://www.crucial.de/memory/ddr4/CP2K16G4DFRA32A)
- [LEICKE 120 W power supply](https://www.leicke.eu/de/products/NT03015)
- [PicoPSU-150-XT](https://www.mini-box.com/picoPSU-150-XT)
- [IPC-C236 Case](https://www.yakkaroo.de/19-zoll-2he-server-gehaeuse-ipc-c236-36cm-kurz)
- [Noctua NF-A8 PWM](https://www.noctua.at/en/products/nf-a8-pwm)
- [Delock SATA power Y-cable](https://www.delock.de/produkt/60135/merkmale.html?g=835)
- [SDDR-B531-GN6NN card reader](https://www.westerndigital.com/de-de/products/accessories/sandisk-mobilemate-uhs-i-usb-3-0-microsd-reader-writer?sku=SDDR-B531-GN6NN)
- [SDSQXAH-064G-GN6GN microSD](https://www.westerndigital.com/products/memory-cards/sandisk-extreme-uhs-i-for-mobile-gaming-microsd?sku=SDSQXAH-064G-GN6GN)
- [DIEWU TXA403-10G-4X](https://24wireless.info/diewu-txa403-and-txa405)
- [Intel I350-T2](https://www.intel.de/content/www/de/de/products/sku/84804/intel-ethernet-server-adapter-i350t2v2/specifications.html)
- WD Red WD40EFRX 4TB
- WD Blue SN580 2TB
- Samsung SSD 980 1TB
- Samsung SSD 860 1TB


### Smart Home

- [Pulse-Eight P8-USBCECv1](https://www.pulse-eight.com/p/104/usb-hdmi-cec-adapter)
- [nRF52840 Dongle](https://www.nordicsemi.com/Products/Development-hardware/nRF52840-Dongle)
- CC2652P USB dongle

## Installation

### CoreOS

Convert ignition config

```bash
podman run --interactive --rm quay.io/coreos/butane:release --pretty --strict < coreos/homeserver.bu > coreos/homeserver.ign
```

Download current OS image:

```bash
podman run --privileged --rm -v .:/data -w /data quay.io/coreos/coreos-installer:release download --architecture x86_64
```

Write to micro SD:

```bash
sudo podman run --privileged --rm -v /dev:/dev -v /run/udev:/run/udev -v .:/data -w /data quay.io/coreos/coreos-installer:release install --offline --image-file fedora-coreos-37.20221106.3.0-metal.x86_64.raw.xz --ignition-file coreos/homeserver.ign /dev/mmcblk0
```

### Install additional packages

```bash
rpm-ostree install dmidecode efivar hdparm htop inotify-tools lm_sensors node-exporter pciutils powertop s-tui stress tcpdump usbutils
```

- dmidecode, efivar, lm_sensors, powertop, s-tui, stress: Useful on x86
- hdparm: For putting the backup HDD to sleep
- htop: it's just very useful
- inotify-tools: required for my syncthing rsyncd setup
- node-exporter: for recording system information
- pciutils, tcpdump, usbutils: useful for debugging

### Trust my own CA

The gotify client needs this.

```bash
update-ca-trust
```

### Update

```bash
./update
```

