-- The rules are the same in every level: assets/lua/topple/game.lua.
-- What is here is what differs.
return assert(loadfile(ASSETS_PATH .. "lua/topple/game.lua"))()({
    level = 1,
    scene = "scenes/Meadow.json",
    next = "scenes/Dunes.json",
    stars = { 4000, 8000, 11000 },
})
