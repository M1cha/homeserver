#!/bin/sh

set -euo pipefail

ssh-keygen -A
exec /usr/sbin/sshd -D "$@"
