local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local modules = require("./support/modules")
local U = require("./support/ui_helpers")

local describe, it = runner.describe, runner.it

local TodayView = modules.load("views/today.luau")

local NOW = 1792065600000 -- 2026-10-15 09:00
local TODAY = "2026-10-15"
local EV_START = 1792065600 + 3600

local function makeCtx(over)
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
		renders = 0,
		view = {
			data = {
				tasks = {
					{ id = "t1", title = "write", date = TODAY, done = false, createdAt = "a" },
					{ id = "t0", title = "old", date = "2026-10-10", done = false, createdAt = "b" },
				},
				eventChecks = {},
			},
			calendar = {
				available = true,
				events = { { uid = "e1", calendar = "Eventos", summary = "Daily", start = EV_START, ["end"] = EV_START + 1800, allDay = false } },
			},
			deleting = {},
		},
	}
	ctx.send = function(name, args, onAck)
		table.insert(sent, { name = name, args = args, onAck = onAck })
	end
	ctx.render = function()
		ctx.renders += 1
	end
	for k, v in over or {} do
		ctx[k] = v
	end
	return ctx
end

local function build(ctx)
	return TodayView.build(ctx)
end

describe("today view", function()
	it("lists events first, then tasks, with the overdue flag", function()
		local tree = build(makeCtx())
		assert.equal(U.hasLabel(tree, "Daily"), true)
		assert.equal(U.hasLabel(tree, "10:00"), true)
		assert.equal(U.hasLabel(tree, "write"), true)
		assert.equal(U.hasLabel(tree, "today.overdue"), true)
	end)

	it("toggles a task and an event check", function()
		local ctx = makeCtx()
		local tree = build(ctx)
		U.byKey(tree, "check-t1").props.onClick()
		U.byKey(tree, "check-" .. "e1|" .. TODAY).props.onClick()
		assert.equal(ctx.sent[1].name, "toggleTask")
		assert.same(ctx.sent[1].args, { id = "t1" })
		assert.equal(ctx.sent[2].name, "toggleEvent")
		assert.same(ctx.sent[2].args, { uid = "e1", date = TODAY })
	end)

	it("adds a task and clears the field after the ack", function()
		local ctx = makeCtx()
		local tree = build(ctx)
		local field = U.ofType(tree, "input")[1]
		local key = field.props.key
		field.props.onSubmit("call the bank 15h")
		assert.equal(ctx.sent[1].name, "addTask")
		assert.same(ctx.sent[1].args, { title = "call the bank", time = "15:00", date = TODAY })
		ctx.sent[1].onAck({ ok = true })
		assert.equal(U.ofType(build(ctx), "input")[1].props.key ~= key, true)
	end)

	it("renames inline, with a cancel button", function()
		local ctx = makeCtx()
		U.button(build(ctx), "tooltip", "today.rename").props.onClick()
		local tree = build(ctx)
		local field = U.byKey(tree, "rename-t1")
		assert.equal(field.props.value, "write")
		U.button(tree, "text", "confirm.cancel").props.onClick()
		assert.equal(U.byKey(build(ctx), "rename-t1"), nil)
		U.button(build(ctx), "tooltip", "today.rename").props.onClick()
		U.byKey(build(ctx), "rename-t1").props.onSubmit("newer")
		assert.same(ctx.sent[1].args, { id = "t1", title = "newer" })
	end)

	it("deletes a task only after confirming", function()
		local ctx = makeCtx()
		U.button(build(ctx), "tooltip", "today.delete").props.onClick()
		assert.equal(#ctx.sent, 0)
		local tree = build(ctx)
		assert.equal(U.hasLabel(tree, "today.delete"), true)
		U.button(tree, "text", "confirm.delete").props.onClick()
		assert.equal(ctx.sent[1].name, "deleteTask")
	end)

	it("locates an event before offering to delete it", function()
		local ctx = makeCtx()
		U.button(build(ctx), "tooltip", "events.delete").props.onClick()
		assert.same(ctx.sent[1], { name = "locateEvent", args = { uid = "e1", calendar = "Eventos" }, onAck = nil })
		ctx.view.deleting = { e1 = { phase = "locating", recurring = false } }
		local tree = build(ctx)
		assert.equal(U.button(tree, "text", "confirm.delete").props.enabled, false)
		ctx.view.deleting = { e1 = { phase = "ready", recurring = true } }
		tree = build(ctx)
		assert.equal(U.hasLabel(tree, "events.confirm-delete-recurring"), true)
		U.button(tree, "text", "confirm.delete").props.onClick()
		assert.same(ctx.sent[2].args, { uid = "e1", calendar = "Eventos" })
		assert.equal(ctx.sent[2].name, "deleteEvent")
	end)

	it("cancelling an event delete clears the service state", function()
		local ctx = makeCtx()
		U.button(build(ctx), "tooltip", "events.delete").props.onClick()
		ctx.view.deleting = { e1 = { phase = "ready", recurring = false } }
		U.button(build(ctx), "text", "confirm.cancel").props.onClick()
		assert.equal(ctx.sent[2].name, "cancelDelete")
	end)

	it("shows the empty message on a free day", function()
		local ctx = makeCtx()
		ctx.view.data.tasks = {}
		ctx.view.calendar.events = {}
		assert.equal(U.hasLabel(build(ctx), "today.empty-title"), true)
	end)
end)
