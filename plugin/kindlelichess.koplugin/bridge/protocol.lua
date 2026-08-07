-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Protocol = { VERSION = 1, MAX_MESSAGE_BYTES = 65536 }

local plugin_types = {
    connect = true, disconnect = true, accept_challenge = true, decline_challenge = true,
    open_game = true, close_game = true, move = true, offer_draw = true,
    accept_draw = true, decline_draw = true, resign = true, abort = true,
    seek = true, cancel_seek = true, ping = true,
}

local server_types = {
    connected = true, challenge = true, challenge_canceled = true, challenge_declined = true,
    game_start = true, game_finish = true, game_full = true, game_state = true,
    opponent_gone = true, command_ok = true, move_rejected = true, reconnecting = true,
    disconnected = true, error = true, pong = true,
}

local mutating_commands = {
    accept_challenge = true, decline_challenge = true, move = true, offer_draw = true,
    accept_draw = true, decline_draw = true, resign = true, abort = true,
    seek = true, cancel_seek = true,
}

local game_commands = {
    open_game = true, close_game = true, move = true, offer_draw = true,
    accept_draw = true, decline_draw = true, resign = true, abort = true,
}

local function bounded_string(value, minimum, maximum)
    return type(value) == "string" and #value >= minimum and #value <= maximum
end

local function ascii_id(value, maximum)
    if not bounded_string(value, 1, maximum) then return false end
    return value:match("^[A-Za-z0-9_-]+$") ~= nil
end

local function valid_uci(value)
    if type(value) ~= "string" or (#value ~= 4 and #value ~= 5) then return false end
    if not value:sub(1, 2):match("^[a-h][1-8]$")
            or not value:sub(3, 4):match("^[a-h][1-8]$") then return false end
    return #value == 4 or value:sub(5, 5):match("^[qrbn]$") ~= nil
end

local function contains_secret(value, depth)
    if type(value) ~= "table" then return false end
    if depth > 8 then return true end
    for key, child in pairs(value) do
        local lowered = type(key) == "string" and key:lower() or ""
        if lowered == "token" or lowered == "authorization" or lowered == "access_token" then
            return true
        end
        if type(child) == "table" and contains_secret(child, depth + 1) then return true end
    end
    return false
end

local function validate_envelope(message, allowed_types)
    if type(message) ~= "table" then return nil, "message_not_object" end
    if contains_secret(message, 0) then return nil, "secret_field_forbidden" end
    if message.v ~= Protocol.VERSION then return nil, "unsupported_version" end
    if not bounded_string(message.type, 1, 64) then return nil, "invalid_type" end
    if not allowed_types[message.type] then return nil, "unknown_type" end
    return true
end

local function valid_game_state(state)
    if type(state) ~= "table" or type(state.moves) ~= "string" or #state.moves > 32768 then
        return false
    end
    for move in state.moves:gmatch("%S+") do
        if not valid_uci(move) then return false end
    end
    local max_time = 366 * 24 * 60 * 60 * 1000
    return type(state.wtime) == "number" and state.wtime >= 0 and state.wtime <= max_time
        and type(state.btime) == "number" and state.btime >= 0 and state.btime <= max_time
        and bounded_string(state.status, 1, 32)
end

function Protocol.validate_plugin(message)
    local ok, err = validate_envelope(message, plugin_types)
    if not ok then return nil, err end
    local kind = message.type

    if mutating_commands[kind] and not ascii_id(message.requestId, 64) then
        return nil, "invalid_request_id"
    end
    if game_commands[kind] and not ascii_id(message.gameId, 32) then
        return nil, "invalid_game_id"
    end
    if (kind == "accept_challenge" or kind == "decline_challenge")
            and not ascii_id(message.challengeId, 32) then
        return nil, "invalid_challenge_id"
    end
    if kind == "move" and not valid_uci(message.move) then return nil, "invalid_move" end
    if kind == "seek" and not bounded_string(message.timeControl, 1, 32) then
        return nil, "invalid_time_control"
    end
    if kind == "decline_challenge" and message.reason ~= nil
            and not bounded_string(message.reason, 1, 64) then
        return nil, "invalid_reason"
    end
    if kind == "ping" and not bounded_string(message.nonce, 1, 64) then return nil, "invalid_nonce" end
    return true
end

function Protocol.validate_server(message)
    local ok, err = validate_envelope(message, server_types)
    if not ok then return nil, err end
    local kind = message.type

    if kind == "connected" then
        local account = message.account
        if type(account) ~= "table" or not ascii_id(account.id, 32)
                or not bounded_string(account.username, 1, 64) then return nil, "invalid_account" end
    elseif kind == "challenge" then
        if type(message.challenge) ~= "table" or not ascii_id(message.challenge.id, 32) then
            return nil, "invalid_challenge"
        end
    elseif kind == "challenge_canceled" or kind == "challenge_declined" then
        if not ascii_id(message.challengeId, 32) then return nil, "invalid_challenge_id" end
    elseif kind == "game_start" or kind == "game_finish" then
        if type(message.game) ~= "table" or not ascii_id(message.game.id, 32) then
            return nil, "invalid_game"
        end
    elseif kind == "game_full" then
        if not ascii_id(message.gameId, 32) or type(message.state) ~= "table"
                or not bounded_string(message.state.initialFen or "startpos", 1, 128)
                or not valid_game_state(message.state.state) then return nil, "invalid_game_full" end
    elseif kind == "game_state" then
        if not ascii_id(message.gameId, 32) or not valid_game_state(message.state) then
            return nil, "invalid_game_state"
        end
    elseif kind == "command_ok" then
        if not ascii_id(message.requestId, 64) or not bounded_string(message.command, 1, 64) then
            return nil, "invalid_command_result"
        end
    elseif kind == "move_rejected" then
        if not ascii_id(message.requestId, 64) or not ascii_id(message.gameId, 32)
                or not valid_uci(message.move) or not bounded_string(message.reason, 1, 160) then
            return nil, "invalid_move_rejection"
        end
    elseif kind == "reconnecting" then
        if not bounded_string(message.stream, 1, 32) or type(message.retryIn) ~= "number"
                or message.retryIn < 0 or type(message.attempt) ~= "number" then
            return nil, "invalid_reconnect"
        end
    elseif kind == "disconnected" then
        if not bounded_string(message.reason, 1, 160) then return nil, "invalid_disconnect" end
    elseif kind == "error" then
        if not bounded_string(message.code, 1, 64) or not bounded_string(message.message, 1, 240)
                or type(message.fatal) ~= "boolean" then return nil, "invalid_error" end
    elseif kind == "pong" then
        if not bounded_string(message.nonce, 1, 64) then return nil, "invalid_nonce" end
    end
    return true
end

return Protocol
