--!strict
-- The last timers started (newest first), shown as one-click chips in the Timer view
-- and kept in data.json `recentTimers`. Entries: { seconds, label }.

local Duration = require("./duration.luau")
local Pomodoro = require("./pomodoro.luau")
local Tbl = require("./tbl.luau")

local Timers = {}

Timers.MAX_RECENT = 4
local CHIP_LABEL_CHARS = 18

function Timers.sameTimer(a: { [string]: any }, b: { [string]: any }): boolean
	return a.seconds == b.seconds and a.label == b.label
end

local function isValid(e: any): boolean
	if typeof(e) ~= "table" then
		return false
	end
	local seconds = (e :: { [string]: any }).seconds
	if typeof(seconds) ~= "number" then
		return false
	end
	if seconds ~= math.floor(seconds) then
		return false
	end
	return seconds > 0 and seconds <= Duration.MAX_SECONDS
end

-- Stored list -> at most MAX_RECENT valid entries; a non-string label becomes "".
function Timers.normalizeRecent(raw: any): { any }
	if not Tbl.isArray(raw) then
		return {}
	end
	local out = {}
	for _, e in ipairs(raw :: { any }) do
		if isValid(e) then
			local label = (e :: { [string]: any }).label
			table.insert(out, {
				seconds = (e :: { [string]: any }).seconds,
				label = if typeof(label) == "string" then label else "",
			})
			if #out >= Timers.MAX_RECENT then
				break
			end
		end
	end
	return out
end

-- New list with `entry` first and its older copy dropped; the same list when it is
-- already first, so starting the same timer again does not schedule a write.
function Timers.addRecent(list: { any }, entry: { [string]: any }): { any }
	if #list > 0 and Timers.sameTimer(list[1], entry) then
		return list
	end
	local e = { seconds = entry.seconds, label = entry.label or "" }
	local out = { e }
	for _, x in ipairs(list) do
		if not Timers.sameTimer(x, e) then
			table.insert(out, x)
			if #out >= Timers.MAX_RECENT then
				break
			end
		end
	end
	return out
end

-- Store-level wrapper: same data object back when nothing changes.
function Timers.recordRecent(data: { [string]: any }, entry: { [string]: any }): { [string]: any }
	local list = if Tbl.isArray(data.recentTimers) then data.recentTimers else {}
	local nextList = Timers.addRecent(list, entry)
	if nextList == list and Tbl.isArray(data.recentTimers) then
		return data
	end
	return Tbl.merge(data, { recentTimers = nextList })
end

-- "05:00" or "05:00 · chá"; long labels are cut with an ellipsis.
function Timers.chipText(entry: { [string]: any }): string
	local label = entry.label
	if #label > CHIP_LABEL_CHARS then
		label = string.sub(label, 1, CHIP_LABEL_CHARS - 1) .. "…"
	end
	return Pomodoro.formatClock(entry.seconds) .. (if label ~= "" then " · " .. label else "")
end

return Timers
