-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Export = {}

local function safe(value)
    value = tostring(value or "game"):gsub("[^A-Za-z0-9_-]", "_")
    value = value:gsub("_+", "_"):sub(1, 48)
    return value ~= "" and value or "game"
end

local function exists(path)
    local handle = io.open(path, "rb")
    if not handle then return false end
    handle:close()
    return true
end

local function ensure_directory(path, lfs)
    if lfs.attributes(path, "mode") == "directory" then return true end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or lfs.attributes(parent, "mode") ~= "directory" then
        return nil, "pgn_parent_missing"
    end
    local ok, err = lfs.mkdir(path)
    if not ok and lfs.attributes(path, "mode") ~= "directory" then
        return nil, err or "pgn_mkdir_failed"
    end
    return true
end


function Export.save(directory, game, content, options)
    if type(directory) ~= "string" or directory:sub(1, 1) ~= "/" then
        return nil, "pgn_directory_not_absolute"
    end
    if type(content) ~= "string" or content == "" then return nil, "pgn_empty" end
    options = options or {}
    local lfs = options.lfs
    if not lfs then
        local ok, loaded = pcall(require, "lfs")
        if not ok then return nil, "lfs_unavailable" end
        lfs = loaded
    end
    local made, make_err = ensure_directory(directory, lfs)
    if not made then return nil, make_err end

    local stamp = options.stamp or os.date("%Y-%m-%d_%H%M%S")
    local base = safe(stamp) .. "_" .. safe(game and game.id) .. ".pgn"
    local path = directory:gsub("/+$", "") .. "/" .. base
    local suffix = 1
    while exists(path) do
        path = directory:gsub("/+$", "") .. "/" .. safe(stamp) .. "_"
            .. safe(game and game.id) .. "_" .. tostring(suffix) .. ".pgn"
        suffix = suffix + 1
        if suffix > 100 then return nil, "pgn_name_exhausted" end
    end
    local temporary = path .. ".tmp"
    local handle, open_err = io.open(temporary, "wb")
    if not handle then return nil, open_err or "pgn_open_failed" end
    local ok, write_err = handle:write(content)
    local closed, close_err = handle:close()
    if not ok or not closed then
        os.remove(temporary)
        return nil, write_err or close_err or "pgn_write_failed"
    end
    local renamed, rename_err = os.rename(temporary, path)
    if not renamed then
        os.remove(temporary)
        return nil, rename_err or "pgn_rename_failed"
    end
    return path
end

return Export
