# homeserver
This is my full homeserver setup.

## scripts
These are located in `./scripts`

- `mkimage-docker`: runs `./scripts/mkimag` in a docker container. This uses
   the `podman` runtime so you don't need root permissions.
- `mkimage`: builds a full OS image for the LXD host.
   If you don't run this on aarch64, you'll need to setup qemu-user for your kernel.

## boot-partition
This directory contains all manually installed files that are needed on the
boot partition. I could generate an image but I don't really need that since
I'll rarely update it.
