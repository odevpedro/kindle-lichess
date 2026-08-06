-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Protocol = require("bridge/protocol")
local UnixTransport = require("bridge/unix_transport")

local SocketBridge = {}
SocketBridge.__index = SocketBridge

local function default_json()
    local rapidjson = require("rapidjson")
    return rapidjson.encode, rapidjson.decode
end

function SocketBridge.new(options)
    options = options or {}
    local encode, decode = options.encode, options.decode
    if not encode or not decode then encode, decode = default_json() end
    return setmetatable({
        emit_callback = assert(options.emit, "emit callback is required"),
        socket_path = options.socket_path or "/tmp/kindle-lichess.sock",
        transport_factory = options.transport_factory
            or function(path) return UnixTransport.new(path) end,
        process = options.process,
        schedule = options.schedule or function(_, callback) callback() end,
        cancel = options.cancel or function() end,
        register = options.register or function() end,
        unregister = options.unregister or function() end,
        encode = encode,
        decode = decode,
        retry_delay = options.retry_delay or 0.05,
        max_connect_attempts = options.max_connect_attempts or 40,
        max_message_bytes = Protocol.MAX_MESSAGE_BYTES,
        transport = nil,
        input = "",
        output = "",
        retry_callback = nil,
        connect_attempts = 0,
        alive = false,
        connected = false,
        failed = false,
        registered = false,
        generation = 0,
    }, SocketBridge)
end

function SocketBridge:_emit_error(code, fatal)
    if not self.alive then return end
    self.emit_callback({
        v = 1, type = "error", code = code,
        message = "Bridge communication failed", fatal = fatal,
    })
end

function SocketBridge:_disconnect(code)
    if self.transport then self.transport:close() end
    self.transport = nil
    self.connected = false
    if self.registered then
        self.unregister(self)
        self.registered = false
    end
    self:_emit_error(code, true)
    self.failed = true
end

function SocketBridge:_flush()
    while self.connected and #self.output > 0 do
        local count, err = self.transport:write(self.output)
        if count and count > 0 then
            self.output = self.output:sub(count + 1)
        elseif err == "again" then
            return true
        else
            self:_disconnect("socket_write_failed")
            return nil, err or "socket_write_failed"
        end
    end
    return true
end

function SocketBridge:_connect()
    if not self.alive or self.connected then return end
    self.connect_attempts = self.connect_attempts + 1
    local factory_ok, transport = pcall(self.transport_factory, self.socket_path)
    local call_ok, connected = false, false
    if factory_ok and transport then
        call_ok, connected = pcall(transport.connect, transport)
    end
    if call_ok and connected then
        self.transport = transport
        self.connected = true
        self.retry_callback = nil
        self.register(self)
        self.registered = true
        self:_flush()
        return
    end
    if transport then pcall(transport.close, transport) end
    if self.connect_attempts >= self.max_connect_attempts then
        self:_emit_error("socket_unavailable", true)
        self.failed = true
        return
    end
    local generation = self.generation
    local callback
    callback = function()
        if self.retry_callback == callback then self.retry_callback = nil end
        if self.alive and self.generation == generation then self:_connect() end
    end
    self.retry_callback = callback
    self.schedule(self.retry_delay, callback)
end

function SocketBridge:start()
    if self.alive then return true end
    self.alive = true
    self.generation = self.generation + 1
    self.connect_attempts = 0
    self.failed = false
    if self.process then
        local ok, err = self.process:start()
        if not ok then
            self.alive = false
            return nil, err
        end
    end
    self:_connect()
    return true
end

function SocketBridge:send(message)
    if not self.alive then return nil, "bridge_closed" end
    if self.failed then return nil, "socket_unavailable" end
    local ok, err = Protocol.validate_plugin(message)
    if not ok then return nil, err end
    local encoded_ok, encoded = pcall(self.encode, message)
    if not encoded_ok or type(encoded) ~= "string" then return nil, "json_encode_failed" end
    encoded = encoded .. "\n"
    if #encoded > self.max_message_bytes then return nil, "message_too_large" end
    if #self.output + #encoded > self.max_message_bytes * 4 then
        return nil, "output_queue_full"
    end
    self.output = self.output .. encoded
    if self.connected then return self:_flush() end
    return true
end

function SocketBridge:_consume_line(line)
    if #line == 0 then return end
    if line:sub(-1) == "\r" then line = line:sub(1, -2) end
    if #line + 1 > self.max_message_bytes then
        self:_emit_error("message_too_large", false)
        return
    end
    local ok, message = pcall(self.decode, line)
    if not ok or type(message) ~= "table" then
        self:_emit_error("invalid_json", false)
        return
    end
    local valid, validation_err = Protocol.validate_server(message)
    if not valid then
        self:_emit_error(validation_err, false)
        return
    end
    self.emit_callback(message)
end

function SocketBridge:_consume(data)
    self.input = self.input .. data
    while true do
        local newline = self.input:find("\n", 1, true)
        if not newline then
            if #self.input >= self.max_message_bytes then
                self.input = ""
                self:_disconnect("message_too_large")
            end
            return
        end
        local line = self.input:sub(1, newline - 1)
        self.input = self.input:sub(newline + 1)
        self:_consume_line(line)
        if not self.alive or not self.connected then return end
    end
end

function SocketBridge:waitEvent()
    if not self.alive or not self.connected then return end
    self:_flush()
    for _ = 1, 8 do
        local data, err = self.transport:read(4096)
        if data and #data > 0 then
            self:_consume(data)
            if not self.connected then return end
        elseif err == "again" then
            return
        else
            self:_disconnect(err == "eof" and "bridge_closed" or "socket_read_failed")
            return
        end
    end
end

function SocketBridge:close()
    if not self.alive then return end
    self.alive = false
    self.generation = self.generation + 1
    if self.retry_callback then
        self.cancel(self.retry_callback)
        self.retry_callback = nil
    end
    if self.registered then
        self.unregister(self)
        self.registered = false
    end
    if self.transport then self.transport:close() end
    self.transport = nil
    self.connected = false
    self.failed = false
    self.input, self.output = "", ""
    if self.process then self.process:stop() end
end

return SocketBridge
