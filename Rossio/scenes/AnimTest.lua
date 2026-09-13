-- AnimTest.lua
-- Scene main script (no GameObject owner).
-- Created automatically next to the scene .json — not listed in Assets.

local AnimTest = class('AnimTest')

function AnimTest:initialize()
end

function AnimTest:init(owner)
	-- owner is always nil for scene scripts
end

function AnimTest:update(time)
end

function AnimTest:destroy()
end

return AnimTest
