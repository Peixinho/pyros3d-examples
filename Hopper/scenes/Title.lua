-- The title: the same script, told it is the menu.
return assert(loadfile(ASSETS_PATH .. "lua/hopper/game.lua"))()({ menu = true, scene = "scenes/Title.json" })
