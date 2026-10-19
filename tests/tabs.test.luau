local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Tabs = modules.load("lib/tabs.luau")

local function emptyData()
	return {
		version = 2,
		tasks = {},
		eventChecks = {},
		reminders = {},
		bookmarks = {},
		notes = {},
		focusLog = {},
		recentTimers = {},
		ui = { lastTab = "" },
	}
end

local function sortedKeys(t)
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function sortedCopy(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	table.sort(out)
	return out
end

describe("tabs", function()
	it("lists the toolbar tabs in order", function()
		assert.same(Tabs.TABS, { "calendar", "today", "focus", "bookmarks", "notes" })
	end)

	it("prefers an IPC request, then the setting, then the last tab", function()
		assert.equal(Tabs.initialTab("notes", "today", "focus"), "notes")
		assert.equal(Tabs.initialTab("", "last", "removed"), "today")
		assert.equal(Tabs.initialTab("", "calendar", "focus"), "calendar")
		assert.equal(Tabs.initialTab("", "last", "focus"), "focus")
	end)

	it("falls back to today for unknown or missing values", function()
		assert.equal(Tabs.initialTab("", "last", ""), "today")
		assert.equal(Tabs.initialTab("bogus", "bogus", "bogus"), "today")
		assert.equal(Tabs.initialTab("", nil, nil), "today")
	end)

	it("stores the last tab without mutating, ignoring unknown keys", function()
		local data = emptyData()
		local nextData = Tabs.setLastTab(data, "focus")
		assert.equal(nextData.ui.lastTab, "focus")
		assert.equal(data.ui.lastTab, "")
		assert.equal(Tabs.setLastTab(nextData, "focus"), nextData)
		assert.equal(Tabs.setLastTab(nextData, "bogus"), nextData)
	end)

	it("returns the same table when the last tab is unchanged", function()
		local d = emptyData()
		d.ui.lastTab = "today"
		assert.equal(Tabs.setLastTab(d, "today"), d)
	end)

	it("has one icon per tab, shared by the tab bar and the bar widget", function()
		assert.same(sortedKeys(Tabs.ICONS), sortedCopy(Tabs.TABS))
		assert.equal(Tabs.ICONS.calendar, "calendar")
	end)
end)
