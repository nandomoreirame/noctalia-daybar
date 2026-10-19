--!strict
-- Timer capture: "/t 10m chá" starts a countdown (replacing the one set), "/t" alone
-- pauses or resumes the timer that is set, "/t parar" (or "stop") resets it.

local Duration = require("../duration.luau")

local Timer = {}

Timer.TYPE = "timer"
-- "/t" with nothing after it is a command, not an empty capture.
Timer.ALLOW_EMPTY = true

local STOP_WORDS: { [string]: boolean } = { parar = true, stop = true }

function Timer.build(text: any): { [string]: any }
	local raw = if text == nil then "" else tostring(text)
	local body = string.match(raw, "^%s*(.-)%s*$") or ""
	if body == "" then
		return { ok = true, type = Timer.TYPE, action = "timerToggle", payload = {} }
	end
	if STOP_WORDS[string.lower(body)] then
		return { ok = true, type = Timer.TYPE, action = "timerStop", payload = {} }
	end
	local d = Duration.parseDuration(body)
	if not d.ok then
		return { ok = false, type = Timer.TYPE, error = d.error }
	end
	return { ok = true, type = Timer.TYPE, action = "startTimer", payload = { seconds = d.seconds, label = d.label } }
end

-- i18n key of the preview line, given the timer state { set, running, ringing }. For
-- startTimer the overlay shows the clock and label and appends this key when non-empty.
function Timer.previewKey(action: string, timer: { [string]: any }): string
	if action == "timerStop" then
		return "capture.timer.stop"
	end
	if action == "timerToggle" then
		if not timer.set then
			return "capture.error.no-timer"
		end
		if timer.ringing then
			return "capture.timer.dismiss"
		end
		return if timer.running then "capture.timer.pause" else "capture.timer.resume"
	end
	return if timer.set then "capture.timer.replaces" else ""
end

return Timer
