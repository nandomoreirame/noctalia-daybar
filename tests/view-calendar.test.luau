local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local modules = require("./support/modules")
local U = require("./support/ui_helpers")

local describe, it = runner.describe, runner.it

local CalendarView = modules.load("views/calendar.luau")

local NOW = 1792065600000 -- 2026-10-15 09:00
local EV_START = 1792065600 + 3600 -- 10:00

local function makeCtx()
	local env = mock.new({})
	local sent = {}
	local ctx = {
		ui = env.ui,
		tr = function(k)
			return k
		end,
		nowMs = NOW,
		st = {},
		sent = sent,
		view = {
			data = { tasks = {}, eventChecks = {} },
			calendar = {
				available = true,
				from = "2026-10-01",
				to = "2026-11-15",
				events = { { uid = "e1", calendar = "Eventos", summary = "Daily", start = EV_START, ["end"] = EV_START + 1800, allDay = false } },
			},
			details = {},
			deleting = {},
		},
	}
	ctx.send = function(name, args, onAck)
		table.insert(sent, { name = name, args = args })
	end
	ctx.render = function() end
	return ctx
end

describe("calendar view", function()
	it("only says the calendar is not configured without khal", function()
		local ctx = makeCtx()
		ctx.view.calendar = { available = false, events = {} }
		local tree = CalendarView.build(ctx)
		assert.equal(U.hasLabel(tree, "calendar.not-configured"), true)
		assert.equal(#U.ofType(tree, "button"), 0)
	end)

	it("draws the month with today selected and event days marked", function()
		local tree = CalendarView.build(makeCtx())
		assert.equal(U.hasLabel(tree, "2026-10"), true)
		local cell = U.byKey(tree, "day-2026-10-15")
		assert.equal(cell ~= nil, true)
		assert.equal(#U.ofType(cell, "box"), 1)
		assert.equal(#U.ofType(U.byKey(tree, "day-2026-10-16"), "box"), 0)
		assert.equal(U.byKey(tree, "day-2026-09-27") ~= nil, true)
	end)

	it("gives every day cell an explicit fill so a deselected day is cleared", function()
		-- The host keeps a prop that a later render omits.
		local ctx = makeCtx()
		U.byKey(CalendarView.build(ctx), "day-2026-10-16").props.onClick()
		local tree = CalendarView.build(ctx)
		for _, iso in { "2026-10-15", "2026-10-16", "2026-10-20" } do
			local cell = U.byKey(tree, "day-" .. iso)
			assert.equal(typeof(cell.props.fill), "string")
			assert.equal(typeof(cell.children[1].props.fontWeight), "string")
		end
		assert.equal(U.byKey(tree, "day-2026-10-20").props.fill, "#00000000")
	end)

	it("lists the selected day's events with their time range", function()
		local tree = CalendarView.build(makeCtx())
		assert.equal(U.hasLabel(tree, "Daily"), true)
		assert.equal(U.hasLabel(tree, "10:00–10:30"), true)
	end)

	it("selecting another day lists that day", function()
		local ctx = makeCtx()
		U.byKey(CalendarView.build(ctx), "day-2026-10-16").props.onClick()
		local tree = CalendarView.build(ctx)
		assert.equal(U.hasLabel(tree, "calendar.nothing-day"), true)
	end)

	it("moving to a month outside the loaded range asks for it", function()
		local ctx = makeCtx()
		-- November runs past the loaded window (to 2026-11-15).
		U.byKey(CalendarView.build(ctx), "next").props.onClick()
		assert.same(ctx.sent[1], { name = "loadRange", args = { from = "2026-11-01", to = "2026-11-30" } })
		U.byKey(CalendarView.build(ctx), "next").props.onClick()
		assert.same(ctx.sent[2].args, { from = "2026-12-01", to = "2026-12-31" })
		assert.equal(U.hasLabel(CalendarView.build(ctx), "2026-12"), true)
		-- Back to October, inside the window: nothing to load.
		U.byKey(CalendarView.build(ctx), "prev").props.onClick()
		U.byKey(CalendarView.build(ctx), "prev").props.onClick()
		assert.equal(#ctx.sent, 3)
		U.byKey(CalendarView.build(ctx), "prev").props.onClick()
		assert.same(ctx.sent[4].args, { from = "2026-09-01", to = "2026-09-30" })
	end)

	it("expanding an event loads its details once and shows them", function()
		local ctx = makeCtx()
		U.byKey(CalendarView.build(ctx), "expand-e1").props.onClick()
		assert.same(ctx.sent[1], { name = "loadDetails", args = { uid = "e1", calendar = "Eventos" } })
		local tree = CalendarView.build(ctx)
		assert.equal(U.hasLabel(tree, "events.details-loading"), true)
		ctx.view.details = {
			e1 = { people = { { name = "Ana", email = "a@x.dev", status = "accepted" } }, meetUrl = "https://meet.google.com/abc", location = "Sala 3" },
		}
		tree = CalendarView.build(ctx)
		assert.equal(U.hasLabel(tree, "Ana"), true)
		assert.equal(U.hasLabel(tree, "Sala 3"), true)
		U.button(tree, "text", "events.join-meet").props.onClick()
		assert.same(ctx.sent[2], { name = "openUrl", args = { url = "https://meet.google.com/abc" } })
		U.byKey(tree, "expand-e1").props.onClick()
		U.byKey(CalendarView.build(ctx), "expand-e1").props.onClick()
		assert.equal(#ctx.sent, 2)
	end)

	it("deletes through locate and confirm", function()
		local ctx = makeCtx()
		U.button(CalendarView.build(ctx), "tooltip", "events.delete").props.onClick()
		assert.equal(ctx.sent[1].name, "locateEvent")
		ctx.view.deleting = { e1 = { phase = "ready", recurring = false } }
		U.button(CalendarView.build(ctx), "text", "confirm.delete").props.onClick()
		assert.equal(ctx.sent[2].name, "deleteEvent")
	end)
end)
