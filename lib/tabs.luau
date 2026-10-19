--!strict
-- Toolbar tabs and which one the panel opens on.

local Tbl = require("./tbl.luau")

local Tabs = {}

Tabs.TABS = { "calendar", "today", "focus", "bookmarks", "notes" }
Tabs.FALLBACK = "today"
Tabs.ICONS = {
	calendar = "calendar",
	today = "list-check",
	focus = "hourglass",
	bookmarks = "bookmark",
	notes = "notes",
}

function Tabs.isTab(key: any): boolean
	return Tbl.contains(Tabs.TABS, key)
end

-- An IPC open <tab> request wins; then the "initialTab" setting, where "last"
-- means the tab the user had open last time.
function Tabs.initialTab(requested: any, setting: any, lastTab: any): string
	if Tabs.isTab(requested) then
		return requested
	end
	if setting == "last" then
		return if Tabs.isTab(lastTab) then lastTab else Tabs.FALLBACK
	end
	return if Tabs.isTab(setting) then setting else Tabs.FALLBACK
end

-- Same table back when nothing changes, so selecting the current tab does not
-- schedule a write.
function Tabs.setLastTab(data: { [any]: any }, key: any): { [any]: any }
	local ui = data.ui or {}
	if not Tabs.isTab(key) or ui.lastTab == key then
		return data
	end
	return Tbl.merge(data, { ui = Tbl.merge(ui, { lastTab = key }) })
end

return Tabs
