#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${repo_dir}/dist/desktop/kindle-lichess-bridge"
token_file="${1:-}"
ca_file="${2:-}"
probe_dir="$(mktemp -d /tmp/kindle-lichess-account.XXXXXX)"
bridge_pid=""

cleanup() {
    if [[ -n "${bridge_pid}" ]] && kill -0 "${bridge_pid}" 2>/dev/null; then
        kill -TERM "${bridge_pid}" 2>/dev/null || true
        wait "${bridge_pid}" 2>/dev/null || true
    fi
    if [[ "${probe_dir}" == /tmp/kindle-lichess-account.* ]]; then
        rm -rf -- "${probe_dir}"
    fi
}
trap cleanup EXIT

if [[ "${token_file}" != /* || ! -f "${token_file}" || -L "${token_file}" ]]; then
    echo "erro: informe um arquivo de token absoluto, regular e não simbólico" >&2
    exit 2
fi
if [[ "$(stat -c '%a' "${token_file}")" != "600" ]]; then
    echo "erro: o arquivo de token deve ter permissão 600" >&2
    exit 2
fi
if [[ ! -x "${binary}" ]]; then
    echo "erro: execute ./scripts/build-desktop.sh primeiro" >&2
    exit 2
fi
if [[ -n "${ca_file}" && ( "${ca_file}" != /* || ! -f "${ca_file}" || -L "${ca_file}" ) ]]; then
    echo "erro: CA bundle deve ser absoluto, regular e não simbólico" >&2
    exit 2
fi
if ! command -v socat >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "erro: socat e jq são necessários para o probe local" >&2
    exit 2
fi

bridge_args=(-socket "${probe_dir}/bridge.sock" -token-file "${token_file}")
if [[ -n "${ca_file}" ]]; then bridge_args+=(-ca-file "${ca_file}"); fi
"${binary}" "${bridge_args[@]}" >"${probe_dir}/bridge.log" 2>&1 &
bridge_pid="$!"
for _ in {1..200}; do
    if [[ -S "${probe_dir}/bridge.sock" ]]; then break; fi
    if ! kill -0 "${bridge_pid}" 2>/dev/null; then
        echo "erro: bridge encerrou antes de criar o socket" >&2
        exit 1
    fi
    sleep 0.01
done
if [[ ! -S "${probe_dir}/bridge.sock" ]]; then
    echo "erro: socket não foi criado" >&2
    exit 1
fi

if ! {
        printf '%s\n' '{"v":1,"type":"connect"}'
        sleep 3
        printf '%s\n' '{"v":1,"type":"disconnect"}'
    } | socat - "UNIX-CONNECT:${probe_dir}/bridge.sock" >"${probe_dir}/response.jsonl"; then
    # The one-session bridge may close while socat is still unwinding its two directions.
    # The JSON response below, rather than socat's exit status, is authoritative.
    true
fi
if ! wait "${bridge_pid}"; then
    # A peer close may race the explicit disconnect; the protocol response is checked below.
    true
fi
bridge_pid=""

account="$(jq -cer -s '
    [.[] | select(
        type == "object"
        and .type == "connected"
        and (.account.id | type) == "string"
        and (.account.username | type) == "string"
    )][0]
    | if . == null then empty else .account | {id, username, title} end
' "${probe_dir}/response.jsonl" 2>/dev/null || true)"
if [[ -z "${account}" || "${account}" == "null" ]]; then
    code="$(jq -r -s '
        [.[] | select(type == "object" and .type == "error")][0].code
        // "account_probe_failed"
    ' "${probe_dir}/response.jsonl" 2>/dev/null || true)"
    echo "erro: ${code:-account_probe_failed}" >&2
    exit 1
fi

echo "${account}"
