-- The rules are the same in every level: assets/lua/topple/game.lua.
-- What is here is what differs.
return assert(loadfile(ASSETS_PATH .. "lua/topple/game.lua"))()({
    level = 3,
    scene = "scenes/Grove.json",
    next = "scenes/Keep.json",
    stars = { 5000, 10000, 14000 },
})
