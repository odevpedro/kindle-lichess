-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

package.path = "./plugin/kindlelichess.koplugin/?.lua;"
    .. "./plugin/kindlelichess.koplugin/?/?.lua;" .. package.path

local Position = require("chess/position")
local Selection = require("chess/selection")
local Clock = require("chess/clock")
local GameState = require("chess/game_state")
local BoardGeometry = require("ui/board_geometry")
local Controller = require("controller")
local MockBridge = require("bridge/mock_bridge")
local Protocol = require("bridge/protocol")

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

local promotion_fen = "8/P3k3/8/8/8/8/7p/4K3 w - - 0 1"
local promoted = assert(Position.reconstruct(promotion_fen, "a7a8q h2h1n"))
piece(promoted, "a8", "q", "w")
piece(promoted, "h1", "n", "b")

local illegal = assert(Position.from_fen("startpos"))
local _, illegal_reason = illegal:apply_uci("e2e5")
check(illegal_reason == "evidently_illegal", "obvious illegal move must be rejected")
check(illegal:to_fen() == Position.START_FEN, "rejected move must not mutate position")

local king_capture = assert(Position.from_fen("4k3/8/8/8/8/8/4Q3/4K3 w - - 0 1"))
local _, king_capture_reason = king_capture:apply_uci("e2e8")
check(king_capture_reason == "king_capture_forbidden", "the opposing king can never be captured")
piece(king_capture, "e8", "k", "b")

local pinned = assert(Position.from_fen("4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1"))
local _, pinned_reason = pinned:apply_uci("e2d2")
check(pinned_reason == "leaves_king_in_check", "a pinned piece cannot expose its king")
local pinned_destinations = table.concat(pinned:legal_destinations("e2", "w"), " ")
check(not pinned_destinations:find("d2", 1, true), "illegal pinned destination is not highlighted")

local king_into_check = assert(Position.from_fen("4k3/8/8/8/8/8/8/r3K3 w - - 0 1"))
local _, king_check_reason = king_into_check:apply_uci("e1d1")
check(king_check_reason == "leaves_king_in_check", "king cannot move onto an attacked square")

local castle_through_check = assert(Position.from_fen("4k3/8/8/8/8/8/5r2/4K2R w K - 0 1"))
local _, castle_reason = castle_through_check:apply_uci("e1g1")
check(castle_reason == "castle_through_check", "castling through check is forbidden")

local en_passant_pin = assert(Position.from_fen("7k/8/8/4KPpr/8/8/8/8 w - g6 0 1"))
local _, en_passant_pin_reason = en_passant_pin:apply_uci("f5g6")
check(en_passant_pin_reason == "leaves_king_in_check", "en passant cannot expose the king")

local check_evasion = assert(Position.from_fen("4k3/8/8/8/8/8/4r3/4K3 w - - 0 1"))
check(assert(check_evasion:apply_uci("e1e2")), "king may legally capture an undefended checking piece")
piece(check_evasion, "e2", "k", "w")

