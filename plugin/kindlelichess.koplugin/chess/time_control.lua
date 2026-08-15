-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local TimeControl = {}

local function integers(limit, increment)
    return limit and increment and limit >= 0 and increment >= 0
        and limit % 1 == 0 and increment % 1 == 0
end

function TimeControl.parse_wire(value)
    if type(value) ~= "string" then return nil, "time_control_not_string" end
    local limit, increment = value:match("^(%d+)%+(%d+)$")
    limit, increment = tonumber(limit), tonumber(increment)
    if not integers(limit, increment) then return nil, "invalid_time_control" end
    return { limit = limit, increment = increment }
end

function TimeControl.parse_user(value)
    if type(value) ~= "string" then return nil, "time_control_not_string" end
    value = value:gsub("%s+", ""):gsub(",", ".")
    local minutes, increment = value:match("^(%d+%.?%d*)%+(%d+)$")
    minutes, increment = tonumber(minutes), tonumber(increment)
    if not minutes or not increment then return nil, "invalid_time_control" end
    local seconds = minutes * 60
    if seconds % 1 ~= 0 then return nil, "fractional_seconds" end
    return { limit = seconds, increment = increment }
end

function TimeControl.to_wire(control)
    if type(control) ~= "table" or not integers(control.limit, control.increment) then
        return nil, "invalid_time_control"
    end
    return tostring(control.limit) .. "+" .. tostring(control.increment)
end

local function valid_challenge_limit(limit)
    return limit == 0 or limit == 15 or limit == 30 or limit == 45 or limit == 60
        or limit == 90 or (limit >= 120 and limit <= 10800 and limit % 60 == 0)
end

function TimeControl.validate_challenge(control)
    if type(control) ~= "table" or not integers(control.limit, control.increment) then
        return nil, "invalid_time_control"
    end
    if not valid_challenge_limit(control.limit) then return nil, "invalid_initial_time" end
    if control.increment > 60 then return nil, "increment_too_large" end
    -- Board API direct challenges support Blitz or slower, not Bullet.
    if control.limit + 40 * control.increment < 180 then return nil, "board_api_too_fast" end
    return true
end

function TimeControl.validate_seek(control)
    if type(control) ~= "table" or not integers(control.limit, control.increment) then
        return nil, "invalid_time_control"
    end
    if control.limit > 10800 then return nil, "initial_time_too_large" end
    if control.increment > 180 then return nil, "increment_too_large" end
    -- Public Board API seeks are Rapid or Classical only.
    if control.limit + 40 * control.increment < 600 then return nil, "board_api_too_fast" end
    return true
end

function TimeControl.display(control)
    if type(control) ~= "table" then return "?+?" end
    local minutes
    if control.limit % 60 == 0 then
        minutes = tostring(control.limit / 60)
    else
        minutes = string.format("%.2f", control.limit / 60):gsub("0+$", ""):gsub("%.$", "")
    end
    return minutes .. "+" .. tostring(control.increment)
end

function TimeControl.seek_minutes(control)
    if not TimeControl.validate_seek(control) then return nil, "invalid_seek_time" end
    return TimeControl.display({ limit = control.limit, increment = 0 }):match("^([^+]+)")
end

return TimeControl
