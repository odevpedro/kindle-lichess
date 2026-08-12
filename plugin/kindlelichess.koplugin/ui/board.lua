-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt
-- Grid and tap interaction adapted from Kochess board.lua at
-- b9e05a8202083b58e290dc719890584919d81245.
-- Original Kochess code copyright Baptiste Fouques, GPL-3.0-or-later.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Screen = require("device").screen
local TextWidget = require("ui/widget/textwidget")
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

local function mark_move_squares(refresh, move)
    if type(move) ~= "table" then return end
    if move.from then refresh[move.from] = true end
    if move.to then refresh[move.to] = true end
end

local Square = InputContainer:extend{
    size = 64,
    square = nil,
    piece = nil,
    selected = false,
    last_move = false,
    destination = false,
    checked = false,
    callback = nil,
    show_parent = nil,
}

function Square:_icon()
    if not self.piece then return icon_path .. "empty.svg" end
    return icon_path .. self.piece.color .. piece_names[self.piece.type] .. ".svg"
end

function Square:_background()
    if self.checked then return Blitbuffer.COLOR_GRAY end
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

function Square:set_state(piece, selected, last_move, destination, checked)
    local unchanged_piece = (not self.piece and not piece)
        or (self.piece and piece and self.piece.type == piece.type and self.piece.color == piece.color)
    if unchanged_piece and self.selected == selected and self.last_move == last_move
            and self.destination == destination and self.checked == checked then return end
    local dirty = self.dimen
    self.piece, self.selected, self.last_move, self.destination, self.checked =
        piece, selected, last_move, destination, checked
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
    self.label_size = math.max(13, math.floor(self.board_size * 0.05))
    local square_size = math.floor((self.board_size - self.label_size) / 8)
    self.board_size = square_size * 8 + self.label_size
    self.squares = {}
    self.destinations = square_set(self.destinations)

    local checked_square = self.position:is_in_check(self.position.turn)
        and self.position:king_square(self.position.turn) or nil
    self.checked_square = checked_square

    local label_face = Font:getFace("cfont", math.max(10, math.floor(square_size * 0.26)))
    local function label_widget(text)
        return TextWidget:new{ text = text, face = label_face }
    end

    local rows = VerticalGroup:new{}
    for row = 1, 8 do
        local columns = HorizontalGroup:new{}
        -- rank label of this row (outer file column "1..8", from the left-hand square)
        local rank_square = BoardGeometry.square_at(row, 1, self.orientation)
        table.insert(columns, CenterContainer:new{
            dimen = Geom:new{ w = self.label_size, h = square_size },
            label_widget(rank_square:sub(2, 2)),
        })
        for column = 1, 8 do
            local square = BoardGeometry.square_at(row, column, self.orientation)
            local widget = Square:new{
                size = square_size,
                square = square,
                piece = self.position:piece_at(square),
                checked = square == checked_square,
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

    -- file labels along the bottom (a..h, from the bottom row's squares), padded
    local files = HorizontalGroup:new{}
    table.insert(files, HorizontalSpan:new{ width = self.label_size })
    for column = 1, 8 do
        local file_square = BoardGeometry.square_at(8, column, self.orientation)
        table.insert(files, CenterContainer:new{
            dimen = Geom:new{ w = square_size, h = self.label_size },
            label_widget(file_square:sub(1, 1)),
        })
    end

    self[1] = VerticalGroup:new{ rows, files }
end

function Board:update(position, dirty_squares, selected, last_move, destinations)
    local refresh = {}
    for _, square in ipairs(dirty_squares or {}) do refresh[square] = true end
    if self.selected then refresh[self.selected] = true end
    if selected then refresh[selected] = true end
    mark_move_squares(refresh, self.last_move)
    mark_move_squares(refresh, last_move)
    for square in pairs(self.destinations or {}) do refresh[square] = true end
    local destination_set = square_set(destinations)
    for square in pairs(destination_set) do refresh[square] = true end

    self.position, self.selected, self.last_move, self.destinations =
        position, selected, last_move, destination_set
    local checked_square = position:is_in_check(position.turn)
        and position:king_square(position.turn) or nil
    if self.checked_square then refresh[self.checked_square] = true end
    if checked_square then refresh[checked_square] = true end
    self.checked_square = checked_square
    for square in pairs(refresh) do
        local widget = self.squares[square]
        if widget then
            widget:set_state(position:piece_at(square), square == selected,
                last_move and (square == last_move.from or square == last_move.to) or false,
                destination_set[square] == true, square == checked_square)
        end
    end
end

return Board
