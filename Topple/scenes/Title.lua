-- The title screen. It is a level like the others - the same script runs
-- it - told that nobody is playing: the sling fires by itself, and the
-- buttons on top open the levels.
return assert(loadfile(ASSETS_PATH .. "lua/topple/game.lua"))()({
    menu = true,
    scene = "scenes/Title.json",
    levels = { "scenes/Meadow.json", "scenes/Dunes.json", "scenes/Grove.json", "scenes/Keep.json" },
    stars = { 0, 0, 0 },
})
