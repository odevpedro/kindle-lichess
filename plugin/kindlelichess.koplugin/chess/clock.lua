-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

local Clock = {}
Clock.__index = Clock

function Clock.new(monotonic_now)
    assert(type(monotonic_now) == "function", "monotonic clock function is required")
    return setmetatable({ now = monotonic_now, snapshot = nil }, Clock)
end

function Clock:update(wtime, btime, active_color, latency_ms)
    assert(type(wtime) == "number" and wtime >= 0, "invalid white time")
    assert(type(btime) == "number" and btime >= 0, "invalid black time")
    assert(active_color == "w" or active_color == "b" or active_color == nil, "invalid active color")
    self.snapshot = {
        wtime = wtime,
        btime = btime,
        active_color = active_color,
        latency_ms = math.max(0, latency_ms or 0),
        received_at = self.now(),
    }
end

function Clock:remaining(color, at)
    if not self.snapshot then return nil end
    local base = color == "w" and self.snapshot.wtime or self.snapshot.btime
    if color ~= self.snapshot.active_color then return base end
    local elapsed_ms = math.max(0, ((at or self.now()) - self.snapshot.received_at) * 1000)
    local estimate = base - elapsed_ms - self.snapshot.latency_ms / 2
    return math.max(0, math.floor(estimate + 0.5))
end

function Clock.format(milliseconds)
    if milliseconds == nil then return "--:--" end
    local seconds = math.max(0, math.ceil(milliseconds / 1000))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds / 60) % 60
    local remainder = seconds % 60
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, remainder) end
    return string.format("%02d:%02d", minutes, remainder)
end

return Clock
