local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")
local mock = require("./support/noctalia_mock")

local describe, it = runner.describe, runner.it
local KhalRead = modules.load("lib/khalread.luau")

local decode = mock.new({}).noctalia.json.decode

local function find(evs, uidPrefix)
	for _, ev in ipairs(evs) do
		if string.sub(ev.uid, 1, #uidPrefix) == uidPrefix then
			return ev
		end
	end
	return nil
end

local function fixture()
	return KhalRead.parse(modules.text("tests/fixtures/khal-list.txt"), decode)
end

describe("khalread.parse", function()
	it("parses timed, all-day and multi-day events, deduplicated", function()
		local evs = fixture()
		assert.equal(#evs, 3)
	end)

	it("sorts events by start", function()
		local evs = fixture()
		for i = 2, #evs do
			assert.equal(evs[i - 1].start <= evs[i].start, true)
		end
		assert.equal(evs[3].uid, "t1")
	end)

	it("makes all-day end exclusive at the next midnight", function()
		local h = find(fixture(), "h1")
		assert.equal(h.allDay, true)
		assert.equal(os.date("%Y-%m-%d %H:%M", h.start), "2026-10-15 00:00")
		assert.equal(h["end"] - h.start, 86400)
	end)

	it("reads timed events in local time", function()
		local m = find(fixture(), "m1")
		assert.equal(m.allDay, false)
		assert.equal(os.date("%Y-%m-%d %H:%M", m.start), "2026-10-15 09:00")
		assert.equal(os.date("%Y-%m-%d %H:%M", m["end"]), "2026-10-15 10:00")
		assert.equal(m.repeats, true)
	end)

	it("keeps the v4 event shape with the title as summary", function()
		local m = find(fixture(), "m1")
		assert.same(m, {
			uid = "m1",
			calendar = "Eventos",
			summary = "Review",
			start = m.start,
			["end"] = m["end"],
			allDay = false,
			location = "Sala 2",
			url = "",
			description = "",
			repeats = true,
		})
		local h = find(fixture(), "h1")
		assert.equal(h.summary, "Dia do Professor")
		assert.equal(h.description, "Data comemorativa")
		assert.equal(h.repeats, false)
	end)

	it("reads multi-day timed events across midnight", function()
		local t = find(fixture(), "t1")
		assert.equal(os.date("%Y-%m-%d %H:%M", t.start), "2026-10-16 22:00")
		assert.equal(os.date("%Y-%m-%d %H:%M", t["end"]), "2026-10-17 01:00")
		assert.equal(t.summary, "Plantão")
	end)

	it("keeps both occurrences of a recurring uid at different starts", function()
		local out = table.concat({
			'[{"uid": "r", "title": "a", "all-day": "False", "start-date": "2026-10-15", "start-time": "09:00", "end-date": "2026-10-15", "end-time": "10:00"}]',
			'[{"uid": "r", "title": "a", "all-day": "False", "start-date": "2026-10-16", "start-time": "09:00", "end-date": "2026-10-16", "end-time": "10:00"}]',
		}, "\n")
		assert.equal(#KhalRead.parse(out, decode), 2)
	end)

	it("skips malformed lines and items without uid or start", function()
		local out = table.concat({
			"not json",
			'{"uid": "obj"}',
			'[{"title": "no uid", "all-day": "False", "start-date": "2026-10-15", "start-time": "09:00"}]',
			'[{"uid": "nostart", "all-day": "False", "start-date": "", "start-time": "09:00"}]',
			'[{"uid": "baddate", "all-day": "True", "start-date": "2026-13-40"}]',
			'[{"uid": "badtime", "all-day": "False", "start-date": "2026-10-15", "start-time": "9h"}]',
			'["x", 3]',
			'[{"uid": "ok", "title": "fine", "all-day": "False", "start-date": "2026-10-15", "start-time": "09:00", "end-date": "2026-10-15", "end-time": "09:30"}]',
		}, "\n")
		local evs = KhalRead.parse(out, decode)
		assert.equal(#evs, 1)
		assert.equal(evs[1].uid, "ok")
	end)

	it("defaults a missing end to the start and missing text fields to empty strings", function()
		local evs = KhalRead.parse('[{"uid": "x", "all-day": "False", "start-date": "2026-10-15", "start-time": "09:00"}]', decode)
		assert.equal(evs[1]["end"], evs[1].start)
		assert.equal(evs[1].summary, "")
		assert.equal(evs[1].calendar, "")
		assert.equal(evs[1].repeats, false)
	end)

	it("skips lines when the decoder throws", function()
		local evs = KhalRead.parse("[1]\n[2]", function()
			error("boom")
		end)
		assert.same(evs, {})
	end)

	it("returns an empty list for empty output", function()
		assert.same(KhalRead.parse("", decode), {})
		assert.same(KhalRead.parse("\n\n  \n", decode), {})
		assert.same(KhalRead.parse(nil, decode), {})
	end)
end)
