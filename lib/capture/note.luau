--!strict
-- Note capture: free text kept verbatim (trimmed) in the Inbox.

local Note = {}

Note.TYPE = "note"

function Note.build(text: any): { [string]: any }
	local raw = if text == nil then "" else tostring(text)
	local body = string.match(raw, "^%s*(.-)%s*$") or ""
	if body == "" then
		return { ok = false, type = Note.TYPE, error = "empty" }
	end
	return { ok = true, type = Note.TYPE, action = "addNote", payload = { text = body } }
end

return Note
