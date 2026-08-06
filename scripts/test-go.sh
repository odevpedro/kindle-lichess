#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
go_image="golang:1.26.5-bookworm@sha256:6c5605ab3a9a9fb3c4eafe5b3d63cdbf3881caf113262b67862547b54a9db599"

if ! command -v docker >/dev/null 2>&1; then
    echo "erro: Docker é necessário; nenhuma toolchain Go é instalada no host" >&2
    exit 1
fi

docker run --rm --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e GOCACHE=/tmp/go-cache \
    -e PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin \
    -v "${repo_dir}/bridge:/src" \
    -w /src \
    "${go_image}" \
    bash -c '
        unformatted="$(gofmt -l .)"
        if [[ -n "${unformatted}" ]]; then
            echo "arquivos Go sem gofmt:" >&2
            echo "${unformatted}" >&2
            exit 1
        fi
        go vet ./...
        go test -race ./...
    '
