--!strict
-- Shared rules for the two countdowns (pomodoro and timer). Only one counts at a
-- time: starting one pauses the other.

local Clock = {}

Clock.TIMER_ICON = "alarm"
-- Chip value of the Timer chip in the Focus tab (pomodoro modes are 0..2).
Clock.TIMER_CHIP = -1

-- Which clock the bar shows: the running one, else the one whose alarm rings.
-- state: { pomodoroRunning, timerRunning, alarmSource } -> "timer" | "pomodoro" | ""
function Clock.barSource(state: { [string]: any }): string
	if state.timerRunning then
		return "timer"
	end
	if state.pomodoroRunning then
		return "pomodoro"
	end
	if state.alarmSource == "timer" or state.alarmSource == "pomodoro" then
		return state.alarmSource
	end
	return ""
end

-- Ring fill: remaining over total, clamped to [0, 1]; 0 without a positive total.
function Clock.progress(remaining: number?, total: number?): number
	if not (typeof(total) == "number" and (total :: number) > 0) then
		return 0
	end
	local r = remaining or 0
	return math.min(1, math.max(0, r / (total :: number)))
end

-- Middle click on the bar pauses or resumes the clock shown, else the pomodoro.
function Clock.middleClickTarget(source: string): string
	return if source == "timer" then "timer" else "pomodoro"
end

-- Focus tab chip click -> "show-timer" | "show-pomodoro" | "set-mode".
-- Coming back from the Timer view to the current pomodoro mode must not reset it.
function Clock.chipAction(chip: number, view: string, mode: number): string
	if chip == Clock.TIMER_CHIP then
		return "show-timer"
	end
	if view == "timer" and chip == mode then
		return "show-pomodoro"
	end
	return "set-mode"
end

-- Detached clock (panel and desktop): the bar's clock while one runs or rings,
-- else the clock of the view selected in the Focus tab. Never "".
function Clock.shownClock(state: { [string]: any }): string
	local source = Clock.barSource(state)
	if source ~= "" then
		return source
	end
	return if state.focusPanel == "timer" then "timer" else "pomodoro"
end

-- Live remaining seconds from the deadline while running; otherwise the stored value.
function Clock.remaining(state: { [string]: any }, nowMs: number): number
	if state.running then
		return math.max(0, math.ceil((state.endsAtMs - nowMs) / 1000))
	end
	return state.remaining
end

return Clock
