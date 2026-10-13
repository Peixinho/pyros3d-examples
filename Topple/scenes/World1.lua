-- A world: its scene is the stage, and this is all its script says. The
-- rules, and which level's prefab goes on the stage, are in
-- assets/lua/topple/game.lua.
return assert(loadfile(ASSETS_PATH .. "lua/topple/game.lua"))()({
    world = 1,
    scene = "scenes/World1.json",
})
