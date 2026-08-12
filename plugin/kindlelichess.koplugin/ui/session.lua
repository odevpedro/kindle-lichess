-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Blitbuffer = require("ffi/blitbuffer")
local Board = require("ui/board")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Clock = require("chess/clock")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Screen = Device.screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Session = InputContainer:extend{
    name = "kindle_lichess_session",
    modal = true,
    covers_fullscreen = true,
    controller = nil,
    on_close = nil,
}

local function text_widget(text, face, size)
    return TextWidget:new{ text = text, face = Font:getFace(face or "cfont", size or 22) }
end

local CenteredText = WidgetContainer:extend{
    text = "",
    face = nil,
    width = nil,
}

function CenteredText:init()
    self.label = TextWidget:new{ text = self.text, face = self.face, max_width = self.width }
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.label:getSize().h }
    self[1] = self.label
end

function CenteredText:setText(text)
    self.text = text
    self.label:setText(text)
end

function CenteredText:getText()
    return self.label.text
end

function CenteredText:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local size = self.label:getSize()
    self.label:paintTo(bb, x + math.floor((self.dimen.w - size.w) / 2), y)
end

local function centered_text(text, face, size)
    return CenteredText:new{
        text = text, face = Font:getFace(face or "cfont", size or 22),
        width = math.floor(Screen:getWidth() * 0.98),
    }
end

local function clock_refresh_interval(remaining)
    if remaining <= 60000 then return 2 end
    if remaining <= 300000 then return 5 end
    return 15
end

Session.clock_refresh_interval = clock_refresh_interval

function Session:init()
    assert(self.controller, "controller is required")
    self.dimen = Screen:getSize()
    self.full_refresh_counter = 0
    self.pending_dialog = nil
    self.clock_callback = function() self:_refresh_clocks() end
    self.controller.on_change = function(event, payload) self:_controller_changed(event, payload) end
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self:_rebuild()
end

function Session:_title()
    local connection = ({
        connected = _("connected"), connecting = _("connecting"),
        reconnecting = _("reconnecting"), offline = _("offline"),
    })[self.controller.connection] or self.controller.connection
    return TitleBar:new{
        width = Screen:getWidth(), fullscreen = true,
        title = _("Kindle Lichess"), subtitle = connection,
        with_bottom_line = true,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
end

function Session:_button_table(buttons)
    return ButtonTable:new{
        buttons = buttons, width = math.floor(Screen:getWidth() * 0.94),
        show_parent = self,
    }
end

function Session:_simple_content()
    local controller = self.controller
    self.status_widget = TextBoxWidget:new{
        text = controller.status_text, width = math.floor(Screen:getWidth() * 0.82),
        face = Font:getFace("infofont", 26), alignment = "center",
    }
    local group = VerticalGroup:new{
        align = "center",
        self:_title(),
        VerticalSpan:new{ width = Screen:scaleBySize(30) },
        self.status_widget,
    }

    if controller.view == "lobby" then
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(28) })
        if controller.seeking then
            self.lobby_actions = self:_button_table({{
                { text = _("Cancelar busca"), callback = function() controller:cancel_seek() end },
            }})
        else
            self.lobby_actions = self:_button_table({{
                { text = _("Jogar com alguém (10+5)"), callback = function() controller:seek_game() end },
                { text = _("Desafiar jogador…"), callback = function() self:_ask_username() end },
            }})
        end
        table.insert(group, self.lobby_actions)
    elseif controller.view == "challenging" then
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(28) })
        self.lobby_actions = self:_button_table({{
            { text = _("Cancelar desafio"), callback = function() controller:cancel_challenge() end },
        }})
        table.insert(group, self.lobby_actions)
    elseif controller.view == "challenge" and controller.challenge then
        local challenger = controller.challenge.challenger or {}
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(24) })
        table.insert(group, TextBoxWidget:new{
            text = string.format(_("%s challenges you\nRapid • 10+5 • Casual"),
                challenger.username or _("Opponent")),
            width = math.floor(Screen:getWidth() * 0.82),
            face = Font:getFace("cfont", 24), alignment = "center",
        })
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(24) })
        self.challenge_actions = self:_button_table({{
            { id = "decline", text = _("Decline"),
                callback = function() controller:decline_challenge() end },
            { id = "accept", text = _("Accept"),
                callback = function() controller:accept_challenge() end },
        }})
        table.insert(group, self.challenge_actions)
    elseif controller.view == "result" then
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(32) })
        local summary = controller.result_summary or controller.status_text
        table.insert(group, text_widget(summary, "front", 32))
        if controller.result_detail and controller.result_detail ~= "" then
            table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(16) })
            table.insert(group, text_widget(controller.result_detail, "cfont", 24))
        end
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(32) })
        table.insert(group, self:_button_table({{
            { text = _("Close"), callback = function() self:onClose() end },
        }}))
    end
    return group
