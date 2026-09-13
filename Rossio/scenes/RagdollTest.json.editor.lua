-- RagdollTest.json.editor.lua
-- Scene main script (no GameObject owner).
-- Created automatically next to the scene .json — not listed in Assets.

local RagdollTestjsoneditor = class('RagdollTestjsoneditor')

function RagdollTestjsoneditor:initialize()
end

function RagdollTestjsoneditor:init(owner)
	-- owner is always nil for scene scripts
end

function RagdollTestjsoneditor:update(time)
end

function RagdollTestjsoneditor:destroy()
end

return RagdollTestjsoneditor
