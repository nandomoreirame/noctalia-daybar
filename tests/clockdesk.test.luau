local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local entry = require("./support/entry")

local describe, it = runner.describe, runner.it

local NOW = 1792065600000

local RUNNING = {
	pomodoro = { mode = 0, running = true, endsAtMs = NOW + 754000, remaining = 1500, total = 1500 },
	timer = { set = false, running = false, remaining = 0, total = 0, label = "" },
	alarmSource = "",
	focusPanel = "pomodoro",
}

local function tree(d)
	local calls = mock.calls(d.env, "desktopWidget.render")
	return calls[#calls][1]
end

local function find(node, pred)
	if pred(node) then
		return node
	end
	for _, c in node.children or {} do
		local hit = find(c, pred)
		if hit ~= nil then
			return hit
		end
	end
	return nil
end

describe("desktop clock", function()
	it("asks for second ticks and renders on every update", function()
		local d = entry.load("clockdesk.luau", { now = NOW })
		assert.same(mock.calls(d.env, "desktopWidget.setWantsSecondTicks")[1], { true })
		d.env.noctalia.state.set("view", RUNNING)
		local before = #mock.calls(d.env, "desktopWidget.render")
		mock.advance(d.env, 1000)
		d.call("update")
		assert.equal(#mock.calls(d.env, "desktopWidget.render"), before + 1)
		local digits = find(tree(d), function(n)
			return n.type == "label" and n.props.text == "12:33"
		end)
		assert.equal(digits.props.fontSize, 48)
		assert.equal(tree(d).props.width, nil)
	end)

	it("shows controls on hover, never close", function()
		local d = entry.load("clockdesk.luau", { now = NOW })
		d.env.noctalia.state.set("view", RUNNING)
		d.call("update")
		tree(d).props.onHover("true", "")
		local close = find(tree(d), function(n)
			return n.type == "button" and n.props.glyph == "x"
		end)
		local pause = find(tree(d), function(n)
			return n.type == "button" and n.props.glyph == "player-pause"
		end)
		assert.equal(close, nil)
		assert.equal(pause ~= nil, true)
		pause.props.onClick()
		assert.equal(d.env.noctalia.state.get("cmd.clockdesk")[1].name, "pomodoro")
	end)

	it("shows --:-- without a view", function()
		local d = entry.load("clockdesk.luau", { now = NOW })
		d.call("update")
		local digits = find(tree(d), function(n)
			return n.type == "label"
		end)
		assert.equal(digits.props.text, "--:--")
	end)
end)
