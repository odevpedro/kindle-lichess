-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Position = require("chess/position")
local Protocol = require("bridge/protocol")

local MockBridge = {}
MockBridge.__index = MockBridge

local GAME_ID = "mockgame01"
local CHALLENGE_ID = "mockchallenge01"

local replies = {
    [1] = "e7e5", [3] = "b8c6", [5] = "g8f6", [7] = "f8c5", [9] = "d7d6",
}

local function immediate(_, callback) callback() end
local function no_cancel() end

-- Deterministic mock-only responder: generates legal moves but performs no evaluation or search.
local function first_legal_move(position)
    for file = string.byte("a"), string.byte("h") do
        for rank = 1, 8 do
            local from = string.char(file) .. tostring(rank)
            local piece = position:piece_at(from)
            if piece and piece.color == position.turn then
                for _, to in ipairs(position:legal_destinations(from, position.turn)) do
                    local promotion = piece.type == "p" and (to:sub(2, 2) == "1" or to:sub(2, 2) == "8")
                    return from .. to .. (promotion and "q" or "")
                end
            end
        end
    end
end

function MockBridge.new(options)
    options = options or {}
    return setmetatable({
        emit_callback = assert(options.emit, "emit callback is required"),
        schedule = options.schedule or immediate,
        cancel = options.cancel or no_cancel,
        scheduled = {},
        alive = false,
        generation = 0,
        moves = {},
        initial_fen = "startpos",
        scenario = "standard",
        wtime = 600000,
        btime = 600000,
        increment = 5,
        status = "started",
    }, MockBridge)
end

function MockBridge:_later(delay, callback)
    local generation = self.generation
    local wrapped
    wrapped = function()
        self.scheduled[wrapped] = nil
        if self.alive and self.generation == generation then callback() end
    end
    self.scheduled[wrapped] = true
    self.schedule(delay, wrapped)
end

function MockBridge:_emit(message, delay)
    local ok, err = Protocol.validate_server(message)
    assert(ok, "invalid mock server message: " .. tostring(err))
    self:_later(delay or 0, function() self.emit_callback(message) end)
end

function MockBridge:_moves_string()
    return table.concat(self.moves, " ")
end

function MockBridge:_state(extra)
    local state = {
        moves = self:_moves_string(), wtime = self.wtime, btime = self.btime,
        winc = self.increment * 1000, binc = self.increment * 1000, status = self.status,
    }
    for key, value in pairs(extra or {}) do state[key] = value end
    return state
end

function MockBridge:start()
    self.alive = true
    self.generation = self.generation + 1
end

function MockBridge:set_scenario(name)
    if self.alive then return nil, "scenario_already_started" end
    if name ~= "standard" and name ~= "promotion" then return nil, "unknown_scenario" end
    self.scenario = name
    self.moves = {}
    self.initial_fen = name == "promotion" and "8/P3k3/8/8/8/8/7p/4K3 w - - 0 1" or "startpos"
    self.status = "started"
    return true
end

function MockBridge:close()
    self.alive = false
    self.generation = self.generation + 1
    for callback in pairs(self.scheduled) do self.cancel(callback) end
    self.scheduled = {}
end

function MockBridge:_command_ok(message)
    self:_emit({ v = 1, type = "command_ok", requestId = message.requestId, command = message.type })
end

function MockBridge:_finish(status, winner)
    self.status = status
    self:_emit({ v = 1, type = "game_state", gameId = GAME_ID,
        state = self:_state({ winner = winner }) }, 0.1)
    self:_emit({ v = 1, type = "game_finish",
        game = { id = GAME_ID, status = status, winner = winner } }, 0.2)
end

function MockBridge:_set_time_control(value)
    local limit, increment = tostring(value or ""):match("^(%d+)%+(%d+)$")
    limit, increment = tonumber(limit), tonumber(increment)
    if limit and increment then
        self.wtime, self.btime = limit * 1000, limit * 1000
        self.increment = increment
    end
end

