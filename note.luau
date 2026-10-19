-- Daybar note panel (REQ-030, REQ-031): Markdown preview, an editor that saves
-- 600 ms after the last change, copy and delete. The toolbar sets `note.request`
-- (a note id, or "new") before opening the panel.

local Client = require("./views/client.luau")
local MarkdownView = require("./views/markdown.luau")
local MdView = require("./lib/mdview.luau")
local Notes = require("./lib/notes.luau")
local Format = require("./lib/format.luau")

local SAVE_DELAY_MS = 600

local client = Client.new(noctalia.state, noctalia.nowMs(), "note")

local noteId = "" -- "" until the service creates the note
local createdHere = false
local editing = false
local text = ""
local dirtyAt: number? = nil
local creating = false -- a create is in flight; later saves wait for its id
local confirmDelete = false
local closed = true
local editorRev = 0

local function tr(key: string, subst: any?): string
	return noctalia.tr(key, subst)
end

local function view(): { [string]: any }?
	local v = noctalia.state.get("view")
	return if typeof(v) == "table" then v else nil
end

local function currentNote(): { [string]: any }?
	local v = view()
	if v == nil or noteId == "" then
		return nil
	end
	for _, n in ipairs((v.data or {}).notes or {}) do
		if n.id == noteId then
			return n
		end
	end
	return nil
end

local function editedLine(): string
	local note = currentNote()
	if note == nil then
		return ""
	end
	local r = Format.relativeTime(note.updatedAt, math.floor(noctalia.nowMs() / 1000))
	local k = Format.relativeKey(r)
	local when = if k.key == "" then k.date else tr(k.key, { n = k.n })
	return tr("notes.edited", { time = when })
end

local render: () -> ()

local function save()
	dirtyAt = nil
	if noteId == "" then
		if Notes.isBlank(text) or creating then
			if creating then
				dirtyAt = noctalia.nowMs()
			end
			return
		end
		creating = true
		client.send("saveNote", { text = text }, function(ack: any)
			creating = false
			local id = if ack.ok and typeof(ack.result) == "table" then ack.result.id else nil
			if typeof(id) == "string" and id ~= "" then
				noteId = id
				createdHere = true
			end
		end)
		return
	end
	client.send("saveNote", { id = noteId, text = text })
end

local function toggleEdit()
	if editing then
		save()
		editing = false
	else
		editing = true
		editorRev += 1
	end
	render()
end

local function close()
	panel.close()
end

local function deleteNow()
	confirmDelete = false
	dirtyAt = nil
	if noteId ~= "" then
		client.send("deleteNote", { id = noteId })
	end
	closed = true
	close()
end

render = function()
	local title = Notes.titleOf(text)
	if title == "" then
		title = tr("notes.untitled")
	end
	local header = ui.row({ gap = 6, align = "center" }, {
		ui.column({ gap = 2, flexGrow = 1 }, {
			ui.label({ text = title, fontSize = 16, fontWeight = "bold", maxLines = 1 }),
			ui.label({ text = editedLine(), fontSize = 11, color = "on_surface_variant" }),
		}),
		ui.button({
			glyph = "pencil",
			variant = "ghost",
			selected = editing,
			tooltip = tr(if editing then "notes.preview" else "notes.edit"),
			onClick = toggleEdit,
		}),
		ui.button({
			glyph = "copy",
			variant = "ghost",
			tooltip = tr("notes.copy"),
			onClick = function()
				client.send("copyText", { text = text })
			end,
		}),
		ui.button({
			glyph = "trash",
			variant = "ghost",
			tooltip = tr("notes.delete"),
			onClick = function()
				confirmDelete = true
				render()
			end,
		}),
		ui.button({ glyph = "x", variant = "ghost", tooltip = tr("notes.close"), onClick = close }),
	})

	local children = { header }
	if confirmDelete then
		table.insert(children, ui.row({ gap = 8, align = "center" }, {
			ui.label({ text = tr("notes.confirm-delete"), flexGrow = 1 }),
			ui.button({ text = tr("confirm.cancel"), variant = "ghost", onClick = function()
				confirmDelete = false
				render()
			end }),
			ui.button({ text = tr("confirm.delete"), variant = "destructive", onClick = deleteNow }),
		}))
	end
	if editing then
		table.insert(children, ui.input({
			key = "editor-" .. editorRev,
			value = text,
			multiline = true,
			focus = true,
			flexGrow = 1,
			placeholder = tr("notes.placeholder"),
			onChange = "onChange",
		}))
	else
		local home = string.gsub(noctalia.expandPath("~/"), "/$", "")
		table.insert(children, MarkdownView.build(MdView.render(text, { home = home }), {
			ui = ui,
			onLink = function(href: string)
				client.send("openUrl", { url = href })
			end,
		}))
	end
	table.insert(children, ui.label({ text = tr("notes.keys"), fontSize = 11, color = "on_surface_variant" }))
	panel.render(ui.column({ gap = 10, padding = 16 }, children))
end

function onOpen(_context: string?)
	local request = noctalia.state.get("note.request")
	closed = false
	confirmDelete = false
	createdHere = false
	creating = false
	dirtyAt = nil
	noteId = if typeof(request) == "string" and request ~= "new" then request else ""
	local note = currentNote()
	if note == nil then
		noteId = ""
	end
	text = if note ~= nil then note.text else ""
	editing = noteId == ""
	editorRev += 1
	render()
end

-- Saves what is pending; a note created here and emptied again is discarded.
function onClose()
	if closed then
		return
	end
	closed = true
	if noteId ~= "" and Notes.closeAction(createdHere, text) == "discard" then
		dirtyAt = nil
		client.send("deleteNote", { id = noteId })
		return
	end
	if dirtyAt ~= nil then
		save()
	end
end

function onChange(value: string)
	text = value or ""
	dirtyAt = noctalia.nowMs()
end

function onKey(chord: string, pressed: boolean)
	if not pressed then
		return
	end
	if chord == "ctrl+e" then
		toggleEdit()
	elseif chord == "ctrl+s" then
		save()
	end
end

function update()
	if dirtyAt ~= nil and noctalia.nowMs() - (dirtyAt :: number) >= SAVE_DELAY_MS then
		save()
	end
end

noctalia.setUpdateInterval(200)
