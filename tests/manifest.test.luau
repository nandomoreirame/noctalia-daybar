local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it

-- Minimal TOML line scanner, enough for plugin.toml: root keys, [[array]] tables,
-- [sub.table] tables attached to the last array entry, strings, ints, bools,
-- string arrays and (possibly multi-line) arrays of inline tables.
local function trim(s: string): string
	return string.match(s, "^%s*(.-)%s*$") or ""
end

local function stripComment(line: string): string
	local out, inString = {}, false
	for i = 1, #line do
		local c = string.sub(line, i, i)
		if c == '"' then
			inString = not inString
		elseif c == "#" and not inString then
			break
		end
		table.insert(out, c)
	end
	return table.concat(out)
end

local function parseScalar(raw: string): any
	raw = trim(raw)
	local str = string.match(raw, '^"(.*)"$')
	if str ~= nil then
		return str
	end
	if raw == "true" then
		return true
	end
	if raw == "false" then
		return false
	end
	local n = tonumber(raw)
	if n ~= nil then
		return n
	end
	error("toml scanner: cannot parse value " .. raw)
end

local function parseValue(raw: string): any
	raw = trim(raw)
	if string.sub(raw, 1, 1) ~= "[" then
		return parseScalar(raw)
	end
	local inner = string.sub(raw, 2, -2)
	local list = {}
	if string.find(inner, "{", 1, true) then
		for body in string.gmatch(inner, "{(.-)}") do
			local item = {}
			for key, value in string.gmatch(body, '([%w_]+)%s*=%s*("[^"]*")') do
				item[key] = parseScalar(value)
			end
			table.insert(list, item)
		end
	else
		for value in string.gmatch(inner, '"[^"]*"') do
			table.insert(list, parseScalar(value))
		end
	end
	return list
end

local function bracketBalance(s: string): number
	local open = select(2, string.gsub(s, "%[", ""))
	local close = select(2, string.gsub(s, "%]", ""))
	return open - close
end

