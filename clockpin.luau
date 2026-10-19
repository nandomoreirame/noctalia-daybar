-- Daybar pinned clock (REQ-027): a persistent panel that never takes focus,
-- shown while `data.ui.clockOverlay` is on. Its corner is the host-injected
-- `clock_position` panel setting.

local ClockFace = require("./views/clockface.luau")
local Client = require("./views/client.luau")

local client = Client.new(noctalia.state, noctalia.nowMs(), "clockpin")
local hovered = false

local render: () -> ()

local function view(): { [string]: any }?
	local v = noctalia.state.get("view")
	return if typeof(v) == "table" then v else nil
end

render = function()
	panel.render(ClockFace.build(view(), noctalia.nowMs(), {
		ui = ui,
		tr = noctalia.tr,
		size = 34,
		hovered = hovered,
		closable = true,
		onHover = function(state: string)
			hovered = state == "true"
			render()
		end,
		onToggle = function(source: string)
			client.send(source, { action = "toggle" })
		end,
		onReset = function(source: string)
			client.send(source, { action = "reset" })
		end,
		onClose = function()
			client.send("setClockOverlay", { value = false })
		end,
	}))
end

function onOpen(_context: string?)
	panel.setWantsSecondTicks(true)
	render()
end

function update()
	render()
end

noctalia.state.watch("view", function()
	render()
end)
