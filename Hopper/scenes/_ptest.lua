-- _ptest.lua
-- Scene main script (no GameObject owner).
-- Created automatically next to the scene .json — not listed in Assets.

local _ptest = class('_ptest')

function _ptest:initialize()
end

function _ptest:init(owner)
	-- owner is always nil for scene scripts
end

function _ptest:update(time)
end

function _ptest:destroy()
end

return _ptest
