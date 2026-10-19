local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local H = require("./support/service_helpers")

local describe, it = runner.describe, runner.it

local HOME = "/mock/home"
local KHAL_CONFIG = HOME .. "/.config/khal/config"
local ROOT = HOME .. "/.local/share/vdirsyncer/google"
local CONFIG_TEXT = "[calendars]\n[[google]]\npath = ~/.local/share/vdirsyncer/google/*\ntype = discover\n"
local LIST_PREFIX = "khal list"

local function ok(stdout)
	return { exitCode = 0, stdout = stdout or "", stderr = "" }
end

local function line(fields)
	-- One khal JSON day line with a single timed event.
	return '[{"uid":"'
		.. fields.uid
		.. '","title":"'
		.. fields.title
		.. '","calendar":"Eventos","all-day":"False","start-date":"'
		.. fields.date
		.. '","start-time":"'
		.. fields.start
		.. '","end-date":"'
		.. fields.date
		.. '","end-time":"'
		.. fields.finish
		.. '","location":"","url":"","description":"","repeat-symbol":""}]\n'
end

local function calendar(s)
	return H.view(s).calendar
end

-- Boots with khal present and answers printcalendars and the first list.
local function bootReady(opts)
	local o = opts or {}
	local s = H.boot({ commands = { khal = true, vdirsyncer = true }, config = o.config, fs = o.fs })
	H.resolveCmd(s, "khal printcalendars", ok("Eventos\n"))
	H.resolveCmd(s, LIST_PREFIX, ok(o.list or line({ uid = "a1", title = "Daily", date = H.TODAY, start = "10:00", finish = "10:30" })))
	return s
end

local function notifyErrors(s)
	return #mock.calls(s.env, "noctalia.notifyError")
end

