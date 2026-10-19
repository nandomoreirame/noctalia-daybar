--!strict
-- Notes tab (REQ-031): search, "New note", rows with title, snippet and the last
-- edit time. Opening a note hands its id (or "new") to the note panel through
-- `note.request`, then toggles that panel.
-- st: { query }

local Notes = require("../lib/notes.luau")
local Format = require("../lib/format.luau")

local NotesView = {}

local NOTE_PANEL = "nandomoreirame/daybar:note"

local function open(ctx: any, id: string)
	ctx.state.set("note.request", id)
	ctx.togglePanel(NOTE_PANEL)
end

local function relative(ctx: any, iso: any): string
	local r = Format.relativeTime(iso, math.floor(ctx.nowMs / 1000))
	local k = Format.relativeKey(r)
	return if k.key == "" then k.date else ctx.tr(k.key, { n = k.n })
end

function NotesView.build(ctx: any): any
	local ui = ctx.ui
	local st = ctx.st
	local list = Notes.sorted(((ctx.view or {}).data or {}).notes or {})
	if st.query ~= nil and st.query ~= "" then
		list = Notes.search(list, st.query)
	end
	local rows = {}
	for _, n in ipairs(list) do
		local title = Notes.titleOf(n.text)
		local snippet = Notes.snippetOf(n.text)
		local text = {
			ui.label({ text = if title ~= "" then title else ctx.tr("notes.untitled"), fontWeight = "bold", maxLines = 1 }),
		}
		if snippet ~= "" then
			table.insert(text, ui.label({ text = snippet, fontSize = 12, maxLines = 2, color = "on_surface_variant" }))
		end
		table.insert(rows, ui.row({
			key = "note-" .. n.id,
			gap = 8,
			align = "center",
			radius = 6,
			onClick = function()
				open(ctx, n.id)
			end,
		}, {
			ui.column({ gap = 2, flexGrow = 1 }, text),
			ui.label({ text = relative(ctx, n.updatedAt), fontSize = 11, color = "on_surface_variant" }),
		}))
	end
	if #rows == 0 then
		local key = if st.query ~= nil and st.query ~= "" then "notes.no-results" else "notes.empty"
		table.insert(rows, ui.label({ text = ctx.tr(key), color = "on_surface_variant" }))
	end
	return ui.column({ gap = 8, flexGrow = 1 }, {
		ui.row({ gap = 6, align = "center" }, {
			ui.input({
				key = "search",
				placeholder = ctx.tr("notes.search"),
				controlSize = "sm",
				flexGrow = 1,
				onChange = function(value: string)
					st.query = value
					ctx.render()
				end,
			}),
			ui.button({
				text = ctx.tr("notes.new"),
				glyph = "plus",
				variant = "secondary",
				controlSize = "sm",
				onClick = function()
					open(ctx, "new")
				end,
			}),
		}),
		ui.scroll({ gap = 6, flexGrow = 1 }, rows),
	})
end

return NotesView
