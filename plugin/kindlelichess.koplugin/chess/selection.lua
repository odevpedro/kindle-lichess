-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt
-- Interaction pattern adapted from Kochess board.lua at b9e05a8202083b58e290dc719890584919d81245.
-- Original Kochess code copyright Baptiste Fouques, GPL-3.0-or-later.

local Selection = {}
Selection.__index = Selection

function Selection.new(position, player_color)
    assert(position, "position is required")
    assert(player_color == "w" or player_color == "b", "player_color must be w or b")
    return setmetatable({ position = position, player_color = player_color, selected = nil, pending = false }, Selection)
end

function Selection:set_position(position)
    self.position = assert(position, "position is required")
    self.selected = nil
    self.pending = false
end

function Selection:set_pending(pending)
    self.pending = pending == true
    if self.pending then self.selected = nil end
end

function Selection:available_destinations()
    if self.pending or not self.selected or self.position.turn ~= self.player_color then return {} end
    return self.position:legal_destinations(self.selected, self.player_color)
end

function Selection:tap(square)
    if self.pending then return { type = "ignored", reason = "move_pending" } end
    if self.position.turn ~= self.player_color then
        self.selected = nil
        return { type = "ignored", reason = "not_your_turn" }
    end

    local piece = self.position:piece_at(square)
    if not self.selected then
        if piece and piece.color == self.player_color then
            self.selected = square
            return { type = "selected", square = square }
        end
        return { type = "ignored", reason = "empty_or_opponent" }
    end

    local from = self.selected
    if square == from then
        self.selected = nil
        return { type = "deselected", square = square }
    end
    if piece and piece.color == self.player_color then
        self.selected = square
        return { type = "selected", square = square, previous = from }
    end

    self.selected = nil
    local legal, reason, promotion_required = self.position:is_legal(from, square, nil, self.player_color)
    if promotion_required then
        return { type = "promotion", from = from, to = square }
    end
    if not legal then
        return { type = "rejected", from = from, to = square, reason = reason }
    end
    return { type = "move", from = from, to = square, uci = from .. square }
end

function Selection:promote(from, to, piece)
    local legal, reason = self.position:is_legal(from, to, piece, self.player_color)
    if not legal then return { type = "rejected", from = from, to = to, reason = reason } end
    return { type = "move", from = from, to = to, uci = from .. to .. piece }
end

return Selection
