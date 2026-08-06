-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Position = require("chess/position")

local GameState = {}
GameState.__index = GameState

local function split_moves(moves)
    if type(moves) ~= "string" then return nil, "moves_not_string" end
    local result = {}
    for move in moves:gmatch("%S+") do result[#result + 1] = move end
    return result
end

local function is_prefix(prefix, complete)
    if #prefix > #complete then return false end
    for index, move in ipairs(prefix) do
        if complete[index] ~= move then return false end
    end
    return true
end

local function all_squares()
    local result = {}
    for file = string.byte("a"), string.byte("h") do
        for rank = 1, 8 do result[#result + 1] = string.char(file) .. tostring(rank) end
    end
    return result
end

function GameState.new(clock)
    return setmetatable({
        clock = assert(clock, "clock is required"),
        initial_fen = nil,
        moves = {},
        position = nil,
        pending_move = nil,
        force_reset = false,
        status = "idle",
    }, GameState)
end

function GameState:mark_pending(uci)
    if self.pending_move then return nil, "move_already_pending" end
    self.pending_move = uci
    return true
end

function GameState:reject_pending()
    local rejected = self.pending_move
    self.pending_move = nil
    return rejected
end

function GameState:begin_reconnect()
    self.pending_move = nil
    self.force_reset = true
    self.status = "reconnecting"
end

function GameState:_apply(initial_fen, snapshot)
    if type(snapshot) ~= "table" then return nil, "state_not_object" end
    local moves, moves_err = split_moves(snapshot.moves)
    if not moves then return nil, moves_err end
    if type(snapshot.wtime) ~= "number" or snapshot.wtime < 0 then return nil, "bad_wtime" end
    if type(snapshot.btime) ~= "number" or snapshot.btime < 0 then return nil, "bad_btime" end

    local next_position, position_err = Position.reconstruct(initial_fen, moves)
    if not next_position then return nil, position_err end

    local kind
    if self.force_reset then
        kind = "reconnected"
    elseif not self.position then
        kind = "initial"
    elseif #self.moves == #moves and is_prefix(self.moves, moves) then
        kind = "duplicate"
    elseif is_prefix(self.moves, moves) then
        kind = "advanced"
    elseif is_prefix(moves, self.moves) then
        kind = "rewound"
    else
        kind = "diverged"
    end

    local dirty = self.position and Position.changed_squares(self.position, next_position) or all_squares()
    if self.force_reset then dirty = all_squares() end

    if self.pending_move then
        if #moves > #self.moves and moves[#self.moves + 1] == self.pending_move then
            self.pending_move = nil
        elseif kind == "rewound" or kind == "diverged" or kind == "reconnected" then
            self.pending_move = nil
        end
    end

    self.initial_fen = initial_fen
    self.moves = moves
    self.position = next_position
    self.status = snapshot.status or self.status
    self.force_reset = false

    local active_color = self.status == "started" and next_position.turn or nil
    self.clock:update(snapshot.wtime, snapshot.btime, active_color, snapshot.latencyMs or 0)

    return {
        kind = kind,
        dirty = dirty,
        position = next_position,
        pending_move = self.pending_move,
        status = self.status,
    }
end

function GameState:apply_game_full(game)
    if type(game) ~= "table" then return nil, "game_not_object" end
    local initial_fen = game.initialFen or "startpos"
    return self:_apply(initial_fen, game.state)
end

function GameState:apply_game_state(state)
    if not self.initial_fen then return nil, "game_full_required" end
    return self:_apply(self.initial_fen, state)
end

return GameState
