-- assets/lua/fps/deathfx.lua
-- What a droid does when it stops working: a dirty smoke plume out of the
-- chest and a shorting main bus arcing across the wreck for a second or two.
--
-- Unlike every other visual in this game, these emitters are NOT placed in
-- the scene. A death effect has to follow a corpse that is being thrown
-- around by the ragdoll, and several droids die within a second of each
-- other in the late waves, so what is needed is a small ring of emitters
-- that get taken, driven for a couple of seconds and handed back - the same
-- shape as the enemy pool itself. Authoring six copies of the same two
-- emitters in PyrosBuilder would only make them harder to keep in step.
--
-- Everything that decides how it LOOKS is still config.lua (C.deathFX), so
-- the tuning lives where the rest of the game's tuning lives.

local DeathFX = {}
DeathFX.__index = DeathFX

-- Well below the level, like the muzzle light: an idle emitter costs nothing
-- once it has stopped spawning, but parking it keeps any particle still
-- ageing out of the player's sight.
local PARK_Y = -60.0

local function loadTex(name)
	local t = Texture.new()
	t:loadTexture(ASSETS_PATH .. "textures/" .. name, TextureType.Texture, true, 0)
	t:setTransparency(TextureTransparency.Transparent)
	return t
end

-- ------------------------------------------------------------- emitters
local function newEmitter(build)
	local go = GameObject.new()
	local d = ParticleSystemDesc.new()
	build(d)
	local ps = ParticleSystem.new(d)
	go:addComponent(ps)
	go:setPosition(Vec3.new(0, PARK_Y, 0))
	go:refreshTransformation()
	scene:add(go)
	-- desc is copied by the ParticleSystem, but the texture is shared - the
	-- caller holds it for as long as the emitter lives.
	return { go = go, ps = ps }
end

local function smokeEmitter(cfg, tex)
	return newEmitter(function(d)
		d.maxParticles = 110
		d.texture = tex
		-- Looping, because this is a plume that runs for a couple of seconds
		-- and is then stopped - not a one-shot. Stop() only halts spawning;
		-- the smoke already in the air still ages out normally, which is what
		-- lets the plume thin instead of vanishing.
		d.looping = true
		d.emissionRate = cfg.smokeRate
		d.burstCount = 1
		d.minLifetime = 0.85
		d.maxLifetime = 2.10
		d.direction = Vec3.new(0, 1, 0)
		d.spreadAngle = 0.85
		d.minSpeed = 0.25
		d.maxSpeed = 0.95
		d.gravity = Vec3.new(0, 0.40, 0)
		d.damping = 1.20
		d.startSize = 0.12
		d.endSize = 0.85
		d.sizeRandomJitter = 0.35
		-- Oily and dark, not the pale steam the vents make: a burnt droid has
		-- to read as damage against a station that is already full of white
		-- smoke and dust.
		d.startColor = Vec4.new(0.22, 0.23, 0.26, 0.45)
		d.endColor = Vec4.new(0.14, 0.15, 0.17, 0.0)
		d.fadeInFraction = 0.10
		d.fadeOutFraction = 0.45
		d.minRotationSpeed = -0.8
		d.maxRotationSpeed = 0.8
		d.blendMode = ParticleBlendMode.AlphaBlend
	end)
end

local function arcEmitter(cfg, tex)
	return newEmitter(function(d)
		d.maxParticles = 180
		d.texture = tex
		-- One-shot: every play() is one crack of the arc. Direction, spread,
		-- speed and count are re-set per burst (see DeathFX:burst) so a
		-- single emitter covers both the wide blowout at the moment of death
		-- and the narrow whips afterwards.
		d.looping = false
		d.burstCount = cfg.arcCount
		d.minLifetime = 0.10
		d.maxLifetime = 0.34
		d.direction = Vec3.new(0, 1, 0)
		d.spreadAngle = 0.25
		d.minSpeed = 2.0
		d.maxSpeed = 5.0
		-- No gravity and heavy damping: an electric arc is over before
		-- anything has time to fall, and the damping is what turns a straight
		-- spray into a whip that snaps out and stops.
		--
		-- Speed and damping together decide how far a spark gets, and that is
		-- the whole difference between an arc and a firework: a particle
		-- travels about speed/damping metres before it stops. The first
		-- version ran 17 m/s against damping 4, which is four metres - the
		-- sparks were landing on the train, well clear of the body, and read
		-- as debris thrown across the platform. 5 against 6.5 is 0.75 m, so
		-- they stay on the wreck.
		d.gravity = Vec3.new(0, 0, 0)
		d.damping = 6.5
		d.startSize = 0.200
		d.endSize = 0.020
		d.sizeRandomJitter = 0.45
		d.startColor = Vec4.new(0.80, 0.95, 1.0, 1.0)
		d.endColor = Vec4.new(0.12, 0.38, 1.0, 0.0)
		d.fadeInFraction = 0.0
		d.fadeOutFraction = 0.55
		d.minRotationSpeed = -2.0
		d.maxRotationSpeed = 2.0
		-- AlphaBlend, NOT Additive, which is what an electric arc obviously
		-- wants. Additive particles do not render at all in this project:
		-- measured with this emitter (41 live particles, 0.4 m across, right
		-- in front of the camera, nothing on screen) and then again with the
		-- scene's own ImpactFX, which is additive and equally invisible while
		-- the alpha-blended BloodFX fired at the same point shows normally.
		-- So it is the renderer, not this file - but until that is fixed,
		-- additive here means no sparks at all.
		d.blendMode = ParticleBlendMode.AlphaBlend
	end)
