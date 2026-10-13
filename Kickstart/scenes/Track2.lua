-- A track: its scene is the stage; the rules are in assets/lua/kickstart/game.lua.
return assert(loadfile(ASSETS_PATH .. "lua/kickstart/game.lua"))()({ track = 2 })
