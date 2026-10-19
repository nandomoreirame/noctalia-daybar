local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")
local entry = require("./support/entry")

local describe, it = runner.describe, runner.it

describe("harness", function()
	it("loads a module that requires a sibling with the host .luau form", function()
		local probe = modules.load("tests/support/fixtures/probe.luau")
		assert.equal(probe.answer(), 42)
	end)

	it("loads modules in nested directories (lib/capture style)", function()
		local deep = modules.load("tests/support/fixtures/nested/deep.luau")
		assert.equal(deep.parentAnswer(), 42)
	end)

	it("rejects require paths the host rejects", function()
		local req = modules.requirer("lib/x.luau")
		assert.throws(function()
			req("./y")
		end, "relative and end in .luau")
	end)

	it("runs with the Sao Paulo timezone", function()
		-- 2026-10-15 12:00 UTC is 09:00 in America/Sao_Paulo (UTC-3, no DST)
		assert.equal(os.date("%H:%M", 1792065600), "09:00")
	end)

	it("gives entries a host-style require", function()
		local loaded = entry.load("tests/support/fixtures/probe.luau", {})
		assert.equal(typeof(loaded.env.require), "function")
	end)
end)
