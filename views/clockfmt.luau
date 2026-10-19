--!strict
-- What a clock surface shows for the published view: which clock, its digits,
-- its progress and its glyph. Pure; shared by the bar, the pinned panel and the
-- desktop widget.

local Clock = require("../lib/clock.luau")
local Pomodoro = require("../lib/pomodoro.luau")

local ClockFmt = {}

local MODE_KEYS: { [number]: string } = {
	[Pomodoro.WORK] = "focus.mode.work",
	[Pomodoro.SHORT] = "focus.mode.short",
	[Pomodoro.LONG] = "focus.mode.long",
}

local function clockState(view: { [string]: any }): { [string]: any }
	local pom = view.pomodoro or {}
	local tmr = view.timer or {}
	return {
		pomodoroRunning = pom.running == true,
		timerRunning = tmr.running == true,
		alarmSource = view.alarmSource or "",
		focusPanel = view.focusPanel or "pomodoro",
	}
end

-- Clock of `source` ("pomodoro" | "timer"):
-- { source, remaining, total, progress, text, glyph, running, ringing, labelKey, label }
function ClockFmt.of(view: { [string]: any }, source: string, nowMs: number): { [string]: any }
	local clock = (if source == "timer" then view.timer else view.pomodoro) or {}
	local remaining = if clock.running then Clock.remaining(clock, nowMs) else (clock.remaining or 0)
	local ringing = view.alarmSource == source and not clock.running
	if ringing then
		remaining = 0
	end
	local total = clock.total or 0
	return {
		source = source,
		remaining = remaining,
		total = total,
		progress = Clock.progress(remaining, total),
		text = Pomodoro.formatClock(remaining),
		glyph = if source == "timer" then Clock.TIMER_ICON else "hourglass",
		running = clock.running == true,
		ringing = ringing,
		labelKey = if source == "timer" then nil else MODE_KEYS[clock.mode or Pomodoro.WORK],
		label = if source == "timer" then (clock.label or "") else "",
	}
end

-- The bar's clock (running or ringing), or nil when none.
function ClockFmt.bar(view: { [string]: any }, nowMs: number): { [string]: any }?
	local source = Clock.barSource(clockState(view))
	if source == "" then
		return nil
	end
	return ClockFmt.of(view, source, nowMs)
end

-- The detached clock: the bar's clock, else the Focus view's. Never nil.
function ClockFmt.shown(view: { [string]: any }, nowMs: number): { [string]: any }
	return ClockFmt.of(view, Clock.shownClock(clockState(view)), nowMs)
end

return ClockFmt
