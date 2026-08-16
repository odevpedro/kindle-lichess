-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Clock = require("chess/clock")
local GameState = require("chess/game_state")
local I18n = require("i18n")
local Pgn = require("chess/pgn")
local Position = require("chess/position")
local Protocol = require("bridge/protocol")
local TimeControl = require("chess/time_control")
local Selection = require("chess/selection")

local Controller = {}
Controller.__index = Controller
local T = I18n.t

local error_messages = {
    token_missing = "No Lichess token was found. Add the token and reopen the plugin",
    token_permissions = "The token file permissions are unsafe. Set mode 0600 and try again",
    token_invalid = "The token file is invalid. Create a new token with board:play access",
    lichess_rejected = "Lichess rejected the action; the challenge may have expired",
    auth_unauthorized = "Token rejected by Lichess",
    auth_forbidden = "Token lacks the board:play permission",
    not_found = "Challenge or game not found",
    rate_limited = "Too many requests; wait and try again",
    network_timeout = "Lichess response timed out",
    network_error = "Network failure while accessing Lichess",
    http_error = "Lichess is temporarily unavailable. Wait and try again",
    not_connected = "Bridge is not connected yet",
    process_start_failed = "The local bridge could not be started. Restart KOReader",
    socket_unavailable = "The local bridge is unavailable. Restart KOReader and check the token",
    socket_in_use = "Another bridge is already using the local socket. Restart KOReader",
    unsafe_socket_path = "The local bridge socket is unsafe. Restart KOReader",
    bridge_closed = "The local bridge stopped. Reopen the plugin",
    socket_read_failed = "The local bridge connection failed while reading. Reopen the plugin",
    socket_write_failed = "The local bridge connection failed while writing. Reopen the plugin",
    ca_file_invalid = "KOReader's certificate file is invalid or unavailable",
    invalid_json = "The bridge returned an invalid message. Reopen the plugin",
    invalid_response = "Lichess returned an unsupported response",
    message_too_large = "A bridge message exceeded the safe size limit",
    internal = "The bridge encountered an internal error. Reopen the plugin",
}

local function error_status(message)
    local source = error_messages[message.code]
    local text = source and T(source) or T("Unexpected bridge error")
    return T("%{message} (%{code})", {
        message = text, code = tostring(message.code or "unknown"),
    })
end

function Controller:error_message(code)
    return error_status({ code = code })
end

function Controller:remember_error(code)
    self.record_error(tostring(code or "internal"))
end

local function last_move(moves)
    local value
    for move in tostring(moves or ""):gmatch("%S+") do value = move end
    if not value then return nil end
    return { from = value:sub(1, 2), to = value:sub(3, 4), uci = value }
end

local supported_speeds = {
    unlimited = true, ultraBullet = true, bullet = true, blitz = true,
    rapid = true, classical = true, correspondence = true, relay = true,
}

local function supported_speed(speed)
    return supported_speeds[speed] == true
end

local end_reasons = {
    mate = "by checkmate",
    checkmate = "by checkmate",
    resign = "by resignation",
    timeout = "on time",
    outoftime = "on time",
    flag = "on time",
    illegalmove = "by illegal move",
    illegal_move = "by illegal move",
    stalemate = "by stalemate",
    draw = "",
    aborted = "",
}

local function normalize_winner(winner)
    if winner == "w" or winner == "white" then return "w" end
    if winner == "b" or winner == "black" then return "b" end
    return nil
end

local function result_summary(game)
    local winner = normalize_winner(game.winner)
    local status = tostring(game.status)
    if status == "aborted" then return T("Game aborted"), "" end
    if winner then
        local color = winner == "w" and T("White") or T("Black")
        local reason = end_reasons[status]
        return T("Victory for %{color}", { color = color }), reason and T(reason) or ""
    end
    local reason = end_reasons[status]
    return T("Drawn game"), reason and T(reason) or ""
end

