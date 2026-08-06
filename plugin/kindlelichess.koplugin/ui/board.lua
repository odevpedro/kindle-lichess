-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt
-- Grid and tap interaction adapted from Kochess board.lua at
-- b9e05a8202083b58e290dc719890584919d81245.
-- Original Kochess code copyright Baptiste Fouques, GPL-3.0-or-later.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")

local BoardGeometry = require("ui/board_geometry")

local source = debug.getinfo(1, "S").source:gsub("^@", "")
local plugin_path = assert(source:match("^(.*)/ui/board%.lua$"), "cannot resolve plugin path")
local icon_path = plugin_path .. "/icons/"

local piece_names = { p = "P", n = "N", b = "B", r = "R", q = "Q", k = "K" }

local MoveIndicator = Widget:extend{
    size = 64,
    capture = false,
}

function MoveIndicator:getSize()
    return Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
end

function MoveIndicator:paintTo(bb, x, y)
    local center = math.floor(self.size / 2)
    if self.capture then
        local radius = math.max(4, math.floor(self.size * 0.40))
        local width = math.max(2, math.floor(self.size * 0.045))
        bb:paintCircle(x + center, y + center, radius, Blitbuffer.COLOR_GRAY, width)
    else
        local radius = math.max(3, math.floor(self.size * 0.105))
        bb:paintCircle(x + center, y + center, radius, Blitbuffer.COLOR_GRAY)
    end
end

local function square_set(squares)
    local result = {}
    for _, square in ipairs(squares or {}) do result[square] = true end
    return result
end

local Square = InputContainer:extend{
    size = 64,
    square = nil,
    piece = nil,
    selected = false,
    last_move = false,
    destination = false,
    callback = nil,
    show_parent = nil,
}

function Square:_icon()
    if not self.piece then return icon_path .. "empty.svg" end
    return icon_path .. self.piece.color .. piece_names[self.piece.type] .. ".svg"
end

function Square:_background()
    local file = self.square:byte(1) - string.byte("a")
    local rank = tonumber(self.square:sub(2, 2)) - 1
    return (file + rank) % 2 == 0 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_LIGHT_GRAY
end

function Square:_build()
    local border = self.selected and Screen:scaleBySize(4)
        or (self.last_move and Screen:scaleBySize(2) or 0)
    local inner = self.size - 2 * border
    local image_size = math.max(1, math.floor(inner * 0.88))
    local image = ImageWidget:new{
        file = self:_icon(), width = image_size, height = image_size,
        alpha = true, is_icon = true,
    }
    local layers = OverlapGroup:new{
        dimen = Geom:new{ w = inner, h = inner },
        CenterContainer:new{ dimen = Geom:new{ w = inner, h = inner }, image },
    }
    if self.destination then
        table.insert(layers, MoveIndicator:new{ size = inner, capture = self.piece ~= nil })
    end
    self.frame = FrameContainer:new{
        margin = 0, padding = 0, bordersize = border,
        background = self:_background(),
        layers,
    }
    self[1] = self.frame
    if self.dimen then
        self.dimen.w, self.dimen.h = self.size, self.size
    else
        self.dimen = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
    end
end

function Square:init()
    self:_build()
    self.ges_events = {
        TapSquare = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function Square:onTapSquare()
    if self.callback then self.callback(self.square) end
    return true
end

function Square:set_state(piece, selected, last_move, destination)
    local unchanged_piece = (not self.piece and not piece)
        or (self.piece and piece and self.piece.type == piece.type and self.piece.color == piece.color)
    if unchanged_piece and self.selected == selected and self.last_move == last_move
            and self.destination == destination then return end
    local dirty = self.dimen
    self.piece, self.selected, self.last_move, self.destination =
        piece, selected, last_move, destination
    if self[1] then self[1]:free() end
    self:_build()
    if dirty and dirty.w > 0 then UIManager:setDirty(self.show_parent or self, "ui", dirty) end
end

local Board = FrameContainer:extend{
    position = nil,
    orientation = "w",
    board_size = 560,
    on_tap = nil,
    selected = nil,
    last_move = nil,
    destinations = nil,
    bordersize = 0,
    padding = 0,
    margin = 0,
}

function Board:init()
    assert(self.position, "position is required")
    local square_size = math.floor(self.board_size / 8)
    self.board_size = square_size * 8
    self.squares = {}
    self.destinations = square_set(self.destinations)
    local rows = VerticalGroup:new{}
    for row = 1, 8 do
        local columns = HorizontalGroup:new{}
        for column = 1, 8 do
            local square = BoardGeometry.square_at(row, column, self.orientation)
            local widget = Square:new{
                size = square_size,
                square = square,
                piece = self.position:piece_at(square),
                selected = square == self.selected,
                last_move = self.last_move
                    and (square == self.last_move.from or square == self.last_move.to),
                destination = self.destinations[square] == true,
                callback = function(tapped) if self.on_tap then self.on_tap(tapped) end end,
                show_parent = self,
            }
            self.squares[square] = widget
            table.insert(columns, widget)
        end
        table.insert(rows, columns)
    end
    self[1] = rows
end

function Board:update(position, dirty_squares, selected, last_move, destinations)
    local refresh = {}
    for _, square in ipairs(dirty_squares or {}) do refresh[square] = true end
    if self.selected then refresh[self.selected] = true end
    if selected then refresh[selected] = true end
    if self.last_move then refresh[self.last_move.from], refresh[self.last_move.to] = true, true end
    if last_move then refresh[last_move.from], refresh[last_move.to] = true, true end
    for square in pairs(self.destinations or {}) do refresh[square] = true end
    local destination_set = square_set(destinations)
    for square in pairs(destination_set) do refresh[square] = true end

    self.position, self.selected, self.last_move, self.destinations =
        position, selected, last_move, destination_set
    for square in pairs(refresh) do
        local widget = self.squares[square]
        if widget then
            widget:set_state(position:piece_at(square), square == selected,
                last_move and (square == last_move.from or square == last_move.to) or false,
                destination_set[square] == true)
        end
    end
end

return Board
