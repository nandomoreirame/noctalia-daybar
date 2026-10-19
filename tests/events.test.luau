local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Dates = modules.load("lib/dates.luau")
local Events = modules.load("lib/events.luau")

local function at(isoDate: string, time: string?): number
	return Dates.toDate(isoDate, time)
end

local function ev(uid: string, start: number, endSec: number, summary: string?): { [string]: any }
	return {
		uid = uid,
		summary = summary or uid,
		start = start,
		["end"] = endSec,
		calendar = "c",
	}
end

describe("events", function()
	local meeting = ev("m", at("2026-10-09", "15:00"), at("2026-10-09", "16:00"))
	local allDay = ev("a", at("2026-10-09"), at("2026-10-10"))
	local trip = ev("t", at("2026-10-08", "10:00"), at("2026-10-11", "10:00"))
	local tomorrow = ev("x", at("2026-10-10", "09:00"), at("2026-10-10", "10:00"))
	local breakfast = ev("b", at("2026-10-09", "08:00"), at("2026-10-09", "09:00"))

	it("detects overlap with a day", function()
		assert.equal(Events.overlapsDay(meeting, "2026-10-09"), true)
		assert.equal(Events.overlapsDay(allDay, "2026-10-10"), false)
		assert.equal(Events.overlapsDay(trip, "2026-10-10"), true)
		assert.equal(Events.overlapsDay(tomorrow, "2026-10-09"), false)
	end)

	it("detects all-day events", function()
		assert.equal(Events.isAllDay(allDay), true)
		assert.equal(Events.isAllDay(meeting), false)
	end)

	it("gives a start time only on the starting day", function()
		assert.equal(Events.timeOn(meeting, "2026-10-09"), "15:00")
		assert.equal(Events.timeOn(trip, "2026-10-09"), nil)
		assert.equal(Events.timeOn(allDay, "2026-10-09"), nil)
	end)

	it("gives an end time only when the event ends on that day", function()
		assert.equal(Events.endTimeOn(meeting, "2026-10-09"), "16:00")
		assert.equal(Events.endTimeOn(trip, "2026-10-09"), nil)
		assert.equal(Events.endTimeOn(trip, "2026-10-11"), "10:00")
		assert.equal(Events.endTimeOn(allDay, "2026-10-09"), nil)
		local late = ev("late", at("2026-10-09", "23:00"), at("2026-10-10", "00:00"))
		assert.equal(Events.endTimeOn(late, "2026-10-09"), nil)
	end)

	it("joins start and end into a range, or keeps whatever exists", function()
		assert.equal(Events.timeRange({ time = "16:00", endTime = "17:00" }), "16:00–17:00")
		assert.equal(Events.timeRange({ time = "16:00", endTime = nil }), "16:00")
		assert.equal(Events.timeRange({ time = "16:00" }), "16:00")
		assert.equal(Events.timeRange({ time = "16:00", endTime = "16:00" }), "16:00")
		assert.equal(Events.timeRange({ time = nil, endTime = "10:00" }), nil)
	end)

	it("carries the end time on the day's list", function()
		local list = Events.eventsOn({ meeting, trip }, "2026-10-09")
		assert.same({
			{ list[1].uid, list[1].time, list[1].endTime },
			{ list[2].uid, list[2].time, list[2].endTime },
		}, {
			{ "t", nil, nil },
			{ "m", "15:00", "16:00" },
		})
	end)

	it("lists a day's events, untimed first then by time", function()
		local list = Events.eventsOn({ meeting, tomorrow, breakfast, allDay, trip }, "2026-10-09")
		assert.same({
			{ list[1].uid, list[1].time },
			{ list[2].uid, list[2].time },
			{ list[3].uid, list[3].time },
			{ list[4].uid, list[4].time },
		}, {
			{ "t", nil },
			{ "a", nil },
			{ "b", "08:00" },
			{ "m", "15:00" },
		})
	end)

	it("orders null times first", function()
		assert.equal(Events.compareTime(nil, "09:00"), -1)
		assert.equal(Events.compareTime("10:00", "09:00"), 1)
	end)

	it("treats an all-day event as untimed and lists it first", function()
		-- civilLocal via Dates.toDate (bare os.time table is UTC in Luau CLI)
		local day = Dates.toDate("2026-10-15")
		local evs = {
			{ uid = "a", summary = "Meeting", start = day + 9 * 3600, ["end"] = day + 10 * 3600 },
			{ uid = "b", summary = "Holiday", start = day, ["end"] = day + 86400 },
		}
		local out = Events.eventsOn(evs, "2026-10-15")
		assert.equal(out[1].uid, "b")
		assert.equal(out[1].time, nil)
		assert.equal(out[2].time, "09:00")
		assert.equal(out[2].endTime, "10:00")
	end)
end)

describe("nextEvent", function()
	local now = at("2026-10-09", "15:00")

	it("picks the earliest timed event of today that has not ended, including one in progress", function()
		local events = {
			ev("later", at("2026-10-10", "09:00"), at("2026-10-10", "10:00"), "Dentista"),
			ev("past", at("2026-10-09", "08:00"), at("2026-10-09", "09:00"), "Café"),
			ev("now", at("2026-10-09", "14:30"), at("2026-10-09", "15:30"), "Reunião"),
			ev("allday", at("2026-10-09"), at("2026-10-10"), "Feriado"),
		}
		assert.same(Events.nextEvent(events, now), {
			uid = "now",
			summary = "Reunião",
			date = "2026-10-09",
			time = "14:30",
		})
	end)

	it("ignores events on other days", function()
		assert.equal(
			Events.nextEvent({
				ev("tomorrow", at("2026-10-10", "09:00"), at("2026-10-10", "10:00"), "Dentista"),
			}, now),
			nil
		)
	end)

	it("returns null when nothing is ahead", function()
		assert.equal(Events.nextEvent({
			ev("past", at("2026-10-09", "08:00"), at("2026-10-09", "09:00")),
		}, now), nil)
		assert.equal(Events.nextEvent({}, now), nil)
		assert.equal(Events.nextEvent(nil, now), nil)
	end)
end)
