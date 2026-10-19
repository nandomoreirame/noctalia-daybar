local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")
local mock = require("./support/noctalia_mock")

local describe, it = runner.describe, runner.it

local function flatten(t: { [string]: any }, prefix: string, out: { [string]: any })
	for k, v in t do
		local key = if prefix == "" then k else prefix .. "." .. k
		if typeof(v) == "table" then
			flatten(v, key, out)
		else
			out[key] = v
		end
	end
	return out
end

local function sortedKeys(map: { [string]: any }): { string }
	local list = {}
	for k in map do
		table.insert(list, k)
	end
	table.sort(list)
	return list
end

local function decode(path: string): { [string]: any }
	local value, err = mock.json.decode(modules.text(path))
	if value == nil then
		error(path .. " is not valid JSON: " .. tostring(err))
	end
	return value
end

local en = flatten(decode("translations/en.json"), "", {})
local pt = flatten(decode("translations/pt-BR.json"), "", {})
local toml = modules.text("plugin.toml")

describe("translations", function()
	it("en and pt-BR have the same keys", function()
		assert.same(sortedKeys(pt), sortedKeys(en))
		assert.equal(#sortedKeys(en) > 150, true)
	end)

	it("have no empty or non-string value", function()
		for _, map in { en, pt } do
			for key, value in map do
				if typeof(value) ~= "string" or value == "" then
					error("empty or non-string translation: " .. key)
				end
			end
		end
	end)

	it("cover every label_key and description_key of plugin.toml", function()
		local count = 0
		for key in string.gmatch(toml, '_key%s*=%s*"([^"]+)"') do
			count += 1
			if en[key] == nil then
				error("missing translation: " .. key)
			end
		end
		-- 12 labels, 3 descriptions, 6 initial_tab options.
		assert.equal(count, 21)
	end)

	it("carry the v5 keys", function()
		for _, key in {
			"calendar.not-configured",
			"capture.not-ready",
			"confirm.delete",
			"confirm.cancel",
			"focus.pin",
			"focus.unpin",
			"store.imported",
		} do
			if en[key] == nil then
				error("missing translation: " .. key)
			end
		end
		for _, map in { en, pt } do
			for _, placeholder in { "{tasks}", "{notes}", "{bookmarks}" } do
				assert.equal(string.find(map["store.imported"], placeholder, 1, true) ~= nil, true)
			end
		end
	end)

	it("drop the keys of removed features", function()
		for key in en do
			for _, gone in { "focus.clock-window-", "settings.clock-corner", "settings.clock-size" } do
				if string.sub(key, 1, #gone) == gone then
					error("stale translation: " .. key)
				end
			end
		end
	end)
end)
