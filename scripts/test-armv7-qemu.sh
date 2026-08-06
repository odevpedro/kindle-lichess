#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${repo_dir}/dist/armv7/kindle-lichess-bridge"
qemu="${1:-}"
token_file="${2:-}"
ca_file="${3:-}"

if [[ "${qemu}" != /* || ! -x "${qemu}" || -L "${qemu}" ]]; then
    echo "erro: qemu-arm deve ser executável absoluto e não simbólico" >&2
    exit 2
fi
if [[ "${token_file}" != /* || ! -f "${token_file}" || -L "${token_file}"
        || "$(stat -c '%a' "${token_file}")" != "600" ]]; then
    echo "erro: token deve ser um arquivo absoluto, regular e 0600" >&2
    exit 2
fi
if [[ "${ca_file}" != /* || ! -f "${ca_file}" || -L "${ca_file}" ]]; then
    echo "erro: CA bundle deve ser um arquivo absoluto, regular e não simbólico" >&2
    exit 2
fi
if [[ ! -x "${binary}" ]]; then
    echo "erro: execute ./scripts/build-armv7.sh primeiro" >&2
    exit 2
fi

test_dir="$(mktemp -d /tmp/kindle-lichess-armv7.XXXXXX)"
socket_path="${test_dir}/bridge.sock"
bridge_pid=""

cleanup() {
    if [[ -n "${bridge_pid}" ]] && kill -0 "${bridge_pid}" 2>/dev/null; then
        kill -TERM "${bridge_pid}" 2>/dev/null || true
        wait "${bridge_pid}" 2>/dev/null || true
    fi
    if [[ "${test_dir}" == /tmp/kindle-lichess-armv7.* ]]; then
        rm -rf -- "${test_dir}"
    fi
}
trap cleanup EXIT INT TERM

"${qemu}" "${binary}" -socket "${socket_path}" -token-file "${token_file}" \
    -ca-file "${ca_file}" \
    >"${test_dir}/stdout.log" 2>"${test_dir}/stderr.log" &
bridge_pid="$!"

for _ in {1..300}; do
    [[ -S "${socket_path}" ]] && break
    if ! kill -0 "${bridge_pid}" 2>/dev/null; then
        echo "erro: ARM bridge encerrou antes de criar o socket" >&2
        exit 1
    fi
    sleep 0.01
done
if [[ ! -S "${socket_path}" ]]; then
    echo "erro: ARM bridge não criou o socket" >&2
    exit 1
fi

max_rss_kib=0
for _ in {1..20}; do
    rss_kib="$(ps -o rss= -p "${bridge_pid}" | tr -d '[:space:]')"
    if [[ "${rss_kib}" =~ ^[0-9]+$ ]] && (( rss_kib > max_rss_kib )); then
        max_rss_kib="${rss_kib}"
    fi
    sleep 0.05
done

kill -TERM "${bridge_pid}"
set +e
wait "${bridge_pid}"
exit_code="$?"
set -e
bridge_pid=""

if [[ -S "${socket_path}" ]]; then
    echo "erro: socket permaneceu após SIGTERM" >&2
    exit 1
fi
if [[ "${exit_code}" -ne 0 ]]; then
    echo "erro: processo ARM encerrou com código ${exit_code}" >&2
    exit 1
fi

printf 'execution=ok\nsocket_create=ok\nsigterm_exit=%s\nsocket_cleanup=ok\nqemu_max_rss_kib=%s\n' \
    "${exit_code}" "${max_rss_kib}"
