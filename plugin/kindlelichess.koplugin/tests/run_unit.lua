-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

package.path = "./plugin/kindlelichess.koplugin/?.lua;"
    .. "./plugin/kindlelichess.koplugin/?/?.lua;" .. package.path

local Position = require("chess/position")
local Pgn = require("chess/pgn")
local Selection = require("chess/selection")
local Clock = require("chess/clock")
local GameState = require("chess/game_state")
local I18n = require("i18n")
local TimeControl = require("chess/time_control")
local BoardGeometry = require("ui/board_geometry")
local Controller = require("controller")
local DiagnosticExport = require("storage/diagnostic_export")
local MockBridge = require("bridge/mock_bridge")
local Protocol = require("bridge/protocol")

I18n.set_language("en")

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

check(I18n.normalize("pt-BR") == "pt_BR", "hyphenated Brazilian Portuguese is normalized")
check(I18n.normalize("en_US") == "en", "English locale falls back to English")
check(I18n.t("Open Kindle Lichess") == "Open Kindle Lichess",
    "English source is the default and fallback")
I18n.set_language("pt_BR")
check(I18n.t("Open Kindle Lichess") == "Abrir Kindle Lichess",
    "Brazilian Portuguese catalog translates known source strings")
check(I18n.t("Connected as %{username}", { username = "Ana" }) == "Conectado como Ana",
    "translations safely interpolate named values")
check(I18n.t("Uncatalogued source") == "Uncatalogued source",
    "missing catalog entries fall back to the English source")
local original_reader_settings = rawget(_G, "G_reader_settings")
_G.G_reader_settings = {
    readSetting = function(_, name)
        if name == "kindlelichess_language" then return "auto" end
        if name == "language" then return "pt-BR" end
    end,
}
I18n.set_language("auto")
check(I18n.language() == "pt_BR" and I18n.t("Closed") == "Fechado",
    "automatic mode follows the KOReader language setting")
local translated_controller = Controller.new{ monotonic_now = function() return 0 end }
check(translated_controller.status_text == "Fechado",
    "controller status is translated through the shared catalog")
_G.G_reader_settings = original_reader_settings
I18n.set_language("en")

local diagnostic_canary = "private-user-game-token-canary"
local diagnostic = DiagnosticExport.format{
    language = "pt_BR", bridge_mode = "live", last_error = "token_missing",
    username = diagnostic_canary, game_id = diagnostic_canary, token = diagnostic_canary,
}
check(diagnostic:find("language=pt_BR", 1, true) ~= nil
        and diagnostic:find("last_error=token_missing", 1, true) ~= nil,
    "sanitized diagnostics retain allowlisted support fields")
check(diagnostic:find(diagnostic_canary, 1, true) == nil,
    "sanitized diagnostics omit account, game and token values")
local poisoned_diagnostic = DiagnosticExport.format{
    language = diagnostic_canary, bridge_mode = diagnostic_canary,
    last_error = diagnostic_canary,
}
check(poisoned_diagnostic:find(diagnostic_canary, 1, true) == nil,
    "sanitized diagnostics reject untrusted values even in allowlisted fields")

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
check(#en_passant:captured_by("w") == 1 and en_passant:captured_by("w")[1].type == "p",
    "en passant records the captured pawn")
check(en_passant:material_advantage("w") == 1 and en_passant:material_advantage("b") == -1,
    "material advantage reflects the confirmed board")

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

local captured_promotion = assert(Position.reconstruct(
    "1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1", "a7a8q b8a8"))
check(#captured_promotion:captured_by("b") == 1
        and captured_promotion:captured_by("b")[1].type == "q",
    "a promoted piece is recorded with its promoted type when captured")
check(captured_promotion:material_advantage("b") == 5,
    "promotion and capture use conventional current material values")

local custom_capture = assert(Position.reconstruct(
    "4k3/8/8/8/8/8/r3Q3/4K3 w - - 0 1", "e2a2"))
check(#custom_capture:captured_by("w") == 1 and custom_capture:captured_by("w")[1].type == "r",
    "custom initial positions count only pieces captured after initialFen")
check(custom_capture:material_advantage("w") == 9,
    "custom initial positions compute material from their current board")

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

