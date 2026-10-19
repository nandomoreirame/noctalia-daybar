-- Harness fixture: requires a sibling the way the Noctalia host does.
local dep = require("./probe_dep.luau")
return {
	answer = function()
		return dep.half * 2
	end,
}
