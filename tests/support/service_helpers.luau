-- Boots service.luau against the recorded mock and drives it like the entries do:
-- commands go through the Outbox on `cmd.<entry>`, processes stay pending until a
-- test resolves them.

local modules = require("./modules")
local mock = require("./noctalia_mock")
local entry = require("./entry")

local Outbox = modules.load("lib/outbox.luau")

local H = {}

-- Thursday 2026-10-15 09:00 in America/Sao_Paulo (run-tests TZ).
H.NOW = 1792065600000
H.TODAY = "2026-10-15"
H.DATA = "/data"

H.CONFIG = {
	work_duration = 25,
	short_break_duration = 5,
	long_break_duration = 15,
	sessions_before_long_break = 4,
	daily_pomodoro_goal = 8,
	auto_start_breaks = false,
	auto_start_work = false,
	play_sound = true,
	focus_mode_command = "",
	default_calendar = "",
	initial_tab = "last",
	fetch_previews = true,
}

function H.boot(opts: any?): any
	local o = opts or {}
	local config = {}
	for k, v in H.CONFIG do
		config[k] = v
	end
	for k, v in o.config or {} do
		config[k] = v
	end
	local s = entry.load("service.luau", {
		pluginDataDir = H.DATA,
		deferAsync = true,
		commands = o.commands or {},
		config = config,
		fs = o.fs,
		now = o.now or H.NOW,
		clipboard = o.clipboard,
	})
	s.clients = {}
	return s
end

function H.view(s: any): any
	return s.env.noctalia.state.get("view")
end

function H.fs(s: any): { [string]: any }
	return mock.fs(s.env)
end

function H.ack(s: any, name: string): any
	return s.env.noctalia.state.get("ack." .. name)
end

-- Pushes one command for entry `name` and returns the ack published right after
-- (an async command acks later: read it again with H.ack).
function H.command(s: any, name: string, cmd: string, args: any?): any
	local q = s.clients[name]
	if q == nil then
		q = Outbox.newClient(s.env.noctalia.nowMs())
		s.clients[name] = q
	end
	local pushed = Outbox.push(q, cmd, args)
	s.env.noctalia.state.set("cmd." .. name, Outbox.pending(q))
	local ack = H.ack(s, name)
	Outbox.ack(q, ack)
	if typeof(ack) == "table" and ack.seq == pushed.seq then
		return ack
	end
	return nil
end

-- Calls update() after moving the clock forward by ms.
function H.tick(s: any, ms: number)
	mock.advance(s.env, ms)
	s.call("update")
end

local function joined(argv: any): string
	if typeof(argv) ~= "table" then
		return tostring(argv)
	end
	local parts = {}
	for _, a in argv do
		table.insert(parts, tostring(a))
	end
	return table.concat(parts, " ")
end
H.joined = joined

-- Joined argv of every process still waiting for an answer.
function H.pending(s: any): { string }
	local out = {}
	for _, p in mock.pendingAsync(s.env) do
		table.insert(out, joined(p.argv))
	end
	return out
end

-- Index of the first pending process whose joined argv starts with prefix, or nil.
function H.findCmd(s: any, prefix: string): number?
	for i, p in mock.pendingAsync(s.env) do
		if string.sub(joined(p.argv), 1, #prefix) == prefix then
			return i
		end
	end
	return nil
end

-- Resolves the first pending process matching prefix; errors when none matches.
function H.resolveCmd(s: any, prefix: string, result: any)
	local i = H.findCmd(s, prefix)
	if i == nil then
		error("no pending process starting with " .. prefix .. " in: " .. table.concat(H.pending(s), " | "), 2)
	end
	mock.resolveAsync(s.env, i, result)
end

-- Every argv passed to runAsync, joined.
function H.ran(s: any): { string }
	local out = {}
	for _, call in mock.calls(s.env, "noctalia.runAsync") do
		table.insert(out, joined(call[1]))
	end
	return out
end

function H.countRan(s: any, prefix: string): number
	local n = 0
	for _, line in H.ran(s) do
		if string.sub(line, 1, #prefix) == prefix then
			n += 1
		end
	end
	return n
end

return H
