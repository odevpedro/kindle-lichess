#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${repo_dir}/dist/desktop/kindle-lichess-bridge"
token_file="${1:-}"
game_id="${2:-}"
action="${3:-}"

if [[ "${token_file}" != /* || ! -f "${token_file}" || -L "${token_file}"
        || "$(stat -c '%a' "${token_file}")" != "600" ]]; then
    echo '{"ok":false,"error":"invalid_token_file"}'
    exit 2
fi
if [[ ! "${game_id}" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
    echo '{"ok":false,"error":"invalid_game_id"}'
    exit 2
fi
case "${action}" in
    offer_draw|resign|abort) ;;
    *) echo '{"ok":false,"error":"invalid_action"}'; exit 2 ;;
esac
if [[ ! -x "${binary}" ]] || ! command -v jq >/dev/null 2>&1 \
        || ! command -v socat >/dev/null 2>&1; then
    echo '{"ok":false,"error":"missing_local_dependency"}'
    exit 2
fi

action_dir="$(mktemp -d /tmp/kindle-lichess-action.XXXXXX)"
socket_path="${action_dir}/bridge.sock"
response_file="${action_dir}/responses.jsonl"
bridge_pid=""

cleanup() {
    if [[ -n "${bridge_pid}" ]] && kill -0 "${bridge_pid}" 2>/dev/null; then
        kill -TERM "${bridge_pid}" 2>/dev/null || true
        wait "${bridge_pid}" 2>/dev/null || true
    fi
    if [[ "${action_dir}" == /tmp/kindle-lichess-action.* ]]; then
        rm -rf -- "${action_dir}"
    fi
}
trap cleanup EXIT INT TERM

"${binary}" -socket "${socket_path}" -token-file "${token_file}" \
    >"${action_dir}/bridge.log" 2>&1 &
bridge_pid="$!"
for _ in {1..200}; do
    [[ -S "${socket_path}" ]] && break
    if ! kill -0 "${bridge_pid}" 2>/dev/null; then
        echo '{"ok":false,"error":"bridge_start_failed"}'
        exit 1
    fi
    sleep 0.01
done
if [[ ! -S "${socket_path}" ]]; then
    echo '{"ok":false,"error":"socket_timeout"}'
    exit 1
fi

request_id="phase3-${action}-${game_id}"
{
    printf '%s\n' '{"v":1,"type":"connect"}'
    sleep 1
    jq -cn --arg game "${game_id}" '{v:1,type:"open_game",gameId:$game}'
    sleep 1
    jq -cn --arg request "${request_id}" --arg game "${game_id}" --arg action "${action}" \
        '{v:1,type:$action,requestId:$request,gameId:$game}'
    sleep 5
    printf '%s\n' '{"v":1,"type":"disconnect"}'
} | socat - "UNIX-CONNECT:${socket_path}" >"${response_file}" || true

if ! jq -e --arg request "${request_id}" --arg action "${action}" '
    select(.type == "command_ok" and .requestId == $request and .command == $action)
' "${response_file}" >/dev/null; then
    code="$(jq -r -s --arg request "${request_id}" '
        [.[] | select(.type == "error" and (.requestId == $request or .requestId == null))][0].code
        // "action_not_confirmed"
    ' "${response_file}" 2>/dev/null || true)"
    jq -cn --arg error "${code:-action_not_confirmed}" '{ok:false,error:$error}'
    exit 1
fi

state="$(jq -c -s --arg game "${game_id}" '
    [.[] | select(.type == "game_state" and .gameId == $game)][-1].state
    | if . == null then null else {
        moves, status, winner: (.winner // null),
        wdraw: (.wdraw // false), bdraw: (.bdraw // false)
      } end
' "${response_file}" 2>/dev/null || true)"
jq -cn --arg game "${game_id}" --arg action "${action}" --argjson state "${state:-null}" \
    '{ok:true,gameId:$game,action:$action,state:$state}'