describe("service agenda: read", function()
	it("leaves the calendar unavailable without khal and starts no process", function()
		local s = H.boot({})
		assert.equal(calendar(s).available, false)
		assert.same(H.ran(s), {})
	end)

	it("is unavailable when khal prints no calendar", function()
		local s = H.boot({ commands = { khal = true } })
		H.resolveCmd(s, "khal printcalendars", ok(""))
		assert.equal(calendar(s).available, false)
		assert.equal(H.findCmd(s, LIST_PREFIX), nil)
	end)

	it("lists today-14 to today+31 and publishes the parsed events", function()
		local s = H.boot({ commands = { khal = true } })
		H.resolveCmd(s, "khal printcalendars", ok("Eventos\n"))
		local c = calendar(s)
		assert.equal(c.available, true)
		assert.same(c.calendars, { "Eventos" })
		assert.equal(c.loading, true)
		local pending = H.pending(s)
		assert.equal(string.sub(pending[1], -21), "2026-10-01 2026-11-15")
		H.resolveCmd(s, LIST_PREFIX, ok(line({ uid = "a1", title = "Daily", date = H.TODAY, start = "10:00", finish = "10:30" })))
		c = calendar(s)
		assert.equal(c.loading, false)
		assert.equal(c.from, "2026-10-01")
		assert.equal(c.to, "2026-11-15")
		assert.equal(#c.events, 1)
		assert.equal(c.events[1].uid, "a1")
		assert.equal(c.events[1].summary, "Daily")
	end)

	it("drops a late list answer after a newer reload", function()
		local s = H.boot({ commands = { khal = true } })
		H.resolveCmd(s, "khal printcalendars", ok("Eventos\n"))
		H.command(s, "toolbar", "reloadCalendar", {})
		-- The vdirsyncer-less reload goes straight to a second list.
		assert.equal(#H.pending(s), 2)
		mock.resolveAsync(s.env, 2, ok(line({ uid = "new", title = "New", date = H.TODAY, start = "11:00", finish = "12:00" })))
		mock.resolveAsync(s.env, 1, ok(line({ uid = "old", title = "Old", date = H.TODAY, start = "09:00", finish = "10:00" })))
		local c = calendar(s)
		assert.equal(#c.events, 1)
		assert.equal(c.events[1].uid, "new")
	end)

	it("reloads every five minutes", function()
		local s = bootReady()
		assert.equal(H.countRan(s, LIST_PREFIX), 1)
		H.tick(s, 299000)
		assert.equal(H.countRan(s, LIST_PREFIX), 1)
		H.tick(s, 1000)
		assert.equal(H.countRan(s, LIST_PREFIX), 2)
	end)

	it("loadRange outside the window loads that month and merges by uid and start", function()
		local s = bootReady()
		local ack = H.command(s, "toolbar", "loadRange", { from = "2026-12-01", to = "2026-12-31" })
		assert.equal(ack, nil)
		assert.equal(H.pending(s)[1], H.pending(s)[1])
		local i = H.findCmd(s, LIST_PREFIX)
		assert.equal(string.sub(H.pending(s)[i :: number], -21), "2026-12-01 2026-12-31")
		H.resolveCmd(s, LIST_PREFIX, ok(line({ uid = "x9", title = "Natal", date = "2026-12-24", start = "20:00", finish = "23:00" })
			.. line({ uid = "a1", title = "Daily", date = H.TODAY, start = "10:00", finish = "10:30" })))
		local c = calendar(s)
		assert.equal(#c.events, 2)
		assert.equal(H.ack(s, "toolbar").ok, true)
	end)

	it("loadRange inside the window starts nothing", function()
		local s = bootReady()
		assert.equal(H.command(s, "toolbar", "loadRange", { from = "2026-10-01", to = "2026-10-31" }).ok, true)
		assert.equal(H.findCmd(s, LIST_PREFIX), nil)
	end)

	it("loadRange rejects bad dates", function()
		local s = bootReady()
		assert.equal(H.command(s, "toolbar", "loadRange", { from = "x", to = "2026-10-31" }).error, "invalid-date")
	end)
end)

describe("service agenda: write", function()
	it("commits an event with the default calendar, then syncs and reloads", function()
		local s = bootReady({ config = { default_calendar = "Trabalho" } })
		local ack = H.command(s, "capture", "commit", { text = "/e reunião amanhã 15h" })
		assert.equal(ack, nil)
		assert.equal(calendar(s).writing, true)
		local i = H.findCmd(s, "khal new") :: number
		assert.equal(H.pending(s)[i], "khal new -a Trabalho -- 2026-10-16 15:00 2026-10-16 16:00 reunião")
		H.resolveCmd(s, "khal new", ok())
		assert.equal(calendar(s).writing, false)
		assert.equal(H.ack(s, "capture").ok, true)
		H.resolveCmd(s, "vdirsyncer sync", ok())
		assert.equal(H.countRan(s, LIST_PREFIX), 2)
	end)

	it("an event commit without the calendar acks calendar-not-configured", function()
		local s = H.boot({})
		assert.equal(H.command(s, "capture", "commit", { text = "/e reunião amanhã 15h" }).error, "calendar-not-configured")
	end)

	it("a failed khal new acks khal-failed and does not sync", function()
		local s = bootReady()
		H.command(s, "capture", "commit", { text = "/e reunião amanhã 15h" })
		H.resolveCmd(s, "khal new", { exitCode = 1, stdout = "", stderr = "boom" })
		assert.equal(H.ack(s, "capture").error, "khal-failed")
		assert.equal(H.findCmd(s, "vdirsyncer sync"), nil)
	end)

	it("a failed sync notifies once, flags syncFailed and retries on the next tick", function()
		local s = bootReady()
		H.command(s, "toolbar", "reloadCalendar", {})
		H.resolveCmd(s, "vdirsyncer sync", { exitCode = 1, stdout = "", stderr = "" })
		assert.equal(notifyErrors(s), 1)
		assert.equal(calendar(s).syncFailed, true)
		H.resolveCmd(s, LIST_PREFIX, ok(""))
		H.tick(s, 300000)
		assert.equal(H.countRan(s, "vdirsyncer sync"), 2)
		H.resolveCmd(s, "vdirsyncer sync", ok())
		assert.equal(calendar(s).syncFailed, false)
		assert.equal(notifyErrors(s), 1)
	end)

	it("a reminder writes a khal event with an alarm and stores a local reminder", function()
		local s = bootReady()
		H.command(s, "capture", "commit", { text = "/l tomar remédio 14h" })
		local i = H.findCmd(s, "khal new") :: number
		assert.equal(H.pending(s)[i], "khal new --alarms 0m -- 2026-10-15 14:00 2026-10-15 14:15 tomar remédio")
		H.resolveCmd(s, "khal new", ok())
		local reminders = H.view(s).data.reminders
		assert.equal(#reminders, 1)
		assert.equal(reminders[1].title, "tomar remédio")
		assert.equal(reminders[1].time, "14:00")
	end)

	it("a reminder without the calendar is stored locally only", function()
		local s = H.boot({})
		assert.equal(H.command(s, "capture", "commit", { text = "/l tomar remédio 14h" }).ok, true)
		assert.equal(#H.view(s).data.reminders, 1)
		assert.same(H.ran(s), {})
	end)

	it("commits a task and a note through the capture registry", function()
		local s = H.boot({})
		assert.equal(H.command(s, "capture", "commit", { text = "comprar pão" }).ok, true)
		assert.equal(H.view(s).data.tasks[1].title, "comprar pão")
		assert.equal(H.command(s, "capture", "commit", { text = "/n ideia solta" }).ok, true)
		assert.equal(#H.view(s).data.notes, 1)
	end)

	it("a calculation copies the result", function()
		local s = H.boot({})
		local ack = H.command(s, "capture", "commit", { text = "=2+3" })
		assert.equal(ack.ok, true)
		assert.equal(mock.calls(s.env, "noctalia.copyToClipboard")[1][1], "5")
	end)

	it("an unparseable capture acks its error", function()
		local s = H.boot({})
		assert.equal(H.command(s, "capture", "commit", { text = "   " }).ok, false)
	end)
end)

describe("service agenda: delete and details", function()
	local ICS = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:a1\nSUMMARY:Daily\nLOCATION:Sala 3\nEND:VEVENT\nEND:VCALENDAR\n"
	local FILE = ROOT .. "/primary/a1.ics"

	local function readyWithFiles()
		local fs = { [KHAL_CONFIG] = CONFIG_TEXT, [FILE] = ICS }
		return bootReady({ fs = fs })
	end

	local function locate(s)
		H.command(s, "toolbar", "locateEvent", { uid = "a1", calendar = "Eventos" })
		H.resolveCmd(s, "grep -rH --include=displayname", ok(ROOT .. "/primary/displayname:Eventos\n"))
		H.resolveCmd(s, "grep -rlF --include=*.ics -- UID:a1", ok(FILE .. "\n"))
	end

	it("locates the file through the khal config, the collections and grep", function()
		local s = readyWithFiles()
		H.command(s, "toolbar", "locateEvent", { uid = "a1", calendar = "Eventos" })
		assert.equal(H.view(s).deleting.a1.phase, "locating")
		local reads = mock.calls(s.env, "noctalia.readFile")
		local readConfig = false
		for _, call in reads do
			if call[1] == KHAL_CONFIG then
				readConfig = true
			end
		end
		assert.equal(readConfig, true)
		H.resolveCmd(s, "grep -rH --include=displayname", ok(ROOT .. "/primary/displayname:Eventos\n"))
		H.resolveCmd(s, "grep -rlF --include=*.ics -- UID:a1 " .. ROOT, ok(FILE .. "\n"))
		local d = H.view(s).deleting.a1
		assert.equal(d.phase, "ready")
		assert.equal(d.recurring, false)
		assert.equal(H.ack(s, "toolbar").ok, true)
	end)

	it("deleteEvent removes the file, hides the event, clears its checks and syncs", function()
		local s = readyWithFiles()
		H.command(s, "toolbar", "toggleEvent", { uid = "a1", date = H.TODAY })
		locate(s)
		assert.equal(H.command(s, "toolbar", "deleteEvent", { uid = "a1", calendar = "Eventos" }).ok, true)
		local removed = mock.calls(s.env, "noctalia.removeFile")
		assert.equal(removed[1][1], FILE)
		assert.equal(#calendar(s).events, 0)
		assert.same(H.view(s).data.eventChecks, {})
		assert.equal(H.view(s).deleting.a1, nil)
		assert.equal(H.findCmd(s, "vdirsyncer sync") ~= nil, true)
	end)

	it("deleteEvent without a located file removes nothing", function()
		local s = readyWithFiles()
		assert.equal(H.command(s, "toolbar", "deleteEvent", { uid = "a1", calendar = "Eventos" }).error, "not-located")
		assert.equal(#mock.calls(s.env, "noctalia.removeFile"), 0)
	end)

	it("not-found and ambiguous outcomes ack their error and remove nothing", function()
		local s = readyWithFiles()
		H.command(s, "toolbar", "locateEvent", { uid = "a1", calendar = "Eventos" })
		H.resolveCmd(s, "grep -rH --include=displayname", ok(ROOT .. "/primary/displayname:Eventos\n"))
		H.resolveCmd(s, "grep -rlF", ok(""))
		assert.equal(H.ack(s, "toolbar").error, "not-found")
		assert.equal(H.view(s).deleting.a1.phase, "error")

		H.command(s, "toolbar", "locateEvent", { uid = "a1", calendar = "Eventos" })
		H.resolveCmd(s, "grep -rH --include=displayname", ok(ROOT .. "/primary/displayname:Eventos\n"))
		H.resolveCmd(s, "grep -rlF", ok(FILE .. "\n" .. ROOT .. "/primary/copy.ics\n"))
		assert.equal(H.ack(s, "toolbar").error, "ambiguous")
		assert.equal(#mock.calls(s.env, "noctalia.removeFile"), 0)
	end)

	it("cancelDelete clears the state", function()
		local s = readyWithFiles()
		locate(s)
		assert.equal(H.command(s, "toolbar", "cancelDelete", { uid = "a1" }).ok, true)
		assert.equal(H.view(s).deleting.a1, nil)
	end)

	it("loadDetails reads the .ics once and caches the details", function()
		local s = readyWithFiles()
		H.command(s, "toolbar", "loadDetails", { uid = "a1", calendar = "Eventos" })
		H.resolveCmd(s, "grep -rH --include=displayname", ok(ROOT .. "/primary/displayname:Eventos\n"))
		H.resolveCmd(s, "grep -rlF", ok(FILE .. "\n"))
		assert.equal(H.view(s).details.a1.location, "Sala 3")
		local greps = H.countRan(s, "grep -rlF")
		assert.equal(H.command(s, "toolbar", "loadDetails", { uid = "a1", calendar = "Eventos" }).ok, true)
		assert.equal(H.countRan(s, "grep -rlF"), greps)
	end)

	it("rejects ids with path or option characters", function()
		local s = readyWithFiles()
		assert.equal(H.command(s, "toolbar", "locateEvent", { uid = "", calendar = "Eventos" }).error, "invalid-id")
		assert.equal(H.command(s, "toolbar", "locateEvent", { uid = "a1", calendar = 3 }).error, "invalid-calendar")
	end)
end)
