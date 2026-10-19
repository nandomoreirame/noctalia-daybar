local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local entry = require("./support/entry")
local H = require("./support/service_helpers")

local describe, it = runner.describe, runner.it

local function boot(colors)
	local s = entry.load("service.luau", {
		pluginDataDir = H.DATA,
		deferAsync = true,
		config = H.CONFIG,
		now = H.NOW,
		colors = colors,
	})
	return s
end

describe("service rings", function()
	it("writes one ring per percent for the theme's primary color and publishes the dir", function()
		local s = boot({ primary = "#FFB38A" })
		local dir = H.DATA .. "/rings/ffb38a"
		local fs = mock.fs(s.env)
		assert.equal(typeof(fs[dir .. "/0.svg"]), "string")
		assert.equal(typeof(fs[dir .. "/100.svg"]), "string")
		assert.equal(s.env.noctalia.state.get("view").ringDir, dir)
	end)

	it("does not rewrite rings that already exist", function()
		local s = boot({ primary = "#FFB38A" })
		local writes = #mock.calls(s.env, "noctalia.writeFile")
		mock.advance(s.env, 5000)
		s.call("update")
		assert.equal(#mock.calls(s.env, "noctalia.writeFile"), writes)
	end)

	it("regenerates when the primary color changes", function()
		local s = boot({ primary = "#FFB38A" })
		mock.setColor(s.env, "primary", "#00AAFF")
		mock.advance(s.env, 5000)
		s.call("update")
		assert.equal(typeof(mock.fs(s.env)[H.DATA .. "/rings/00aaff/50.svg"]), "string")
		assert.equal(s.env.noctalia.state.get("view").ringDir, H.DATA .. "/rings/00aaff")
	end)

	it("publishes no ring dir without a theme color", function()
		local s = boot({})
		assert.equal(s.env.noctalia.state.get("view").ringDir, nil)
	end)
end)
