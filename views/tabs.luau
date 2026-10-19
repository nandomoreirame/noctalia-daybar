--!strict
-- The toolbar's tab strip and its refresh button.

local Tabs = require("../lib/tabs.luau")

local TabsView = {}

function TabsView.build(ctx: any, active: string, onSelect: (string) -> (), onReload: () -> ()): any
	local ui = ctx.ui
	local buttons = {}
	for _, tab in ipairs(Tabs.TABS) do
		table.insert(buttons, ui.button({
			key = "tab-" .. tab,
			glyph = Tabs.ICONS[tab],
			text = ctx.tr("tabs." .. tab),
			variant = if tab == active then "secondary" else "ghost",
			selected = tab == active,
			controlSize = "sm",
			onClick = function()
				onSelect(tab)
			end,
		}))
	end
	table.insert(buttons, ui.spacer({ flexGrow = 1 }))
	table.insert(buttons, ui.button({
		key = "reload",
		glyph = "refresh",
		variant = "ghost",
		controlSize = "sm",
		tooltip = ctx.tr("tabs.reload"),
		onClick = onReload,
	}))
	return ui.row({ gap = 4, align = "center" }, buttons)
end

return TabsView
