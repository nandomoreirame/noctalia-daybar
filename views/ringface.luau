--!strict
-- A progress ring (SVG files from the service, lib/ring.luau) with content drawn
-- over its center. ui.* has no stacking, so the overlap comes from a negative
-- gap: [ring, content, spacer] where the spacer brings the column back to the
-- ring's own height, so siblings below never overlap it. Without a ring
-- directory it falls back to the content over a linear progress bar.

local Ring = require("../lib/ring.luau")

local RingFace = {}

-- spec: { ui, ringDir, progress, size, content = { nodes }, contentHeight, key }
function RingFace.build(spec: { [string]: any }): any
	local ui = spec.ui
	if spec.ringDir == nil then
		local children = {}
		for _, node in ipairs(spec.content) do
			table.insert(children, node)
		end
		table.insert(children, ui.progress({ progress = spec.progress, height = 6, fill = "primary" }))
		return ui.column({ key = spec.key, gap = 6, align = "stretch" }, children)
	end
	local size = spec.size
	local inner = spec.contentHeight
	local path = spec.ringDir .. "/" .. tostring(Ring.step(spec.progress)) .. ".svg"
	return ui.column({ key = spec.key, align = "center", gap = -(size / 2 + inner / 2) }, {
		ui.image({ path = path, width = size, height = size, fit = "contain" }),
		ui.column({ align = "center", justify = "center", gap = 2, height = inner }, spec.content),
		ui.box({ width = size, height = size, fill = "#00000000" }),
	})
end

return RingFace
