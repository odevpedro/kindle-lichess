-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Position = require("chess/position")

local Pgn = {}
local piece_letter = { k = "K", q = "Q", r = "R", b = "B", n = "N" }

local function words(value)
    if type(value) == "table" then return value end
    local result = {}
    for word in tostring(value or ""):gmatch("%S+") do result[#result + 1] = word end
    return result
end

local function escape_tag(value)
    return tostring(value or "?"):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("[%c]", " ")
end

local function has_legal_move(position)
    for square, piece in pairs(position.board) do
        if piece.color == position.turn and #position:legal_destinations(square, position.turn) > 0 then
            return true
        end
    end
    return false
end

local function disambiguation(position, from, to, piece, promotion)
    local alternatives = {}
    for square, candidate in pairs(position.board) do
        if square ~= from and candidate.color == piece.color and candidate.type == piece.type then
            local legal = position:is_legal(square, to, promotion, piece.color)
            if legal then alternatives[#alternatives + 1] = square end
        end
    end
    if #alternatives == 0 then return "" end
    local same_file, same_rank = false, false
    for _, square in ipairs(alternatives) do
        if square:sub(1, 1) == from:sub(1, 1) then same_file = true end
        if square:sub(2, 2) == from:sub(2, 2) then same_rank = true end
    end
    if not same_file then return from:sub(1, 1) end
    if not same_rank then return from:sub(2, 2) end
    return from
end

function Pgn.san(position, uci)
    if type(position) ~= "table" or type(uci) ~= "string" then return nil, "invalid_move" end
    local from, to, promotion = uci:sub(1, 2), uci:sub(3, 4), uci:sub(5, 5)
    if #uci ~= 4 and #uci ~= 5 then return nil, "invalid_move" end
    if promotion == "" then promotion = nil end
    local piece = position:piece_at(from)
    if not piece then return nil, "empty_origin" end
    local legal, reason = position:is_legal(from, to, promotion, piece.color)
    if not legal then return nil, reason end

    local from_file = from:sub(1, 1)
    local to_file = to:sub(1, 1)
    local capture = position:piece_at(to) ~= nil
        or (piece.type == "p" and from_file ~= to_file and to == position.en_passant)
    local san
    if piece.type == "k" and math.abs(from:byte(1) - to:byte(1)) == 2 then
        san = to_file == "g" and "O-O" or "O-O-O"
    elseif piece.type == "p" then
        san = (capture and from_file .. "x" or "") .. to
        if promotion then san = san .. "=" .. promotion:upper() end
    else
        san = piece_letter[piece.type] .. disambiguation(position, from, to, piece, promotion)
            .. (capture and "x" or "") .. to
    end

    local next_position = position:clone()
    local applied, apply_err = next_position:apply_uci(uci)
    if not applied then return nil, apply_err end
    if next_position:is_in_check(next_position.turn) then
        san = san .. (has_legal_move(next_position) and "+" or "#")
    end
    return san
end

local function result_code(result)
    local winner = result and result.winner
    if winner == "w" or winner == "white" then return "1-0" end
    if winner == "b" or winner == "black" then return "0-1" end
    local status = result and result.status
    if status == "draw" or status == "stalemate" then return "1/2-1/2" end
    if status == "aborted" then return "*" end
    return "*"
end

function Pgn.generate(game, moves, result, options)
    game, options = game or {}, options or {}
    local initial_fen = game.initialFen or "startpos"
    local position, position_err = Position.from_fen(initial_fen)
    if not position then return nil, position_err end
    local move_list = words(moves)
    local tokens = {}
    for index, uci in ipairs(move_list) do
        if position.turn == "w" then
            tokens[#tokens + 1] = tostring(position.fullmove) .. "."
        elseif index == 1 then
            tokens[#tokens + 1] = tostring(position.fullmove) .. "..."
        end
        local san, san_err = Pgn.san(position, uci)
        if not san then return nil, "move_" .. tostring(index) .. ":" .. tostring(san_err) end
        tokens[#tokens + 1] = san
        local _, move_err = position:apply_uci(uci)
        if move_err then return nil, "move_" .. tostring(index) .. ":" .. move_err end
    end

    local code = result_code(result)
    tokens[#tokens + 1] = code
    local white, black = game.white or {}, game.black or {}
    local tags = {
        { "Event", game.rated and "Lichess Rated Game" or "Lichess Casual Game" },
        { "Site", game.id and ("https://lichess.org/" .. tostring(game.id)) or "https://lichess.org" },
        { "Date", options.date or os.date("%Y.%m.%d") },
        { "Round", "-" },
        { "White", white.username or white.name or "?" },
        { "Black", black.username or black.name or "?" },
        { "Result", code },
    }
    if white.rating then tags[#tags + 1] = { "WhiteElo", white.rating } end
    if black.rating then tags[#tags + 1] = { "BlackElo", black.rating } end
    if initial_fen ~= "startpos" and initial_fen ~= Position.START_FEN then
        tags[#tags + 1] = { "SetUp", "1" }
        tags[#tags + 1] = { "FEN", initial_fen }
    end
    local lines = {}
    for _, tag in ipairs(tags) do
        lines[#lines + 1] = "[" .. tag[1] .. ' "' .. escape_tag(tag[2]) .. '"]'
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = table.concat(tokens, " ")
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

return Pgn
