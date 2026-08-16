-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Blitbuffer = require("ffi/blitbuffer")
local Board = require("ui/board")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CapturedPieces = require("ui/captured_pieces")
local Clock = require("chess/clock")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local I18n = require("i18n")
local Screen = Device.screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = I18n.t

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
    self.chat_open = false
    self.clock_callback = function() self:_refresh_clocks() end
    self.controller.on_change = function(event, payload) self:_controller_changed(event, payload) end
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self:_rebuild()
end

function Session:_title()
    local connection = ({
        connected = T("connected"), connecting = T("connecting"),
        reconnecting = T("reconnecting"), offline = T("offline"),
    })[self.controller.connection] or self.controller.connection
    return TitleBar:new{
        width = Screen:getWidth(), fullscreen = true,
        title = T("Kindle Lichess"), subtitle = connection,
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
                { text = T("Cancel search"), callback = function() controller:cancel_seek() end },
            }})
        else
            local label = controller:time_control_label()
            self.lobby_actions = self:_button_table({{
                { text = T("Play someone (%{time})", { time = label }),
                    callback = function() self:_start_seek() end },
                { text = T("Challenge player…"), callback = function() self:_ask_username() end },
            }, {
                { text = T("Time: %{time}", { time = label }),
                    callback = function() self:_ask_time_control() end },
                { text = T("Free board"), callback = function() controller:enter_free_board() end },
            }})
        end
        table.insert(group, self.lobby_actions)
    elseif controller.view == "challenging" then
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(28) })
        self.lobby_actions = self:_button_table({{
            { text = T("Cancel challenge"), callback = function() controller:cancel_challenge() end },
        }})
        table.insert(group, self.lobby_actions)
    elseif controller.view == "challenge" and controller.challenge then
        local challenger = controller.challenge.challenger or {}
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(24) })
        table.insert(group, TextBoxWidget:new{
            text = T("%{username} challenges you\nRapid • 10+5 • Casual", {
                username = challenger.username or T("Opponent"),
            }),
            width = math.floor(Screen:getWidth() * 0.82),
            face = Font:getFace("cfont", 24), alignment = "center",
        })
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(24) })
        self.challenge_actions = self:_button_table({{
            { id = "decline", text = T("Decline"),
                callback = function() controller:decline_challenge() end },
            { id = "accept", text = T("Accept"),
                callback = function() controller:accept_challenge() end },
        }})
        table.insert(group, self.challenge_actions)
    elseif controller.view == "result" then
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(32) })
        local summary = controller.result_summary or controller.status_text
        table.insert(group, text_widget(summary, "cfont", 32))
        if controller.result_detail and controller.result_detail ~= "" then
            table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(16) })
            table.insert(group, text_widget(controller.result_detail, "cfont", 24))
        end
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(32) })
        table.insert(group, self:_button_table({{
            { text = T("Close"), callback = function() self:onClose() end },
        }}))
    end
    return group
end

function Session:_player_label(player, color)
    player = player or {}
    local clock = self.controller.game_state.clock
    local remaining = clock:remaining(color)
    return string.format("%s  %s", player.username or T("Player"), Clock.format(remaining))
end

