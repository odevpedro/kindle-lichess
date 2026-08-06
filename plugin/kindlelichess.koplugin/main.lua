-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Controller = require("controller")
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
        keep_menu_open = false,
        callback = function() self:open() end,
    }
end

function KindleLichess:onKindleLichessStart()
    self:open()
    return true
end

function KindleLichess:open()
    if self.session then return end
    local controller = Controller.new{
        monotonic_now = function()
            return time.to_number(time.boottime_or_realtime_coarse())
        end,
    }
    local bridge = MockBridge.new{
        emit = function(message) controller:handle(message) end,
        schedule = function(delay, callback) UIManager:scheduleIn(delay, callback) end,
        cancel = function(callback) UIManager:unschedule(callback) end,
    }
    controller:attach_bridge(bridge)
    self.session = Session:new{
        controller = controller,
        on_close = function() self.session = nil end,
    }
    UIManager:show(self.session, "flashui")
    controller:start()
end

return KindleLichess
