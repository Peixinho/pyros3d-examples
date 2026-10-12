-- assets/lua/topple/sounds.lua - every sound the game makes, by name.
--
-- Each is a Sound with a few voices, so a pile of planks coming down is a
-- clatter and not one knock restarting itself. All are Kenney's (CC0).

local Sounds = {}
Sounds.__index = Sounds

-- name = voices
local BANK = {
    wood_1 = 4, wood_2 = 4, wood_3 = 3, wood_break = 4,
    glass_1 = 3, glass_2 = 3, glass_break = 4,
    stone_1 = 3, stone_2 = 3, stone_break = 3,
    metal_1 = 3, metal_2 = 3, metal_3 = 2, metal_break = 2,
    thud_1 = 4, thud_2 = 3, pop = 3, squeak = 3, bell = 1,
    boom_1 = 3, boom_low = 2,
    click = 2, select = 2, confirm = 1, back = 1, open = 1, pluck = 2, tick = 2,
    stretch = 1, whoosh = 2, cloth = 2, coins = 3,
    star_1 = 1, star_2 = 1, star_3 = 1, win = 1, lose = 1, start = 1,
}

function Sounds.new()
    local self = setmetatable({ bank = {}, last = {} }, Sounds)
    for name, voices in pairs(BANK) do
        local ok, s = pcall(function() return Sound.new(ASSETS_PATH .. "sounds/" .. name .. ".wav", voices) end)
        if ok and s and s:isLoaded() then self.bank[name] = s end
    end
    self.now = 0      -- the game's clock; the level sets it each frame
    return self
end

-- A sound asked for again within a few hundredths of a second is the same
-- event heard twice - two blocks landing together - and only gets louder.
function Sounds:play(name, volume, pitch)
    local s = self.bank[name]
    if not s then return end
    local now = self.now
    if self.last[name] and now - self.last[name] < 0.035 and now >= self.last[name] then return end
    self.last[name] = now
    s:play(volume or 1.0, pitch or (0.94 + math.random() * 0.12))
end

return Sounds
