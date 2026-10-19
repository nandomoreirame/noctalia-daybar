local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local entry = require("./support/entry")

local describe, it = runner.describe, runner.it

local NOW = 1792065600000 -- 2026-10-15 09:00 in America/Sao_Paulo

local function view(over)
	local v = {
		rev = 1,
		now = NOW,
		data = { bookmarks = {}, tasks = {} },
		pomodoro = { mode = 0, running = false, remaining = 1500, total = 1500 },
		timer = { set = false, running = false, remaining = 0, total = 0, label = "" },
		alarmSource = "",
	}
	for k, val in over or {} do
		v[k] = val
	end
	return v
end

local function boot(opts)
	local o = opts or {}
	local p = entry.load("capture.luau", { now = NOW, clipboard = o.clipboard })
	if o.view ~= false then
		p.env.noctalia.state.set("view", o.view or view())
	end
	p.call("onOpen")
	return p
end

local function tree(p)
	local calls = mock.calls(p.env, "panel.render")
	return calls[#calls][1]
end

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

local function input(p)
	return findAll(tree(p), function(n)
		return n.type == "input"
	end)[1]
end

local function hasText(p, text)
	return #findAll(tree(p), function(n)
		return n.type == "label" and n.props.text ~= nil and string.find(n.props.text, text, 1, true) ~= nil
	end) > 0
end

local function commands(p)
	return p.env.noctalia.state.get("cmd.capture") or {}
end

local function ack(p, ok, err)
	local list = commands(p)
	p.env.noctalia.state.set("ack.capture", { seq = list[#list].seq, ok = ok, error = err })
end

describe("capture panel", function()
	it("opens with a focused, keyed input, the type chip and the keys hint", function()
		local p = boot()
		local field = input(p)
		assert.equal(field.props.focus, true)
		assert.equal(typeof(field.props.key), "string")
		assert.equal(field.props.value, "")
		assert.equal(hasText(p, "capture.type.task"), true)
		assert.equal(hasText(p, "capture.keys"), true)
	end)

	it("prefills a clipboard URL that is not bookmarked yet", function()
		assert.equal(input(boot({ clipboard = "https://new.dev" })).props.value, "https://new.dev")
		local saved = view({ data = { bookmarks = { { id = "b", url = "https://new.dev" } }, tasks = {} } })
		assert.equal(input(boot({ clipboard = "https://new.dev", view = saved })).props.value, "")
	end)

	it("previews what Enter will save as the text changes", function()
		local p = boot()
		p.call("onChange", "amanhã 9h comprar pão")
		assert.equal(hasText(p, "comprar pão"), true)
		assert.equal(hasText(p, "09:00"), true)
		assert.equal(hasText(p, "capture.type.task"), true)
	end)

	it("Tab and Shift+Tab force the next and previous type", function()
		local p = boot()
		p.call("onChange", "reunião")
		p.call("onKey", "tab", true)
		assert.equal(hasText(p, "capture.type.event"), true)
		p.call("onKey", "shift+tab", true)
		p.call("onKey", "shift+tab", true)
		assert.equal(hasText(p, "capture.type.timer"), true)
		-- Releases do nothing.
		p.call("onKey", "tab", false)
		assert.equal(hasText(p, "capture.type.timer"), true)
	end)

	it("Enter commits the text with the forced type and closes on success", function()
		local p = boot()
		p.call("onChange", "reunião")
		p.call("onKey", "tab", true)
		p.call("onSubmit", "reunião amanhã 15h")
		local cmd = commands(p)[1]
		assert.equal(cmd.name, "commit")
		assert.same(cmd.args, { text = "reunião amanhã 15h", type = "event" })
		ack(p, true)
		assert.equal(#mock.calls(p.env, "panel.close"), 1)
		assert.equal(#mock.calls(p.env, "noctalia.notify"), 1)
	end)

	it("keeps the text and shows the error when the service refuses", function()
		local p = boot()
		p.call("onSubmit", "/e reunião amanhã 15h")
		ack(p, false, "calendar-not-configured")
		assert.equal(#mock.calls(p.env, "panel.close"), 0)
		assert.equal(#mock.calls(p.env, "noctalia.notifyError"), 1)
		assert.equal(hasText(p, "capture.error.calendar-not-configured"), true)
		assert.equal(input(p).props.value, "/e reunião amanhã 15h")
	end)

	it("Shift+Enter saves and clears the field, keeping the panel open", function()
		local p = boot()
		local firstKey = input(p).props.key
		p.call("onChange", "comprar pão")
		p.call("onKey", "shift+Return", true)
		assert.equal(commands(p)[1].args.text, "comprar pão")
		ack(p, true)
		assert.equal(#mock.calls(p.env, "panel.close"), 0)
		assert.equal(input(p).props.key ~= firstKey, true)
		assert.equal(input(p).props.value, "")
	end)

	it("copies a calculation and stays open without a command", function()
		local p = boot()
		p.call("onSubmit", "=200*15%")
		assert.same(mock.calls(p.env, "noctalia.copyToClipboard")[1], { "30", "text/plain" })
		assert.equal(#commands(p), 0)
		assert.equal(#mock.calls(p.env, "panel.close"), 0)
		p.call("onSubmit", "=2+")
		assert.equal(#mock.calls(p.env, "noctalia.copyToClipboard"), 1)
	end)

	it("an invalid capture sends nothing", function()
		local p = boot()
		p.call("onSubmit", "/e")
		assert.equal(#commands(p), 0)
	end)

	it("says the service is not ready before the first view", function()
		local p = boot({ view = false })
		p.call("onSubmit", "comprar pão")
		assert.equal(hasText(p, "capture.not-ready"), true)
		assert.equal(#commands(p), 0)
	end)

	it("closing drops the typed text and a late answer only notifies", function()
		local p = boot()
		p.call("onChange", "comprar pão")
		p.call("onSubmit", "comprar pão")
		p.call("onClose")
		ack(p, true)
		assert.equal(#mock.calls(p.env, "panel.close"), 0)
		assert.equal(#mock.calls(p.env, "noctalia.notify"), 1)
		p.call("onOpen")
		assert.equal(input(p).props.value, "")
	end)
end)
