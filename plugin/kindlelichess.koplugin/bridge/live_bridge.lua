-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Process = require("bridge/process")
local SocketBridge = require("bridge/socket_bridge")

local LiveBridge = {}

function LiveBridge.new(options)
    options = options or {}
    local process = Process.new{
        binary = assert(options.binary, "bridge binary path is required"),
        token_file = assert(options.token_file, "token file path is required"),
        socket_path = assert(options.socket_path, "socket path is required"),
        schedule = assert(options.schedule, "schedule callback is required"),
    }
    return SocketBridge.new{
        emit = assert(options.emit, "emit callback is required"),
        socket_path = options.socket_path,
        process = process,
        schedule = options.schedule,
        cancel = assert(options.cancel, "cancel callback is required"),
        register = assert(options.register, "register callback is required"),
        unregister = assert(options.unregister, "unregister callback is required"),
    }
end

return LiveBridge
