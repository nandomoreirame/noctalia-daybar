--!strict
-- Pomodoro commands, reachable only through "/p": "/p" starts or pauses, "/p foco",
-- "/p curta", "/p longa" switch to that phase (if different) and start it, "/p parar" resets.

local Pomodoro = require("../pomodoro.luau")

local PomodoroCommand = {}

PomodoroCommand.TYPE = "pomodoro"
PomodoroCommand.ALLOW_EMPTY = true

-- Plain table with no metatable: rawget keeps keys like "__index" from matching.
local COMMANDS: { [string]: string } = {
	[""] = "toggle",
	["foco"] = "work",
	["focus"] = "work",
	["curta"] = "short",
	["pausa curta"] = "short",
	["short"] = "short",
	["longa"] = "long",
	["pausa longa"] = "long",
	["long"] = "long",
	["parar"] = "stop",
	["stop"] = "stop",
}
local MODES: { [string]: number } = { work = Pomodoro.WORK, short = Pomodoro.SHORT, long = Pomodoro.LONG }
local MODE_NAMES: { [number]: string } = {
	[Pomodoro.WORK] = "work",
	[Pomodoro.SHORT] = "short",
	[Pomodoro.LONG] = "long",
}

function PomodoroCommand.build(text: any): { [string]: any }
	local raw = if text == nil then "" else tostring(text)
	local key = string.lower(string.match(raw, "^%s*(.-)%s*$") or "")
	key = (string.gsub(key, "%s+", " "))
	local command = rawget(COMMANDS, key)
	if command == nil then
		return { ok = false, type = PomodoroCommand.TYPE, error = "unknown-command" }
	end
	return { ok = true, type = PomodoroCommand.TYPE, action = "pomodoro", payload = { command = command } }
end

-- What Enter does, given { running, mode }: { op = "start" | "pause" | "reset", switchTo }.
-- switchTo is the phase to set first, or -1 to keep the current one (a paused phase resumes).
function PomodoroCommand.plan(command: string, state: { [string]: any }): { op: string, switchTo: number }
	if command == "stop" then
		return { op = "reset", switchTo = -1 }
	end
	if command == "toggle" then
		return { op = if state.running then "pause" else "start", switchTo = -1 }
	end
	local mode = MODES[command]
	return { op = "start", switchTo = if mode == state.mode then -1 else mode }
end

-- i18n key of the preview line.
function PomodoroCommand.previewKey(command: string, state: { [string]: any }): string
	local p = PomodoroCommand.plan(command, state)
	if p.op == "reset" then
		return "capture.pomodoro.stop"
	end
	if p.op == "pause" then
		return "capture.pomodoro.pause"
	end
	local mode = if p.switchTo >= 0 then p.switchTo else state.mode
	return "capture.pomodoro.start-" .. MODE_NAMES[mode]
end

return PomodoroCommand