local selection_position = assert(Position.from_fen("startpos"))
local selection = Selection.new(selection_position, "w")
check(selection:tap("e2").type == "selected", "select own piece")
local pawn_destinations = table.concat(selection:available_destinations(), " ")
check(pawn_destinations == "e3 e4", "selected pawn exposes local destinations")
local intent = selection:tap("e4")
check(intent.type == "move" and intent.uci == "e2e4", "emit UCI intent")
piece(selection_position, "e2", "p", "w")
check(selection_position:piece_at("e4") == nil, "intent must not mutate confirmed board")
check(#selection:available_destinations() == 0, "destinations clear after move intent")

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
    "8/8/8/8/8/8/8/4K3 w - - 0 1", "4k3/8/8/8/8/8/4K3/4K3 w - - 0 1",
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

local protocol_ok, protocol_err = Protocol.validate_plugin({
    v = 1, type = "move", requestId = "req-1", gameId = "game01", move = "e2e4",
})
check(protocol_ok and not protocol_err, "valid plugin protocol message")
local _, secret_err = Protocol.validate_plugin({ v = 1, type = "connect", token = "forbidden" })
check(secret_err == "secret_field_forbidden", "token fields never cross IPC")
local _, version_err = Protocol.validate_server({ v = 2, type = "disconnected", reason = "test" })
check(version_err == "unsupported_version", "unsupported protocol version")
local _, unknown_err = Protocol.validate_server({ v = 1, type = "future_message" })
check(unknown_err == "unknown_type", "unknown message type")

local controller_events = {}
local controller = Controller.new({
    monotonic_now = function() return now end,
    on_change = function(event) controller_events[#controller_events + 1] = event end,
})
local mock = MockBridge.new({ emit = function(message) return controller:handle(message) end })
controller:attach_bridge(mock)
controller:start()
check(controller.view == "challenge" and controller.challenge.id == "mockchallenge01",
    "mock connection delivers direct challenge")
assert(controller:accept_challenge())
check(controller.view == "game" and controller.game.id == "mockgame01", "accept opens gameFull")
check(controller.game_state.position:piece_at("e2").type == "p", "game starts from server snapshot")
controller:tap_square("e2")
controller:tap_square("e4")
piece(controller.game_state.position, "e4", "p", "w")
piece(controller.game_state.position, "e5", "p", "b")
check(controller.game_state.pending_move == nil and controller.game_state.position.turn == "w",
    "mock confirms local move then opponent reply")
local continued_moves = {
    { "g1", "f3" }, { "f1", "c4" }, { "d2", "d3" },
    { "c2", "c3" }, { "b1", "d2" },
}
for _, move in ipairs(continued_moves) do
    check(controller:tap_square(move[1]).type == "selected", "mock continuation selects " .. move[1])
    check(controller:tap_square(move[2]).type == "move", "mock continuation moves to " .. move[2])
end
check(#controller.game_state.moves == 12 and controller.game_state.position.turn == "w",
    "mock continues with a legal reply after its scripted opening")
controller:simulate_disconnect()
check(controller.connection == "connected" and controller.view == "game",
    "mock reconnect restores current game")
assert(controller:offer_draw())
check(controller.view == "result" and controller.status_text == "Empate", "draw reaches result screen")
controller:close()
check(controller.view == "closed" and not mock.alive, "closing UI stops mock bridge")

local invalid_controller = Controller.new({ monotonic_now = function() return now end })
invalid_controller.closed = false
local invalid_ok, invalid_err = invalid_controller:handle({ v = 1, type = "connected", account = {} })
check(not invalid_ok and invalid_err == "invalid_account", "malformed bridge message is recoverable")

local decline_controller = Controller.new({ monotonic_now = function() return now end })
local decline_mock = MockBridge.new({ emit = function(message) decline_controller:handle(message) end })
decline_controller:attach_bridge(decline_mock)
decline_controller:start()
assert(decline_controller:decline_challenge())
check(decline_controller.view == "lobby" and decline_controller.challenge == nil,
    "declining challenge returns to lobby")
decline_controller:close()

local promotion_controller = Controller.new({ monotonic_now = function() return now end })
local promotion_mock = MockBridge.new({ emit = function(message) promotion_controller:handle(message) end })
assert(promotion_mock:set_scenario("promotion"))
promotion_controller:attach_bridge(promotion_mock)
promotion_controller:start()
assert(promotion_controller:accept_challenge())
check(promotion_controller:tap_square("a7").type == "selected", "mock promotion selects pawn")
local promotion_prompt = promotion_controller:tap_square("a8")
check(promotion_prompt.type == "promotion", "mock promotion requests piece")
assert(promotion_controller:promote("a7", "a8", "q"))
check(promotion_controller.view == "result" and promotion_controller.status_text == "Vitória",
    "promotion scenario reaches victory")
promotion_controller:close()

local defeat_controller = Controller.new({ monotonic_now = function() return now end })
local defeat_mock = MockBridge.new({ emit = function(message) defeat_controller:handle(message) end })
defeat_controller:attach_bridge(defeat_mock)
defeat_controller:start()
assert(defeat_controller:accept_challenge())
assert(defeat_mock:simulate_result("defeat"))
check(defeat_controller.view == "result" and defeat_controller.status_text == "Derrota",
    "mock defeat reaches result screen")
defeat_controller:close()

local abort_controller = Controller.new({ monotonic_now = function() return now end })
local abort_mock = MockBridge.new({ emit = function(message) abort_controller:handle(message) end })
abort_controller:attach_bridge(abort_mock)
abort_controller:start()
assert(abort_controller:accept_challenge())
assert(abort_controller:abort())
check(abort_controller.status_text == "Partida abortada", "mock abort is not reported as defeat")
abort_controller:close()

local queued, canceled = {}, {}
local pending_mock = MockBridge.new({
    emit = function() end,
    schedule = function(_, callback) queued[#queued + 1] = callback end,
    cancel = function(callback) canceled[callback] = true end,
})
pending_mock:start()
assert(pending_mock:send({ v = 1, type = "connect" }))
pending_mock:close()
check(#queued == 2 and canceled[queued[1]] and canceled[queued[2]],
    "closing mock cancels every scheduled event")
check(next(pending_mock.scheduled) == nil, "closing mock leaves no pending task references")

print(string.format("ok - %d checks", count))
