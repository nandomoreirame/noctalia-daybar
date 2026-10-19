--!strict
-- Focus tab (REQ-024, REQ-027): mode chips, the pomodoro or the free timer, the
-- task link, today's count and the "pin to corner" switch.

local Clock = require("../lib/clock.luau")
local Pomodoro = require("../lib/pomodoro.luau")
local Timers = require("../lib/timers.luau")
local FocusLog = require("../lib/focuslog.luau")
local Dates = require("../lib/dates.luau")

local FocusView = {}

local PRESETS = { 1, 5, 10, 15, 30 }
local CHIPS = {
	{ chip = Pomodoro.WORK, key = "chip-0", label = "focus.mode.work" },
	{ chip = Pomodoro.SHORT, key = "chip-1", label = "focus.mode.short" },
	{ chip = Pomodoro.LONG, key = "chip-2", label = "focus.mode.long" },
	{ chip = Clock.TIMER_CHIP, key = "chip-timer", label = "focus.mode.timer" },
}

local function chips(ctx: any, v: any): any
	local ui = ctx.ui
	local panelName = v.focusPanel or "pomodoro"
	local mode = (v.pomodoro or {}).mode or Pomodoro.WORK
	local row = {}
	for _, c in ipairs(CHIPS) do
		local active = if c.chip == Clock.TIMER_CHIP then panelName == "timer" else (panelName == "pomodoro" and mode == c.chip)
		table.insert(row, ui.button({
			key = c.key,
			text = ctx.tr(c.label),
			variant = if active then "secondary" else "ghost",
			selected = active,
			controlSize = "sm",
			onClick = function()
				local action = Clock.chipAction(c.chip, panelName, mode)
				local target = if action == "show-timer" then "timer" else "pomodoro"
				if action == "set-mode" then
					ctx.send("pomodoro", { action = "setMode", mode = c.chip })
				end
				if target ~= panelName then
					ctx.send("setFocusPanel", { panel = target })
				end
			end,
		}))
	end
	return ui.row({ gap = 4, justify = "center" }, row)
end

local function digits(ctx: any, clock: any, total: number): { any }
	local ui = ctx.ui
	local remaining = if clock.running then Clock.remaining(clock, ctx.nowMs) else (clock.remaining or 0)
	return {
		ui.label({ text = Pomodoro.formatClock(remaining), fontSize = 44, fontWeight = "bold", textAlign = "center" }),
		ui.progress({ progress = Clock.progress(remaining, total), height = 6, fill = "primary" }),
	}
end

local function controlButton(ctx: any, glyph: string, tip: string, onClick: () -> ()): any
	return ctx.ui.button({ glyph = glyph, variant = "ghost", tooltip = ctx.tr(tip), onClick = onClick })
end

local function pomodoroBody(ctx: any, v: any): { any }
	local ui = ctx.ui
	local pom = v.pomodoro or {}
	local out = digits(ctx, pom, pom.total or 0)
	table.insert(out, ui.row({ gap = 6, justify = "center" }, {
		controlButton(ctx, if pom.running then "player-pause" else "player-play", if pom.running then "focus.pause" else "focus.start", function()
			ctx.send("pomodoro", { action = "toggle" })
		end),
		controlButton(ctx, "player-skip-forward", "focus.skip", function()
			ctx.send("pomodoro", { action = "skip" })
		end),
		controlButton(ctx, "refresh", "focus.reset", function()
			ctx.send("pomodoro", { action = "reset" })
		end),
	}))

	local today = Dates.isoDate(math.floor(ctx.nowMs / 1000))
	local open = {}
	for _, t in ipairs((v.data or {}).tasks or {}) do
		if not t.done and (t.date or today) <= today then
			table.insert(open, t)
		end
	end
	local options = { ctx.tr("focus.no-task") }
	local selected = 0
	for i, t in ipairs(open) do
		table.insert(options, t.title)
		if t.id == pom.linkedTaskId then
			selected = i
		end
	end
	table.insert(out, ui.select({
		options = options,
		selectedIndex = selected,
		controlSize = "sm",
		placeholder = ctx.tr("focus.link-task"),
		onChange = function(index: string)
			local task = open[tonumber(index) or 0]
			if task ~= nil then
				ctx.send("linkTask", { id = task.id })
			end
		end,
	}))

	local goal = tonumber((v.settings or {}).daily_pomodoro_goal) or 0
	local count = FocusLog.sessionsOn(v.data or {}, today)
	local countText = if goal > 0
		then ctx.tr("focus.today-goal", { n = count, total = goal })
		else ctx.tr("focus.today-count", { n = count })
	table.insert(out, ui.label({ text = countText, fontSize = 12, color = "on_surface_variant", textAlign = "center" }))
	return out
