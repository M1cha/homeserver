#!/bin/bash

set -euo pipefail

platform="${1:-linux/amd64}"

script=$(readlink -f "$0")
source_dir=$(realpath $(dirname "$script"))
target_dir="$source_dir/target"
build_dir="$target_dir/$platform"

mkdir -p "$build_dir"
echo 'Signature: 8a477f597d28d172789f06886806bc55' > "$target_dir/CACHEDIR.TAG"

podman buildx build \
    --platform "$platform" \
    -f "$source_dir/Containerfile" \
    --iidfile "$build_dir/dockeriid" \
    "$source_dir"
iid=$(cat "$build_dir/dockeriid")

exec podman run \
    --rm \
    -v "$source_dir:$source_dir:Z" \
    -w "$source_dir" \
    -e "BUILD=$build_dir" \
    "$iid" \
    sh -c 'set -euo pipefail; cmake -S . -B "$BUILD" -GNinja -DCMAKE_BUILD_TYPE=Release; cmake --build "$BUILD"'
