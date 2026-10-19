--!strict
-- The detached clock face shared by the pinned panel and the desktop widget
-- (REQ-027, REQ-028): digits, a progress bar, the label, and controls that show
-- only while the pointer is over the face.
-- opts: { ui, tr, size, hovered, closable, onHover, onToggle, onReset, onClose }

local ClockFmt = require("./clockfmt.luau")

local ClockFace = {}

function ClockFace.build(view: { [string]: any }?, nowMs: number, opts: { [string]: any }): any
	local ui = opts.ui
	local size = opts.size or 40
	if view == nil then
		return ui.column({ align = "center", justify = "center", gap = 6, onHover = opts.onHover }, {
			ui.label({ text = "--:--", fontSize = size, fontWeight = "bold", textAlign = "center" }),
		})
	end
	local clock = ClockFmt.shown(view, nowMs)
	local caption = if clock.labelKey ~= nil then opts.tr(clock.labelKey) else clock.label
	local children = {
		ui.label({ text = clock.text, fontSize = size, fontWeight = "bold", textAlign = "center", color = if clock.ringing then "error" else nil }),
		ui.progress({ progress = clock.progress, height = 4, fill = "primary" }),
	}
	if caption ~= "" then
		table.insert(children, ui.label({ text = caption, fontSize = 12, color = "on_surface_variant", textAlign = "center", maxLines = 1 }))
	end
	if opts.hovered then
		local controls = {
			ui.button({
				glyph = if clock.running then "player-pause" else "player-play",
				variant = "ghost",
				controlSize = "sm",
				tooltip = opts.tr(if clock.running then "focus.pause" else "focus.start"),
				onClick = function()
					opts.onToggle(clock.source)
				end,
			}),
			ui.button({
				glyph = "refresh",
				variant = "ghost",
				controlSize = "sm",
				tooltip = opts.tr("focus.reset"),
				onClick = function()
					opts.onReset(clock.source)
				end,
			}),
		}
		if opts.closable then
			table.insert(controls, ui.button({
				glyph = "x",
				variant = "ghost",
				controlSize = "sm",
				tooltip = opts.tr("focus.unpin"),
				onClick = opts.onClose,
			}))
		end
		table.insert(children, ui.row({ gap = 4, justify = "center" }, controls))
	end
	return ui.column({ align = "center", justify = "center", gap = 6, padding = 10, onHover = opts.onHover }, children)
end

return ClockFace
