#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
go_image="golang:1.26.5-bookworm@sha256:6c5605ab3a9a9fb3c4eafe5b3d63cdbf3881caf113262b67862547b54a9db599"
output_dir="${repo_dir}/dist/desktop"

if ! command -v docker >/dev/null 2>&1; then
    echo "erro: Docker é necessário; nenhuma toolchain Go é instalada no host" >&2
    exit 1
fi

mkdir -p "${output_dir}"
docker run --rm --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e GOCACHE=/tmp/go-cache \
    -e PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin \
    -e CGO_ENABLED=0 \
    -e GOOS=linux \
    -e GOARCH=amd64 \
    -v "${repo_dir}:/src" \
    -w /src/bridge \
    "${go_image}" \
    go build -trimpath -ldflags="-s -w -buildid=" \
        -o /src/dist/desktop/kindle-lichess-bridge \
        ./cmd/kindle-lichess-bridge

file "${output_dir}/kindle-lichess-bridge"
sha256sum "${output_dir}/kindle-lichess-bridge"
