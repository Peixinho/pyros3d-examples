-- RagdollTest.lua
-- Scene main script (no GameObject owner).
-- Created automatically next to the scene .json — not listed in Assets.

local RagdollTest = class('RagdollTest')

function RagdollTest:initialize()
end

function RagdollTest:init(owner)
	-- owner is always nil for scene scripts
end

function RagdollTest:update(time)
end

function RagdollTest:destroy()
end

return RagdollTest
