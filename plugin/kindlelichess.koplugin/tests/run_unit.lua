-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

package.path = "./plugin/kindlelichess.koplugin/?.lua;"
    .. "./plugin/kindlelichess.koplugin/?/?.lua;" .. package.path

local Position = require("chess/position")
local Selection = require("chess/selection")
local Clock = require("chess/clock")
local GameState = require("chess/game_state")
local BoardGeometry = require("ui/board_geometry")

local count = 0
local function check(condition, message)
    count = count + 1
    if not condition then error("check " .. tostring(count) .. " failed: " .. message, 2) end
end

local function piece(position, square, kind, color)
    local value = position:piece_at(square)
    check(value and value.type == kind and value.color == color,
        square .. " should contain " .. color .. kind)
end

local start = assert(Position.from_fen("startpos"))
check(start:to_fen() == Position.START_FEN, "startpos must round-trip")
piece(start, "e2", "p", "w")
piece(start, "e8", "k", "b")
check(start:piece_at("e4") == nil, "e4 must start empty")

local opening = assert(Position.reconstruct("startpos", "e2e4 e7e5 g1f3"))
check(opening:to_fen() == "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
    "opening reconstruction")

local previous = assert(Position.from_fen("startpos"))
local after_e4 = assert(Position.reconstruct("startpos", "e2e4"))
local changed = Position.changed_squares(previous, after_e4)
check(#changed == 2 and changed[1] == "e2" and changed[2] == "e4", "dirty squares after e2e4")

local en_passant = assert(Position.reconstruct("startpos", "e2e4 a7a6 e4e5 d7d5 e5d6"))
piece(en_passant, "d6", "p", "w")
check(en_passant:piece_at("d5") == nil, "en passant captured pawn must be removed")

local castled = assert(Position.reconstruct("startpos",
    "e2e4 e7e5 g1f3 b8c6 f1e2 g8f6 e1g1"))
piece(castled, "g1", "k", "w")
piece(castled, "f1", "r", "w")
check(castled:piece_at("e1") == nil and castled:piece_at("h1") == nil, "castling source squares")
check(not castled.castling:find("K", 1, true) and not castled.castling:find("Q", 1, true),
    "white castling rights removed")

local promotion_fen = "4k3/P7/8/8/8/8/7p/4K3 w - - 0 1"
local promoted = assert(Position.reconstruct(promotion_fen, "a7a8q h2h1n"))
piece(promoted, "a8", "q", "w")
piece(promoted, "h1", "n", "b")

local illegal = assert(Position.from_fen("startpos"))
local _, illegal_reason = illegal:apply_uci("e2e5")
check(illegal_reason == "evidently_illegal", "obvious illegal move must be rejected")
check(illegal:to_fen() == Position.START_FEN, "rejected move must not mutate position")

local selection_position = assert(Position.from_fen("startpos"))
local selection = Selection.new(selection_position, "w")
check(selection:tap("e2").type == "selected", "select own piece")
local intent = selection:tap("e4")
check(intent.type == "move" and intent.uci == "e2e4", "emit UCI intent")
piece(selection_position, "e2", "p", "w")
check(selection_position:piece_at("e4") == nil, "intent must not mutate confirmed board")

local promotion_position = assert(Position.from_fen(promotion_fen))
local promotion_selection = Selection.new(promotion_position, "w")
promotion_selection:tap("a7")
local promotion_intent = promotion_selection:tap("a8")
check(promotion_intent.type == "promotion", "promotion dialog intent")
check(promotion_selection:promote("a7", "a8", "n").uci == "a7a8n", "promotion UCI suffix")

local now = 100
local clock = Clock.new(function() return now end)
clock:update(60000, 90000, "w", 200)
check(clock:remaining("w") == 59900, "half latency correction")
check(clock:remaining("b") == 90000, "inactive clock stays fixed")
now = 105
check(clock:remaining("w") == 54900, "active monotonic countdown")
check(Clock.format(54900) == "00:55", "clock rounds display upward")

local bad_fens = {
    "", "8/8/8/8/8/8/8 w - - 0 1", "8/8/8/8/8/8/8/8 x - - 0 1",
    "8/8/8/8/8/8/8/8 w KK - 0 1", "8/8/8/8/8/8/8/8 w - e4 0 1",
}
for _, fen in ipairs(bad_fens) do
    local value = Position.from_fen(fen)
    check(value == nil, "invalid FEN must fail: " .. fen)
end

check(BoardGeometry.square_at(1, 1, "w") == "a8", "white top-left orientation")
check(BoardGeometry.square_at(8, 8, "w") == "h1", "white bottom-right orientation")
check(BoardGeometry.square_at(1, 1, "b") == "h1", "black top-left orientation")
check(BoardGeometry.square_at(8, 8, "b") == "a8", "black bottom-right orientation")
local row, column = BoardGeometry.coordinates("e4", "b")
check(row == 4 and column == 4, "black reverse coordinate mapping")

now = 200
local state_clock = Clock.new(function() return now end)
local game_state = GameState.new(state_clock)
local initial_event = assert(game_state:apply_game_full({
    initialFen = "startpos",
    state = { moves = "", wtime = 60000, btime = 60000, status = "started" },
}))
check(initial_event.kind == "initial" and #initial_event.dirty == 64, "gameFull rebuilds entire board")
check(assert(game_state:mark_pending("e2e4")), "mark pending move")
local advanced_event = assert(game_state:apply_game_state({
    moves = "e2e4", wtime = 59000, btime = 60000, status = "started",
}))
check(advanced_event.kind == "advanced" and game_state.pending_move == nil, "stream confirms pending move")
local duplicate_event = assert(game_state:apply_game_state({
    moves = "e2e4", wtime = 58900, btime = 60000, status = "started",
}))
check(duplicate_event.kind == "duplicate" and #duplicate_event.dirty == 0, "duplicate state is idempotent")
local diverged_event = assert(game_state:apply_game_state({
    moves = "d2d4", wtime = 58000, btime = 60000, status = "started",
}))
check(diverged_event.kind == "diverged", "divergent server history is detected")
game_state:begin_reconnect()
local reconnected_event = assert(game_state:apply_game_state({
    moves = "d2d4 d7d5", wtime = 58000, btime = 59000, status = "started",
}))
check(reconnected_event.kind == "reconnected" and #reconnected_event.dirty == 64,
    "reconnection discards transient state and redraws all")

print(string.format("ok - %d checks", count))
