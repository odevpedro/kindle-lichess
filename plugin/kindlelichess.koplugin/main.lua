-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Controller = require("controller")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local MockBridge = require("bridge/mock_bridge")
local Session = require("ui/session")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local time = require("ui/time")
local _ = require("gettext")

local KindleLichess = WidgetContainer:extend{
    name = "kindlelichess",
    is_doc_only = false,
    session = nil,
}

function KindleLichess:onDispatcherRegisterActions()
    Dispatcher:registerAction("kindlelichess_start", {
        category = "none", event = "KindleLichessStart",
        title = _("Kindle Lichess"), general = true,
    })
end

function KindleLichess:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function KindleLichess:addToMainMenu(menu_items)
    menu_items.kindlelichess = {
        text = _("Kindle Lichess"), sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Open Kindle Lichess"),
                keep_menu_open = false,
                callback = function() self:open() end,
            },
            {
                text = _("Mock mode"),
                checked_func = function() return self:_bridge_mode() == "mock" end,
                callback = function()
                    self.bridge_mode = nil
                    G_reader_settings:saveSetting("kindlelichess_bridge_mode", "mock")
                end,
            },
            {
                text = _("Lichess test account"),
                help_text = _("Uses the local 0600 token file and the official Board API."),
                checked_func = function() return self:_bridge_mode() == "live" end,
                callback = function()
                    self.bridge_mode = nil
                    G_reader_settings:saveSetting("kindlelichess_bridge_mode", "live")
                end,
            },
        },
    }
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

    local data_dir = self.data_dir or (DataStorage:getDataDir() .. "/kindle-lichess")
    local binary = self.bridge_binary
        or G_reader_settings:readSetting("kindlelichess_bridge_binary")
        or (self.path .. "/bin/kindle-lichess-bridge")
    local token_file = self.token_file
        or G_reader_settings:readSetting("kindlelichess_token_file")
        or (data_dir .. "/token")
    local live_factory = self.live_bridge_factory
        or function(options) return require("bridge/live_bridge").new(options) end
    callbacks.binary = binary
    callbacks.token_file = token_file
    callbacks.socket_path = "/tmp/kindle-lichess.sock"
    callbacks.register = function(bridge) UIManager:insertZMQ(bridge) end
    callbacks.unregister = function(bridge) UIManager:removeZMQ(bridge) end
    return live_factory(callbacks)
end

function KindleLichess:open()
    if self.session then return end
    local controller = Controller.new{
        monotonic_now = function()
            return time.to_number(time.boottime_or_realtime_coarse())
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

return KindleLichess