function Controller.new(options)
    options = options or {}
    local time_control = TimeControl.parse_wire(options.time_control or "600+5")
        or { limit = 600, increment = 5 }
    return setmetatable({
        monotonic_now = assert(options.monotonic_now, "monotonic clock is required"),
        on_change = options.on_change or function() end,
        record_error = options.record_error or function() end,
        bridge = nil,
        request_sequence = 0,
        view = "closed",
        connection = "offline",
        status_text = T("Closed"),
        account = nil,
        challenge = nil,
        game = nil,
        game_state = nil,
        selection = nil,
        last_move = nil,
        promotion = nil,
        seeking = false,
        challenging = false,
        result = nil,
        result_summary = nil,
        result_detail = nil,
        review_index = nil,
        review_position = nil,
        time_control = time_control,
        save_time_control = options.save_time_control or function() end,
        pgn_writer = options.pgn_writer,
        pgn_directory = options.pgn_directory or "/mnt/us/documents/KindleLichess",
        saved_pgn_path = nil,
        chat_messages = {},
        chat_unread = 0,
        chat_pending = false,
        chat_request_id = nil,
        free_position = nil,
        free_selected = nil,
        free_tool = "move",
        awaiting_reconnect_snapshot = false,
        closed = true,
    }, Controller)
end

function Controller:attach_bridge(bridge)
    self.bridge = assert(bridge, "bridge is required")
end

function Controller:_notify(event, payload)
    self.on_change(event, payload or {}, self)
end

function Controller:_request_id()
    self.request_sequence = self.request_sequence + 1
    return "lua-" .. tostring(self.request_sequence)
end

function Controller:_send(message)
    message.v = 1
    local ok, validation_err = Protocol.validate_plugin(message)
    if not ok then return nil, validation_err end
    return self.bridge:send(message)
end

function Controller:start()
    assert(self.bridge, "bridge must be attached")
    self.closed = false
    self.view = "connecting"
    self.connection = "connecting"
    self.status_text = T("Connecting…")
    self:_notify("view")
    local started, start_err = self.bridge:start()
    if start_err ~= nil or started == false then
        self.connection = "offline"
        self:remember_error(start_err)
        self.status_text = self:error_message(start_err)
        self:_notify("error", { code = start_err })
        return nil, start_err
    end
    local ok, err = self:_send({ type = "connect" })
    if not ok then
        self.connection = "offline"
        self:remember_error(err)
        self.status_text = self:error_message(err)
        self:_notify("error", { code = err })
        return nil, err
    end
    return true
end

function Controller:close()
    if self.closed then return end
    self.closed = true
    if self.bridge then
        self:_send({ type = "disconnect" })
        self.bridge:close()
    end
    self.view = "closed"
    self.connection = "offline"
    self.promotion = nil
    self.status_text = T("Closed")
    self:_notify("closed")
end

function Controller:accept_challenge()
    if not self.challenge then return nil, "no_challenge" end
    self.status_text = T("Accepting challenge…")
    self:_notify("status")
    return self:_send({
        type = "accept_challenge", requestId = self:_request_id(),
        challengeId = self.challenge.id,
    })
end

function Controller:decline_challenge()
    if not self.challenge then return nil, "no_challenge" end
    return self:_send({
        type = "decline_challenge", requestId = self:_request_id(),
        challengeId = self.challenge.id, reason = "generic",
    })
end

function Controller:tap_square(square)
    if self.view ~= "game" or not self.selection then return { type = "ignored", reason = "no_game" } end
    if self.review_index ~= nil then return { type = "ignored", reason = "reviewing_history" } end
    local action = self.selection:tap(square)
    if action.type == "promotion" then
        self.promotion = { from = action.from, to = action.to }
    elseif action.type == "move" then
        local marked, mark_err = self.game_state:mark_pending(action.uci)
        if not marked then return { type = "rejected", reason = mark_err } end
        self.selection:set_pending(true)
        self.status_text = T("Sending %{move}…", { move = action.uci })
        local ok, err = self:_send({
            type = "move", requestId = self:_request_id(), gameId = self.game.id, move = action.uci,
        })
        if not ok then
            self.game_state:reject_pending()
            self.selection:set_pending(false)
            self.status_text = T("Move not sent")
            action = { type = "rejected", reason = err }
        end
    end
    self:_notify(action.type, action)
    return action
end

function Controller:promote(from, to, piece)
    if not self.selection then return nil, "no_game" end
    local action = self.selection:promote(from, to, piece)
    if action.type ~= "move" then
        self:_notify("rejected", action)
        return nil, action.reason
    end
    local marked, mark_err = self.game_state:mark_pending(action.uci)
    if not marked then return nil, mark_err end
    self.selection:set_pending(true)
    self.status_text = T("Sending promotion…")
    local ok, err = self:_send({
        type = "move", requestId = self:_request_id(), gameId = self.game.id, move = action.uci,
    })
    if not ok then
        self.game_state:reject_pending()
        self.selection:set_pending(false)
        return nil, err
    end
    self.promotion = nil
    self:_notify("move", action)
    return true