end

-- The flicker that makes the arc light the wreck rather than just sit on top
-- of it. Built in Lua because it belongs to a pooled slot, not to the level,
-- and parked below the floor between deaths exactly like the muzzle light -
-- moving a light is free, and it keeps the authored intensity in one place.
local function arcLight(cfg)
	local go, light
	local ok = pcall(function()
		go = GameObject.new()
		light = PointLight.new(Vec4.new(0.42, 0.68, 1.0, 1.0), cfg.lightRadius)
		light:setLightIntensity(0.0)
		go:addComponent(light)
		go:setPosition(Vec3.new(0, PARK_Y, 0))
		go:refreshTransformation()
		scene:add(go)
	end)
	if not ok then return nil end
	return { go = go, light = light }
end

-- ---------------------------------------------------------------- pool
function DeathFX.new(C)
	local fx = setmetatable({}, DeathFX)
	fx.C = C
	fx.cfg = C.deathFX
	fx.clock = 0
	fx.slots = {}
	fx.next = 1

	local ok, err = pcall(function()
		fx.smokeTex = loadTex("smoke.png")
		fx.sparkTex = loadTex("spark.png")
		for i = 1, fx.cfg.slots do
			fx.slots[i] = {
				smoke = smokeEmitter(fx.cfg, fx.smokeTex),
				arc = arcEmitter(fx.cfg, fx.sparkTex),
				light = fx.cfg.light and arcLight(fx.cfg) or nil,
				busy = false,
			}
		end
	end)
	if not ok then
		echo("[FPS] death FX unavailable: " .. tostring(err))
		fx.slots = {}
	else
		echo("[FPS] death FX slots: " .. #fx.slots
			.. (fx.slots[1] and fx.slots[1].light and " (with arc light)" or ""))
	end
	return fx
end

local function park(slot)
	slot.busy = false
	slot.enemy = nil
	slot.smoke.ps:stop()
	slot.smoke.go:setPosition(Vec3.new(0, PARK_Y, 0))
	slot.smoke.go:refreshTransformation()
	slot.arc.go:setPosition(Vec3.new(0, PARK_Y, 0))
	slot.arc.go:refreshTransformation()
	if slot.light then
		slot.light.light:setLightIntensity(0.0)
		slot.light.go:setPosition(Vec3.new(0, PARK_Y, 0))
		slot.light.go:refreshTransformation()
	end
end

