-- Daybar desktop clock (REQ-028): the same face as the pinned clock, placed and
-- sized by the user in the desktop-widgets editor. No close: removing it is the
-- editor's job.

local ClockFace = require("./views/clockface.luau")
local Client = require("./views/client.luau")

local client = Client.new(noctalia.state, noctalia.nowMs(), "clockdesk")
local hovered = false

local render: () -> ()

local function view(): { [string]: any }?
	local v = noctalia.state.get("view")
	return if typeof(v) == "table" then v else nil
end

render = function()
	desktopWidget.render(ClockFace.build(view(), noctalia.nowMs(), {
		ui = ui,
		tr = noctalia.tr,
		size = 48,
		hovered = hovered,
		closable = false,
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
	}))
end

function update()
	render()
end

desktopWidget.setWantsSecondTicks(true)
noctalia.state.watch("view", function()
	render()
end)
