-- EnemyTest.lua
-- Scene main script (no GameObject owner).
-- Created automatically next to the scene .json — not listed in Assets.

local EnemyTest = class('EnemyTest')

function EnemyTest:initialize()
end

function EnemyTest:init(owner)
	-- owner is always nil for scene scripts
end

function EnemyTest:update(time)
end

function EnemyTest:destroy()
end

return EnemyTest