function Session:_build_game()
    local controller = self.controller
    local game = controller.game
    local is_result = controller.view == "result"
    local display_position = controller:display_position()
    local player_color = game.player_color
    local top_color = player_color == "w" and "b" or "w"
    local bottom_color = player_color
    local top_player = top_color == "w" and game.white or game.black
    local bottom_player = bottom_color == "w" and game.white or game.black

    local title = self:_title()
    self.top_clock = centered_text(self:_player_label(top_player, top_color), "cfont", 24)
    self.bottom_clock = centered_text(self:_player_label(bottom_player, bottom_color), "cfont", 24)
    self.top_captures = CapturedPieces:new{
        position = display_position, color = top_color, show_parent = self,
    }
    self.bottom_captures = CapturedPieces:new{
        position = display_position, color = bottom_color, show_parent = self,
    }
    local history_index, history_maximum = controller:history_index()
    local status = controller.status_text
    if is_result then
        if not controller.saved_pgn_path then
            status = (controller.result_summary or status) .. " • " .. tostring(history_index)
                .. "/" .. tostring(history_maximum)
        end
    elseif controller.review_index ~= nil then
        status = T("Reviewing move %{current}/%{total}", {
            current = history_index, total = history_maximum,
        })
    end
    self.status_widget = centered_text(status, "smallinfofont", 20)

    local reserved = title:getSize().h + self.top_clock:getSize().h + self.bottom_clock:getSize().h
        + self.top_captures:getSize().h + self.bottom_captures:getSize().h
        + self.status_widget:getSize().h + Screen:scaleBySize(130)
    local board_size = math.min(Screen:getWidth() - Screen:scaleBySize(8), Screen:getHeight() - reserved)
    board_size = math.max(Screen:scaleBySize(320), board_size)
    self.board = Board:new{
        position = display_position,
        orientation = player_color,
        board_size = board_size,
        selected = controller.review_index == nil and controller.selection.selected or nil,
        last_move = controller:display_last_move(),
        destinations = controller.review_index == nil and controller.selection:available_destinations() or {},
        on_tap = function(square) controller:tap_square(square) end,
    }

    local actions
    local promotion = controller.promotion
    local history_row = {
        { text = "<", callback = function() controller:history_back() end },
        { text = ">", callback = function() controller:history_forward() end },
    }
    if is_result then
        actions = self:_button_table({ history_row, {
            { text = T("Save PGN"), callback = function()
                local _, err = controller:save_pgn_file()
                if err then self:_action_error(err) end
            end },
            { text = T("Close"), callback = function() self:onClose() end },
        } })
    elseif promotion then
        actions = self:_button_table({{
            { text = T("Queen"), callback = function() controller:promote(promotion.from, promotion.to, "q") end },
            { text = T("Rook"), callback = function() controller:promote(promotion.from, promotion.to, "r") end },
        }, {
            { text = T("Bishop"), callback = function() controller:promote(promotion.from, promotion.to, "b") end },
            { text = T("Knight"), callback = function() controller:promote(promotion.from, promotion.to, "n") end },
        }})
        self.promotion_actions = actions
    else
        local moves_played = #controller.game_state.moves
        local finish_text = moves_played < 2 and T("Abort") or T("Resign")
        local action_row = {
            { text = controller:chat_label(), callback = function() self:_open_chat() end },
            { text = T("Draw"), callback = function() controller:offer_draw() end },
        }
        if controller.bridge and controller.bridge.simulate_disconnect then
            action_row[#action_row + 1] = {
                text = T("Reconnect"), callback = function() controller:simulate_disconnect() end,
            }
        end
        action_row[#action_row + 1] = {
            text = finish_text, callback = function() self:_confirm_finish(moves_played < 2) end,
        }
        actions = self:_button_table({ history_row, action_row })
        self.promotion_actions = nil
    end

    if not is_result then self:_schedule_clock() end
    return VerticalGroup:new{
        align = "center", title, self.top_clock, self.top_captures, self.board,
        self.bottom_clock, self.bottom_captures, self.status_widget, actions,
    }
end

function Session:_build_chat()
    local controller = self.controller
    self.status_widget = centered_text(controller.status_text, "smallinfofont", 18)
    self.chat_transcript = TextBoxWidget:new{
        text = controller:chat_transcript(5),
        width = math.floor(Screen:getWidth() * 0.88),
        face = Font:getFace("cfont", 22),
        alignment = "left",
    }
    self.chat_actions = self:_button_table({{
        { text = T("Back to board"), callback = function() self:_close_chat() end },
        { text = T("Write…"), callback = function() self:_ask_chat_message() end },
    }})
    return VerticalGroup:new{
        align = "center", self:_title(),
        VerticalSpan:new{ width = Screen:scaleBySize(18) },
        centered_text(T("Game chat — players only"), "cfont", 24),
        VerticalSpan:new{ width = Screen:scaleBySize(18) },
        self.chat_transcript,
        VerticalSpan:new{ width = Screen:scaleBySize(18) },
        self.status_widget,
        VerticalSpan:new{ width = Screen:scaleBySize(18) },
        self.chat_actions,
    }
end

