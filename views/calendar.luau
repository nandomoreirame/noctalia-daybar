--!strict
-- Calendar tab (REQ-017, REQ-019, REQ-020, REQ-023): month grid with event days,
-- the selected day's events, details on expand, delete through locate + confirm.
-- st: { year, month (0-based), selected (ISO), expanded = { [uid] = true }, confirm }

local Month = require("../lib/month.luau")
local Events = require("../lib/events.luau")
local Dates = require("../lib/dates.luau")
local ConfirmView = require("./confirm.luau")

local CalendarView = {}

local function nowSec(ctx: any): number
	return math.floor(ctx.nowMs / 1000)
end

local function monthBounds(year: number, month: number): (string, string)
	local first = string.format("%04d-%02d-01", year, month + 1)
	local nextMonth = Month.shiftMonth(year, month, 1)
	local nextFirst = Dates.parseIsoDate(string.format("%04d-%02d-01", nextMonth.year, nextMonth.month + 1)) :: number
	return first, Dates.isoDate(Dates.addDays(nextFirst, -1))
end

local function ensureState(ctx: any)
	local st = ctx.st
	if st.year == nil then
		local parts = os.date("*t", nowSec(ctx)) :: { year: number, month: number }
		st.year = parts.year
		st.month = parts.month - 1
		st.selected = Dates.isoDate(nowSec(ctx))
		st.expanded = {}
	end
end

local function shift(ctx: any, delta: number)
	local st = ctx.st
	local nextMonth = Month.shiftMonth(st.year, st.month, delta)
	st.year = nextMonth.year
	st.month = nextMonth.month
	local from, to = monthBounds(st.year, st.month)
	local cal = (ctx.view or {}).calendar or {}
	if cal.from == nil or from < cal.from or to > cal.to then
		ctx.send("loadRange", { from = from, to = to })
	end
	ctx.render()
end

local function grid(ctx: any, cal: any): any
	local ui = ctx.ui
	local st = ctx.st
	local cells = Month.monthGrid(st.year, st.month, nowSec(ctx), cal.events, ((ctx.view or {}).data or {}).tasks)
	local rows = {}
	local weekdays = {}
	for name in string.gmatch(ctx.tr("calendar.weekdays"), "%S+") do
		table.insert(weekdays, ui.label({ text = name, fontSize = 11, color = "on_surface_variant", textAlign = "center", flexGrow = 1 }))
	end
	table.insert(rows, ui.row({ gap = 2 }, weekdays))
	for r = 0, 5 do
		local week = {}
		for c = 1, 7 do
			local cell = cells[r * 7 + c]
			local marks = {}
			if cell.hasEvents then
				table.insert(marks, ui.box({ width = 4, height = 4, radius = 2, fill = "primary" }))
			end
			table.insert(week, ui.column({
				key = "day-" .. cell.date,
				flexGrow = 1,
				align = "center",
				gap = 2,
				radius = 6,
				fill = if cell.date == st.selected then "primary/0.2" elseif cell.today then "surface_variant" else nil,
				opacity = if cell.inMonth then 1 else 0.45,
				tooltip = cell.date,
				onClick = function()
					st.selected = cell.date
					ctx.render()
				end,
			}, {
				ui.label({ text = tostring(cell.day), fontSize = 12, textAlign = "center", fontWeight = if cell.today then "bold" else nil }),
				ui.row({ justify = "center", minHeight = 4 }, marks),
			}))
		end
		table.insert(rows, ui.row({ gap = 2 }, week))
	end
	return ui.column({ gap = 2 }, rows)
end

