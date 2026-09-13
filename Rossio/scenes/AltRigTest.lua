-- AltRigTest.lua
-- Scene main script (no GameObject owner).
-- Created automatically next to the scene .json — not listed in Assets.

local AltRigTest = class('AltRigTest')

function AltRigTest:initialize()
end

function AltRigTest:init(owner)
	-- owner is always nil for scene scripts
end

function AltRigTest:update(time)
end

function AltRigTest:destroy()
end

return AltRigTest
