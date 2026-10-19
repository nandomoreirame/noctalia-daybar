local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local entry = require("./support/entry")

local describe, it = runner.describe, runner.it

local NOW = 1792065600000

local function boot(view)
	local p = entry.load("clockpin.luau", { now = NOW })
	if view ~= nil then
		p.env.noctalia.state.set("view", view)
	end
	p.call("onOpen")
	return p
end

local function tree(p)
	local calls = mock.calls(p.env, "panel.render")
	return calls[#calls][1]
end

local function buttons(p)
	local out = {}
	local function walk(n)
		if n.type == "button" then
			out[n.props.glyph] = n
		end
		for _, c in n.children or {} do
			walk(c)
		end
	end
	walk(tree(p))
	return out
end

local TIMER = {
	pomodoro = { mode = 0, running = false, remaining = 1500, total = 1500 },
	timer = { set = true, running = true, endsAtMs = NOW + 60000, remaining = 300, total = 300, label = "" },
	alarmSource = "",
	focusPanel = "timer",
}

describe("pinned clock panel", function()
	it("renders on open and ticks every second", function()
		local p = boot(TIMER)
		assert.equal(#mock.calls(p.env, "panel.render") >= 1, true)
		assert.same(mock.calls(p.env, "panel.setWantsSecondTicks")[1], { true })
	end)

	it("hovering the root shows the controls", function()
		local p = boot(TIMER)
		assert.equal(buttons(p)["player-pause"], nil)
		tree(p).props.onHover("true", "")
		assert.equal(buttons(p)["player-pause"] ~= nil, true)
		tree(p).props.onHover("false", "")
		assert.equal(buttons(p)["player-pause"], nil)
	end)

	it("play/pause toggles the shown clock, reset resets it, close unpins", function()
		local p = boot(TIMER)
		tree(p).props.onHover("true", "")
		local b = buttons(p)
		b["player-pause"].props.onClick()
		b["refresh"].props.onClick()
		b["x"].props.onClick()
		local cmds = p.env.noctalia.state.get("cmd.clockpin")
		assert.equal(cmds[1].name, "timer")
		assert.same(cmds[1].args, { action = "toggle" })
		assert.same(cmds[2].args, { action = "reset" })
		assert.equal(cmds[3].name, "setClockOverlay")
		assert.same(cmds[3].args, { value = false })
	end)

	it("pushes pomodoro commands when the pomodoro is shown", function()
		local view = {
			pomodoro = { mode = 0, running = true, endsAtMs = NOW + 60000, remaining = 1500, total = 1500 },
			timer = { set = false, running = false, remaining = 0, total = 0, label = "" },
			alarmSource = "",
			focusPanel = "pomodoro",
		}
		local p = boot(view)
		tree(p).props.onHover("true", "")
		buttons(p)["player-pause"].props.onClick()
		assert.equal(p.env.noctalia.state.get("cmd.clockpin")[1].name, "pomodoro")
	end)
end)
