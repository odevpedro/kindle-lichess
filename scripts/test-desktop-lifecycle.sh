#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${repo_dir}/dist/desktop/kindle-lichess-bridge"
test_dir="$(mktemp -d /tmp/kindle-lichess-lifecycle.XXXXXX)"
bridge_pid=""

cleanup() {
    if [[ -n "${bridge_pid}" ]] && kill -0 "${bridge_pid}" 2>/dev/null; then
        kill -TERM "${bridge_pid}" 2>/dev/null || true
        wait "${bridge_pid}" 2>/dev/null || true
    fi
    if [[ "${test_dir}" == /tmp/kindle-lichess-lifecycle.* ]]; then
        rm -rf -- "${test_dir}"
    fi
}
trap cleanup EXIT

if [[ ! -x "${binary}" ]]; then
    echo "erro: execute ./scripts/build-desktop.sh primeiro" >&2
    exit 1
fi

cp "${repo_dir}/token.example" "${test_dir}/token"
sed -i '1,3d' "${test_dir}/token"
chmod 600 "${test_dir}/token"
"${binary}" -socket "${test_dir}/bridge.sock" -token-file "${test_dir}/token" &
bridge_pid="$!"

for _ in {1..200}; do
    if [[ -S "${test_dir}/bridge.sock" ]]; then break; fi
    if ! kill -0 "${bridge_pid}" 2>/dev/null; then
        echo "erro: bridge encerrou antes de criar o socket" >&2
        exit 1
    fi
    sleep 0.01
done
if [[ ! -S "${test_dir}/bridge.sock" ]]; then
    echo "erro: socket não foi criado" >&2
    exit 1
fi

kill -TERM "${bridge_pid}"
wait "${bridge_pid}"
bridge_pid=""
if [[ -e "${test_dir}/bridge.sock" ]]; then
    echo "erro: socket permaneceu após SIGTERM" >&2
    exit 1
fi

echo "ok - binário desktop encerrou e removeu o socket sem abrir sessão HTTPS"
