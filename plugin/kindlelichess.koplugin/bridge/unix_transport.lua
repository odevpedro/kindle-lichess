-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local bit = require("bit")
local ffi = require("ffi")

require("ffi/posix_h")

local C = ffi.C
if not pcall(function() return C.connect end) then
    ffi.cdef[[ int connect(int, const struct sockaddr *, unsigned int); ]]
end
ffi.cdef[[
    static const unsigned KINDLE_LICHESS_AF_UNIX = 1;
    static const unsigned KINDLE_LICHESS_SOCK_STREAM = 1;
    static const unsigned KINDLE_LICHESS_F_GETFL = 3;
    static const unsigned KINDLE_LICHESS_F_SETFL = 4;
    static const unsigned KINDLE_LICHESS_F_SETFD = 2;
    static const unsigned KINDLE_LICHESS_FD_CLOEXEC = 1;
    static const unsigned KINDLE_LICHESS_O_NONBLOCK = 2048;
    struct kindle_lichess_sockaddr_un {
        unsigned short sun_family;
        char sun_path[108];
    };
]]
local UnixTransport = {}
UnixTransport.__index = UnixTransport

local function would_block()
    return ffi.errno() == C.EAGAIN
end

function UnixTransport.new(path)
    return setmetatable({ path = assert(path, "socket path is required"), fd = -1 }, UnixTransport)
end

function UnixTransport:connect()
    if self.fd >= 0 then return true end
    if self.path:sub(1, 1) ~= "/" or #self.path >= 108 or self.path:find("\0", 1, true) then
        return nil, "invalid_socket_path"
    end
    local fd = C.socket(C.KINDLE_LICHESS_AF_UNIX, C.KINDLE_LICHESS_SOCK_STREAM, 0)
    if fd < 0 then return nil, "socket_unavailable" end
    local address = ffi.new("struct kindle_lichess_sockaddr_un")
    address.sun_family = C.KINDLE_LICHESS_AF_UNIX
    ffi.copy(address.sun_path, self.path, #self.path)
    if C.connect(fd, ffi.cast("const struct sockaddr *", address), ffi.sizeof(address)) ~= 0 then
        C.close(fd)
        return nil, "socket_unavailable"
    end
    local flags = C.fcntl(fd, C.KINDLE_LICHESS_F_GETFL)
    local nonblocking_flags = ffi.cast("int", bit.bor(flags, C.KINDLE_LICHESS_O_NONBLOCK))
    local close_on_exec = ffi.cast("int", C.KINDLE_LICHESS_FD_CLOEXEC)
    if flags < 0
            or C.fcntl(fd, C.KINDLE_LICHESS_F_SETFL, nonblocking_flags) ~= 0
            or C.fcntl(fd, C.KINDLE_LICHESS_F_SETFD, close_on_exec) ~= 0 then
        C.close(fd)
        return nil, "socket_configuration_failed"
    end
    self.fd = fd
    return true
end

function UnixTransport:read(maximum)
    if self.fd < 0 then return nil, "socket_closed" end
    local buffer = ffi.new("uint8_t[?]", maximum)
    while true do
        local count = C.read(self.fd, buffer, maximum)
        if count > 0 then return ffi.string(buffer, count) end
        if count == 0 then return nil, "eof" end
        if ffi.errno() == C.EINTR then
            -- Retry only interrupted syscalls.
        elseif would_block() then
            return "", "again"
        else
            return nil, "socket_read_failed"
        end
    end
end

function UnixTransport:write(data)
    if self.fd < 0 then return nil, "socket_closed" end
    if #data == 0 then return 0 end
    while true do
        local count = C.write(self.fd, data, #data)
        if count >= 0 then return tonumber(count) end
        if ffi.errno() == C.EINTR then
            -- Retry only interrupted syscalls.
        elseif would_block() then
            return 0, "again"
        else
            return nil, "socket_write_failed"
        end
    end
end

function UnixTransport:close()
    if self.fd >= 0 then
        C.close(self.fd)
        self.fd = -1
    end
end

return UnixTransport
