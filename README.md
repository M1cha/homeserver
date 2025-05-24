# homeserver

This is my full homeserver setup.

## Hardware

- [ASUS Pro H610M-C D4-CSM](https://www.asus.com/motherboards-components/motherboards/business/pro-h610m-c-d4-csm/)
- [Intel® Core™ i3-12100](https://ark.intel.com/content/www/us/en/ark/products/134584/intel-core-i3-12100-processor-12m-cache-up-to-4-30-ghz.html)
- [CP2K16G4DFRA32A RAM](https://www.crucial.de/memory/ddr4/CP2K16G4DFRA32A)
- [LEICKE 120 W power supply](https://www.leicke.eu/de/products/NT03015)
- [PicoPSU-150-XT](https://www.mini-box.com/picoPSU-150-XT)
- [IPC-C236 Case](https://www.yakkaroo.de/19-zoll-2he-server-gehaeuse-ipc-c236-36cm-kurz)
- [Delock SATA power Y-cable](https://www.delock.de/produkt/60135/merkmale.html?g=835)
- [SDDR-B531-GN6NN card reader](https://www.westerndigital.com/de-de/products/accessories/sandisk-mobilemate-uhs-i-usb-3-0-microsd-reader-writer?sku=SDDR-B531-GN6NN)
- [SDSQXAH-064G-GN6GN microSD](https://www.westerndigital.com/products/memory-cards/sandisk-extreme-uhs-i-for-mobile-gaming-microsd?sku=SDSQXAH-064G-GN6GN)
- [JEYI M.2 NVME SSD to PCIe 4.0 x1 Adapter Card](https://de.aliexpress.com/item/1005005802093622.html?spm=a2g0o.order_list.order_list_main.11.130e5c5fU2vg1Y&gatewayAdapt=glo2deu)
- [8cm PCI-E Card Bracket](https://www.aliexpress.com/item/1005006014444931.html?spm=a2g0o.order_list.order_list_main.5.130e5c5fU2vg1Y)
- WD Red WD40EFRX 4TB
- WD Blue SN580 2TB
- Samsung SSD 980 1TB
- Samsung SSD 860 1TB


### Smart Home

- CC2652P USB dongle

## Installation

### Disable PCI IC

This IC prevents the CPU from entering lower power states. Here's the info you
need to change the hidden BIOS setting to disable The root port it's connected to.
It was extracted from BIOS version `Pro-H610M-C-D4-SI-3401`.

```
VarStore Guid: 4570B7F1-ADE8-4943-8DC3-406472842384, VarStoreId: 0x6, Size: 0x811, Name: "PchSetup"

OneOf Prompt: "PCI Express Root Port 3", Help: "Control the PCI Express Root Port.", QuestionFlags: 0x10, QuestionId: 0xB25, VarStoreId: 0x6, VarOffset: 0x102, Flags: 0x10, Size: 8, Min: 0x0, Max: 0x1, Step: 0x0
    OneOfOption Option: "Disabled" Value: 0
    OneOfOption Option: "Enabled" Value: 1, Default, MfgDefault
End
```

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
sudo podman run --privileged --rm -v /dev:/dev -v /run/udev:/run/udev -v .:/data -w /data quay.io/coreos/coreos-installer:release install --offline --image-file fedora-coreos-37.20221106.3.0-metal.x86_64.raw.xz --ignition-file coreos/homeserver.ign /dev/mmcblk0
```

### Install additional packages

```bash
rpm-ostree install dmidecode efivar hdparm htop inotify-tools lm_sensors pciutils powertop s-tui stress tcpdump usbutils
```

- dmidecode, efivar, lm_sensors, powertop, s-tui, stress: Useful on x86
- hdparm: For putting the backup HDD to sleep
- htop: it's just very useful
- inotify-tools: required for my syncthing rsyncd setup
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