local capture_state = GameState.new(Clock.new(function() return now end))
assert(capture_state:apply_game_full({
    initialFen = "startpos",
    state = { moves = "e2e4 d7d5 e4d5 d8d5", wtime = 60000, btime = 60000, status = "started" },
}))
check(#capture_state.position:captured_by("w") == 1
        and #capture_state.position:captured_by("b") == 1,
    "game state reconstructs both players' capture ledgers")
local reset_captures = assert(capture_state:apply_game_state({
    moves = "d2d4", wtime = 59000, btime = 60000, status = "started",
}))
check(reset_captures.kind == "diverged"
        and #capture_state.position:captured_by("w") == 0
        and #capture_state.position:captured_by("b") == 0,
    "divergent authoritative history replaces rather than accumulates captures")

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
check(Protocol.validate_plugin({ v = 1, type = "send_chat", requestId = "chat-1",
    gameId = "game01", room = "player", text = "Boa partida!" }) == true,
    "player chat command is valid")
local _, bad_room_err = Protocol.validate_plugin({ v = 1, type = "send_chat",
    requestId = "chat-2", gameId = "game01", room = "spectator", text = "oi" })
check(bad_room_err == "invalid_chat_room", "spectator chat is not exposed")
local _, bad_chat_err = Protocol.validate_plugin({ v = 1, type = "send_chat",
    requestId = "chat-3", gameId = "game01", room = "player", text = "oi\n" })
check(bad_chat_err == "invalid_chat_text", "chat rejects control characters")

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
assert(controller:send_chat("  Boa partida!  "))
check(#controller.chat_messages == 1 and controller.chat_messages[1].text == "Boa partida!"
        and controller.chat_unread == 0 and controller.chat_pending == false,
    "own chat message is streamed back without becoming unread")
assert(mock:simulate_chat("Bom jogo!"))
check(#controller.chat_messages == 2 and controller.chat_messages[2].username == "MockOpponent"
        and controller.chat_unread == 1 and controller:chat_label() == "Chat (1)",
    "opponent chat message increments unread count")
check(controller:chat_transcript(2):find("MockOpponent: Bom jogo!", 1, true) ~= nil,
    "chat transcript includes the opponent message")
assert(controller:mark_chat_read())
check(controller.chat_unread == 0 and controller:chat_label() == "Chat", "opening chat marks it read")
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
check(controller.view == "result" and controller.status_text == "Drawn game", "draw reaches result screen")
controller:close()
check(controller.view == "closed" and not mock.alive, "closing UI stops mock bridge")

local result_cases = {
    { status = "mate", winner = "white", summary = "Victory for White", detail = "by checkmate" },
    { status = "resign", winner = "black", summary = "Victory for Black", detail = "by resignation" },
    { status = "timeout", winner = "w", summary = "Victory for White", detail = "on time" },
    { status = "stalemate", winner = nil, summary = "Drawn game", detail = "by stalemate" },
    { status = "draw", winner = nil, summary = "Drawn game", detail = "" },
    { status = "aborted", winner = nil, summary = "Game aborted", detail = "" },
}
local result_controller = Controller.new({ monotonic_now = function() return now end })
result_controller.closed = false
result_controller.game = { id = "mockgame01", player_color = "w" }
for _, case in ipairs(result_cases) do
    assert(result_controller:handle({ v = 1, type = "game_finish",
        game = { id = "mockgame01", status = case.status, winner = case.winner } }))
    check(result_controller.result_summary == case.summary, "result summary for " .. case.status)
    check(result_controller.result_detail == case.detail, "result detail for " .. case.status)
end

local speed_controller = Controller.new({ monotonic_now = function() return now end })
speed_controller.closed = false
local function speed_payload(speed)
    return { variant = "standard", speed = speed, color = "w", id = "speedgame",
        initialFen = "startpos", state = { moves = "", wtime = 0, btime = 0, status = "started" } }
end
for _, speed in ipairs({ "unlimited", "bullet", "blitz", "ultraBullet", "rapid", "classical", "relay" }) do
    check(speed_controller:_apply_full(speed_payload(speed)) ~= nil, "accepted unsupported speed " .. speed)
end
check(speed_controller:_apply_full(speed_payload("nonsense")) == nil, "rejects unknown speed")
check(speed_controller:_apply_full({ variant = "binary", speed = "rapid", color = "w", id = "v",
    initialFen = "startpos", state = { moves = "", wtime = 0, btime = 0, status = "started" } }) == nil,
    "rejects unsupported variant")

