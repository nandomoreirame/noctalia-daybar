--!strict
-- Deliberately failing fixture. Not under tests/*.test.luau, so normal discovery
-- skips it. Invoked by run-tests --expect-fail (bash subprocess; Luau CLI has no
-- os.execute / os.exit).
local assert = require("../assert")
local runner = require("../runner")

runner.describe("failing fixture", function()
	runner.it("deliberately fails", function()
		assert.equal(1, 2)
	end)
end)
