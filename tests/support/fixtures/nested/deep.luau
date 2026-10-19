local probe = require("../probe.luau")
return {
	parentAnswer = function()
		return probe.answer()
	end,
}
