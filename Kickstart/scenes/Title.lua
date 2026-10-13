-- The title: the same script, told it is the menu.
return assert(loadfile(ASSETS_PATH .. "lua/kickstart/game.lua"))()({ menu = true })
