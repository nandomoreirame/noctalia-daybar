--!strict
-- Pomodoro phase machine (see THIRD_PARTY.md). Same semantics as the original:
--   - a finished WORK goes to LONG when completed+1 >= sessionsBeforeLong, else SHORT
--   - a finished SHORT increments `completed`; a finished LONG resets it to 0

local Pomodoro = {}

Pomodoro.WORK = 0
Pomodoro.SHORT = 1
Pomodoro.LONG = 2

-- Integer setting clamped to [min, max]; non-numeric values fall back to `fallback`.
local function clampInt(value: any, min: number, max: number, fallback: number): number
	local n = tonumber(value)
	if n == nil then
		return fallback
	end
	n = math.round(n)
	if n ~= n then
		return fallback
	end
	return math.min(max, math.max(min, n))
end

-- Plugin settings (minutes, snake_case) -> phase config (seconds).
function Pomodoro.configFrom(s: { [string]: any }): { [string]: any }
	return {
		work = clampInt(s.work_duration, 1, 180, 25) * 60,
		short = clampInt(s.short_break_duration, 1, 60, 5) * 60,
		long = clampInt(s.long_break_duration, 1, 120, 15) * 60,
		sessionsBeforeLong = clampInt(s.sessions_before_long_break, 1, 12, 4),
		dailyGoal = clampInt(s.daily_pomodoro_goal, 0, 24, 8),
		autoStartBreaks = not not s.auto_start_breaks,
		autoStartWork = not not s.auto_start_work,
	}
end

-- Remaining seconds after a config change: an untouched phase follows the new
-- duration; a started one (running or paused) keeps its countdown.
function Pomodoro.idleRemaining(started: boolean, remaining: number, mode: number, cfg: { [string]: any }): number
	if started then
		return remaining
	end
	return Pomodoro.durationFor(mode, cfg)
end

-- The "focus on this task" shortcut: allowed unless a focus session is already
-- counting down. A running break may be interrupted by it.
function Pomodoro.canFocusTask(running: boolean, mode: number): boolean
	return not (running and mode == Pomodoro.WORK)
end

-- cfg: { work, short, long } in seconds, sessionsBeforeLong, autoStartBreaks, autoStartWork
function Pomodoro.durationFor(mode: number, cfg: { [string]: any }): number
	if mode == Pomodoro.SHORT then
		return cfg.short
	end
	if mode == Pomodoro.LONG then
		return cfg.long
	end
	return cfg.work
end

function Pomodoro.nextPhase(state: { [string]: any }, cfg: { [string]: any }): { [string]: any }
	if state.mode == Pomodoro.WORK then
		local mode = if state.completed + 1 >= cfg.sessionsBeforeLong then Pomodoro.LONG else Pomodoro.SHORT
		return { mode = mode, completed = state.completed }
	end
	return {
		mode = Pomodoro.WORK,
		completed = if state.mode == Pomodoro.LONG then 0 else state.completed + 1,
	}
end

-- What happens when a phase timer reaches zero.
function Pomodoro.finish(state: { [string]: any }, cfg: { [string]: any }): { [string]: any }
	local nextState = Pomodoro.nextPhase(state, cfg)
	return {
		next = nextState,
		remaining = Pomodoro.durationFor(nextState.mode, cfg),
		workCompleted = state.mode == Pomodoro.WORK,
		autoStart = if state.mode == Pomodoro.WORK then not not cfg.autoStartBreaks else not not cfg.autoStartWork,
	}
end

-- "mm:ss", or "h:mm:ss" past one hour.
function Pomodoro.formatClock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local function pad(n: number): string
		return (if n < 10 then "0" else "") .. tostring(n)
	end
	local head = if h > 0 then tostring(h) .. ":" .. pad(m) else pad(m)
	return head .. ":" .. pad(s % 60)
end

return Pomodoro
