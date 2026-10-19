local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Text = modules.load("lib/text.luau")

describe("text.fold", function()
	it("lowercases and strips pt-BR accents", function()
		assert.equal(Text.fold("Ação É Ótima, CÃO"), "acao e otima, cao")
		assert.equal(Text.fold("Ç ü ñ"), "c u n")
	end)

	it("handles empty and non-string input", function()
		assert.equal(Text.fold(""), "")
		assert.equal(Text.fold(nil), "")
	end)
end)

describe("text.matches", function()
	it("matches every word of the query in any of the fields", function()
		assert.equal(Text.matches({ "Reunião de equipe", "notas" }, "reuniao"), true)
		assert.equal(Text.matches({ "Reunião de equipe", "notas" }, "equipe notas"), true)
		assert.equal(Text.matches({ "Reunião de equipe" }, "equipe cafe"), false)
	end)

	it("matches everything for a blank query", function()
		assert.equal(Text.matches({ "x" }, "   "), true)
		assert.equal(Text.matches({}, ""), true)
	end)

	it("skips nil fields and still matches later ones", function()
		assert.equal(Text.matches({ "a", nil, "zeta" }, "zeta"), true)
	end)
end)
