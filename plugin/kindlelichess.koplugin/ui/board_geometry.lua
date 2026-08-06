-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt
-- Coordinate concept adapted from Kochess board.lua at b9e05a8202083b58e290dc719890584919d81245.
-- Original Kochess code copyright Baptiste Fouques, GPL-3.0-or-later.

local BoardGeometry = {}

local function valid_orientation(orientation)
    return orientation == "w" or orientation == "b"
end

function BoardGeometry.square_at(row, column, orientation)
    if not valid_orientation(orientation) or type(row) ~= "number" or type(column) ~= "number"
            or row < 1 or row > 8 or column < 1 or column > 8 then
        return nil
    end
    local file = orientation == "w" and column or 9 - column
    local rank = orientation == "w" and 9 - row or row
    return string.char(string.byte("a") + file - 1) .. tostring(rank)
end

function BoardGeometry.coordinates(square, orientation)
    if not valid_orientation(orientation) or type(square) ~= "string"
            or not square:match("^[a-h][1-8]$") then
        return nil, nil
    end
    local file = square:byte(1) - string.byte("a") + 1
    local rank = tonumber(square:sub(2, 2))
    local row = orientation == "w" and 9 - rank or rank
    local column = orientation == "w" and file or 9 - file
    return row, column
end

return BoardGeometry
