local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Dates = modules.load("lib/dates.luau")
local When = modules.load("lib/when.luau")

-- Friday, 9 October 2026, 15:00 local time (same as vitest NOW).
local NOW = Dates.toDate("2026-10-09", "15:00")
-- Thursday, 15 October 2026, 10:00 local (plan extras; civilLocal, not bare os.time).
local NOW_THU_10H = Dates.toDate("2026-10-15", "10:00")

describe("parseWhen: days", function()
	local cases = {
		{ "pagar boleto amanhã", "pagar boleto", "2026-10-10" },
		{ "Amanhã comprar pão", "comprar pão", "2026-10-10" },
		{ "comprar pão amanha", "comprar pão", "2026-10-10" },
		{ "dentista depois de amanhã", "dentista", "2026-10-11" },
		{ "hoje revisar PR", "revisar PR", "2026-10-09" },
		{ "pagar boleto na segunda", "pagar boleto", "2026-10-12" },
		{ "reunião sexta", "reunião", "2026-10-16" },
		{ "feira no sábado", "feira", "2026-10-10" },
		{ "feira sabado", "feira", "2026-10-10" },
		{ "terca-feira academia", "academia", "2026-10-13" },
		{ "consulta 05/11", "consulta", "2026-11-05" },
		{ "aniversário 01/10", "aniversário", "2027-10-01" },
		{ "prova 10/10/27", "prova", "2027-10-10" },
	}
	for _, c in ipairs(cases) do
		local text, title, date = c[1], c[2], c[3]
		it(text, function()
			local r = When.parseWhen(text, NOW)
			assert.equal(r.title, title)
			assert.equal(r.date, date)
		end)
	end

	it("ignores invalid calendar dates", function()
		assert.same(When.parseWhen("31/02 teste", NOW), {
			title = "31/02 teste",
			date = nil,
			start = nil,
			["end"] = nil,
		})
	end)

	it("leaves text without date untouched", function()
		assert.same(When.parseWhen("comprar 2 pães", NOW), {
			title = "comprar 2 pães",
			date = nil,
			start = nil,
			["end"] = nil,
		})
	end)

	local ordinals = {
		"ler a sexta parte do livro",
		"ir pra segunda reunião",
		"revisar a quarta versão",
		"matrícula na quinta série",
	}
	for _, text in ipairs(ordinals) do
		it("keeps ordinal adjectives as text: " .. text, function()
			assert.same(When.parseWhen(text, NOW), {
				title = text,
				date = nil,
				start = nil,
				["end"] = nil,
			})
		end)
	end

	local weekdayEdges = {
		{ "segunda revisar PR", "revisar PR", "2026-10-12" },
		{ "pagar boleto sexta, sem falta", "pagar boleto , sem falta", "2026-10-16" },
		{ "ligar pro banco segunda-feira cedo", "ligar pro banco cedo", "2026-10-12" },
	}
	for _, c in ipairs(weekdayEdges) do
		it("still reads weekdays at the start, before punctuation or with -feira: " .. c[1], function()
			local r = When.parseWhen(c[1], NOW)
			assert.equal(r.title, c[2])
			assert.equal(r.date, c[3])
		end)
	end

	it("does not match weekday names inside other words", function()
		assert.equal(When.parseWhen("segundas intenções", NOW).date, nil)
	end)
end)

