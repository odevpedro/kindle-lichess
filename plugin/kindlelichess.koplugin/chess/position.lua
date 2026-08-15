-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt
-- Clean-room position reducer. No chess engine or evaluation code.

local Position = {}
Position.__index = Position

Position.START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

local valid_piece = { p = true, n = true, b = true, r = true, q = true, k = true }
local valid_promotion = { q = true, r = true, b = true, n = true }
local material_value = { p = 1, n = 3, b = 3, r = 5, q = 9, k = 0 }
local captured_order = { q = 1, r = 2, b = 3, n = 4, p = 5 }

local function copy_piece(piece)
    if not piece then return nil end
    return { type = piece.type, color = piece.color }
end

local function copy_board(board)
    local result = {}
    for square, piece in pairs(board) do
        result[square] = copy_piece(piece)
    end
    return result
end

local function copy_captures(captures)
    local result = { w = {}, b = {} }
    for _, color in ipairs({ "w", "b" }) do
        for index, piece in ipairs(captures and captures[color] or {}) do
            result[color][index] = copy_piece(piece)
        end
    end
    return result
end

local function split_words(value)
    local result = {}
    for word in tostring(value or ""):gmatch("%S+") do
        result[#result + 1] = word
    end
    return result
end

local function square_coords(square)
    if type(square) ~= "string" or not square:match("^[a-h][1-8]$") then
        return nil, nil
    end
    return square:byte(1) - string.byte("a") + 1, tonumber(square:sub(2, 2))
end

local function coords_square(file, rank)
    file, rank = math.floor(file), math.floor(rank)
    if file < 1 or file > 8 or rank < 1 or rank > 8 then return nil end
    return string.char(string.byte("a") + file - 1) .. tostring(rank)
end

local function contains(value, needle)
    return value ~= "-" and value:find(needle, 1, true) ~= nil
end

local function remove_castling(value, rights)
    if value == "-" then return value end
    for i = 1, #rights do
        value = value:gsub(rights:sub(i, i), "")
    end
    return value == "" and "-" or value
end

local function same_piece(left, right)
    if left == nil or right == nil then return left == right end
    return left.type == right.type and left.color == right.color
end

local function valid_castling(value)
    if value == "-" then return true end
    if value == "" then return false end
    local allowed, seen = { K = true, Q = true, k = true, q = true }, {}
    for index = 1, #value do
        local right = value:sub(index, index)
        if not allowed[right] or seen[right] then return false end
        seen[right] = true
    end
    return true
end

function Position.is_square(square)
    return square_coords(square) ~= nil
end

function Position.from_fen(fen)
    if fen == "startpos" then fen = Position.START_FEN end
    if type(fen) ~= "string" then return nil, "fen_not_string" end

    local fields = split_words(fen)
    if #fields ~= 6 then return nil, "fen_field_count" end

    local ranks = {}
    for rank in fields[1]:gmatch("[^/]+") do ranks[#ranks + 1] = rank end
    if #ranks ~= 8 then return nil, "fen_rank_count" end

    local board = {}
    local king_count = { w = 0, b = 0 }
    for fen_rank = 1, 8 do
        local file = 1
        for token in ranks[fen_rank]:gmatch(".") do
            local empty = tonumber(token)
            if empty then
                if empty < 1 or empty > 8 then return nil, "fen_bad_empty_run" end
                file = file + empty
            else
                local lower = token:lower()
                if not valid_piece[lower] or file > 8 then return nil, "fen_bad_piece" end
                local color = token == lower and "b" or "w"
                board[coords_square(file, 9 - fen_rank)] = { type = lower, color = color }
                if lower == "k" then king_count[color] = king_count[color] + 1 end
                file = file + 1
            end
        end
        if file ~= 9 then return nil, "fen_bad_rank_width" end
    end

    if fields[2] ~= "w" and fields[2] ~= "b" then return nil, "fen_bad_turn" end
    if king_count.w ~= 1 or king_count.b ~= 1 then return nil, "fen_bad_kings" end
    if not valid_castling(fields[3]) then return nil, "fen_bad_castling" end
    if fields[4] ~= "-" then
        local _, ep_rank = square_coords(fields[4])
        if ep_rank ~= 3 and ep_rank ~= 6 then return nil, "fen_bad_en_passant" end
    end

    local halfmove = tonumber(fields[5])
    local fullmove = tonumber(fields[6])
    if not halfmove or halfmove < 0 or halfmove % 1 ~= 0 then return nil, "fen_bad_halfmove" end
    if not fullmove or fullmove < 1 or fullmove % 1 ~= 0 then return nil, "fen_bad_fullmove" end

    return setmetatable({
        board = board,
        turn = fields[2],
        castling = fields[3],
        en_passant = fields[4],
        halfmove = halfmove,
        fullmove = fullmove,
        moves = {},
        captures = { w = {}, b = {} },
    }, Position)
end

function Position.empty()
    return setmetatable({
        board = {}, turn = "w", castling = "-", en_passant = "-",
        halfmove = 0, fullmove = 1, moves = {}, captures = { w = {}, b = {} },
    }, Position)
end

function Position:set_piece(square, color, piece_type)
    if not Position.is_square(square) then return nil, "bad_square" end
    if color == nil and piece_type == nil then
        self.board[square] = nil
        self.moves, self.captures = {}, { w = {}, b = {} }
        return { square }
    end
    if (color ~= "w" and color ~= "b") or not valid_piece[piece_type] then
        return nil, "bad_piece"
    end
    self.board[square] = { color = color, type = piece_type }
    self.moves, self.captures = {}, { w = {}, b = {} }
    return { square }
end

function Position:move_piece_unchecked(from, to)
    if not Position.is_square(from) or not Position.is_square(to) then return nil, "bad_square" end
    if from == to then return { from } end
    local piece = self.board[from]
    if not piece then return nil, "empty_origin" end
    self.board[from], self.board[to] = nil, copy_piece(piece)
    self.moves, self.captures = {}, { w = {}, b = {} }
    return { from, to }
end

function Position:clear_board()
    local dirty = {}
    for square in pairs(self.board) do dirty[#dirty + 1] = square end
    self.board, self.moves, self.captures = {}, {}, { w = {}, b = {} }
    self.castling, self.en_passant, self.halfmove, self.fullmove = "-", "-", 0, 1
    table.sort(dirty)
    return dirty
end

function Position:set_turn(color)
    if color ~= "w" and color ~= "b" then return nil, "bad_turn" end
    self.turn = color
    return true
end

function Position:clone()
    local moves = {}
    for i, move in ipairs(self.moves) do moves[i] = move end
    return setmetatable({
        board = copy_board(self.board),
        turn = self.turn,
        castling = self.castling,
        en_passant = self.en_passant,
        halfmove = self.halfmove,
        fullmove = self.fullmove,
        moves = moves,
        captures = copy_captures(self.captures),
    }, Position)
end

function Position:piece_at(square)
    return copy_piece(self.board[square])
end

-- Returns pieces captured by color since initialFen. Missing material in a
-- custom initial position is deliberately not treated as captured.
function Position:captured_by(color)
    if color ~= "w" and color ~= "b" then return {} end
    local result = copy_captures(self.captures)[color]
    table.sort(result, function(left, right)
        return captured_order[left.type] < captured_order[right.type]
    end)
    return result
end

function Position:material_advantage(color)
    if color ~= "w" and color ~= "b" then return 0 end
    local totals = { w = 0, b = 0 }
    for _, piece in pairs(self.board) do
        totals[piece.color] = totals[piece.color] + material_value[piece.type]
    end
    local opponent = color == "w" and "b" or "w"
    return totals[color] - totals[opponent]
end

function Position:_path_clear(from_file, from_rank, to_file, to_rank)
    local file_step = to_file == from_file and 0 or (to_file > from_file and 1 or -1)
    local rank_step = to_rank == from_rank and 0 or (to_rank > from_rank and 1 or -1)
    local file, rank = from_file + file_step, from_rank + rank_step
    while file ~= to_file or rank ~= to_rank do
        if self.board[coords_square(file, rank)] then return false end
        file, rank = file + file_step, rank + rank_step
    end
    return true
end

function Position:is_square_attacked(square, by_color)
    local file, rank = square_coords(square)
    if not file or (by_color ~= "w" and by_color ~= "b") then return false end

    local pawn_direction = by_color == "w" and 1 or -1
    local pawn_rank = rank - pawn_direction
    for _, pawn_file in ipairs({ file - 1, file + 1 }) do
        local pawn = self.board[coords_square(pawn_file, pawn_rank)]
        if pawn and pawn.color == by_color and pawn.type == "p" then return true end
    end

    local knight_offsets = {
        { -2, -1 }, { -2, 1 }, { -1, -2 }, { -1, 2 },
        { 1, -2 }, { 1, 2 }, { 2, -1 }, { 2, 1 },
    }
    for _, offset in ipairs(knight_offsets) do
        local knight = self.board[coords_square(file + offset[1], rank + offset[2])]
        if knight and knight.color == by_color and knight.type == "n" then return true end
    end

    for file_delta = -1, 1 do
        for rank_delta = -1, 1 do
            if file_delta ~= 0 or rank_delta ~= 0 then
                local king = self.board[coords_square(file + file_delta, rank + rank_delta)]
                if king and king.color == by_color and king.type == "k" then return true end
            end
        end
    end

    local directions = {
        { 1, 0, r = true, q = true }, { -1, 0, r = true, q = true },
        { 0, 1, r = true, q = true }, { 0, -1, r = true, q = true },
        { 1, 1, b = true, q = true }, { 1, -1, b = true, q = true },
        { -1, 1, b = true, q = true }, { -1, -1, b = true, q = true },
    }
    for _, direction in ipairs(directions) do
        local scan_file, scan_rank = file + direction[1], rank + direction[2]
        while scan_file >= 1 and scan_file <= 8 and scan_rank >= 1 and scan_rank <= 8 do
            local attacker = self.board[coords_square(scan_file, scan_rank)]
            if attacker then
                if attacker.color == by_color and direction[attacker.type] then return true end
                break
            end
            scan_file, scan_rank = scan_file + direction[1], scan_rank + direction[2]
        end
    end
    return false
end

function Position:king_square(color)
    for square, piece in pairs(self.board) do
        if piece.color == color and piece.type == "k" then return square end
    end
end

function Position:is_in_check(color)
    local king = self:king_square(color)
    if not king then return nil, "missing_king" end
    return self:is_square_attacked(king, color == "w" and "b" or "w")
end

function Position:is_pseudo_legal(from, to, promotion, expected_color)
    local from_file, from_rank = square_coords(from)
    local to_file, to_rank = square_coords(to)
    if not from_file or not to_file or from == to then return false, "bad_square" end

    local piece = self.board[from]
    if not piece then return false, "empty_origin" end
    local color = expected_color or self.turn
    if piece.color ~= color or color ~= self.turn then return false, "not_your_turn" end

    local target = self.board[to]
    if target and target.color == piece.color then return false, "own_piece_destination" end

    if promotion and not valid_promotion[promotion] then return false, "bad_promotion" end

    local file_delta = to_file - from_file
    local rank_delta = to_rank - from_rank
    local abs_file, abs_rank = math.abs(file_delta), math.abs(rank_delta)
    local legal = false

    if piece.type == "p" then
        local direction = piece.color == "w" and 1 or -1
        local start_rank = piece.color == "w" and 2 or 7
        local promotion_rank = piece.color == "w" and 8 or 1
        if file_delta == 0 and rank_delta == direction and not target then
            legal = true
        elseif file_delta == 0 and rank_delta == 2 * direction and from_rank == start_rank and not target then
            legal = self.board[coords_square(from_file, from_rank + direction)] == nil
        elseif abs_file == 1 and rank_delta == direction then
            if target then
                legal = true
            elseif to == self.en_passant then
                local captured = self.board[coords_square(to_file, from_rank)]
                legal = captured and captured.type == "p" and captured.color ~= piece.color
            end
        end
        if legal and to_rank == promotion_rank and not promotion then
            return false, "promotion_required", true
        end
        if promotion and to_rank ~= promotion_rank then return false, "unexpected_promotion" end
    elseif piece.type == "n" then
        legal = (abs_file == 1 and abs_rank == 2) or (abs_file == 2 and abs_rank == 1)
    elseif piece.type == "b" then
        legal = abs_file == abs_rank and self:_path_clear(from_file, from_rank, to_file, to_rank)
    elseif piece.type == "r" then
        legal = (file_delta == 0 or rank_delta == 0)
            and self:_path_clear(from_file, from_rank, to_file, to_rank)
    elseif piece.type == "q" then
        legal = (file_delta == 0 or rank_delta == 0 or abs_file == abs_rank)
            and self:_path_clear(from_file, from_rank, to_file, to_rank)
    elseif piece.type == "k" then
        legal = abs_file <= 1 and abs_rank <= 1
        if rank_delta == 0 and abs_file == 2 then
            local home_rank = piece.color == "w" and 1 or 8
            local king_from = "e" .. tostring(home_rank)
            local king_to = (file_delta > 0 and "g" or "c") .. tostring(home_rank)
            local right = piece.color == "w"
                and (file_delta > 0 and "K" or "Q")
                or (file_delta > 0 and "k" or "q")
            local rook_file = file_delta > 0 and 8 or 1
            local rook = self.board[coords_square(rook_file, home_rank)]
            legal = from == king_from and to == king_to and contains(self.castling, right)
                and rook and rook.type == "r" and rook.color == piece.color
                and self:_path_clear(from_file, from_rank, rook_file, home_rank)
        end
    end

    if promotion and piece.type ~= "p" then return false, "unexpected_promotion" end
    return legal, legal and nil or "evidently_illegal"
end

function Position:_apply_unchecked(from, to, promotion, uci)
    local piece = self.board[from]
    local target = self.board[to]
    local from_file, from_rank = square_coords(from)
    local to_file, to_rank = square_coords(to)
    local dirty = { from, to }
    local is_capture = target ~= nil
    local captured_piece = copy_piece(target)

    if piece.type == "p" and from_file ~= to_file and not target and to == self.en_passant then
        local captured_square = coords_square(to_file, from_rank)
        captured_piece = copy_piece(self.board[captured_square])
        self.board[captured_square] = nil
        dirty[#dirty + 1] = captured_square
        is_capture = true
    end

    self.board[from] = nil
    self.board[to] = { type = promotion or piece.type, color = piece.color }
    if captured_piece then
        self.captures[piece.color][#self.captures[piece.color] + 1] = captured_piece
    end

    if piece.type == "k" and math.abs(to_file - from_file) == 2 then
        local rook_from = coords_square(to_file > from_file and 8 or 1, from_rank)
        local rook_to = coords_square(to_file > from_file and 6 or 4, from_rank)
        self.board[rook_to] = self.board[rook_from]
        self.board[rook_from] = nil
        dirty[#dirty + 1] = rook_from
        dirty[#dirty + 1] = rook_to
    end

    if piece.type == "k" then
        self.castling = remove_castling(self.castling, piece.color == "w" and "KQ" or "kq")
    elseif piece.type == "r" then
        local rights_by_square = { a1 = "Q", h1 = "K", a8 = "q", h8 = "k" }
        if rights_by_square[from] then self.castling = remove_castling(self.castling, rights_by_square[from]) end
    end
    local captured_rights = { a1 = "Q", h1 = "K", a8 = "q", h8 = "k" }
    if target and target.type == "r" and captured_rights[to] then
        self.castling = remove_castling(self.castling, captured_rights[to])
    end

    self.en_passant = "-"
    if piece.type == "p" and math.abs(to_rank - from_rank) == 2 then
        self.en_passant = coords_square(from_file, (from_rank + to_rank) / 2)
    end

    self.halfmove = (piece.type == "p" or is_capture) and 0 or self.halfmove + 1
    if self.turn == "b" then self.fullmove = self.fullmove + 1 end
    self.turn = self.turn == "w" and "b" or "w"
    self.moves[#self.moves + 1] = uci
    table.sort(dirty)
    return dirty
end

function Position:is_legal(from, to, promotion, expected_color)
    local pseudo_legal, reason, promotion_required = self:is_pseudo_legal(
        from, to, promotion, expected_color)
    if not pseudo_legal and not promotion_required then return false, reason end

    local piece = self.board[from]
    local target = self.board[to]
    if target and target.type == "k" then return false, "king_capture_forbidden" end

    local opponent = piece.color == "w" and "b" or "w"
    local from_file, from_rank = square_coords(from)
    local to_file = square_coords(to)
    if piece.type == "k" and math.abs(to_file - from_file) == 2 then
        if self:is_square_attacked(from, opponent) then return false, "castle_from_check" end
        local transit = coords_square(from_file + (to_file > from_file and 1 or -1), from_rank)
        local transit_position = self:clone()
        transit_position.board[from] = nil
        transit_position.board[transit] = copy_piece(piece)
        if transit_position:is_square_attacked(transit, opponent) then
            return false, "castle_through_check"
        end
    end

    local simulated_promotion = promotion or (promotion_required and "q" or nil)
    local simulated = self:clone()
    simulated:_apply_unchecked(from, to, simulated_promotion,
        from .. to .. (simulated_promotion or ""))
    if simulated:is_in_check(piece.color) then return false, "leaves_king_in_check" end
    if promotion_required then return false, "promotion_required", true end
    return true
end

function Position:legal_destinations(from, expected_color)
    local destinations = {}
    for file = 1, 8 do
        for rank = 1, 8 do
            local to = coords_square(file, rank)
            local legal, _, promotion_required = self:is_legal(from, to, nil, expected_color)
            if legal or promotion_required then destinations[#destinations + 1] = to end
        end
    end
    table.sort(destinations)
    return destinations
end

function Position:apply_uci(uci)
    if type(uci) ~= "string" then return nil, "uci_not_string" end
    if #uci ~= 4 and #uci ~= 5 then return nil, "uci_bad_format" end
    local from, to = uci:sub(1, 2), uci:sub(3, 4)
    local promotion = #uci == 5 and uci:sub(5, 5) or nil
    if not Position.is_square(from) or not Position.is_square(to)
            or (promotion and not valid_promotion[promotion]) then
        return nil, "uci_bad_format"
    end

    local legal, reason = self:is_legal(from, to, promotion)
    if not legal then return nil, reason end
    return self:_apply_unchecked(from, to, promotion, uci)
end

function Position.reconstruct(initial_fen, moves)
    local position, err = Position.from_fen(initial_fen)
    if not position then return nil, err end
    local move_list = type(moves) == "table" and moves or split_words(moves)
    for index, uci in ipairs(move_list) do
        local _, move_err = position:apply_uci(uci)
        if move_err then return nil, "move_" .. tostring(index) .. ":" .. move_err end
    end
    return position
end

function Position.changed_squares(previous, current)
    local changed = {}
    for file = 1, 8 do
        for rank = 1, 8 do
            local square = coords_square(file, rank)
            if not same_piece(previous.board[square], current.board[square]) then
                changed[#changed + 1] = square
            end
        end
    end
    return changed
end

function Position:to_fen()
    local ranks = {}
    for rank = 8, 1, -1 do
        local row, empty = {}, 0
        for file = 1, 8 do
            local piece = self.board[coords_square(file, rank)]
            if piece then
                if empty > 0 then row[#row + 1], empty = tostring(empty), 0 end
                local symbol = piece.color == "w" and piece.type:upper() or piece.type
                row[#row + 1] = symbol
            else
                empty = empty + 1
            end
        end
        if empty > 0 then row[#row + 1] = tostring(empty) end
        ranks[#ranks + 1] = table.concat(row)
    end
    return table.concat(ranks, "/") .. " " .. self.turn .. " " .. self.castling .. " "
        .. self.en_passant .. " " .. tostring(self.halfmove) .. " " .. tostring(self.fullmove)
end

return Position