end

function Session:_player_label(player, color)
    player = player or {}
    local clock = self.controller.game_state.clock
    local remaining = clock:remaining(color)
    return string.format("%s  %s", player.username or _("Player"), Clock.format(remaining))
end

function Session:_build_game()
    local controller = self.controller
    local game = controller.game
    local player_color = game.player_color
    local top_color = player_color == "w" and "b" or "w"
    local bottom_color = player_color
    local top_player = top_color == "w" and game.white or game.black
    local bottom_player = bottom_color == "w" and game.white or game.black

    local title = self:_title()
    self.top_clock = centered_text(self:_player_label(top_player, top_color), "cfont", 24)
    self.bottom_clock = centered_text(self:_player_label(bottom_player, bottom_color), "cfont", 24)
    self.status_widget = centered_text(controller.status_text, "smallinfofont", 20)

    local reserved = title:getSize().h + self.top_clock:getSize().h + self.bottom_clock:getSize().h
        + self.status_widget:getSize().h + Screen:scaleBySize(86)
    local board_size = math.min(Screen:getWidth() - Screen:scaleBySize(8), Screen:getHeight() - reserved)
    board_size = math.max(Screen:scaleBySize(320), board_size)
    self.board = Board:new{
        position = controller.game_state.position,
        orientation = player_color,
        board_size = board_size,
        selected = controller.selection.selected,
        last_move = controller.last_move,
        destinations = controller.selection:available_destinations(),
        on_tap = function(square) controller:tap_square(square) end,
    }

    local actions
    local promotion = controller.promotion
    if promotion then
        actions = self:_button_table({{
            { text = _("Queen"), callback = function() controller:promote(promotion.from, promotion.to, "q") end },
            { text = _("Rook"), callback = function() controller:promote(promotion.from, promotion.to, "r") end },
        }, {
            { text = _("Bishop"), callback = function() controller:promote(promotion.from, promotion.to, "b") end },
            { text = _("Knight"), callback = function() controller:promote(promotion.from, promotion.to, "n") end },
        }})
        self.promotion_actions = actions
    else
        local moves_played = #controller.game_state.moves
        local finish_text = moves_played < 2 and _("Abort") or _("Resign")
        local action_row = {
            { text = _("Draw"), callback = function() controller:offer_draw() end },
        }
        if controller.bridge and controller.bridge.simulate_disconnect then
            action_row[#action_row + 1] = {
                text = _("Reconnect"), callback = function() controller:simulate_disconnect() end,
            }
        end
        action_row[#action_row + 1] = {
            text = finish_text, callback = function() self:_confirm_finish(moves_played < 2) end,
        }
        actions = self:_button_table({ action_row })
        self.promotion_actions = nil
    end

    self:_schedule_clock()
    return VerticalGroup:new{
        align = "center", title, self.top_clock, self.board,
        self.bottom_clock, self.status_widget, actions,
    }
end

function Session:_root(content)
    return FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0,
        CenterContainer:new{ dimen = Screen:getSize(), content },
    }
end

function Session:_rebuild()
    UIManager:unschedule(self.clock_callback)
    if self[1] then self[1]:free() end
    self.board, self.top_clock, self.bottom_clock, self.status_widget = nil, nil, nil, nil
    self.challenge_actions = nil
    self.lobby_actions = nil
    self.promotion_actions = nil
    local content = self.controller.view == "game" and self.controller.game_state
        and self:_build_game() or self:_simple_content()
    self[1] = self:_root(content)
    UIManager:setDirty(self, "ui")
end

function Session:_refresh_status()
    if self.status_widget then
        local dirty = self.status_widget.dimen:copy()
        self.status_widget:setText(self.controller.status_text)
        UIManager:setDirty(self, "ui", dirty)
    end
end

