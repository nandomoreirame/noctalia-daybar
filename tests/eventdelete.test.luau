local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local EventDelete = modules.load("lib/eventdelete.luau")

-- Fixture home is /opt/u: absolute user-home paths are rejected by the commit hook.
local HOME = "/opt/u"

describe("calendarRoots", function()
	it("reads every path = line, expanding ~ and stripping /* and trailing slashes", function()
		local config =
			'[calendars]\n[[google]]\npath = ~/.local/share/calendars/google/*\ntype = discover\n[[work]]\n  path = "/data/cal/work/"\n[locale]\ntimeformat = %H:%M\n'
		assert.same(EventDelete.calendarRoots(config, HOME), {
			"/opt/u/.local/share/calendars/google",
			"/data/cal/work",
		})
	end)

	it("expands $HOME/ and ${HOME}/ like ~/, and strips trailing slashes before /*", function()
		local config =
			"path = $HOME/.local/share/calendars/a/*\npath = ${HOME}/.local/share/calendars/b/\npath = /data/cal/c/*/\n"
		assert.same(EventDelete.calendarRoots(config, HOME), {
			"/opt/u/.local/share/calendars/a",
			"/opt/u/.local/share/calendars/b",
			"/data/cal/c",
		})
	end)

	it("drops duplicates and relative paths; empty config gives no roots", function()
		assert.same(EventDelete.calendarRoots("path = rel/dir\npath = /a\npath = /a/", HOME), { "/a" })
		assert.same(EventDelete.calendarRoots("", HOME), {})
		assert.same(EventDelete.calendarRoots(nil, HOME), {})
	end)
end)