-- Take the next slot round the ring. Stealing one that is still running is
-- deliberate: with more deaths in flight than slots, the oldest effect losing
-- its last half second is far less visible than the newest death producing
-- nothing at all.
function DeathFX:take()
	if #self.slots == 0 then return nil end
	local slot = self.slots[self.next]
	self.next = (self.next % #self.slots) + 1
	if slot.busy then park(slot) end
	return slot
end

-- One crack of the arc: a whip of sparks from `at`, along `dir`.
local function burst(slot, at, dir, spread, count, speed)
	slot.arc.go:setPosition(at)
	slot.arc.go:refreshTransformation()
	slot.arc.ps:setDirection(dir)
	slot.arc.ps:setSpread(spread)
	slot.arc.ps:setSpeed(speed * 0.45, speed)
	slot.arc.ps:setBurstCount(count)
	slot.arc.ps:play()
end

local function randomDir()
	-- Biased upward: sparks coming off the top of a wreck read; sparks fired
	-- into the floor are a flicker under a body and nothing more.
	local a = math.random() * math.pi * 2
	local y = 0.15 + math.random() * 0.85
	local r = math.sqrt(math.max(0.0, 1.0 - y * y))
	return Vec3.new(math.cos(a) * r, y, math.sin(a) * r)
end

-- `e` is the enemy that just died; `fromDir` the direction the shot was
-- travelling and `hitPoint` where it landed, both optional.
function DeathFX:droidDeath(e, fromDir, hitPoint)
	local slot = self:take()
	if not slot then return end
	local cfg = self.cfg

	slot.busy = true
	slot.enemy = e
	slot.deadAt = e.deadAt
	slot.start = self.clock
	slot.nextArc = self.clock + cfg.arcMin
	slot.flash = 1.0
	slot.x = e.x
	slot.y = e.y + cfg.chestHeight
	slot.z = e.z

	-- The plume starts at the chest and follows it down (see :update).
	slot.smoke.go:setPosition(Vec3.new(slot.x, slot.y, slot.z))
	slot.smoke.go:refreshTransformation()
	slot.smoke.ps:play()

	-- The blowout, at the hole the shot made and mostly along it - a droid
	-- that takes one through the chest sprays out of the far side.
	local at = hitPoint or Vec3.new(slot.x, slot.y, slot.z)
	local dir = fromDir and Vec3.new(
		fromDir.x * 0.65, 0.55, fromDir.z * 0.65) or Vec3.new(0, 1, 0)
	burst(slot, at, dir, 1.5, cfg.blowCount, cfg.blowSpeed)

	if slot.light then
		slot.light.go:setPosition(Vec3.new(slot.x, slot.y, slot.z))
		slot.light.go:refreshTransformation()
		slot.light.light:setLightIntensity(cfg.lightIntensity)
	end
end

function DeathFX:update(dt)
	self.clock = self.clock + dt
	local cfg = self.cfg

	for _, slot in ipairs(self.slots) do
		if slot.busy then
			local t = self.clock - slot.start

			-- Follow the corpse while it is still the same corpse. A pooled
			-- enemy is parked and re-spawned across the platform within
			-- seconds, so the identity check is the death timestamp, not the
			-- object: without it a plume would teleport to wherever that same
			-- pool entry turned up next.
			local e = slot.enemy
			if e and e.dying and e.alive and e.deadAt == slot.deadAt then
				slot.x, slot.y, slot.z = e.x, e.y + cfg.chestHeight, e.z
			end

			if t < cfg.smokeTime then
				slot.smoke.go:setPosition(Vec3.new(slot.x, slot.y, slot.z))
				slot.smoke.go:refreshTransformation()
			elseif slot.smoke.ps:isPlaying() then
				slot.smoke.ps:stop()
			end

			-- Arcs, at random intervals, from random points on the wreck.
			if t < cfg.arcTime and self.clock >= slot.nextArc then
				local j = cfg.jitter
				local at = Vec3.new(
					slot.x + (math.random() * 2 - 1) * j,
					slot.y + (math.random() * 2 - 1) * j * 0.8,
					slot.z + (math.random() * 2 - 1) * j)
				local n = cfg.arcCount
				burst(slot, at, randomDir(),
					cfg.arcSpread * (0.5 + math.random()),
					n - math.random(0, 2),
					cfg.arcSpeed * (0.7 + math.random() * 0.6))
				slot.nextArc = self.clock
					+ cfg.arcMin + math.random() * (cfg.arcMax - cfg.arcMin)
				slot.flash = 1.0
			end

			if slot.light then
				-- Decays between cracks and is kicked back up by each one, so
				-- the light strobes with the arcs rather than glowing steadily
				-- next to them.
				slot.flash = math.max(0.0, slot.flash - dt * cfg.lightDecay)
				local on = (t < cfg.arcTime) and (0.35 + 0.65 * slot.flash * slot.flash) or 0.0
				slot.light.light:setLightIntensity(cfg.lightIntensity * on)
				slot.light.go:setPosition(Vec3.new(slot.x, slot.y, slot.z))
				slot.light.go:refreshTransformation()
			end

			if t > math.max(cfg.smokeTime, cfg.arcTime) + cfg.tail then
				park(slot)
			end
		end
	end
end

function DeathFX:clear()
	for _, slot in ipairs(self.slots) do
		if slot.busy then park(slot) end
	end
end

return DeathFX
