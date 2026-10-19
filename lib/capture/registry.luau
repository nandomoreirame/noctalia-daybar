--!strict
-- Capture type resolution. Inference order:
--   1. "=" -> calculation (always)
--   2. "/p" -> pomodoro command (always; not in the Tab cycle)
--   3. prefix "/e" event, "/l" reminder, "/n" note, "/t" timer
--   4. type forced with Tab
--   5. a lone http(s) URL -> link
--   6. task (default)
-- An empty body is rejected, except after a typed prefix whose handler sets
-- ALLOW_EMPTY ("/t" alone is a command; an empty field on the Timer tab is not).
-- To add a type: create capture/<type>.luau with TYPE and build(text, now), then
-- register it in HANDLERS, CYCLE and (optionally) PREFIXES.

local Task = require("./task.luau")
local Event = require("./event.luau")
local Reminder = require("./reminder.luau")
local Note = require("./note.luau")
local Link = require("./link.luau")
local Calculation = require("./calculation.luau")
local Timer = require("./timer.luau")
local PomodoroCommand = require("./pomodoro.luau")

local Registry = {}

Registry.CYCLE = { "task", "event", "reminder", "note", "link", "timer" }
Registry.PREFIXES = { { "/e", "event" }, { "/l", "reminder" }, { "/n", "note" }, { "/t", "timer" } }
Registry.HANDLERS = {
	task = Task,
	event = Event,
	reminder = Reminder,
	note = Note,
	link = Link,
	timer = Timer,
} :: { [string]: any }

local function hasPrefix(text: string, prefix: string): boolean
	return text == prefix or string.sub(text, 1, #prefix + 1) == prefix .. " "
end

local function trim(s: string): string
	return string.match(s, "^%s*(.-)%s*$") or ""
end

function Registry.resolve(text: any, forcedType: string?, now: number): { [string]: any }
	local trimmed = trim(if text == nil then "" else tostring(text))
	if string.sub(trimmed, 1, 1) == "=" then
		return Calculation.build(string.sub(trimmed, 2))
	end
	if hasPrefix(trimmed, "/p") then
		return PomodoroCommand.build(string.sub(trimmed, 3))
	end

	local kind: string? = nil
	local body = trimmed
	for _, entry in Registry.PREFIXES do
		local prefix, prefixType = entry[1], entry[2]
		if hasPrefix(trimmed, prefix) then
			kind = prefixType
			body = trim(string.sub(trimmed, #prefix + 1))
			break
		end
	end
	local prefixed = kind ~= nil
	if kind == nil then
		if forcedType ~= nil and rawget(Registry.HANDLERS, forcedType) ~= nil then
			kind = forcedType
		elseif Link.isLink(trimmed) then
			kind = "link"
		else
			kind = "task"
		end
	end
	local handler = Registry.HANDLERS[kind :: string]
	if body == "" and not (prefixed and handler.ALLOW_EMPTY) then
		return { ok = false, type = kind, error = "empty" }
	end
	return handler.build(body, now)
end

local function indexIn(list: { string }, value: string?): number
	for i, v in list do
		if v == value then
			return i
		end
	end
	return 0
end

function Registry.nextType(current: string?): string
	local cycle = Registry.CYCLE
	local i = indexIn(cycle, current)
	return cycle[(i % #cycle) + 1]
end

-- Shift+Tab: one step back; a type outside the cycle wraps to the last one.
function Registry.prevType(current: string?): string
	local cycle = Registry.CYCLE
	local i = indexIn(cycle, current)
	return cycle[if i <= 1 then #cycle else i - 1]
end

return Registry
