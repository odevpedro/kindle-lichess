#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${repo_dir}/dist/desktop/kindle-lichess-bridge"
token_file="${1:-}"
game_id="${2:-}"
move="${3:-}"

if [[ "${token_file}" != /* || ! -f "${token_file}" || -L "${token_file}"
        || "$(stat -c '%a' "${token_file}")" != "600" ]]; then
    echo '{"sent":false,"error":"invalid_token_file"}'
    exit 2
fi
if [[ ! "${game_id}" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
    echo '{"sent":false,"error":"invalid_game_id"}'
    exit 2
fi
if [[ ! "${move}" =~ ^[a-h][1-8][a-h][1-8][qrbn]?$ ]]; then
    echo '{"sent":false,"error":"invalid_uci_move"}'
    exit 2
fi
if [[ ! -x "${binary}" ]] || ! command -v jq >/dev/null 2>&1 \
        || ! command -v socat >/dev/null 2>&1; then
    echo '{"sent":false,"error":"missing_local_dependency"}'
    exit 2
fi

move_dir="$(mktemp -d /tmp/kindle-lichess-move.XXXXXX)"
socket_path="${move_dir}/bridge.sock"
response_file="${move_dir}/responses.jsonl"
bridge_pid=""

cleanup() {
    if [[ -n "${bridge_pid}" ]] && kill -0 "${bridge_pid}" 2>/dev/null; then
        kill -TERM "${bridge_pid}" 2>/dev/null || true
        wait "${bridge_pid}" 2>/dev/null || true
    fi
    if [[ "${move_dir}" == /tmp/kindle-lichess-move.* ]]; then
        rm -rf -- "${move_dir}"
    fi
}
trap cleanup EXIT INT TERM

"${binary}" -socket "${socket_path}" -token-file "${token_file}" \
    >"${move_dir}/bridge.log" 2>&1 &
bridge_pid="$!"
for _ in {1..200}; do
    [[ -S "${socket_path}" ]] && break
    if ! kill -0 "${bridge_pid}" 2>/dev/null; then
        echo '{"sent":false,"error":"bridge_start_failed"}'
        exit 1
    fi
    sleep 0.01
done
if [[ ! -S "${socket_path}" ]]; then
    echo '{"sent":false,"error":"socket_timeout"}'
    exit 1
fi

request_id="phase3-move-${game_id}-${move}"
{
    printf '%s\n' '{"v":1,"type":"connect"}'
    sleep 1
    jq -cn --arg game "${game_id}" '{v:1,type:"open_game",gameId:$game}'
    sleep 1
    jq -cn --arg request "${request_id}" --arg game "${game_id}" --arg move "${move}" \
        '{v:1,type:"move",requestId:$request,gameId:$game,move:$move}'
    sleep 5
    printf '%s\n' '{"v":1,"type":"disconnect"}'
} | socat - "UNIX-CONNECT:${socket_path}" >"${response_file}" || true

if ! jq -e --arg request "${request_id}" '
    select(.type == "command_ok" and .requestId == $request and .command == "move")
' "${response_file}" >/dev/null; then
    code="$(jq -r -s --arg request "${request_id}" '
        [.[] | select(.type == "error" and (.requestId == $request or .requestId == null))][0].code
        // "move_not_confirmed"
    ' "${response_file}" 2>/dev/null || true)"
    jq -cn --arg error "${code:-move_not_confirmed}" '{sent:false,error:$error}'
    exit 1
fi

server_moves="$(jq -r -s --arg game "${game_id}" '
    [.[] | select(.type == "game_state" and .gameId == $game)][-1].state.moves // ""
' "${response_file}" 2>/dev/null || true)"
jq -cn --arg game "${game_id}" --arg move "${move}" --arg moves "${server_moves}" \
    '{sent:true,gameId:$game,move:$move,serverMoves:$moves}'