function Session:_refresh_clocks()
    if self.closing or self.controller.view ~= "game" then return end
    local game = self.controller.game
    local top_color = game.player_color == "w" and "b" or "w"
    local top_player = top_color == "w" and game.white or game.black
    local bottom_player = game.player_color == "w" and game.white or game.black
    local top_dirty = self.top_clock.dimen:copy()
    local bottom_dirty = self.bottom_clock.dimen:copy()
    self.top_clock:setText(self:_player_label(top_player, top_color))
    self.bottom_clock:setText(self:_player_label(bottom_player, game.player_color))
    UIManager:setDirty(self, "ui", top_dirty)
    UIManager:setDirty(self, "ui", bottom_dirty)
    self:_schedule_clock()
end

function Session:_schedule_clock()
    UIManager:unschedule(self.clock_callback)
    if not self.controller.game_state then return end
    local clock = self.controller.game_state.clock
    local active = self.controller.game_state.position.turn
    local remaining = clock:remaining(active) or 0
    local interval = clock_refresh_interval(remaining)
    UIManager:scheduleIn(interval, self.clock_callback)
end

function Session:_promotion(payload)
    -- Render a piece-selection ButtonTable inline (replacing the action row)
    -- instead of a ButtonDialog modal: the modal, shown from inside the board
    -- tap callback, collided with the full-screen Session refresh on the KT4 and
    -- only revealed itself after a later refresh (or never). Inline buttons use
    -- the same reliable render path as the board.
    UIManager:nextTick(function() self:_rebuild() end)
end

function Session:_ask_username()
    local dialog = InputDialog:new{
        title = _("Opponent username"),
        info_text = _("Lichess username, e.g. MagnusCarlsen"),
        input = "",
        allow_early_enter = true,
        buttons = {{
            { text = _("Cancel"), callback = function() self:_dismiss_dialog() end },
            { text = _("Challenge"), callback = function()
                local username = dialog:getInputText()
                self:_dismiss_dialog()
                if username and username ~= "" then
                    self.controller:create_challenge(username)
                end
            end },
        }},
    }
    self.pending_dialog = dialog
    UIManager:show(dialog)
end

function Session:_confirm_finish(abort)
    local dialog
    dialog = ConfirmBox:new{
        text = abort and _("Abort this game?") or _("Resign this game?"),
        ok_text = abort and _("Abort") or _("Resign"),
        ok_callback = function()
            if abort then self.controller:abort() else self.controller:resign() end
        end,
    }
    self.pending_dialog = dialog
    UIManager:show(dialog, "flashui")
end

function Session:_dismiss_dialog()
    local dialog = self.pending_dialog
    self.pending_dialog = nil
    if dialog and UIManager:isWidgetShown(dialog) then
        UIManager:close(dialog, "flashui")
    end
end

function Session:_controller_changed(event, payload)
    if self.closing then return end
    if event == "status" then
        -- Do not free and rebuild the button tree from inside its own tap callback.
        if self.controller.view == "lobby" then
            UIManager:nextTick(function() self:_rebuild() end)
        else
            self:_refresh_status()
        end
    elseif event == "selected" or event == "deselected" or event == "rejected" or event == "move" then
        self:_dismiss_dialog()
        if self.promotion_actions then
            UIManager:nextTick(function() self:_rebuild() end)
            return
        end
        if self.board and self.controller.game_state then
            self.board:update(self.controller.game_state.position, {},
                self.controller.selection.selected, self.controller.last_move,
                self.controller.selection:available_destinations())
        end
        self:_refresh_status()
    elseif event == "promotion" then
        self:_promotion()
    elseif event == "game_state" and self.board then
        self:_dismiss_dialog()
        self.board:update(payload.position, payload.dirty,
            self.controller.selection.selected, self.controller.last_move,
            self.controller.selection:available_destinations())
        self:_refresh_status()
        self:_refresh_clocks()
        self.full_refresh_counter = self.full_refresh_counter + 1
        if payload.kind == "reconnected" or self.full_refresh_counter >= 12 then
            UIManager:setDirty(self, "flashui")
            self.full_refresh_counter = 0
        end
    elseif event ~= "command_ok" and event ~= "pong" then
        self:_dismiss_dialog()
        self:_rebuild()
    end
end

function Session:onShow()
    UIManager:setDirty(self, "flashui")
end

function Session:onClose()
    UIManager:close(self, "flashui")
    return true
end

function Session:onCloseWidget()
    if self.closing then return end
    self.closing = true
    UIManager:unschedule(self.clock_callback)
    self:_dismiss_dialog()
    self.controller:close()
    if self.on_close then self.on_close() end
end

return Session
