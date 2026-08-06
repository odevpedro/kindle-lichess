-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local ffi = require("ffi")
local FFIUtil = require("ffi/util")

require("ffi/posix_h")

local C = ffi.C
local Process = {}
Process.__index = Process

local function valid_absolute_path(path)
    return type(path) == "string" and path:sub(1, 1) == "/"
        and not path:find("\0", 1, true)
end

function Process.new(options)
    options = options or {}
    assert(valid_absolute_path(options.binary), "absolute bridge binary path is required")
    assert(valid_absolute_path(options.token_file), "absolute token file path is required")
    assert(valid_absolute_path(options.ca_file), "absolute CA file path is required")
    assert(valid_absolute_path(options.socket_path), "absolute socket path is required")
    return setmetatable({
        binary = options.binary,
        token_file = options.token_file,
        ca_file = options.ca_file,
        socket_path = options.socket_path,
        schedule = options.schedule or function(_, callback) callback() end,
        util = options.util or FFIUtil,
        kill = options.kill or function(pid, signal) return C.kill(pid, signal) end,
        pid = nil,
        stop_generation = 0,
    }, Process)
end

function Process:start()
    if self.pid then return true end
    local binary, socket_path = self.binary, self.socket_path
    local token_file, ca_file = self.token_file, self.ca_file
    local pid = self.util.runInSubProcess(function()
        C.execl(binary, binary, "-socket", socket_path, "-token-file", token_file,
            "-ca-file", ca_file, nil)
    end)
    if not pid then return nil, "process_start_failed" end
    self.pid = pid
    return true
end

function Process:stop()
    local pid = self.pid
    if not pid then return end
    self.pid = nil
    self.stop_generation = self.stop_generation + 1
    local generation = self.stop_generation
    self.kill(-pid, C.SIGTERM)

    local attempts = 0
    local function reap()
        if generation ~= self.stop_generation then return end
        if self.util.isSubProcessDone(pid) then return end
        attempts = attempts + 1
        if attempts >= 8 then
            self.util.terminateSubProcess(pid)
            self.util.isSubProcessDone(pid)
            return
        end
        self.schedule(0.25, reap)
    end
    self.schedule(0.25, reap)
end

return Process
