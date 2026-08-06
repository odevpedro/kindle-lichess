#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="$repo_dir/dist/desktop/kindle-lichess-bridge"
token_file="${1:-}"
challenge_id="${2:-}"

if [[ -z "$token_file" || -z "$challenge_id" ]]; then
    echo '{"accepted":false,"error":"usage"}'
    exit 2
fi

if [[ "$token_file" != /* || ! -f "$token_file" || -L "$token_file" ]]; then
    echo '{"accepted":false,"error":"invalid_token_file"}'
    exit 2
fi

token_mode="$(stat -c '%a' "$token_file")"
if [[ "$token_mode" != "600" ]]; then
    echo '{"accepted":false,"error":"unsafe_token_permissions"}'
    exit 2
fi

if [[ ! "$challenge_id" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
    echo '{"accepted":false,"error":"invalid_challenge_id"}'
    exit 2
fi

if [[ ! -x "$binary" ]]; then
    echo '{"accepted":false,"error":"desktop_binary_missing"}'
    exit 2
fi

for dependency in jq socat; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo "{\"accepted\":false,\"error\":\"missing_${dependency}\"}"
        exit 2
    fi
done

accept_dir="$(mktemp -d /tmp/kindle-lichess-accept.XXXXXX)"
socket_path="$accept_dir/bridge.sock"
response_file="$accept_dir/responses.jsonl"
bridge_log="$accept_dir/bridge.log"
bridge_pid=""

cleanup() {
    if [[ -n "$bridge_pid" ]] && kill -0 "$bridge_pid" 2>/dev/null; then
        kill -TERM "$bridge_pid" 2>/dev/null || true
        wait "$bridge_pid" 2>/dev/null || true
    fi
    case "$accept_dir" in
        /tmp/kindle-lichess-accept.*) rm -rf -- "$accept_dir" ;;
    esac
}
trap cleanup EXIT INT TERM

"$binary" --socket "$socket_path" --token-file "$token_file" >"$bridge_log" 2>&1 &
bridge_pid=$!

for _ in $(seq 1 50); do
    [[ -S "$socket_path" ]] && break
    if ! kill -0 "$bridge_pid" 2>/dev/null; then
        echo '{"accepted":false,"error":"bridge_start_failed"}'
        exit 1
    fi
    sleep 0.1
done

if [[ ! -S "$socket_path" ]]; then
    echo '{"accepted":false,"error":"socket_timeout"}'
    exit 1
fi

request_id="phase3-accept-${challenge_id}"
{
    printf '%s\n' '{"v":1,"type":"connect"}'
    sleep 2
    jq -cn --arg request "$request_id" --arg challenge "$challenge_id" \
        '{v:1,type:"accept_challenge",requestId:$request,challengeId:$challenge}'
    sleep 5
    printf '%s\n' '{"v":1,"type":"disconnect"}'
} | socat - "UNIX-CONNECT:$socket_path" >"$response_file" || true

if ! jq -e --arg request "$request_id" \
    'select(.type == "command_ok" and .requestId == $request and .command == "accept_challenge")' \
    "$response_file" >/dev/null; then
    error_code="$(jq -r --arg request "$request_id" \
        'select(.type == "error" and (.requestId == $request or .requestId == null)) | .code // "bridge_error"' \
        "$response_file" | tail -n 1)"
    jq -cn --arg error "${error_code:-accept_not_confirmed}" \
        '{accepted:false,error:$error}'
    exit 1
fi

game="$(jq -cs --arg challenge "$challenge_id" '
    map(select(.type == "game_start" and (.game.id | type) == "string"))
    | last
    | if . == null then empty else {
        id: .game.id,
        color: (.game.color // null),
        challengeId: $challenge
      } end
' "$response_file")"

if [[ -z "$game" ]]; then
    jq -cn --arg challenge "$challenge_id" \
        '{accepted:true,challengeId:$challenge,error:"game_start_not_observed"}'
    exit 1
fi

jq -cn --arg challenge "$challenge_id" --argjson game "$game" \
    '{accepted:true,challengeId:$challenge,game:$game}'
