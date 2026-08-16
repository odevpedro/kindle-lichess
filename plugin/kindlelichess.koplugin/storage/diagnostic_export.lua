-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Export = {}

local error_codes = {
    none = true, token_missing = true, token_permissions = true, token_invalid = true,
    auth_unauthorized = true, auth_forbidden = true, not_found = true,
    rate_limited = true, network_timeout = true, network_error = true,
    http_error = true, not_connected = true, process_start_failed = true,
    socket_unavailable = true, socket_in_use = true, unsafe_socket_path = true,
    bridge_closed = true, socket_read_failed = true, socket_write_failed = true,
    ca_file_invalid = true, invalid_json = true, invalid_response = true,
    message_too_large = true, lichess_rejected = true, internal = true,
}

local function one_of(value, allowed, fallback)
    value = tostring(value or "")
    return allowed[value] and value or fallback
end

function Export.format(values)
    values = values or {}
    local language = one_of(values.language, { en = true, pt_BR = true }, "unknown")
    local bridge_mode = one_of(values.bridge_mode, { mock = true, live = true }, "unknown")
    local last_error = one_of(values.last_error, error_codes, "unknown")
    return table.concat({
        "Kindle Lichess sanitized diagnostics",
        "format=1",
        "plugin_version=unreleased",
        "language=" .. language,
        "bridge_mode=" .. bridge_mode,
        "last_error=" .. last_error,
        "contains_account=false",
        "contains_game_id=false",
        "contains_chat=false",
        "contains_position=false",
        "contains_token=false",
        "",
    }, "\n")
end

local function ensure_directory(path, lfs)
    if lfs.attributes(path, "mode") == "directory" then return true end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or lfs.attributes(parent, "mode") ~= "directory" then
        return nil, "diagnostic_parent_missing"
    end
    local ok, err = lfs.mkdir(path)
    if not ok and lfs.attributes(path, "mode") ~= "directory" then
        return nil, err or "diagnostic_mkdir_failed"
    end
    return true
end

function Export.save(directory, values, options)
    if type(directory) ~= "string" or directory:sub(1, 1) ~= "/" then
        return nil, "diagnostic_directory_not_absolute"
    end
    options = options or {}
    local lfs = options.lfs
    if not lfs then
        local ok, loaded = pcall(require, "lfs")
        if not ok then return nil, "lfs_unavailable" end
        lfs = loaded
    end
    local made, make_err = ensure_directory(directory, lfs)
    if not made then return nil, make_err end
    local path = directory:gsub("/+$", "") .. "/kindle-lichess-diagnostics.txt"
    local temporary = path .. ".tmp"
    local handle, open_err = io.open(temporary, "wb")
    if not handle then return nil, open_err or "diagnostic_open_failed" end
    local ok, write_err = handle:write(Export.format(values))
    local closed, close_err = handle:close()
    if not ok or not closed then
        os.remove(temporary)
        return nil, write_err or close_err or "diagnostic_write_failed"
    end
    local renamed, rename_err = os.rename(temporary, path)
    if not renamed then
        os.remove(temporary)
        return nil, rename_err or "diagnostic_rename_failed"
    end
    return path
end

return Export