function Session:_build_free_board()
    local controller = self.controller
    local title = self:_title()
    self.status_widget = centered_text(controller.status_text, "smallinfofont", 20)
    local reserved = title:getSize().h + self.status_widget:getSize().h + Screen:scaleBySize(220)
    local board_size = math.min(Screen:getWidth() - Screen:scaleBySize(8),
        Screen:getHeight() - reserved)
    board_size = math.max(Screen:scaleBySize(280), board_size)
    self.board = Board:new{
        position = controller.free_position, orientation = "w", board_size = board_size,
        selected = controller.free_selected, destinations = {},
        on_tap = function(square) controller:free_tap_square(square) end,
    }
    self.free_actions = self:_button_table({
        {
            { text = T("Move"), callback = function() controller:free_select_tool("move") end },
            { text = T("Erase"), callback = function() controller:free_select_tool("erase") end },
            { text = T("Clear"), callback = function() controller:free_clear() end },
            { text = T("Initial"), callback = function() controller:free_reset() end },
        },
        {
            { text = "WP", callback = function() controller:free_select_tool("wp") end },
            { text = "WN", callback = function() controller:free_select_tool("wn") end },
            { text = "WB", callback = function() controller:free_select_tool("wb") end },
            { text = "WR", callback = function() controller:free_select_tool("wr") end },
            { text = "WQ", callback = function() controller:free_select_tool("wq") end },
            { text = "WK", callback = function() controller:free_select_tool("wk") end },
        },
        {
            { text = "BP", callback = function() controller:free_select_tool("bp") end },
            { text = "BN", callback = function() controller:free_select_tool("bn") end },
            { text = "BB", callback = function() controller:free_select_tool("bb") end },
            { text = "BR", callback = function() controller:free_select_tool("br") end },
            { text = "BQ", callback = function() controller:free_select_tool("bq") end },
            { text = "BK", callback = function() controller:free_select_tool("bk") end },
        },
        {
            { text = T("Toggle turn"), callback = function() controller:free_toggle_turn() end },
            { text = T("Edit FEN…"), callback = function() self:_ask_fen() end },
        },
    })
    return VerticalGroup:new{ align = "center", title, self.board, self.status_widget, self.free_actions }
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
    self.top_captures, self.bottom_captures = nil, nil
    self.challenge_actions = nil
    self.lobby_actions = nil
    self.promotion_actions = nil
    self.free_actions = nil
    self.chat_actions = nil
    self.chat_transcript = nil
    local content
    if self.chat_open and self.controller.game_state then
        content = self:_build_chat()
    elseif (self.controller.view == "game" or self.controller.view == "result")
            and self.controller.game_state then
        content = self:_build_game()
    elseif self.controller.view == "free_board" and self.controller.free_position then
        content = self:_build_free_board()
    else
        content = self:_simple_content()
    end
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

function Session:_action_error(err)
    local messages = {
        invalid_time_control = T("Use minutes+increment, for example 10+5"),
        initial_time_too_large = T("Initial time exceeds the Lichess limit"),
        invalid_initial_time = T("Initial time is not accepted by Lichess"),
        increment_too_large = T("Increment exceeds the Lichess limit"),
        board_api_too_fast = T("This time control is too fast for this Board API mode"),
        fractional_seconds = T("The time must result in whole seconds"),
        invalid_chat_text = T("The message must contain 1 to 280 bytes and no line breaks"),
        invalid_chat_room = T("Invalid chat room"),
        chat_unavailable = T("Chat is unavailable on this screen"),
        chat_pending = T("Wait for the previous message to be sent"),
    }
    self.controller:remember_error(err)
    self.controller.status_text = messages[err] or self.controller:error_message(err)
    UIManager:nextTick(function() self:_rebuild() end)
end

function Session:_start_seek()
    local ok, err = self.controller:seek_game()
    if not ok then self:_action_error(err) end
end

function Session:_show_input_dialog(dialog)
    dialog.modal = true
    self.pending_dialog = dialog
    UIManager:show(dialog, "flashui")
    dialog:onShowKeyboard()
end

function Session:_ask_username()
    local dialog
    dialog = InputDialog:new{
        title = T("Opponent username"),
        description = T("Lichess username, e.g. MagnusCarlsen"),
        input = "",
        allow_early_enter = true,
        buttons = {{
            { id = "cancel", text = T("Cancel"), callback = function() self:_dismiss_dialog() end },
            { id = "challenge", text = T("Challenge"), callback = function()
                local username = dialog:getInputText()
                self:_dismiss_dialog()
                if username and username ~= "" then
                    local ok, err = self.controller:create_challenge(username)
                    if not ok then self:_action_error(err) end
                end
            end },
        }},
    }
    self:_show_input_dialog(dialog)
