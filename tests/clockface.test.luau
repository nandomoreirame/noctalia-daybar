local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it

local ClockFace = modules.load("views/clockface.luau")

local NOW = 1792065600000

local function findAll(node, pred, out)
	out = out or {}
	if pred(node) then
		table.insert(out, node)
	end
	for _, child in node.children or {} do
		findAll(child, pred, out)
	end
	return out
end

local function ofType(node, kind)
	return findAll(node, function(n)
		return n.type == kind
	end)
end

local function build(view, opts)
	local env = mock.new({})
	local o = { ui = env.ui, tr = function(k)
		return k
	end, size = 40, onToggle = function() end, onReset = function() end, onClose = function() end }
	for k, v in opts or {} do
		o[k] = v
	end
	return ClockFace.build(view, NOW, o)
end

local RUNNING = {
	pomodoro = { mode = 0, running = true, endsAtMs = NOW + 754000, remaining = 1500, total = 1500 },
	timer = { set = false, running = false, remaining = 0, total = 0, label = "" },
	alarmSource = "",
	focusPanel = "pomodoro",
}

describe("clock face", function()
	it("shows --:-- and no controls without a view", function()
		local tree = build(nil, { hovered = true })
		assert.equal(ofType(tree, "label")[1].props.text, "--:--")
		assert.equal(#ofType(tree, "button"), 0)
	end)

	it("shows the running clock with its size and progress", function()
		local tree = build(RUNNING, {})
		local digits = findAll(tree, function(n)
			return n.type == "label" and n.props.text == "12:34"
		end)[1]
		assert.equal(digits.props.fontSize, 40)
		assert.equal(#ofType(tree, "progress"), 1)
	end)

	it("shows controls only while hovered, close only when closable", function()
		assert.equal(#ofType(build(RUNNING, { hovered = false }), "button"), 0)
		local glyphs = {}
		for _, b in ofType(build(RUNNING, { hovered = true }), "button") do
			table.insert(glyphs, b.props.glyph)
		end
		assert.same(glyphs, { "player-pause", "refresh" })
		local closable = ofType(build(RUNNING, { hovered = true, closable = true }), "button")
		assert.equal(closable[#closable].props.glyph, "x")
	end)

	it("shows the Focus view's clock when nothing runs", function()
		local view = {
			pomodoro = { mode = 0, running = false, remaining = 1500, total = 1500 },
			timer = { set = true, running = false, remaining = 300, total = 300, label = "chá" },
			alarmSource = "",
			focusPanel = "timer",
		}
		local tree = build(view, { hovered = true })
		local texts = {}
		for _, l in ofType(tree, "label") do
			texts[l.props.text] = true
		end
		assert.equal(texts["05:00"], true)
		assert.equal(texts["chá"], true)
		assert.equal(ofType(tree, "button")[1].props.glyph, "player-play")
	end)
end)