describe("calendarSections", function()
	it("maps [[name]] sections with type and path", function()
		local config = [=[
[calendars]
[[google]]
path = ~/.local/share/calendars/google/*
type = discover
[[work]]
path = /data/cal/work/
type = calendar
[[birthdays]]
path = /data/cal/bd/
type = calendar
]=]
		assert.same(EventDelete.calendarSections(config, HOME), {
			{ name = "google", path = "/opt/u/.local/share/calendars/google", type = "discover" },
			{ name = "work", path = "/data/cal/work", type = "calendar" },
			{ name = "birthdays", path = "/data/cal/bd", type = "calendar" },
		})
	end)
end)

describe("collections", function()
	it("lists displayname files recursively under the roots", function()
		assert.same(EventDelete.collectionsArgs({ "/r1", "/r2" }), {
			"grep",
			"-rH",
			"--include=displayname",
			"",
			"--",
			"/r1",
			"/r2",
		})
	end)

	it("parses grep -H output into dir, id and name", function()
		local out = "/r/abc@virtual/displayname:Feriados no Brasil\n/r/me@gmail.com/displayname:Eventos\n\n"
		assert.same(EventDelete.parseCollections(out), {
			{ dir = "/r/abc@virtual", id = "abc@virtual", name = "Feriados no Brasil" },
			{ dir = "/r/me@gmail.com", id = "me@gmail.com", name = "Eventos" },
		})
	end)

	it("names a type=calendar collection by its section name", function()
		local out = "/data/cal/work/displayname:Whatever\n"
		local sections = {
			{ name = "work", path = "/data/cal/work", type = "calendar" },
			{ name = "google", path = "/r/g", type = "discover" },
		}
		assert.same(EventDelete.parseCollections(out, sections), {
			{ dir = "/data/cal/work", id = "work", name = "work" },
		})
		assert.same(EventDelete.parseCollections("", sections), {
			{ dir = "/data/cal/work", id = "work", name = "work" },
		})
	end)

	it("treats virtual, holiday, birthday, import and group calendars as read-only", function()
		assert.equal(EventDelete.isReadOnlyCollection("e1q2@virtual"), true)
		assert.equal(EventDelete.isReadOnlyCollection("pt.brazilian#holiday@group.v.calendar.google.com"), true)
		assert.equal(EventDelete.isReadOnlyCollection("#contacts@group.v.calendar.google.com"), true)
		assert.equal(EventDelete.isReadOnlyCollection("abc#contacts@group.v.calendar.google.com"), true)
		assert.equal(EventDelete.isReadOnlyCollection("xyz@import.calendar.google.com"), true)
		assert.equal(EventDelete.isReadOnlyCollection("abc@group.v.calendar.google.com"), true)
		assert.equal(EventDelete.isReadOnlyCollection("me@gmail.com"), false)
	end)

	it("allows deleting only in calendars backed by a writable collection", function()
		local cols = EventDelete.parseCollections("/r/a@virtual/displayname:Feriados\n/r/me@gmail.com/displayname:Eventos\n")
		assert.equal(EventDelete.isWritableCalendar(cols, "Eventos"), true)
		assert.equal(EventDelete.isWritableCalendar(cols, "Feriados"), false)
		assert.equal(EventDelete.isWritableCalendar(cols, "Unknown"), false)
		assert.equal(EventDelete.isWritableCalendar({}, "Eventos"), false)
	end)

	it("flags a calendar read-only only when every collection with its name is read-only", function()
		local cols = EventDelete.parseCollections("/r/a@virtual/displayname:Feriados\n/r/me@gmail.com/displayname:Eventos\n")
		assert.equal(EventDelete.isReadOnlyCalendar(cols, "Feriados"), true)
		assert.equal(EventDelete.isReadOnlyCalendar(cols, "Eventos"), false)
		assert.equal(EventDelete.isReadOnlyCalendar(cols, "Unknown"), false)
		assert.equal(EventDelete.isReadOnlyCalendar({}, "Feriados"), false)
		assert.equal(EventDelete.isReadOnlyCalendar(nil, "Feriados"), false)
	end)
end)

describe("UID lookup", function()
	it("escapes regex metacharacters", function()
		assert.equal(EventDelete.escapeRegex("a.b+c(1)[x]"), "a\\.b\\+c\\(1\\)\\[x\\]")
	end)

	it("greps the exact UID line, fixed-string, .ics only, roots after --", function()
		assert.same(EventDelete.findArgs("7799ut.p@google.com", { "/r" }), {
			"grep",
			"-rlF",
			"--include=*.ics",
			"--",
			"UID:7799ut.p@google.com",
			"/r",
		})
	end)

	it("keeps a hostile UID inside one argument", function()
		local args = EventDelete.findArgs("x$(rm -rf ~)", { "/r" })
		assert.equal(args[5], "UID:x$(rm -rf ~)")
		assert.equal(#args, 6)
	end)

	it("parses grep -l output into .ics paths", function()
		assert.same(EventDelete.parsePaths("/r/a/1.ics\n\n/r/b/2.ics\nnoise\n"), {
			"/r/a/1.ics",
			"/r/b/2.ics",
		})
	end)
end)

describe("pickReadable", function()
	local cols = {
		{ dir = "/r/me", id = "me@x.com", name = "Eventos" },
		{ dir = "/r/hol", id = "h@virtual", name = "Feriados" },
	}

	it("reads read-only calendars too and names the calendar's own address", function()
		assert.same(EventDelete.pickReadable({ "/r/me/1.ics" }, cols, "Eventos"), {
			ok = true,
			path = "/r/me/1.ics",
			self = "me@x.com",
		})
		assert.same(EventDelete.pickReadable({ "/r/hol/2.ics" }, cols, "Feriados"), {
			ok = true,
			path = "/r/hol/2.ics",
			self = "h@virtual",
		})
	end)

	it("keeps the not-found and ambiguous rules of pickFile", function()
		assert.same(EventDelete.pickReadable({}, cols, "Eventos"), { ok = false, error = "not-found" })
		assert.same(EventDelete.pickReadable({ "/r/other/1.ics" }, cols, "Eventos"), {
			ok = false,
			error = "ambiguous",
		})
	end)
end)

describe("pickFile", function()
	local cols = {
		{ dir = "/r/me", id = "me", name = "Eventos" },
		{ dir = "/r/fam", id = "fam", name = "Família" },
	}

	it("returns not-found for no match", function()
		assert.same(EventDelete.pickFile({}, cols, "Eventos"), { ok = false, error = "not-found" })
	end)

	it("accepts a single match only when it sits in the event's writable calendar", function()
		assert.same(EventDelete.pickFile({ "/r/me/1.ics" }, cols, "Eventos"), {
			ok = true,
			path = "/r/me/1.ics",
		})
		assert.same(EventDelete.pickFile({ "/r/other/1.ics" }, cols, "Eventos"), {
			ok = false,
			error = "ambiguous",
		})
	end)

	it("refuses a single match in a read-only collection", function()
		local ro = { { dir = "/r/hol", id = "h@virtual", name = "Feriados" } }
		assert.same(EventDelete.pickFile({ "/r/hol/1.ics" }, ro, "Feriados"), {
			ok = false,
			error = "read-only",
		})
	end)

	it("picks the copy in the event's calendar when the UID is in several", function()
		assert.same(EventDelete.pickFile({ "/r/me/1.ics", "/r/fam/9.ics" }, cols, "Família"), {
			ok = true,
			path = "/r/fam/9.ics",
		})
	end)

	it("refuses when the calendar does not single one out", function()
		assert.same(EventDelete.pickFile({ "/r/me/1.ics", "/r/fam/9.ics" }, cols, "Outra"), {
			ok = false,
			error = "ambiguous",
		})
		assert.same(EventDelete.pickFile({ "/r/me/1.ics", "/r/me/2.ics" }, cols, "Eventos"), {
			ok = false,
			error = "ambiguous",
		})
	end)
end)

describe("recurrence", function()
	it("detects RRULE and RECURRENCE-ID, not the words inside other properties", function()
		assert.equal(EventDelete.isRecurring("BEGIN:VEVENT\nRRULE:FREQ=WEEKLY\nEND:VEVENT"), true)
		assert.equal(
			EventDelete.isRecurring("BEGIN:VEVENT\r\nRECURRENCE-ID;TZID=X:20261010T100000\r\nEND:VEVENT"),
			true
		)
		assert.equal(EventDelete.isRecurring("BEGIN:VEVENT\nDESCRIPTION:no RRULE: here\nEND:VEVENT"), false)
		assert.equal(EventDelete.isRecurring(""), false)
	end)

	it("ignores RRULE inside a VTIMEZONE block", function()
		local ics =
			"BEGIN:VCALENDAR\nBEGIN:VTIMEZONE\nTZID:X\nBEGIN:STANDARD\nRRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU\nEND:STANDARD\nEND:VTIMEZONE\nBEGIN:VEVENT\nUID:a\nSUMMARY:Once\nEND:VEVENT\nEND:VCALENDAR"
		assert.equal(EventDelete.isRecurring(ics), false)
	end)
end)

describe("paths and commands", function()
	local roots = { "/opt/u/.local/share/calendars/google" }

	it("deletes only .ics files strictly inside a root, without dot segments", function()
		assert.equal(
			EventDelete.isDeletablePath("/opt/u/.local/share/calendars/google/me/1.ics", roots),
			true
		)
		assert.equal(
			EventDelete.isDeletablePath("/opt/u/.local/share/calendars/google/me/../../../x.ics", roots),
			false
		)
		assert.equal(
			EventDelete.isDeletablePath("/opt/u/.local/share/calendars/google/me/1.txt", roots),
			false
		)
		assert.equal(
			EventDelete.isDeletablePath("/opt/u/.local/share/calendars/googleX/me/1.ics", roots),
			false
		)
		assert.equal(EventDelete.isDeletablePath("/etc/passwd.ics", roots), false)
	end)

	it("rejects a path that escapes the calendar root through ..", function()
		assert.equal(EventDelete.isDeletablePath("/c/cal/../../etc/x.ics", { "/c/cal" }), false)
	end)
end)

describe("data cleanup", function()
	it("removes every Today check of the UID", function()
		local data = {
			eventChecks = {
				["u1|2026-10-09"] = true,
				["u1|2026-10-10"] = true,
				["u2|2026-10-09"] = true,
			},
		}
		assert.same(EventDelete.removeEventChecks(data, "u1").eventChecks, {
			["u2|2026-10-09"] = true,
		})
		assert.equal(data.eventChecks["u1|2026-10-09"], true)
	end)

	it("hides only events whose uid AND calendar match", function()
		local events = {
			{ uid = "a", calendar = "Work" },
			{ uid = "a", calendar = "Home" },
			{ uid = "b", calendar = "Work" },
		}
		assert.same(EventDelete.hideEvents(events, { EventDelete.eventKey("a", "Work") }), {
			{ uid = "a", calendar = "Home" },
			{ uid = "b", calendar = "Work" },
		})
		assert.equal(EventDelete.hideEvents(events, {}), events)
		assert.same(EventDelete.hideEvents(nil, { EventDelete.eventKey("a", "Work") }), {})
	end)
end)