end

function Controller:offer_draw()
    return self:_send({ type = "offer_draw", requestId = self:_request_id(), gameId = self.game.id })
end

function Controller:resign()
    return self:_send({ type = "resign", requestId = self:_request_id(), gameId = self.game.id })
end

function Controller:abort()
    return self:_send({ type = "abort", requestId = self:_request_id(), gameId = self.game.id })
end

function Controller:time_control_label()
    return TimeControl.display(self.time_control)
end

function Controller:set_time_control(value)
    local control, parse_err = TimeControl.parse_user(value)
    if not control then return nil, parse_err end
    local challenge_valid, challenge_err = TimeControl.validate_challenge(control)
    local seek_valid, seek_err = TimeControl.validate_seek(control)
    if not challenge_valid and not seek_valid then return nil, challenge_err or seek_err end
    self.time_control = control
    local wire = assert(TimeControl.to_wire(control))
    self.save_time_control(wire)
    self.status_text = T("Time set: %{time}", { time = TimeControl.display(control) })
    self:_notify("time_control", { value = wire })
    return true
end

function Controller:seek_game()
    if self.view ~= "lobby" then return nil, "not_in_lobby" end
    local valid, valid_err = TimeControl.validate_seek(self.time_control)
    if not valid then return nil, valid_err end
    local label = TimeControl.display(self.time_control)
    self.seeking = true
    self.status_text = T("Searching for an opponent (%{time} casual)…", { time = label })
    self:_notify("status")
    return self:_send({ type = "seek", requestId = self:_request_id(), rated = false,
        timeControl = assert(TimeControl.to_wire(self.time_control)) })
end

function Controller:cancel_seek()
    if not self.seeking then return true end
    self.seeking = false
    self.status_text = T("Search canceled")
    self:_notify("status")
    return self:_send({ type = "cancel_seek", requestId = self:_request_id() })
end

function Controller:create_challenge(username)
    if self.view ~= "lobby" then return nil, "not_in_lobby" end
    local valid, valid_err = TimeControl.validate_challenge(self.time_control)
    if not valid then return nil, valid_err end
    self.challenging = true
    self.status_text = T("Challenging %{username}…", { username = username })
    self:_notify("status")
    return self:_send({
        type = "create_challenge", requestId = self:_request_id(),
        username = tostring(username), rated = false,
        timeControl = assert(TimeControl.to_wire(self.time_control)),
    })
end

function Controller:cancel_challenge()
    if not (self.challenging and self.challenge) then return true end
    self.challenging = false
    self.status_text = T("Canceling challenge…")
    self:_notify("status")
    return self:_send({
        type = "cancel_challenge", requestId = self:_request_id(),
        challengeId = self.challenge.id,
    })
end

function Controller:_position_at(index)
    if not self.game_state or not self.game then return nil, "no_game" end
    local moves = {}
    for move_index = 1, index do moves[move_index] = self.game_state.moves[move_index] end
    return Position.reconstruct(self.game.initialFen or "startpos", moves)
end

function Controller:history_index()
    if not self.game_state then return 0, 0 end
    return self.review_index or #self.game_state.moves, #self.game_state.moves
end

function Controller:display_position()
    return self.review_position or (self.game_state and self.game_state.position)
end

function Controller:display_last_move()
    local index = self:history_index()
    local move = self.game_state and self.game_state.moves[index]
    return move and { from = move:sub(1, 2), to = move:sub(3, 4), uci = move } or nil
end

function Controller:_set_history_index(index)
    if not self.game_state or (self.view ~= "game" and self.view ~= "result") then
        return nil, "no_game"
    end
    local maximum = #self.game_state.moves
    index = math.max(0, math.min(maximum, index))
    if self.view == "game" and index == maximum then
        self.review_index, self.review_position = nil, nil
    else
        local position, err = self:_position_at(index)
        if not position then return nil, err end
        self.review_index, self.review_position = index, position
    end
    if self.selection then self.selection.selected = nil end
    self.promotion = nil
    self:_notify("history", {
        index = index, maximum = maximum, position = self:display_position(),
    })
    return true
end

function Controller:history_back()
    local index = self:history_index()
    return self:_set_history_index(index - 1)
