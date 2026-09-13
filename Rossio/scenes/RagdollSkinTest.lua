-- RagdollSkinTest.lua
-- Scene main script (no GameObject owner).
-- Created automatically next to the scene .json — not listed in Assets.

local RagdollSkinTest = class('RagdollSkinTest')

function RagdollSkinTest:initialize()
end

function RagdollSkinTest:init(owner)
	-- owner is always nil for scene scripts
end

function RagdollSkinTest:update(time)
end

function RagdollSkinTest:destroy()
end

return RagdollSkinTest