end

local function timerBody(ctx: any, v: any): { any }
	local ui = ctx.ui
	local tmr = v.timer or {}
	local out = {}
	if tmr.set then
		for _, node in ipairs(digits(ctx, tmr, tmr.total or 0)) do
			table.insert(out, node)
		end
		if tmr.label ~= nil and tmr.label ~= "" then
			table.insert(out, ui.label({ text = tmr.label, textAlign = "center", color = "on_surface_variant" }))
		end
		table.insert(out, ui.row({ gap = 6, justify = "center" }, {
			controlButton(ctx, if tmr.running then "player-pause" else "player-play", if tmr.running then "focus.pause" else "focus.start", function()
				ctx.send("timer", { action = "toggle" })
			end),
			controlButton(ctx, "refresh", "focus.reset", function()
				ctx.send("timer", { action = "reset" })
			end),
		}))
	end
	table.insert(out, ui.input({
		key = "timer-entry",
		placeholder = ctx.tr("timer.placeholder"),
		controlSize = "sm",
		onSubmit = function(text: string)
			ctx.send("timer", { action = "set", text = text })
		end,
	}))
	local presets = {}
	for _, minutes in ipairs(PRESETS) do
		table.insert(presets, ui.button({
			key = "preset-" .. minutes,
			text = ctx.tr("timer.preset", { n = minutes }),
			variant = "outline",
			controlSize = "sm",
			onClick = function()
				ctx.send("timer", { action = "preset", seconds = minutes * 60 })
			end,
		}))
	end
	table.insert(out, ui.row({ gap = 4, justify = "center" }, presets))
	local recent = {}
	for i, entry in ipairs((v.data or {}).recentTimers or {}) do
		table.insert(recent, ui.button({
			key = "recent-" .. i,
			text = Timers.chipText(entry),
			variant = "ghost",
			controlSize = "sm",
			onClick = function()
				ctx.send("timer", { action = "preset", seconds = entry.seconds, label = entry.label })
			end,
		}))
	end
	if #recent > 0 then
		table.insert(out, ui.row({ gap = 4, justify = "center" }, recent))
	end
	table.insert(out, ui.label({ text = ctx.tr("timer.entry-help"), fontSize = 11, color = "on_surface_variant", textAlign = "center" }))
	return out
end

function FocusView.build(ctx: any): any
	local ui = ctx.ui
	local v = ctx.view or {}
	local pinned = ((v.data or {}).ui or {}).clockOverlay == true
	local header = ui.row({ gap = 6, align = "center" }, {
		ui.label({ text = ctx.tr("tabs.focus"), fontWeight = "bold", flexGrow = 1 }),
		ui.label({ text = ctx.tr("focus.pin"), fontSize = 12, color = "on_surface_variant" }),
		ui.toggle({
			checked = pinned,
			onChange = function(value: string)
				ctx.send("setClockOverlay", { value = value == "true" })
			end,
		}),
	})
	local body = if v.focusPanel == "timer" then timerBody(ctx, v) else pomodoroBody(ctx, v)
	local children = { header }
	for _, node in ipairs(body) do
		table.insert(children, node)
	end
	table.insert(children, ui.spacer({ flexGrow = 1 }))
	table.insert(children, chips(ctx, v))
	return ui.column({ gap = 10, flexGrow = 1 }, children)
end

return FocusView
