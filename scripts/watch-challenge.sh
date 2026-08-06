#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${repo_dir}/dist/desktop/kindle-lichess-bridge"
token_file="${1:-}"
wait_seconds="${2:-10}"
watch_dir="$(mktemp -d /tmp/kindle-lichess-challenge.XXXXXX)"
bridge_pid=""

cleanup() {
    if [[ -n "${bridge_pid}" ]] && kill -0 "${bridge_pid}" 2>/dev/null; then
        kill -TERM "${bridge_pid}" 2>/dev/null || true
        wait "${bridge_pid}" 2>/dev/null || true
    fi
    if [[ "${watch_dir}" == /tmp/kindle-lichess-challenge.* ]]; then
        rm -rf -- "${watch_dir}"
    fi
}
trap cleanup EXIT

if [[ "${token_file}" != /* || ! -f "${token_file}" || -L "${token_file}"
        || "$(stat -c '%a' "${token_file}")" != "600" ]]; then
    echo "erro: token_file_invalid" >&2
    exit 2
fi
if [[ ! "${wait_seconds}" =~ ^[1-9][0-9]?$ ]]; then
    echo "erro: invalid_wait" >&2
    exit 2
fi

"${binary}" -socket "${watch_dir}/bridge.sock" -token-file "${token_file}" \
    >"${watch_dir}/bridge.log" 2>&1 &
bridge_pid="$!"
for _ in {1..200}; do
    if [[ -S "${watch_dir}/bridge.sock" ]]; then break; fi
    if ! kill -0 "${bridge_pid}" 2>/dev/null; then
        echo "erro: bridge_start_failed" >&2
        exit 1
    fi
    sleep 0.01
done

if ! {
        printf '%s\n' '{"v":1,"type":"connect"}'
        sleep "${wait_seconds}"
        printf '%s\n' '{"v":1,"type":"disconnect"}'
    } | socat - "UNIX-CONNECT:${watch_dir}/bridge.sock" >"${watch_dir}/response.jsonl"; then
    true
fi
if ! wait "${bridge_pid}"; then true; fi
bridge_pid=""

challenge="$(jq -cer -s '
    [.[] | select(
        type == "object"
        and .type == "challenge"
        and (.challenge.id | type) == "string"
    )][0]
    | if . == null then empty else {
        type,
        challenge: {
            id: .challenge.id,
            rated: .challenge.rated,
            speed: .challenge.speed,
            variant: .challenge.variant,
            color: .challenge.color,
            challenger: .challenge.challenger,
            timeControl: .challenge.timeControl
        }
    } end
' "${watch_dir}/response.jsonl" 2>/dev/null || true)"
if [[ -z "${challenge}" ]]; then
    code="$(jq -r -s '
        [.[] | select(type == "object" and .type == "error")][0].code
        // "challenge_not_observed"
    ' "${watch_dir}/response.jsonl" 2>/dev/null || true)"
    echo "erro: ${code:-challenge_not_observed}" >&2
    exit 1
fi

echo "${challenge}"
