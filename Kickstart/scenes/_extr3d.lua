-- _extr3d.lua
-- Scene main script (no GameObject owner).
-- Created automatically next to the scene .json — not listed in Assets.

local _extr3d = class('_extr3d')

function _extr3d:initialize()
end

function _extr3d:init(owner)
	-- owner is always nil for scene scripts
end

function _extr3d:update(time)
end

function _extr3d:destroy()
end

return _extr3d
