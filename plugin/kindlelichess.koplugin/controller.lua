-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Clock = require("chess/clock")
local GameState = require("chess/game_state")
local Protocol = require("bridge/protocol")
local Selection = require("chess/selection")

local Controller = {}
Controller.__index = Controller

local function last_move(moves)
    local value
    for move in tostring(moves or ""):gmatch("%S+") do value = move end
    if not value then return nil end
    return { from = value:sub(1, 2), to = value:sub(3, 4), uci = value }
end

function Controller.new(options)
    options = options or {}
    return setmetatable({
        monotonic_now = assert(options.monotonic_now, "monotonic clock is required"),
        on_change = options.on_change or function() end,
        bridge = nil,
        request_sequence = 0,
        view = "closed",
        connection = "offline",
        status_text = "Fechado",
        account = nil,
        challenge = nil,
        game = nil,
        game_state = nil,
        selection = nil,
        last_move = nil,
        result = nil,
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
    self.status_text = "Conectando ao MockBridge…"
    self:_notify("view")
    self.bridge:start()
    local ok, err = self:_send({ type = "connect" })
    if not ok then
        self.connection = "offline"
        self.status_text = "Falha ao iniciar mock: " .. tostring(err)
        self:_notify("error", { code = err })
    end
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
    self.status_text = "Fechado"
    self:_notify("closed")
end

function Controller:accept_challenge()
    if not self.challenge then return nil, "no_challenge" end
    self.status_text = "Aceitando desafio…"
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
    local action = self.selection:tap(square)
    if action.type == "move" then
        local marked, mark_err = self.game_state:mark_pending(action.uci)
        if not marked then return { type = "rejected", reason = mark_err } end
        self.selection:set_pending(true)
        self.status_text = "Enviando " .. action.uci .. "…"
        local ok, err = self:_send({
            type = "move", requestId = self:_request_id(), gameId = self.game.id, move = action.uci,
        })
        if not ok then
            self.game_state:reject_pending()
            self.selection:set_pending(false)
            self.status_text = "Jogada não enviada"
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
    self.status_text = "Enviando promoção…"
    local ok, err = self:_send({
        type = "move", requestId = self:_request_id(), gameId = self.game.id, move = action.uci,
    })
    if not ok then
        self.game_state:reject_pending()
        self.selection:set_pending(false)
        return nil, err
    end
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

function Controller:simulate_disconnect()
    if self.bridge and self.bridge.simulate_disconnect then self.bridge:simulate_disconnect() end
end

function Controller:_apply_full(payload)
    if payload.variant ~= "standard" then return nil, "unsupported_variant" end
    if payload.speed ~= "rapid" and payload.speed ~= "classical" and payload.speed ~= "correspondence" then
        return nil, "unsupported_speed"
    end
    local player_color = payload.color
    if player_color ~= "w" and player_color ~= "b" then return nil, "invalid_player_color" end

    local game_state
    if self.awaiting_reconnect_snapshot and self.game_state then
        game_state = self.game_state
    else
        game_state = GameState.new(Clock.new(self.monotonic_now))
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
    self.view = "game"
    self.connection = "connected"
    self.status_text = update.position.turn == player_color and "Sua vez" or "Vez do adversário"
    return update
end

function Controller:_apply_state(payload)
    if not self.game_state then return nil, "game_full_required" end
    local update, err = self.game_state:apply_game_state(payload)
    if not update then return nil, err end
    self.selection:set_position(update.position)
    self.selection:set_pending(update.pending_move ~= nil)
    self.last_move = last_move(payload.moves)
    self.status_text = update.status == "started"
        and (update.position.turn == self.game.player_color and "Sua vez" or "Vez do adversário")
        or "Partida encerrada"
    return update
end

function Controller:handle(message)
    if self.closed then return nil, "controller_closed" end
    local valid, validation_err = Protocol.validate_server(message)
    if not valid then
        self.status_text = "Mensagem inválida do bridge"
        self:_notify("invalid_message", { reason = validation_err })
        return nil, validation_err
    end

    local kind = message.type
    if kind == "connected" then
        self.account = message.account
        self.connection = "connected"
        if self.view ~= "game" then self.view = "lobby" end
        self.status_text = "Conectado como " .. message.account.username
        self:_notify("connected", message)
    elseif kind == "challenge" then
        self.challenge = message.challenge
        self.view = "challenge"
        self.status_text = "Desafio recebido"
        self:_notify("challenge", message)
    elseif kind == "challenge_canceled" or kind == "challenge_declined" then
        self.challenge = nil
        self.view = "lobby"
        self.status_text = kind == "challenge_declined" and "Desafio recusado" or "Desafio cancelado"
        self:_notify(kind, message)
    elseif kind == "game_start" then
        self.challenge = nil
        self.game = message.game
        self.view = "opening_game"
        self.status_text = "Abrindo partida…"
        self:_notify("game_start", message)
        self:_send({ type = "open_game", gameId = message.game.id })
    elseif kind == "game_full" then
        local update, err = self:_apply_full(message.state)
        if not update then
            self.status_text = "Partida incompatível: " .. tostring(err)
            self:_notify("error", { code = err })
            return nil, err
        end
        self:_notify("game_full", update)
    elseif kind == "game_state" then
        local update, err = self:_apply_state(message.state)
        if not update then
            self.status_text = "Estado inválido: " .. tostring(err)
            self:_notify("error", { code = err })
            return nil, err
        end
        self:_notify("game_state", update)
    elseif kind == "move_rejected" then
        if self.game_state then self.game_state:reject_pending() end
        if self.selection then self.selection:set_pending(false) end
        self.status_text = "Jogada recusada"
        self:_notify("move_rejected", message)
    elseif kind == "reconnecting" then
        self.connection = "reconnecting"
        self.status_text = "Reconectando em " .. tostring(message.retryIn) .. " s…"
        if self.game_state then self.game_state:begin_reconnect() end
        self.awaiting_reconnect_snapshot = true
        if self.selection then self.selection:set_pending(false) end
        self:_notify("reconnecting", message)
    elseif kind == "disconnected" then
        self.connection = "offline"
        self.status_text = "Sem conexão"
        self:_notify("disconnected", message)
    elseif kind == "game_finish" then
        self.result = message.game
        self.view = "result"
        if message.game.status == "draw" then
            self.status_text = "Empate"
        elseif message.game.status == "aborted" then
            self.status_text = "Partida abortada"
        else
            self.status_text = message.game.winner == (self.game and self.game.player_color)
                and "Vitória" or "Derrota"
        end
        self:_notify("game_finish", message)
    elseif kind == "error" then
        self.status_text = message.message
        if message.fatal then self.connection = "offline" end
        self:_notify("error", message)
    elseif kind == "opponent_gone" then
        self.status_text = message.gone and "Adversário desconectado" or "Adversário reconectou"
        self:_notify("opponent_gone", message)
    elseif kind == "command_ok" or kind == "pong" then
        self:_notify(kind, message)
    end
    return true
end

return Controller
