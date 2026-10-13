-- A world: its scene is the stage. The rules, and which level goes on it,
-- are in assets/lua/hopper/game.lua.
return assert(loadfile(ASSETS_PATH .. "lua/hopper/game.lua"))()({ world = 4, scene = "scenes/World4.json" })
