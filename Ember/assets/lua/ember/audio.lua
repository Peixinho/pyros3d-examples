-- assets/lua/ember/audio.lua
--
-- The one-shot bank. Every entry is a `Sound`, which owns a pool of voices:
-- playing one takes the next free voice, so three coins picked up inside a
-- second are three overlapping dings rather than one restarting and cutting
-- itself off.
--
-- The looping sounds are NOT here - the music and Ember's own crackle are
-- AudioSources placed in the scene, so they stay editable in the editor like
-- any other object.

local Audio = {}
Audio.__index = Audio

-- name -> { file, voices, volume, pitch jitter }
local BANK = {
    jump    = { "jump.wav",   3, 0.55, 0.07 },
    flare   = { "flare.wav",  3, 0.75, 0.06 },
    land    = { "land.wav",   3, 0.60, 0.08 },
    step    = { "step.wav",   4, 0.30, 0.16 },
    pickup  = { "pickup.wav", 6, 0.55, 0.05 },
    melt    = { "melt.wav",   4, 0.75, 0.09 },
    hurt    = { "hurt.wav",   2, 0.85, 0.05 },
    out     = { "out.wav",    2, 0.85, 0.02 },
    torch   = { "torch.wav",  3, 0.80, 0.04 },
    win     = { "win.wav",    1, 0.90, 0.00 },
}

function Audio.new()
    local a = setmetatable({}, Audio)
    a.sounds, a.cfg = {}, {}
    local loaded, failed = 0, 0
    for name, e in pairs(BANK) do
        local ok, snd = pcall(function()
            return Sound.new(ASSETS_PATH .. "sounds/" .. e[1], e[2])
        end)
        if ok and snd and snd:isLoaded() then
            a.sounds[name], a.cfg[name] = snd, e
            loaded = loaded + 1
        else
            failed = failed + 1
        end
    end
    echo("[Ember] audio: " .. loaded .. " sounds" .. (failed > 0 and (", " .. failed .. " missing") or ""))
    return a
end

local function jitter(amount)
    if not amount or amount <= 0 then return 1.0 end
    return 1.0 + (math.random() * 2 - 1) * amount
end

-- Non-positional on purpose: this is a side-on 2D game and the listener is a
-- camera looking at a plane, so panning every jump by where it happened is
-- noise, not information.
function Audio:play(name, gain)
    local s, c = self.sounds[name], self.cfg[name]
    if not s or not c then return end
    s:play(c[3] * (gain or 1.0), jitter(c[4]))
end

return Audio