describe("parseWhen: times", function()
	local cases = {
		{
			"comprar pão amanhã 9h",
			{ title = "comprar pão", date = "2026-10-10", start = "09:00", ["end"] = nil },
		},
		{
			"ligar pro banco 16h",
			{ title = "ligar pro banco", date = "2026-10-09", start = "16:00", ["end"] = nil },
		},
		{
			"ligar pro banco 9h",
			{ title = "ligar pro banco", date = "2026-10-10", start = "09:00", ["end"] = nil },
		},
		{
			"standup 15h",
			{ title = "standup", date = "2026-10-10", start = "15:00", ["end"] = nil },
		},
		{
			"hoje 9h revisar",
			{ title = "revisar", date = "2026-10-09", start = "09:00", ["end"] = nil },
		},
		{
			"reunião sexta 15h-16h",
			{ title = "reunião", date = "2026-10-16", start = "15:00", ["end"] = "16:00" },
		},
		{
			"15h às 16h30 call",
			{ title = "call", date = "2026-10-10", start = "15:00", ["end"] = "16:30" },
		},
		{
			"depois de amanhã às 10h30 dentista",
			{ title = "dentista", date = "2026-10-11", start = "10:30", ["end"] = nil },
		},
		{
			"consulta 05/11 às 14:00",
			{ title = "consulta", date = "2026-11-05", start = "14:00", ["end"] = nil },
		},
		{
			"almoço 12:00 - 13:00 amanhã",
			{ title = "almoço", date = "2026-10-10", start = "12:00", ["end"] = "13:00" },
		},
	}
	for _, c in ipairs(cases) do
		it(c[1], function()
			assert.same(When.parseWhen(c[1], NOW), c[2])
		end)
	end

	it("rejects impossible times", function()
		assert.same(When.parseWhen("treino 25h", NOW), {
			title = "treino 25h",
			date = nil,
			start = nil,
			["end"] = nil,
		})
		assert.equal(When.parseWhen("treino 10h75", NOW).start, nil)
	end)

	it("does not read a bare number followed by a word as a range end", function()
		assert.same(When.parseWhen("aula 9h às 10 pessoas", NOW), {
			title = "aula às 10 pessoas",
			date = "2026-10-10",
			start = "09:00",
			["end"] = nil,
		})
	end)

	it("accepts a bare range end at the end of the text", function()
		assert.same(When.parseWhen("aula 9h às 10", NOW), {
			title = "aula",
			date = "2026-10-10",
			start = "09:00",
			["end"] = "10:00",
		})
	end)

	it("leaves a range whose end is not after its start as plain text", function()
		assert.same(When.parseWhen("plantão 23h-1h", NOW), {
			title = "plantão 23h-1h",
			date = nil,
			start = nil,
			["end"] = nil,
		})
	end)
end)

describe("parseWhen: plan extras", function()
	it("reads a weekday as the next occurrence", function()
		local r = When.parseWhen("reunião sexta 15h", NOW_THU_10H)
		assert.equal(r.date, "2026-10-16")
		assert.equal(r.start, "15:00")
	end)

	it("moves a past time without date to tomorrow", function()
		assert.equal(When.parseWhen("ligar 9h", NOW_THU_10H).date, "2026-10-16")
	end)
end)

describe("parseWhen: parity with v4 when.js", function()
	it("accepts a single-token range with a bare end hour", function()
		assert.same(When.parseWhen("aula 9h-10", NOW), {
			title = "aula",
			date = "2026-10-10",
			start = "09:00",
			["end"] = "10:00",
		})
	end)

	it("accepts mixed h and colon forms in a single-token range", function()
		assert.same(When.parseWhen("reunião 15h-16:00", NOW), {
			title = "reunião",
			date = "2026-10-10",
			start = "15:00",
			["end"] = "16:00",
		})
	end)

	it("continues past an invalid single-token range to a later simple time", function()
		assert.same(When.parseWhen("plantão 23h-1h 9h", NOW), {
			title = "plantão 23h-1h",
			date = "2026-10-10",
			start = "09:00",
			["end"] = nil,
		})
	end)

	it("keeps a bare range end when the next word is already consumed as a day", function()
		assert.same(When.parseWhen("aula 9h às 10 amanhã", NOW), {
			title = "aula",
			date = "2026-10-10",
			start = "09:00",
			["end"] = "10:00",
		})
	end)

	it("reads a weekday after a leading preposition as the start of text", function()
		local r = When.parseWhen("na segunda revisar PR", NOW)
		assert.equal(r.title, "revisar PR")
		assert.equal(r.date, "2026-10-12")
	end)
end)