function MockBridge:send(message)
    if not self.alive then return nil, "mock_closed" end
    local ok, err = Protocol.validate_plugin(message)
    if not ok then return nil, err end

    if message.type == "connect" then
        self:_emit({ v = 1, type = "connected",
            account = { id = "kindletester", username = "KindleTester" } }, 0.05)
        self:_emit({ v = 1, type = "challenge", challenge = {
            id = CHALLENGE_ID, direction = "in", status = "created", rated = false,
            speed = "rapid", variant = "standard", color = "white",
            challenger = { id = "mockopponent", username = "MockOpponent", rating = 1500 },
            timeControl = { type = "clock", limit = 600, increment = 5 },
        } }, 0.1)
    elseif message.type == "disconnect" then
        self:_emit({ v = 1, type = "disconnected", reason = "closed_by_plugin" })
    elseif message.type == "accept_challenge" then
        self:_command_ok(message)
        self:_emit({ v = 1, type = "game_start", game = { id = GAME_ID } }, 0.05)
    elseif message.type == "decline_challenge" then
        self:_command_ok(message)
        self:_emit({ v = 1, type = "challenge_declined", challengeId = message.challengeId,
            reason = message.reason }, 0.05)
    elseif message.type == "open_game" then
        self:_emit({ v = 1, type = "game_full", gameId = GAME_ID, state = {
            id = GAME_ID, variant = "standard", speed = "rapid", rated = false,
            color = "w", initialFen = self.initial_fen,
            white = { id = "kindletester", username = "KindleTester", rating = 1500 },
            black = { id = "mockopponent", username = "MockOpponent", rating = 1500 },
            state = self:_state(),
        } }, 0.05)
    elseif message.type == "move" then
        local position, position_err = Position.reconstruct(self.initial_fen, self.moves)
        local applied, move_err = position and position:apply_uci(message.move)
        if not applied then
            self:_emit({ v = 1, type = "move_rejected", requestId = message.requestId,
                gameId = GAME_ID, move = message.move,
                reason = position_err or move_err or "mock_rejected" })
            return true
        end
        self:_command_ok(message)
        self.moves[#self.moves + 1] = message.move
        self.wtime = math.max(0, self.wtime - 1000 + self.increment * 1000)
        self:_emit({ v = 1, type = "game_state", gameId = GAME_ID, state = self:_state() }, 0.1)
        if self.scenario == "standard" then
            local reply_position = assert(Position.reconstruct(self.initial_fen, self.moves))
            local reply = replies[#self.moves]
            if reply then
                local probe = reply_position:clone()
                if not probe:apply_uci(reply) then reply = nil end
            end
            reply = reply or first_legal_move(reply_position)
            if reply then
                self:_later(0.5, function()
                    local current = assert(Position.reconstruct(self.initial_fen, self.moves))
                    assert(current:apply_uci(reply))
                    self.moves[#self.moves + 1] = reply
                    self.btime = math.max(0, self.btime - 1200 + self.increment * 1000)
                    self:_emit({ v = 1, type = "game_state", gameId = GAME_ID,
                        state = self:_state() })
                end)
            else
                local checked = reply_position:is_in_check(reply_position.turn)
                self:_later(0.5, function()
                    self:_finish(checked and "mate" or "stalemate", checked and "w" or nil)
                end)
            end
        elseif self.scenario == "promotion" then
            self:_finish("mate", "w")
        end
    elseif message.type == "send_chat" then
        self:_command_ok(message)
        self:_emit({ v = 1, type = "chat_line", gameId = GAME_ID,
            room = "player", username = "KindleTester", text = message.text }, 0.05)
    elseif message.type == "offer_draw" or message.type == "accept_draw" then
        self:_command_ok(message)
        self:_finish("draw")
    elseif message.type == "decline_draw" then
        self:_command_ok(message)
    elseif message.type == "resign" then
        self:_command_ok(message)
        self:_finish("resign", "b")
    elseif message.type == "abort" then
        self:_command_ok(message)
        self:_finish("aborted")
    elseif message.type == "seek" then
        self:_set_time_control(message.timeControl)
        self:_command_ok(message)
        self:_emit({ v = 1, type = "game_start", game = { id = GAME_ID } }, 0.05)
    elseif message.type == "cancel_seek" then
        self:_command_ok(message)
    elseif message.type == "create_challenge" then
        self:_set_time_control(message.timeControl)
        self:_command_ok(message)
        self:_emit({ v = 1, type = "game_start", game = { id = GAME_ID } }, 0.05)
    elseif message.type == "cancel_challenge" then
        self:_command_ok(message)
        self:_emit({ v = 1, type = "challenge_canceled", challengeId = message.challengeId }, 0.05)
    elseif message.type == "ping" then
        self:_emit({ v = 1, type = "pong", nonce = message.nonce })
    end
    return true
end

function MockBridge:simulate_disconnect()
    if not self.alive then return end
    self:_emit({ v = 1, type = "reconnecting", stream = "game", retryIn = 1, attempt = 1 })
    self:_emit({ v = 1, type = "disconnected", reason = "mock_wifi_lost", retryIn = 1 }, 0.1)
    self:_emit({ v = 1, type = "connected",
        account = { id = "kindletester", username = "KindleTester" } }, 1)
    self:_emit({ v = 1, type = "game_full", gameId = GAME_ID, state = {
        id = GAME_ID, variant = "standard", speed = "rapid", rated = false,
        color = "w", initialFen = self.initial_fen,
        white = { id = "kindletester", username = "KindleTester", rating = 1500 },
        black = { id = "mockopponent", username = "MockOpponent", rating = 1500 },
        state = self:_state(),
    } }, 1.1)
end


function MockBridge:simulate_chat(text)
    if not self.alive then return nil, "mock_closed" end
    self:_emit({ v = 1, type = "chat_line", gameId = GAME_ID,
        room = "player", username = "MockOpponent", text = text or "Boa partida!" })
    return true
end

function MockBridge:simulate_result(result)
    if result == "victory" then
        self:_finish("mate", "w")
    elseif result == "defeat" then
        self:_finish("resign", "b")
    else
        return nil, "unknown_result"
    end
    return true
end

return MockBridge