end

function Controller:history_forward()
    local index, maximum = self:history_index()
    return self:_set_history_index(math.min(maximum, index + 1))
end

function Controller:save_pgn_file()
    if self.view ~= "result" or not self.game_state or not self.result then
        return nil, "game_not_finished"
    end
    if not self.pgn_writer then return nil, "pgn_writer_unavailable" end
    local content, generate_err = Pgn.generate(self.game, self.game_state.moves, self.result)
    if not content then return nil, generate_err end
    local path, write_err = self.pgn_writer(self.pgn_directory, self.game, content)
    if not path then return nil, write_err end
    self.saved_pgn_path = path
    self.status_text = T("PGN saved to %{path}", { path = path })
    self:_notify("pgn_saved", { path = path })
    return path
end

function Controller:chat_label()
    return self.chat_unread > 0 and T("Chat (%{count})", { count = self.chat_unread }) or T("Chat")
end

function Controller:chat_transcript(limit)
    limit = math.max(1, tonumber(limit) or 12)
    local lines = {}
    local first = math.max(1, #self.chat_messages - limit + 1)
    for index = first, #self.chat_messages do
        local message = self.chat_messages[index]
        lines[#lines + 1] = tostring(message.username) .. ": " .. tostring(message.text)
    end
    return #lines > 0 and table.concat(lines, "\n\n") or T("No messages in this game.")
end

function Controller:mark_chat_read(silent)
    if self.chat_unread == 0 then return true end
    self.chat_unread = 0
    if not silent then self:_notify("chat_read") end
    return true
end

function Controller:send_chat(text)
    if not self.bridge or not self.game or self.view ~= "game" then
        return nil, "chat_unavailable"
    end
    if self.chat_pending then return nil, "chat_pending" end
    if type(text) ~= "string" then return nil, "invalid_chat_text" end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "invalid_chat_text" end
    local request_id = self:_request_id()
    self.chat_pending, self.chat_request_id = true, request_id
    local ok, err = self:_send({
        type = "send_chat", requestId = request_id, gameId = self.game.id,
        room = "player", text = text,
    })
    if not ok then
        self.chat_pending, self.chat_request_id = false, nil
        return nil, err
    end
    self:_notify("chat_sending", { text = text })
    return true
end

function Controller:simulate_disconnect()
    if self.bridge and self.bridge.simulate_disconnect then self.bridge:simulate_disconnect() end
end

function Controller:start_free_board()
    self.closed = false
    self.view, self.connection = "free_board", "offline"
    self.status_text = T("Free board — move pieces")
    self.free_position = assert(Position.from_fen("startpos"))
    self.free_selected, self.free_tool = nil, "move"
    self:_notify("free_board", { position = self.free_position })
    return true
end

function Controller:enter_free_board()
    if self.bridge then
        self:_send({ type = "disconnect" })
        self.bridge:close()
        self.bridge = nil
    end
    return self:start_free_board()
end

function Controller:free_select_tool(tool)
    if self.view ~= "free_board" then return nil, "not_free_board" end
    if tool ~= "move" and tool ~= "erase" and not tostring(tool):match("^[wb][pnbrqk]$") then
        return nil, "bad_editor_tool"
    end
    self.free_tool, self.free_selected = tool, nil
    self.status_text = tool == "move" and T("Move pieces")
        or (tool == "erase" and T("Erase pieces") or T("Add %{piece}", { piece = tool }))
    self:_notify("free_tool", { tool = tool })
    return true
end

function Controller:free_tap_square(square)
    if self.view ~= "free_board" or not self.free_position then return nil, "not_free_board" end
    local dirty, err
    if self.free_tool == "move" then
        if not self.free_selected then
            if not self.free_position:piece_at(square) then return true end
            self.free_selected = square
            self:_notify("free_selected", { square = square })
            return true
        end
        local from = self.free_selected
        self.free_selected = nil
        if from == square then
            self:_notify("free_selected", {})
            return true
        end
        dirty, err = self.free_position:move_piece_unchecked(from, square)
    elseif self.free_tool == "erase" then
        dirty, err = self.free_position:set_piece(square, nil, nil)
    else
        dirty, err = self.free_position:set_piece(square,
            self.free_tool:sub(1, 1), self.free_tool:sub(2, 2))
    end
    if not dirty then return nil, err end
    self:_notify("free_position", { position = self.free_position, dirty = dirty })
    return true
end

function Controller:free_clear()
    local dirty = self.free_position:clear_board()
    self.free_selected = nil
    self:_notify("free_position", { position = self.free_position, dirty = dirty })
end

function Controller:free_reset()
    self.free_position = assert(Position.from_fen("startpos"))
    self.free_selected = nil
    self:_notify("free_board", { position = self.free_position })
end

function Controller:free_toggle_turn()
    self.free_position:set_turn(self.free_position.turn == "w" and "b" or "w")
    self.status_text = self.free_position.turn == "w" and T("White to move") or T("Black to move")
    self:_notify("free_position", { position = self.free_position, dirty = {} })
end

function Controller:free_import_fen(fen)
    local position, err = Position.from_fen(fen)
    if not position then return nil, err end
    self.free_position, self.free_selected = position, nil
    self.status_text = T("FEN loaded")
    self:_notify("free_board", { position = position })
    return true
end

function Controller:free_fen()
    return self.free_position and self.free_position:to_fen() or nil
end

function Controller:_apply_full(payload)
    if payload.variant ~= "standard" then return nil, "unsupported_variant" end
    if not supported_speed(payload.speed) then return nil, "unsupported_speed" end
    local player_color = payload.color
    if player_color ~= "w" and player_color ~= "b" then return nil, "invalid_player_color" end

    local game_state
    if self.awaiting_reconnect_snapshot and self.game_state then
        game_state = self.game_state
    else
        game_state = GameState.new(Clock.new(self.monotonic_now))
    end
    if not self.game or self.game.id ~= payload.id then
        self.chat_messages = {}
        self.chat_unread = 0
        self.chat_pending, self.chat_request_id = false, nil
    end
    local update, err = game_state:apply_game_full(payload)
    if not update then return nil, err end

    self.game_state = game_state
    self.game = payload
    self.game.id = payload.id
    self.game.player_color = player_color
    self.selection = Selection.new(update.position, player_color)
    self.awaiting_reconnect_snapshot = false
    self.last_move = last_move(payload.state.moves)
    self.promotion = nil
    if self.review_index ~= nil then
        self.review_index = math.min(self.review_index, #self.game_state.moves)
        self.review_position = assert(self:_position_at(self.review_index))
    else
        self.review_position = nil
    end
    self.view = "game"
    self.connection = "connected"
    self.status_text = update.position.turn == player_color and T("Your turn") or T("Opponent's turn")
    return update
end

function Controller:_apply_state(payload)
    if not self.game_state then return nil, "game_full_required" end
    local update, err = self.game_state:apply_game_state(payload)
    if not update then return nil, err end
    self.selection:set_position(update.position)
    self.selection:set_pending(update.pending_move ~= nil)
    self.promotion = nil
    self.last_move = last_move(payload.moves)
    if self.review_index ~= nil then
        self.review_index = math.min(self.review_index, #self.game_state.moves)
        self.review_position = assert(self:_position_at(self.review_index))
    end
    self.status_text = update.status == "started"
        and (update.position.turn == self.game.player_color and T("Your turn") or T("Opponent's turn"))
        or T("Game finished")
    return update
end

function Controller:handle(message)
    if self.closed then return nil, "controller_closed" end
    local valid, validation_err = Protocol.validate_server(message)
    if not valid then
        self:remember_error(validation_err)
        self.status_text = T("Invalid bridge message")
        self:_notify("invalid_message", { reason = validation_err })
        return nil, validation_err
    end

    local kind = message.type
    if kind == "connected" then
        self.account = message.account
        self.connection = "connected"
        if self.view ~= "game" then self.view = "lobby" end
        self.status_text = T("Connected as %{username}", { username = message.account.username })
        self:_notify("connected", message)
    elseif kind == "challenge" then
        local direction = message.challenge.direction
        if direction == "out" then
            self.challenge = message.challenge
            self.challenging = true
            self.view = "challenging"
            self.status_text = T("Challenge sent, waiting for acceptance…")
            self:_notify("challenging", message)
        else
            if self.seeking then self.seeking = false end
            self.challenging = false
            self.challenge = message.challenge
            self.view = "challenge"
            self.status_text = T("Challenge received")
            self:_notify("challenge", message)
        end
    elseif kind == "challenge_canceled" or kind == "challenge_declined" then
        self.challenge = nil
        self.challenging = false
        self.view = "lobby"
        self.status_text = kind == "challenge_declined" and T("Challenge declined")
            or T("Challenge canceled")
        self:_notify(kind, message)
    elseif kind == "game_start" then
        self.challenge = nil
        self.seeking = false
        self.challenging = false
        self.review_index, self.review_position = nil, nil
        self.chat_messages, self.chat_unread = {}, 0
        self.chat_pending, self.chat_request_id = false, nil
        self.saved_pgn_path = nil
        self.game = message.game
        self.view = "opening_game"
        self.status_text = T("Opening game…")
        self:_notify("game_start", message)
        self:_send({ type = "open_game", gameId = message.game.id })
    elseif kind == "game_full" then
        local update, err = self:_apply_full(message.state)
        if not update then
            self.status_text = T("Incompatible game: %{error}", { error = err })
            self:_notify("error", { code = err })
            return nil, err
        end
        self:_notify("game_full", update)
    elseif kind == "game_state" then
        local update, err = self:_apply_state(message.state)
        if not update then
            self.status_text = T("Invalid state: %{error}", { error = err })
            self:_notify("error", { code = err })
            return nil, err
        end
        self:_notify("game_state", update)
    elseif kind == "chat_line" then
        self.chat_messages[#self.chat_messages + 1] = {
            username = message.username, text = message.text,
        }
        if #self.chat_messages > 40 then table.remove(self.chat_messages, 1) end
        local own = self.account and self.account.username
            and self.account.username:lower() == message.username:lower()
        if own then self.chat_pending, self.chat_request_id = false, nil end
        if not own then self.chat_unread = math.min(99, self.chat_unread + 1) end
        self:_notify("chat_line", {
            message = self.chat_messages[#self.chat_messages], own = own,
            unread = self.chat_unread,
        })
    elseif kind == "move_rejected" then
        if self.game_state then self.game_state:reject_pending() end
        if self.selection then self.selection:set_pending(false) end
        self.status_text = T("Move rejected")
        self:_notify("move_rejected", message)
    elseif kind == "reconnecting" then
        self.connection = "reconnecting"
        self.status_text = T("Reconnecting in %{seconds} s…", { seconds = message.retryIn })
        if self.game_state then self.game_state:begin_reconnect() end
        self.awaiting_reconnect_snapshot = true
        if self.selection then self.selection:set_pending(false) end
        self:_notify("reconnecting", message)
    elseif kind == "disconnected" then
        if self.game_state then self.game_state:begin_reconnect() end
        self.awaiting_reconnect_snapshot = true
        if self.selection then self.selection:set_pending(false) end
        self.connection = "reconnecting"
        self.status_text = T("Reconnecting…")
        self:_notify("disconnected", message)
    elseif kind == "game_finish" then
        self.result = message.game
        self.view = "result"
        local summary, detail = result_summary(message.game)
        self.result_summary = summary
        self.result_detail = detail
        if self.game_state then
            self.review_index = #self.game_state.moves
            self.review_position = assert(self:_position_at(self.review_index))
        end
        if message.game.status == "draw" then
            self.status_text = T("Drawn game")
        elseif message.game.status == "aborted" then
            self.status_text = T("Game aborted")
        else
            local player_color = self.game and self.game.player_color
            self.status_text = normalize_winner(message.game.winner) == player_color
                and T("Victory") or T("Defeat")
        end
        self:_notify("game_finish", message)
    elseif kind == "error" then
        if message.requestId and message.requestId == self.chat_request_id then
            self.chat_pending, self.chat_request_id = false, nil
        end
        self:remember_error(message.code)
        self.status_text = error_status(message)
        if message.fatal or self.view == "connecting" then self.connection = "offline" end
        if not message.fatal and (self.seeking or self.challenging) then
            self.seeking = false
            self.challenging = false
            self.view = "lobby"
        end
        self:_notify("error", message)
    elseif kind == "opponent_gone" then
        self.status_text = message.gone and T("Opponent disconnected") or T("Opponent reconnected")
        self:_notify("opponent_gone", message)
    elseif kind == "command_ok" then
        if message.command == "send_chat" and message.requestId == self.chat_request_id then
            self.chat_pending, self.chat_request_id = false, nil
        end
        self:_notify(kind, message)
    elseif kind == "pong" then
        self:_notify(kind, message)
    end
    return true
end

return Controller
