-- The rules are the same in every level: assets/lua/topple/game.lua.
-- What is here is what differs.
return assert(loadfile(ASSETS_PATH .. "lua/topple/game.lua"))()({
    level = 2,
    scene = "scenes/Dunes.json",
    next = "scenes/Grove.json",
    stars = { 5000, 10000, 14000 },
})
