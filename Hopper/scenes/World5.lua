-- A world: its scene is the stage. The rules, and which level goes on it,
-- are in assets/lua/hopper/game.lua.
return assert(loadfile(ASSETS_PATH .. "lua/hopper/game.lua"))()({ world = 5, scene = "scenes/World5.json" })
