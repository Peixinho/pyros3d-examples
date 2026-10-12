-- The rules are the same in every level: assets/lua/topple/game.lua.
-- What is here is what differs.
return assert(loadfile(ASSETS_PATH .. "lua/topple/game.lua"))()({
    level = 4,
    scene = "scenes/Keep.json",
    next = nil,
    stars = { 6000, 11000, 15000 },
})
