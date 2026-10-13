-- The title screen. It is a level like the others - the same script runs
-- it - told that nobody is playing: the sling fires by itself, and the
-- buttons on top open the worlds and their levels.
return assert(loadfile(ASSETS_PATH .. "lua/topple/game.lua"))()({
    menu = true,
    scene = "scenes/Title.json",
})
