-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Controller = require("controller")
local DataStorage = require("datastorage")
local DiagnosticExport = require("storage/diagnostic_export")
local Dispatcher = require("dispatcher")
local I18n = require("i18n")
local InfoMessage = require("ui/widget/infomessage")
local MockBridge = require("bridge/mock_bridge")
local PgnExport = require("storage/pgn_export")
local Session = require("ui/session")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local time = require("ui/time")
local T = I18n.t

local KindleLichess = WidgetContainer:extend{
    name = "kindlelichess",
    is_doc_only = false,
    session = nil,
}

local function absolute_path(root, path)
    if path:sub(1, 1) == "/" then return path end
    return root:gsub("/+$", "") .. "/" .. path
end

function KindleLichess:onDispatcherRegisterActions()
    Dispatcher:registerAction("kindlelichess_start", {
        category = "none", event = "KindleLichessStart",
        title = T("Kindle Lichess"), general = true,
    })
end

function KindleLichess:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function KindleLichess:addToMainMenu(menu_items)
    local function configured_language()
        return G_reader_settings:readSetting("kindlelichess_language") or "auto"
    end
    local function select_language(language)
        G_reader_settings:saveSetting("kindlelichess_language", language)
        I18n.set_language(language)
    end
    menu_items.kindlelichess = {
        text = T("Kindle Lichess"), sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = T("Open Kindle Lichess"),
                keep_menu_open = false,
                callback = function() self:open() end,
            },
            {
                text = T("Free board"),
                keep_menu_open = false,
                callback = function() self:open_free_board() end,
            },
            {
                text = T("Mock mode"),
                checked_func = function() return self:_bridge_mode() == "mock" end,
                callback = function()
                    self.bridge_mode = nil
                    G_reader_settings:saveSetting("kindlelichess_bridge_mode", "mock")
                end,
            },
            {
                text = T("Lichess test account"),
                help_text = T("Uses a temporary 0600 token file and the official Board API."),
                checked_func = function() return self:_bridge_mode() == "live" end,
                callback = function()
                    self.bridge_mode = nil
                    G_reader_settings:saveSetting("kindlelichess_bridge_mode", "live")
                end,
            },
            {
                text = T("Language"),
                sub_item_table = {
                    {
                        text = T("Automatic (KOReader)"),
                        checked_func = function() return configured_language() == "auto" end,
                        callback = function() select_language("auto") end,
                    },
                    {
                        text = T("English"),
                        checked_func = function() return configured_language() == "en" end,
                        callback = function() select_language("en") end,
                    },
                    {
                        text = T("Portuguese (Brazil)"),
                        checked_func = function() return configured_language() == "pt_BR" end,
                        callback = function() select_language("pt_BR") end,
                    },
                },
            },
            {
                text = T("Export sanitized diagnostics"),
                keep_menu_open = false,
                callback = function() self:export_diagnostics() end,
            },
        },
    }
end

function KindleLichess:export_diagnostics()
    local directory = self.pgn_directory
        or G_reader_settings:readSetting("kindlelichess_pgn_directory")
        or "/mnt/us/documents/KindleLichess"
    local path, err = DiagnosticExport.save(directory, {
        language = I18n.language(),
        bridge_mode = self:_bridge_mode(),
        last_error = G_reader_settings:readSetting("kindlelichess_last_error") or "none",
    })
    local message = path and T("Sanitized diagnostics saved to %{path}", { path = path })
        or T("Could not save diagnostics: %{error}", { error = err })
    UIManager:show(InfoMessage:new{ text = message })
    return path, err
end

function KindleLichess:onKindleLichessStart()
    self:open()
    return true
end

function KindleLichess:_bridge_mode()
    return self.bridge_mode or G_reader_settings:readSetting("kindlelichess_bridge_mode") or "mock"
end

function KindleLichess:_new_bridge(controller)
    local callbacks = {
        emit = function(message) controller:handle(message) end,
        schedule = function(delay, callback) UIManager:scheduleIn(delay, callback) end,
        cancel = function(callback) UIManager:unschedule(callback) end,
    }
    if self:_bridge_mode() ~= "live" then
        return MockBridge.new(callbacks)
    end

    local data_root = self.data_root or DataStorage:getFullDataDir()
    local plugin_root = absolute_path(data_root, self.path)
    local binary = self.bridge_binary
        or G_reader_settings:readSetting("kindlelichess_bridge_binary")
        or (plugin_root .. "/bin/kindle-lichess-bridge")
    local token_file = self.token_file
        or G_reader_settings:readSetting("kindlelichess_token_file")
        or "/tmp/kindle-lichess-token"
    local ca_file = self.ca_file
        or G_reader_settings:readSetting("kindlelichess_ca_file")
        or (data_root .. "/data/ca-bundle.crt")
    local live_factory = self.live_bridge_factory
        or function(options) return require("bridge/live_bridge").new(options) end
    callbacks.binary = binary
    callbacks.token_file = token_file
    callbacks.ca_file = ca_file
    callbacks.socket_path = "/tmp/kindle-lichess.sock"
    callbacks.register = function(bridge) UIManager:insertZMQ(bridge) end
    callbacks.unregister = function(bridge) UIManager:removeZMQ(bridge) end
    return live_factory(callbacks)
end

function KindleLichess:open()
    if self.session then return end
    local pgn_directory = self.pgn_directory
        or G_reader_settings:readSetting("kindlelichess_pgn_directory")
        or "/mnt/us/documents/KindleLichess"
    local controller = Controller.new{
        monotonic_now = function()
            return time.to_number(time.boottime_or_realtime_coarse())
        end,
        time_control = G_reader_settings:readSetting("kindlelichess_time_control") or "600+5",
        save_time_control = function(value)
            G_reader_settings:saveSetting("kindlelichess_time_control", value)
        end,
        record_error = function(code)
            G_reader_settings:saveSetting("kindlelichess_last_error", code)
        end,
        pgn_directory = pgn_directory,
        pgn_writer = function(directory, game, content)
            return PgnExport.save(directory, game, content)
        end,
    }
    local bridge = self:_new_bridge(controller)
    controller:attach_bridge(bridge)
    self.session = Session:new{
        controller = controller,
        on_close = function() self.session = nil end,
    }
    UIManager:show(self.session, "flashui")
    controller:start()
end

function KindleLichess:open_free_board()
    if self.session then return end
    local controller = Controller.new{
        monotonic_now = function()
            return time.to_number(time.boottime_or_realtime_coarse())
        end,
    }
    self.session = Session:new{
        controller = controller,
        on_close = function() self.session = nil end,
    }
    UIManager:show(self.session, "flashui")
    controller:start_free_board()
end

return KindleLichess
