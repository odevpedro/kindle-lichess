#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${repo_dir}/dist/desktop/kindle-lichess-bridge"
token_file="${1:-}"
game_id="${2:-}"

if [[ "${token_file}" != /* || ! -f "${token_file}" || -L "${token_file}" ]]; then
    echo '{"found":false,"error":"invalid_token_file"}'
    exit 2
fi
if [[ "$(stat -c '%a' "${token_file}")" != "600" ]]; then
    echo '{"found":false,"error":"unsafe_token_permissions"}'
    exit 2
fi
if [[ ! "${game_id}" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
    echo '{"found":false,"error":"invalid_game_id"}'
    exit 2
fi
if [[ ! -x "${binary}" ]]; then
    echo '{"found":false,"error":"desktop_binary_missing"}'
    exit 2
fi
for dependency in jq socat; do
    if ! command -v "${dependency}" >/dev/null 2>&1; then
        echo "{\"found\":false,\"error\":\"missing_${dependency}\"}"
        exit 2
    fi
done

probe_dir="$(mktemp -d /tmp/kindle-lichess-game.XXXXXX)"
socket_path="${probe_dir}/bridge.sock"
response_file="${probe_dir}/responses.jsonl"
bridge_pid=""

cleanup() {
    if [[ -n "${bridge_pid}" ]] && kill -0 "${bridge_pid}" 2>/dev/null; then
        kill -TERM "${bridge_pid}" 2>/dev/null || true
        wait "${bridge_pid}" 2>/dev/null || true
    fi
    if [[ "${probe_dir}" == /tmp/kindle-lichess-game.* ]]; then
        rm -rf -- "${probe_dir}"
    fi
}
trap cleanup EXIT INT TERM

"${binary}" -socket "${socket_path}" -token-file "${token_file}" \
    >"${probe_dir}/bridge.log" 2>&1 &
bridge_pid="$!"

for _ in {1..200}; do
    [[ -S "${socket_path}" ]] && break
    if ! kill -0 "${bridge_pid}" 2>/dev/null; then
        echo '{"found":false,"error":"bridge_start_failed"}'
        exit 1
    fi
    sleep 0.01
done
if [[ ! -S "${socket_path}" ]]; then
    echo '{"found":false,"error":"socket_timeout"}'
    exit 1
fi

{
    printf '%s\n' '{"v":1,"type":"connect"}'
    sleep 2
    jq -cn --arg game "${game_id}" \
        '{v:1,type:"open_game",gameId:$game}'
    sleep 5
    printf '%s\n' '{"v":1,"type":"disconnect"}'
} | socat - "UNIX-CONNECT:${socket_path}" >"${response_file}" || true

snapshot="$(jq -cer -s --arg game "${game_id}" '
    map(select(
        type == "object"
        and .type == "game_full"
        and .gameId == $game
        and (.state.id | type) == "string"
        and (.state.state.status | type) == "string"
    ))
    | last
    | if . == null then empty else {
        id: .state.id,
        variant: .state.variant,
        speed: .state.speed,
        rated: .state.rated,
        color: .state.color,
        initialFen: .state.initialFen,
        white: .state.white,
        black: .state.black,
        state: {
            moves: .state.state.moves,
            wtime: .state.state.wtime,
            btime: .state.state.btime,
            winc: .state.state.winc,
            binc: .state.state.binc,
            status: .state.state.status,
            winner: (.state.state.winner // null)
        }
    } end
' "${response_file}" 2>/dev/null || true)"

if [[ -z "${snapshot}" || "${snapshot}" == "null" ]]; then
    code="$(jq -r -s '
        [.[] | select(type == "object" and .type == "error")][0].code
        // "game_snapshot_not_observed"
    ' "${response_file}" 2>/dev/null || true)"
    jq -cn --arg error "${code:-game_snapshot_not_observed}" \
        '{found:false,error:$error}'
    exit 1
fi

jq -cn --argjson game "${snapshot}" '{found:true,game:$game}'
