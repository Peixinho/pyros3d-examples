-- _extr.lua
-- Scene main script (no GameObject owner).
-- Created automatically next to the scene .json — not listed in Assets.

local _extr = class('_extr')

function _extr:initialize()
end

function _extr:init(owner)
	-- owner is always nil for scene scripts
end

function _extr:update(time)
end

function _extr:destroy()
end

return _extr