end

function Session:_ask_time_control()
    local dialog
    dialog = InputDialog:new{
        title = T("Custom time"),
        description = T("Format: minutes+increment, for example 10+5. Public search accepts Rapid or slower."),
        input = self.controller:time_control_label(),
        allow_early_enter = true,
        buttons = {{
            { text = T("Cancel"), callback = function() self:_dismiss_dialog() end },
            { text = T("Apply"), callback = function()
                local value = dialog:getInputText()
                self:_dismiss_dialog()
                local ok, err = self.controller:set_time_control(value)
                if not ok then self:_action_error(err) end
            end },
        }},
    }
    self:_show_input_dialog(dialog)
end

function Session:_ask_fen()
    local dialog
    dialog = InputDialog:new{
        title = T("FEN position"),
        description = T("Edit all six FEN fields and tap Apply."),
        input = self.controller:free_fen() or "",
        allow_early_enter = true,
        buttons = {{
            { text = T("Cancel"), callback = function() self:_dismiss_dialog() end },
            { text = T("Apply"), callback = function()
                local value = dialog:getInputText()
                self:_dismiss_dialog()
                local ok, err = self.controller:free_import_fen(value)
                if not ok then self:_action_error(err) end
            end },
        }},
    }
    self:_show_input_dialog(dialog)
end

function Session:_open_chat()
    self.chat_open = true
    self.controller:mark_chat_read(true)
    UIManager:nextTick(function() self:_rebuild() end)
end

function Session:_close_chat()
    self.chat_open = false
    UIManager:nextTick(function() self:_rebuild() end)
end

function Session:_ask_chat_message()
    local dialog
    dialog = InputDialog:new{
        title = T("Message to opponent"),
        description = T("Private game chat. Be kind and follow the Lichess rules."),
        input = "",
        allow_early_enter = true,
        buttons = {{
            { text = T("Cancel"), callback = function()
                self:_dismiss_dialog()
                UIManager:nextTick(function() self:_rebuild() end)
            end },
            { text = T("Send"), callback = function()
                local value = dialog:getInputText()
                self:_dismiss_dialog()
                local ok, err = self.controller:send_chat(value)
                if not ok then self:_action_error(err) end
            end },
        }},
    }
    self:_show_input_dialog(dialog)
end

function Session:_confirm_finish(abort)
    local dialog
    dialog = ConfirmBox:new{
        text = abort and T("Abort this game?") or T("Resign this game?"),
        ok_text = abort and T("Abort") or T("Resign"),
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
        dialog:onCloseKeyboard()
        UIManager:close(dialog, "flashui")
    end
end

function Session:_controller_changed(event, payload)
    if self.closing then return end
    if event == "history" or event == "free_board" or event == "free_position"
            or event == "free_selected" or event == "free_tool"
            or event == "time_control" or event == "pgn_saved" then
        self:_dismiss_dialog()
        UIManager:nextTick(function() self:_rebuild() end)
    elseif event == "chat_line" then
        if self.chat_open then self.controller:mark_chat_read(true) end
        if not self.pending_dialog then UIManager:nextTick(function() self:_rebuild() end) end
    elseif event == "chat_read" then
        UIManager:nextTick(function() self:_rebuild() end)
    elseif event == "chat_sending" then
        if self.chat_open then UIManager:nextTick(function() self:_rebuild() end) end
    elseif event == "game_state" and self.chat_open then
        if not self.pending_dialog then UIManager:nextTick(function() self:_rebuild() end) end
    elseif event == "game_finish" then
        self.chat_open = false
        self:_dismiss_dialog()
        UIManager:nextTick(function() self:_rebuild() end)
    elseif event == "status" then
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
        if self.controller.review_index ~= nil then
            self:_rebuild()
            return
        end
        self.board:update(payload.position, payload.dirty,
            self.controller.selection.selected, self.controller.last_move,
            self.controller.selection:available_destinations())
        self.top_captures:update(payload.position)
        self.bottom_captures:update(payload.position)
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
    if self.chat_open then
        self:_close_chat()
        return true
    end
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