local function scan(text: string)
	local root: { [string]: any } = {}
	local arrays: { [string]: { any } } = {}
	local current = root
	local pending: string? = nil
	local pendingKey: string? = nil
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		line = trim(stripComment(line))
		if pending ~= nil then
			pending ..= " " .. line
			if bracketBalance(pending) <= 0 then
				current[pendingKey :: string] = parseValue(pending)
				pending, pendingKey = nil, nil
			end
		elseif line == "" then
			-- skip
		elseif string.match(line, "^%[%[") then
			local name = string.match(line, "^%[%[%s*([%w_%.]+)%s*%]%]$") :: string
			arrays[name] = arrays[name] or {}
			current = {}
			table.insert(arrays[name], current)
		elseif string.match(line, "^%[") then
			local parent, child = string.match(line, "^%[%s*([%w_]+)%.([%w_]+)%s*%]$")
			local list = arrays[parent :: string]
			local owner = list[#list]
			owner[child :: string] = {}
			current = owner[child :: string]
		else
			local key, value = string.match(line, "^([%w_]+)%s*=%s*(.+)$")
			assert.equal(key ~= nil, true)
			if string.sub(value :: string, 1, 1) == "[" and bracketBalance(value :: string) > 0 then
				pending, pendingKey = value, key
			else
				current[key :: string] = parseValue(value :: string)
			end
		end
	end
	return root, arrays
end

local toml = modules.text("plugin.toml")
local root, arrays = scan(toml)

local function byId(kind: string, id: string): { [string]: any }
	for _, entry in arrays[kind] or {} do
		if entry.id == id then
			return entry
		end
	end
	error("plugin.toml has no " .. kind .. " " .. id)
end

local function settingByKey(key: string): { [string]: any }
	for _, s in arrays.setting or {} do
		if s.key == key then
			return s
		end
	end
	error("plugin.toml has no setting " .. key)
end

describe("plugin.toml identity", function()
	it("declares id, name, version, api level, license and dependencies", function()
		assert.equal(root.id, "nandomoreirame/daybar")
		assert.equal(root.name, "Daybar")
		assert.equal(root.version, "0.4.0")
		assert.equal(root.plugin_api, 32)
		assert.equal(root.license, "MIT")
		assert.same(root.dependencies, { "khal", "vdirsyncer", "xdg-utils" })
	end)

	it("keeps the description within 120 characters", function()
		assert.equal(typeof(root.description), "string")
		assert.equal(utf8.len(root.description) <= 120, true)
		assert.equal(#root.description > 0, true)
	end)
end)

describe("plugin.toml entries", function()
	it("declares the core service and the bar widget with middle click freed", function()
		assert.equal(byId("service", "core").entry, "service.luau")
		local bar = byId("widget", "bar")
		assert.equal(bar.entry, "widget.luau")
		assert.same(bar.actions, { middle = "none" })
	end)

	it("declares the toolbar panel attached to the bar", function()
		local p = byId("panel", "toolbar")
		assert.equal(p.entry, "toolbar.luau")
		assert.equal(p.width, 680)
		assert.equal(p.height, 450)
		assert.equal(p.placement, "attached")
		assert.equal(p.open_near_click, true)
	end)

	it("declares the capture panel as a centered overlay that captures Tab", function()
		local p = byId("panel", "capture")
		assert.equal(p.entry, "capture.luau")
		assert.equal(p.width, 640)
		assert.equal(p.height, 240)
		assert.equal(p.placement, "floating")
		assert.equal(p.position, "center")
		assert.equal(p.layer, "overlay")
		assert.equal(p.keyboard_focus, "exclusive")
		assert.same(p.capture_keys, { "tab", "shift+tab", "shift+Return" })
	end)

	it("declares the note panel", function()
		local p = byId("panel", "note")
		assert.equal(p.entry, "note.luau")
		assert.equal(p.width, 1100)
		assert.equal(p.height, 800)
		assert.equal(p.placement, "floating")
		assert.equal(p.position, "center")
		assert.equal(p.keyboard_focus, "exclusive")
		assert.same(p.capture_keys, { "ctrl+e", "ctrl+s" })
	end)

	it("declares the pinned clock panel and the clockface desktop widget", function()
		local p = byId("panel", "clock")
		assert.equal(p.entry, "clockpin.luau")
		assert.equal(p.width, 200)
		assert.equal(p.height, 200)
		assert.equal(p.persistent, true)
		assert.equal(p.keyboard_focus, "none")
		assert.equal(p.dismiss_on_outside_click, false)
		assert.equal(p.position, "top_right")
		assert.equal(p.layer, "overlay")
		assert.equal(byId("desktop_widget", "clockface").entry, "clockdesk.luau")
	end)

	it("has exactly the expected entries", function()
		assert.equal(#arrays.service, 1)
		assert.equal(#arrays.widget, 1)
		assert.equal(#arrays.panel, 4)
		assert.equal(#arrays.desktop_widget, 1)
	end)
end)

describe("plugin.toml settings", function()
	local expected = {
		{ "work_duration", "int", 25, 1, 180 },
		{ "short_break_duration", "int", 5, 1, 60 },
		{ "long_break_duration", "int", 15, 1, 120 },
		{ "sessions_before_long_break", "int", 4, 1, 12 },
		{ "daily_pomodoro_goal", "int", 8, 0, 24 },
		{ "auto_start_breaks", "bool", false },
		{ "auto_start_work", "bool", false },
		{ "play_sound", "bool", true },
		{ "focus_mode_command", "string", "" },
		{ "default_calendar", "string", "" },
		{ "initial_tab", "select", "last" },
		{ "fetch_previews", "bool", true },
	}

	it("declares the 12 plugin-level settings", function()
		assert.equal(#arrays.setting, 12)
	end)

	for _, e in expected do
		it(string.format("%s is %s with default %s", e[1], e[2], tostring(e[3])), function()
			local s = settingByKey(e[1])
			assert.equal(s.type, e[2])
			assert.equal(s.default, e[3])
			assert.equal(s.label_key, "settings." .. e[1] .. ".label")
			if e[4] ~= nil then
				assert.equal(s.min, e[4])
				assert.equal(s.max, e[5])
			end
		end)
	end

	it("describes the command, calendar and preview settings", function()
		for _, key in { "focus_mode_command", "default_calendar", "fetch_previews" } do
			assert.equal(settingByKey(key).description_key, "settings." .. key .. ".description")
		end
	end)

	it("offers the initial tab options", function()
		local values = {}
		for _, o in settingByKey("initial_tab").options do
			assert.equal(typeof(o.label_key), "string")
			table.insert(values, o.value)
		end
		assert.same(values, { "last", "calendar", "today", "focus", "bookmarks", "notes" })
	end)
end)
