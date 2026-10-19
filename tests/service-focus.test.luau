local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local H = require("./support/service_helpers")

local describe, it = runner.describe, runner.it

local MIN = 60 * 1000

local function pomodoro(s)
	return H.view(s).pomodoro
end

local function timer(s)
	return H.view(s).timer
end

local function notifies(s)
	return mock.calls(s.env, "noctalia.notify")
end

local function plays(s)
	return #mock.calls(s.env, "noctalia.sound.play")
end

-- Boots and answers the alarm load.
local function boot(opts)
	local s = H.boot(opts)
	mock.resolveSound(s.env, 1, (opts or {}).soundOk ~= false)
	return s
end

describe("service focus: pomodoro", function()
	it("loads the alarm sound at start", function()
		local s = H.boot({})
		local load = mock.calls(s.env, "noctalia.sound.load")[1]
		assert.equal(load[1], "alarm")
		assert.equal(load[2], "alarm.mp3")
	end)

	it("toggle starts focus with a deadline and runs the focus-mode command", function()
		local s = boot({ config = { focus_mode_command = "focusctl" } })
		assert.equal(H.command(s, "toolbar", "pomodoro", { action = "toggle" }).ok, true)
		local p = pomodoro(s)
		assert.equal(p.running, true)
		assert.equal(p.started, true)
		assert.equal(p.mode, 0)
		assert.equal(p.endsAtMs, H.NOW + 25 * MIN)
		assert.equal(H.ran(s)[1], "focusctl on")
		H.command(s, "toolbar", "pomodoro", { action = "toggle" })
		assert.equal(pomodoro(s).running, false)
		assert.equal(pomodoro(s).remaining, 25 * 60)
		assert.equal(H.ran(s)[2], "focusctl off")
	end)

	it("finishing focus plays the alarm, notifies, logs the session and credits the linked task", function()
		local s = boot({})
		local id = H.command(s, "toolbar", "addTask", { title = "write" }).result.id
		H.command(s, "toolbar", "linkTask", { id = id })
		assert.equal(pomodoro(s).running, true)
		assert.equal(pomodoro(s).linkedTaskId, id)
		H.tick(s, 25 * MIN)
		local p = pomodoro(s)
		assert.equal(p.running, false)
		assert.equal(p.mode, 1)
		assert.equal(p.remaining, 5 * 60)
		assert.equal(plays(s), 1)
		assert.equal(H.view(s).alarmSource, "pomodoro")
		assert.equal(#notifies(s), 1)
		assert.equal(H.view(s).data.focusLog[H.TODAY], 1)
		assert.equal(H.view(s).data.tasks[1].pomodoros, 1)
		assert.equal(p.linkedTaskId, nil)
		H.tick(s, 5000)
		assert.equal(H.view(s).alarmSource, "")
	end)

	it("auto starts the break when auto_start_breaks is on", function()
		local s = boot({ config = { auto_start_breaks = true } })
		H.command(s, "toolbar", "pomodoro", { action = "start" })
		H.tick(s, 25 * MIN)
		local p = pomodoro(s)
		assert.equal(p.mode, 1)
		assert.equal(p.running, true)
		assert.equal(p.endsAtMs, H.NOW + 30 * MIN)
	end)

	it("does not play when play_sound is off, and still notifies", function()
		local s = boot({ config = { play_sound = false } })
		H.command(s, "toolbar", "pomodoro", { action = "start" })
		H.tick(s, 25 * MIN)
		assert.equal(plays(s), 0)
		assert.equal(#notifies(s), 1)
	end)

	it("logs a failed sound load once and still notifies", function()
		local s = boot({ soundOk = false })
		H.command(s, "toolbar", "pomodoro", { action = "start" })
		H.tick(s, 25 * MIN)
		assert.equal(plays(s), 0)
		assert.equal(#notifies(s), 1)
		local logged = 0
		for _, call in mock.calls(s.env, "noctalia.log") do
			if string.find(tostring(call[1]), "alarm", 1, true) then
				logged += 1
			end
		end
		assert.equal(logged, 1)
	end)

	it("skip, reset and setMode move the phase", function()
		local s = boot({})
		H.command(s, "toolbar", "pomodoro", { action = "skip" })
		assert.equal(pomodoro(s).mode, 1)
		H.command(s, "toolbar", "pomodoro", { action = "setMode", mode = 2 })
		assert.equal(pomodoro(s).mode, 2)
		assert.equal(pomodoro(s).remaining, 15 * 60)
		H.command(s, "toolbar", "pomodoro", { action = "start" })
		H.tick(s, MIN)
		H.command(s, "toolbar", "pomodoro", { action = "reset" })
		assert.equal(pomodoro(s).running, false)
		assert.equal(pomodoro(s).remaining, 15 * 60)
		assert.equal(H.command(s, "toolbar", "pomodoro", { action = "setMode", mode = 7 }).error, "invalid-mode")
		assert.equal(H.command(s, "toolbar", "pomodoro", { action = "dance" }).error, "invalid-action")
	end)

	it("a new work_duration applies to an untouched phase only", function()
		local s = boot({})
		mock.setConfig(s.env, "work_duration", 50)
		s.call("onConfigChanged")
		assert.equal(pomodoro(s).remaining, 50 * 60)
		H.command(s, "toolbar", "pomodoro", { action = "start" })
		H.tick(s, MIN)
		H.command(s, "toolbar", "pomodoro", { action = "pause" })
		mock.setConfig(s.env, "work_duration", 10)
		s.call("onConfigChanged")
		assert.equal(pomodoro(s).remaining, 49 * 60)
	end)
end)

describe("service focus: timer", function()
	it("set then toggle runs the timer and records it as recent", function()
		local s = boot({})
		assert.equal(H.command(s, "toolbar", "timer", { action = "set", text = "10m chá" }).ok, true)
		local t = timer(s)
		assert.equal(t.set, true)
		assert.equal(t.total, 600)
		assert.equal(t.label, "chá")
		assert.equal(H.view(s).focusPanel, "timer")
		H.command(s, "toolbar", "timer", { action = "toggle" })
		assert.equal(timer(s).running, true)
		assert.equal(timer(s).endsAtMs, H.NOW + 10 * MIN)
		assert.same(H.view(s).data.recentTimers[1], { seconds = 600, label = "chá" })
	end)

	it("set with start = true starts the timer at once", function()
		local s = boot({})
		assert.equal(H.command(s, "toolbar", "timer", { action = "set", text = "10m chá", start = true }).ok, true)
		assert.equal(timer(s).running, true)
		assert.equal(timer(s).endsAtMs, H.NOW + 10 * MIN)
	end)

	it("starting the pomodoro pauses the timer, keeping its time, and vice versa", function()
		local s = boot({})
		H.command(s, "toolbar", "timer", { action = "set", text = "10m" })
		H.command(s, "toolbar", "timer", { action = "toggle" })
		H.tick(s, 2 * MIN)
		H.command(s, "toolbar", "pomodoro", { action = "start" })
		assert.equal(timer(s).running, false)
		assert.equal(timer(s).remaining, 8 * 60)
		assert.equal(#notifies(s), 1)
		H.command(s, "toolbar", "timer", { action = "toggle" })
		assert.equal(pomodoro(s).running, false)
		assert.equal(#notifies(s), 2)
	end)

	it("the end rings, notifies with the label and waits at full duration", function()
		local s = boot({})
		H.command(s, "toolbar", "timer", { action = "preset", seconds = 300 })
		assert.equal(timer(s).running, true)
		H.tick(s, 5 * MIN)
		local t = timer(s)
		assert.equal(t.running, false)
		assert.equal(t.remaining, 300)
		assert.equal(H.view(s).alarmSource, "timer")
		assert.equal(plays(s), 1)
		local n = notifies(s)
		assert.equal(n[#n][2], "timer.toast-done")
	end)

	it("rejects a bad duration and a toggle without a timer", function()
		local s = boot({})
		assert.equal(H.command(s, "toolbar", "timer", { action = "set", text = "soon" }).ok, false)
		assert.equal(H.command(s, "toolbar", "timer", { action = "toggle" }).error, "no-timer")
		assert.equal(H.command(s, "toolbar", "timer", { action = "preset", seconds = -5 }).error, "invalid-duration")
	end)

	it("setFocusPanel switches the Focus view", function()
		local s = boot({})
		assert.equal(H.command(s, "toolbar", "setFocusPanel", { panel = "timer" }).ok, true)
		assert.equal(H.view(s).focusPanel, "timer")
		assert.equal(H.command(s, "toolbar", "setFocusPanel", { panel = "x" }).error, "invalid-panel")
	end)
end)

describe("service focus: capture commands", function()
	it("maps /p, /p curta, /p longa, /p foco and /p parar", function()
		local s = boot({})
		H.command(s, "capture", "commit", { text = "/p" })
		assert.equal(pomodoro(s).running, true)
		H.command(s, "capture", "commit", { text = "/p" })
		assert.equal(pomodoro(s).running, false)
		H.command(s, "capture", "commit", { text = "/p curta" })
		assert.equal(pomodoro(s).mode, 1)
		assert.equal(pomodoro(s).running, true)
		H.command(s, "capture", "commit", { text = "/p longa" })
		assert.equal(pomodoro(s).mode, 2)
		H.command(s, "capture", "commit", { text = "/p foco" })
		assert.equal(pomodoro(s).mode, 0)
		H.command(s, "capture", "commit", { text = "/p parar" })
		assert.equal(pomodoro(s).running, false)
		assert.equal(pomodoro(s).started, false)
	end)

	it("maps /t <duration>, /t and /t parar", function()
		local s = boot({})
		assert.equal(H.command(s, "capture", "commit", { text = "/t" }).error, "no-timer")
		H.command(s, "capture", "commit", { text = "/t 10m chá" })
		assert.equal(timer(s).running, true)
		H.command(s, "capture", "commit", { text = "/t" })
		assert.equal(timer(s).running, false)
		H.command(s, "capture", "commit", { text = "/t" })
		H.tick(s, MIN)
		H.command(s, "capture", "commit", { text = "/t parar" })
		assert.equal(timer(s).running, false)
		assert.equal(timer(s).remaining, 600)
	end)
end)

describe("service focus: reminders", function()
	it("fires a due reminder once and expires an old one silently", function()
		local s = boot({})
		local data = {
			version = 2,
			reminders = {
				{ id = "r1", title = "call", date = H.TODAY, time = "09:00", fired = false },
				{ id = "r2", title = "old", date = H.TODAY, time = "08:00", fired = false },
				{ id = "r3", title = "later", date = H.TODAY, time = "18:00", fired = false },
			},
		}
		s = H.boot({ fs = { [H.DATA .. "/data.json"] = s.env.noctalia.json.encode(data) } })
		mock.resolveSound(s.env, 1, true)
		H.tick(s, 30000)
		local n = notifies(s)
		assert.equal(#n, 1)
		assert.equal(n[1][2], "call")
		local byId = {}
		for _, r in H.view(s).data.reminders do
			byId[r.id] = r.fired
		end
		assert.same(byId, { r1 = true, r2 = true, r3 = false })
		H.tick(s, 30000)
		assert.equal(#notifies(s), 1)
	end)
end)
