-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local plugin_path = assert(source:match("^(.*)/ui/captured_pieces%.lua$"),
    "cannot resolve plugin path")
local icon_path = plugin_path .. "/icons/"
local piece_names = { p = "P", n = "N", b = "B", r = "R", q = "Q" }

local CapturedPieces = WidgetContainer:extend{
    position = nil,
    color = nil,
    width = nil,
    icon_size = 22,
    show_parent = nil,
}

local function signature(position, color)
    local kinds = {}
    for _, piece in ipairs(position:captured_by(color)) do
        kinds[#kinds + 1] = piece.color .. piece.type
    end
    return table.concat(kinds, ",") .. ":" .. tostring(position:material_advantage(color))
end

function CapturedPieces:_build()
    local children = {}
    local pieces = self.position:captured_by(self.color)
    local maximum_icons = math.max(1, math.floor((self.width - self.icon_size * 2) / self.icon_size))
    for index, piece in ipairs(pieces) do
        if index > maximum_icons then break end
        children[#children + 1] = ImageWidget:new{
            file = icon_path .. piece.color .. piece_names[piece.type] .. ".svg",
            width = self.icon_size, height = self.icon_size,
            alpha = true, is_icon = true,
        }
    end
    if #pieces > maximum_icons then
        children[#children + 1] = TextWidget:new{
            text = "+" .. tostring(#pieces - maximum_icons),
            face = Font:getFace("cfont", math.max(14, self.icon_size - 4)),
        }
    end
    local advantage = self.position:material_advantage(self.color)
    if advantage > 0 then
        children[#children + 1] = HorizontalSpan:new{ width = Screen:scaleBySize(4) }
        children[#children + 1] = TextWidget:new{
            text = "+" .. tostring(advantage),
            face = Font:getFace("cfont", math.max(14, self.icon_size - 3)),
        }
    end
    if #children == 0 then children[1] = HorizontalSpan:new{ width = 1 } end

    local row = HorizontalGroup:new(children)
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        row,
    }
end

function CapturedPieces:init()
    assert(self.position, "position is required")
    assert(self.color == "w" or self.color == "b", "color must be w or b")
    self.width = self.width or math.floor(Screen:getWidth() * 0.98)
    self.icon_size = Screen:scaleBySize(self.icon_size)
    self.height = self.icon_size + Screen:scaleBySize(2)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self._signature = signature(self.position, self.color)
    self:_build()
end

function CapturedPieces:getSize()
    return self.dimen
end

function CapturedPieces:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self[1]:paintTo(bb, x, y)
end

function CapturedPieces:update(position)
    local next_signature = signature(position, self.color)
    self.position = position
    if next_signature == self._signature then return false end
    local dirty = self.dimen:copy()
    self._signature = next_signature
    if self[1] then self[1]:free() end
    self:_build()
    if dirty.w > 0 then UIManager:setDirty(self.show_parent or self, "ui", dirty) end
    return true
end

return CapturedPieces