local seek_controller = Controller.new({ monotonic_now = function() return now end })
local seek_events = {}
local seek_mock = MockBridge.new({
    emit = function(message)
        seek_events[#seek_events + 1] = message.type
        return seek_controller:handle(message)
    end,
})
seek_controller:attach_bridge(seek_mock)
seek_controller:start()
assert(seek_controller:decline_challenge())
check(seek_controller.view == "lobby", "declined challenge returns to lobby")
check(seek_controller.seeking == false, "not seeking before request")
assert(seek_controller:seek_game())
check(seek_controller.view == "game" and seek_controller.game.id == "mockgame01",
    "seek matches a random opponent on the mock")
local saw_game_start, saw_command_ok = false, false
for _, event in ipairs(seek_events) do
    if event == "game_start" then saw_game_start = true end
    if event == "command_ok" then saw_command_ok = true end
end
check(saw_command_ok and saw_game_start, "seek emits command_ok then game_start")
check(seek_controller.seeking == false, "matching clears seeking")
check(seek_controller:cancel_seek() == true, "cancel without active seek is a no-op")

local challenge_controller = Controller.new({ monotonic_now = function() return now end })
local challenge_events = {}
local challenge_sent = {}
local challenge_mock = MockBridge.new({
    emit = function(message)
        challenge_events[#challenge_events + 1] = message.type
        return challenge_controller:handle(message)
    end,
})
challenge_mock.send = function(_, message)
    challenge_sent[#challenge_sent + 1] = message
    return MockBridge.send(challenge_mock, message)
end
challenge_controller:attach_bridge(challenge_mock)
challenge_controller:start()
assert(challenge_controller:decline_challenge())
check(challenge_controller.view == "lobby", "direct challenge starts from lobby")
check(challenge_controller.challenging == false, "not challenging before request")
assert(challenge_controller:create_challenge("PlayerTwo"))
local create_sent
for _, message in ipairs(challenge_sent) do
    if message.type == "create_challenge" then create_sent = message end
end
check(create_sent and create_sent.username == "PlayerTwo" and create_sent.timeControl == "600+5"
        and create_sent.rated == false,
    "direct challenge sends username, casual 10+5 to the bridge")
check(challenge_controller.view == "game" and challenge_controller.game.id == "mockgame01",
    "mock direct challenge matches an opponent immediately")
check(challenge_events[#challenge_events - 2] == "command_ok"
        and challenge_events[#challenge_events - 1] == "game_start",
    "direct challenge emits command_ok before game_start")
check(challenge_controller.challenging == false, "matching clears challenging")
check(challenge_controller:cancel_challenge() == true, "cancel without active challenge is a no-op")
challenge_controller:close()

local outbound_controller = Controller.new({ monotonic_now = function() return now end })
outbound_controller.closed = false
assert(outbound_controller:handle({ v = 1, type = "connected", account = { id = "acc1", username = "test" } }))
assert(outbound_controller:handle({
    v = 1, type = "challenge", challenge = {
        id = "out1", direction = "out", status = "created", rated = false,
        speed = "rapid", variant = "standard",
    },
}))
check(outbound_controller.view == "challenging" and outbound_controller.challenging == true,
    "outbound challenge stays in waiting state, not accept/decline")
assert(outbound_controller:handle({
    v = 1, type = "challenge", challenge = {
        id = "in1", direction = "in", status = "created", rated = false,
        speed = "rapid", variant = "standard",
    },
}))
check(outbound_controller.view == "challenge" and outbound_controller.challenging == false,
    "inbound challenge returns to accept/decline view")
assert(outbound_controller:handle({
    v = 1, type = "challenge_canceled", challengeId = "in1",
}))
check(outbound_controller.view == "lobby", "canceled challenge returns to lobby")
outbound_controller:close()

local recorded_error
local invalid_controller = Controller.new({
    monotonic_now = function() return now end,
    record_error = function(code) recorded_error = code end,
})
invalid_controller.closed = false
local invalid_ok, invalid_err = invalid_controller:handle({ v = 1, type = "connected", account = {} })
check(not invalid_ok and invalid_err == "invalid_account", "malformed bridge message is recoverable")
assert(invalid_controller:handle({
    v = 1, type = "error", code = "lichess_rejected",
    message = "Bridge request failed", fatal = false,
}))
check(invalid_controller.status_text
        == "Lichess rejected the action; the challenge may have expired (lichess_rejected)",
    "controller exposes a useful API error instead of a generic bridge failure")
check(recorded_error == "lichess_rejected", "controller records only the stable error code")
local private_error_canary = "private-upstream-error-canary"
assert(invalid_controller:handle({
    v = 1, type = "error", code = "future_error",
    message = private_error_canary, fatal = false,
}))
check(invalid_controller.status_text == "Unexpected bridge error (future_error)"
        and not invalid_controller.status_text:find(private_error_canary, 1, true),
    "unknown bridge errors do not expose raw upstream text")

local startup_error
local startup_controller = Controller.new({
    monotonic_now = function() return now end,
    record_error = function(code) startup_error = code end,
})
startup_controller:attach_bridge({
    start = function() return nil, "token_missing" end,
    send = function() error("connect must not be sent after failed startup") end,
})
local startup_ok, startup_err = startup_controller:start()
check(not startup_ok and startup_err == "token_missing"
        and startup_error == "token_missing"
        and startup_controller.connection == "offline",
    "missing token is reported before a generic socket failure")
check(startup_controller.status_text
        == "No Lichess token was found. Add the token and reopen the plugin (token_missing)",
    "missing token has an actionable message")

local connecting_controller = Controller.new({ monotonic_now = function() return now end })
connecting_controller.closed = false
connecting_controller.view = "connecting"
connecting_controller.connection = "connecting"
assert(connecting_controller:handle({
    v = 1, type = "error", code = "auth_forbidden",
    message = "Bridge request failed", fatal = false,
}))
check(connecting_controller.connection == "offline",
    "definitive connection error does not leave the title stuck on connecting")

local function fake_bridge()
    local sent = {}
    return {
        sent = sent,
        send = function(_, message) sent[#sent + 1] = message; return true end,
        start = function() return true end,
        close = function() end,
    }
end

local live_controller = Controller.new({ monotonic_now = function() return now end })
live_controller.closed = false
local live_bridge = fake_bridge()
live_controller:attach_bridge(live_bridge)
assert(live_controller:handle({ v = 1, type = "connected", account = { id = "acc1", username = "test" } }))
check(live_controller.view == "lobby" and live_controller.connection == "connected",
    "live handoff: account connection reaches lobby")
assert(live_controller:handle({ v = 1, type = "game_start", game = { id = "livegame" } }))
check(live_controller.view == "opening_game", "live handoff: gameStart opens opening view")
check(live_bridge.sent[1].type == "open_game", "live handoff: open_game sent to bridge")
assert(live_controller:handle({
    v = 1, type = "disconnected", reason = "game_stream_interrupted", retryIn = 1,
}))
check(live_controller.connection == "reconnecting" and live_controller.view == "opening_game",
    "transient stream drop must not collapse the handoff to offline/home")
assert(live_controller:handle({
    v = 1, type = "reconnecting", stream = "game", attempt = 1, retryIn = 1,
}))
check(live_controller.connection == "reconnecting", "reconnect keeps transient state")
assert(live_controller:handle({
    v = 1, type = "game_full", gameId = "livegame",
    state = {
        id = "livegame", variant = "standard", speed = "rapid", rated = false, color = "w",
        initialFen = "startpos",
        white = { id = "acc1", username = "You" }, black = { id = "acc2", username = "Opp" },
        state = { moves = "", wtime = 60000, btime = 60000, winc = 5000, binc = 5000, status = "started" },
    },
}))
check(live_controller.view == "game" and live_controller.game_state ~= nil,
    "gameFull after a transient drop still opens the board")
live_controller:close()

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
check(promotion_controller.view == "result" and promotion_controller.status_text == "Victory",
    "promotion scenario reaches victory")
promotion_controller:close()

local defeat_controller = Controller.new({ monotonic_now = function() return now end })
local defeat_mock = MockBridge.new({ emit = function(message) defeat_controller:handle(message) end })
defeat_controller:attach_bridge(defeat_mock)
defeat_controller:start()
assert(defeat_controller:accept_challenge())
assert(defeat_mock:simulate_result("defeat"))
check(defeat_controller.view == "result" and defeat_controller.status_text == "Defeat",
    "mock defeat reaches result screen")
defeat_controller:close()

local abort_controller = Controller.new({ monotonic_now = function() return now end })
local abort_mock = MockBridge.new({ emit = function(message) abort_controller:handle(message) end })
abort_controller:attach_bridge(abort_mock)
abort_controller:start()
assert(abort_controller:accept_challenge())
assert(abort_controller:abort())
check(abort_controller.status_text == "Game aborted", "mock abort is not reported as defeat")
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

local custom_time = assert(TimeControl.parse_user("5+10"))
check(custom_time.limit == 300 and custom_time.increment == 10,
    "custom time parses minutes and increment")
check(TimeControl.display(custom_time) == "5+10", "custom time round-trips for display")
check(TimeControl.validate_seek(custom_time) == true, "5+10 is a valid rapid seek")
local too_fast, too_fast_err = TimeControl.validate_seek(assert(TimeControl.parse_user("5+0")))
check(not too_fast and too_fast_err == "board_api_too_fast",
    "public Board API seek rejects blitz")
check(TimeControl.validate_challenge(assert(TimeControl.parse_user("5+0"))) == true,
    "direct Board API challenge accepts blitz")

local editor = Position.empty()
assert(editor:set_piece("e1", "w", "k"))
assert(editor:set_piece("e8", "b", "k"))
assert(editor:set_piece("a2", "w", "q"))
assert(editor:move_piece_unchecked("a2", "h7"))
piece(editor, "h7", "q", "w")
assert(editor:set_turn("b"))
check(editor:to_fen() == "4k3/7Q/8/8/8/8/8/4K3 b - - 0 1",
    "free board serializes an edited position")
editor:clear_board()
check(next(editor.board) == nil, "free board can be cleared")

local pgn_game = {
    id = "pgn01", initialFen = "startpos", rated = false,
    white = { username = "White", rating = 1500 },
    black = { username = "Black", rating = 1510 },
}
local pgn = assert(Pgn.generate(pgn_game, { "e2e4", "e7e5", "g1f3" },
    { status = "resign", winner = "w" }, { date = "2026.08.14" }))
check(pgn:find('[Site "https://lichess.org/pgn01"]', 1, true) ~= nil,
    "PGN links to the Lichess game")
check(pgn:find("1. e4 e5 2. Nf3 1-0", 1, true) ~= nil,
    "PGN converts confirmed UCI history to SAN movetext")

local saved_path, saved_content
local history_controller = Controller.new({
    monotonic_now = function() return now end,
    pgn_writer = function(_, _, content)
        saved_content = content
        saved_path = "/mnt/us/documents/KindleLichess/test.pgn"
        return saved_path
    end,
})
history_controller.closed = false
assert(history_controller:handle({
    v = 1, type = "game_full", gameId = "history01", state = {
        id = "history01", variant = "standard", speed = "rapid", rated = false,
        color = "w", initialFen = "startpos",
        white = { username = "White" }, black = { username = "Black" },
        state = { moves = "e2e4 e7e5", wtime = 590000, btime = 590000,
            winc = 5000, binc = 5000, status = "started" },
    },
}))
assert(history_controller:history_back())
local history_index, history_maximum = history_controller:history_index()
check(history_index == 1 and history_maximum == 2,
    "history back reviews the previous confirmed ply")
piece(history_controller:display_position(), "e4", "p", "w")
check(history_controller:display_position():piece_at("e5") == nil,
    "review position excludes later moves")
check(history_controller:tap_square("e4").reason == "reviewing_history",
    "review mode cannot submit a live move")
assert(history_controller:history_forward())
check(history_controller.review_index == nil
        and history_controller:display_position():piece_at("e5") ~= nil,
    "history forward returns to the live position")
assert(history_controller:handle({
    v = 1, type = "game_finish",
    game = { id = "history01", status = "resign", winner = "w" },
}))
assert(history_controller:history_back())
check(history_controller:history_index() == 1, "finished games remain reviewable")
check(history_controller:save_pgn_file() == saved_path
        and saved_content:find("1. e4 e5 1-0", 1, true),
    "finished game exports its confirmed history as PGN")

local free_controller = Controller.new({ monotonic_now = function() return now end })
assert(free_controller:start_free_board())
assert(free_controller:free_select_tool("erase"))
assert(free_controller:free_tap_square("a2"))
check(free_controller.free_position:piece_at("a2") == nil,
    "free-board erase tool removes a piece without Lichess")
assert(free_controller:free_import_fen("4k3/8/8/8/8/8/8/4K3 b - - 0 1"))
check(free_controller.free_position.turn == "b", "free board imports all FEN state")

print(string.format("ok - %d checks", count))
