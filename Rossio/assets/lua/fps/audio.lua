-- assets/lua/fps/audio.lua
-- The game's one-shot sound bank.
--
-- Every entry is a `Sound`, not an `AudioSource`: a Sound owns a pool of
-- voices and `playAt(pos, volume, pitch)` takes the next free one, so ten
-- overlapping shots are ten voices rather than one voice restarting and
-- cutting itself off. Looping room tone is NOT here - the platform ambience
-- is an AudioSource placed in the scene, so it stays editable in the editor
-- like every other object.
--
-- Loading is lazy and failure is silent-but-logged: a missing file must cost
-- the game nothing but its sound.

local Audio = {}
Audio.__index = Audio

-- name -> { file, voices, volume, pitch jitter }
local BANK = {
	shot      = { "gunshot.wav",      8, 0.85, 0.06 },
	dryfire   = { "dryfire.wav",      2, 0.55, 0.04 },
	reload    = { "reload.wav",       2, 0.70, 0.02 },
	hitFlesh  = { "hit_flesh.wav",    6, 0.90, 0.10 },
	hitStone  = { "hit_stone.wav",    6, 0.60, 0.14 },
	alert     = { "enemy_alert.wav",  6, 0.75, 0.12 },
	death     = { "enemy_death.wav",  6, 0.85, 0.10 },
	step      = { "footstep.wav",     4, 0.35, 0.12 },
	pickup    = { "pickup.wav",       2, 0.70, 0.03 },
	hurt      = { "player_hurt.wav",  3, 0.80, 0.08 },
	doors     = { "doors.wav",        2, 0.55, 0.02 },
	train     = { "train_pass.wav",   2, 0.65, 0.03 },
}

function Audio.new()
	local a = setmetatable({}, Audio)
	a.sounds = {}
	a.cfg = {}
	local loaded, failed = 0, 0
	for name, e in pairs(BANK) do
		local ok, snd = pcall(function()
			return Sound.new(ASSETS_PATH .. "sounds/" .. e[1], e[2])
		end)
		if ok and snd and snd:isLoaded() then
			a.sounds[name] = snd
			a.cfg[name] = e
			loaded = loaded + 1
		else
			failed = failed + 1
		end
	end
	echo("[FPS] audio: " .. loaded .. " sounds loaded"
		.. (failed > 0 and (", " .. failed .. " missing") or ""))
	return a
end

local function jitter(amount)
	if not amount or amount <= 0 then return 1.0 end
	return 1.0 + (math.random() * 2 - 1) * amount
end

-- Non-positional: the player's own weapon, their own footsteps, the HUD.
function Audio:play(name, volumeScale)
	local s = self.sounds[name]
	if not s then return end
	local e = self.cfg[name]
	s:play(e[3] * (volumeScale or 1.0), jitter(e[4]))
end

-- Positional: anything that happens somewhere in the station. The listener
-- follows the play-mode camera, so distance and direction come for free.
function Audio:playAt(name, x, y, z, volumeScale)
	local s = self.sounds[name]
	if not s then return end
	local e = self.cfg[name]
	s:playAt(Vec3.new(x, y, z), e[3] * (volumeScale or 1.0), jitter(e[4]))
end

return Audio