local function detailsBlock(ctx: any, ev: any): any
	local ui = ctx.ui
	local info = ((ctx.view or {}).details or {})[ev.uid]
	if info == nil then
		return ui.label({ text = ctx.tr("events.details-loading"), fontSize = 12, color = "on_surface_variant" })
	end
	local lines = {}
	for _, person in ipairs(info.people or {}) do
		local status = if person.status == "declined" then " (" .. ctx.tr("events.declined") .. ")"
			elseif person.status == "tentative" then " (" .. ctx.tr("events.tentative") .. ")"
			else ""
		table.insert(lines, ui.label({ text = tostring(person.name) .. status, fontSize = 12 }))
	end
	if info.location ~= nil and info.location ~= "" then
		table.insert(lines, ui.row({ gap = 4, align = "center" }, {
			ui.glyph({ name = "map-pin", size = 12 }),
			ui.label({ text = info.location, fontSize = 12, maxLines = 2 }),
		}))
	end
	if info.meetUrl ~= nil and info.meetUrl ~= "" then
		local url = info.meetUrl
		table.insert(lines, ui.button({
			text = ctx.tr("events.join-meet"),
			glyph = "video",
			variant = "secondary",
			controlSize = "sm",
			onClick = function()
				ctx.send("openUrl", { url = url })
			end,
		}))
	end
	if #lines == 0 then
		table.insert(lines, ui.label({ text = ctx.tr("events.details-none"), fontSize = 12, color = "on_surface_variant" }))
	end
	return ui.column({ gap = 4, paddingH = 24 }, lines)
end

local function eventRow(ctx: any, ev: any): any
	local ui = ctx.ui
	local st = ctx.st
	if st.confirm == "event:" .. ev.uid then
		return ConfirmView.eventRow(ctx, ev.uid, ev.calendar)
	end
	local open = st.expanded[ev.uid] == true
	local row = ui.row({ gap = 6, align = "center" }, {
		ui.button({
			key = "expand-" .. ev.uid,
			glyph = if open then "chevron-down" else "chevron-right",
			variant = "ghost",
			controlSize = "sm",
			tooltip = ctx.tr("events.expand"),
			onClick = function()
				if not open then
					st.requested = st.requested or {}
					if not st.requested[ev.uid] and ((ctx.view or {}).details or {})[ev.uid] == nil then
						st.requested[ev.uid] = true
						ctx.send("loadDetails", { uid = ev.uid, calendar = ev.calendar })
					end
				end
				st.expanded[ev.uid] = not open
				ctx.render()
			end,
		}),
		ui.label({ text = Events.timeRange(ev) or ctx.tr("calendar.all-day"), fontSize = 12, color = "on_surface_variant" }),
		ui.label({ text = tostring(ev.summary), flexGrow = 1, maxLines = 1 }),
		ui.button({
			glyph = "trash",
			variant = "ghost",
			controlSize = "sm",
			tooltip = ctx.tr("events.delete"),
			onClick = function()
				ConfirmView.startEventDelete(ctx, ev.uid, ev.calendar)
			end,
		}),
	})
	if not open then
		return row
	end
	return ui.column({ key = "event-" .. ev.uid, gap = 4 }, { row, detailsBlock(ctx, ev) })
end

function CalendarView.build(ctx: any): any
	local ui = ctx.ui
	local cal = (ctx.view or {}).calendar or {}
	if not cal.available then
		return ui.column({ gap = 8 }, {
			ui.label({ text = ctx.tr("calendar.not-configured"), color = "on_surface_variant", maxLines = 3 }),
		})
	end
	ensureState(ctx)
	local st = ctx.st
	local header = ui.row({ gap = 6, align = "center" }, {
		ui.button({ key = "prev", glyph = "chevron-left", variant = "ghost", controlSize = "sm", tooltip = ctx.tr("calendar.previous"), onClick = function()
			shift(ctx, -1)
		end }),
		ui.label({ text = string.format("%04d-%02d", st.year, st.month + 1), fontWeight = "bold", textAlign = "center", flexGrow = 1 }),
		ui.button({ key = "next", glyph = "chevron-right", variant = "ghost", controlSize = "sm", tooltip = ctx.tr("calendar.next"), onClick = function()
			shift(ctx, 1)
		end }),
	})
	local rows = {}
	for _, ev in ipairs(Events.eventsOn(cal.events, st.selected)) do
		table.insert(rows, eventRow(ctx, ev))
	end
	if #rows == 0 then
		table.insert(rows, ui.label({ text = ctx.tr("calendar.nothing-day"), color = "on_surface_variant" }))
	end
	return ui.row({ gap = 12, flexGrow = 1 }, {
		ui.column({ gap = 6, width = 300 }, { header, grid(ctx, cal) }),
		ui.scroll({ gap = 4, flexGrow = 1 }, rows),
	})
end

return CalendarView
