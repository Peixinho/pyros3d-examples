-- assets/lua/fps/game.lua
-- The director: waves, spawns, pickups, the HUD readout and the mood
-- (flickering fluorescents, the train doors sighing open, the tunnel glow).

local Game = {}
Game.__index = Game

local function findObject(name)
	for _, o in ipairs(scene:getAllGameObjects()) do
		if o:getName() == name then return o end
		local c = o:findChild(name)
		if c then return c end
	end
	return nil
end

function Game.new(C, Enemies, Weapon)
	local g = setmetatable({}, Game)
	g.C = C
	g.clock = 0
	g.state = "intro"          -- intro | wave | break | won | lost
	g.wave = 0
	g.spawnQueue = 0
	g.nextSpawn = 0
	g.stateUntil = 6.0
	g.kills = 0
	g.hitMarker = 0

	-- The sound bank is built before anything that might want to make a
	-- noise, and lives on FPS so the weapon, the enemies and the player all
	-- reach the same voices rather than each loading their own copy.
	local chunk = loadfile(ASSETS_PATH .. "lua/fps/audio.lua")
	local Audio = chunk and chunk() or nil
	FPS.audio = Audio and Audio.new() or nil
	g.audio = FPS.audio

	-- Death effects, before the enemy pool: an enemy that dies on its first
	-- frame should still find them. Like the audio bank they hang off FPS,
	-- because enemies.lua is the thing that fires them and the two modules
	-- have no handle on each other.
	local fxChunk = loadfile(ASSETS_PATH .. "lua/fps/deathfx.lua")
	local DeathFX = fxChunk and fxChunk() or nil
	FPS.fx = (DeathFX and C.enemy.droid) and DeathFX.new(C) or nil
	g.fx = FPS.fx

	g.enemies = Enemies.new(C, findObject)
	g.weapon = Weapon.new(C)
	FPS.enemies = g.enemies
	FPS.weapon = g.weapon
	FPS.game = g

	-- spawn points: every object tagged EnemySpawn in the scene
	g.spawns = {}
	for _, o in ipairs(scene:getAllGameObjects()) do
		if o:haveTag("EnemySpawn") then
			local p = o:getWorldPosition()
			table.insert(g.spawns, { x = p.x, y = p.y, z = p.z, name = o:getName() })
		end
	end
	echo("[FPS] spawn points: " .. #g.spawns)

	-- pickups: tagged in the scene, spun and bobbed here, consumed on touch
	g.pickups = {}
	for _, o in ipairs(scene:getAllGameObjects()) do
		if o:haveTag("Pickup") then
			local p = o:getPosition()
			table.insert(g.pickups, {
				obj = o, baseY = p.y, x = p.x, z = p.z, taken = false,
				kind = o:haveTag("Health") and "health" or "ammo",
				rc = o:getComponent("RenderingComponent"),
			})
		end
	end
	echo("[FPS] pickups: " .. #g.pickups)

	-- flickering fluorescents
	g.flicker = {}
	for _, n in ipairs(C.flickerLights) do
		local o = findObject(n)
		if o then
			local l = o:getComponent("PointLight")
			if l then
				table.insert(g.flicker, {
					light = l, base = l:getLightIntensity(),
					phase = math.random() * 6.0, next = 0, on = true,
				})
			end
		end
	end

	-- the train doors, so the platform side of the stopped train can open
	g.doors = {}
	for _, car in ipairs({ "TrainCab", "TrainMid" }) do
		for i = 0, 2 do
			for _, side in ipairs({ "L", "R" }) do
				local o = findObject(string.format("%s_Door_%d%s", car, i, side))
				if o then
					local p = o:getPosition()
					table.insert(g.doors, {
						obj = o, x = p.x, y = p.y, z = p.z,
						dir = (side == "L") and -1 or 1, open = 0,
					})
				end
			end
		end
	end
	echo("[FPS] train doors: " .. #g.doors)

	g.doorTarget = 0
	return g
end

function Game:onEnemyKilled(_)
	self.kills = self.kills + 1
end

function Game:startWave(n)
	self.wave = n
	local w = self.C.waves[n]
	if not w then
		self.state = "won"
		self.stateUntil = self.clock + 8.0
		return
	end
	self.state = "wave"
	self.spawnQueue = w.count
	self.nextSpawn = self.clock + 0.4
	self.waveSpeed = w.speed
	self.spawnInterval = w.interval
	self.doorTarget = 1.0
	if FPS.audio then
		FPS.audio:play("doors", 0.9)
		FPS.audio:play("train", 0.7)
	end
	echo(string.format("[FPS] wave %d - %d hostiles", n, w.count))
end

function Game:spawnOne()
	if #self.spawns == 0 then return end
	-- Prefer a spawn point the player is not staring at, so nothing pops in
	-- at the centre of the screen.
	local P = FPS.player
	local best, bestScore = nil, -1
	for _ = 1, 6 do
		local s = self.spawns[math.random(#self.spawns)]
		local score = math.random()
		if P then
			local dx, dz = s.x - P.pos.x, s.z - P.pos.z
			local d = math.sqrt(dx * dx + dz * dz)
			local f = P:forward()
			local dot = (d > 0.01) and ((dx / d) * f.x + (dz / d) * f.z) or 1
			score = (1.0 - dot) * 0.7 + math.min(d / 30.0, 1.0) * 0.3 + math.random() * 0.2
		end
		if score > bestScore then best, bestScore = s, score end
	end
	if best then
		self.enemies:spawn(best.x, best.y, best.z, self.waveSpeed)
	end
end

function Game:update(dt)
	if dt <= 0 or dt > 0.25 then dt = 0.016 end
	self.clock = self.clock + dt
	local P = FPS.player

	self.weapon:update(dt)

	if P then
		self.enemies:update(dt, P.pos.x, P.pos.y, P.pos.z)
	end
	-- After the enemies, so a plume started this frame is already following
	-- the corpse the ragdoll just moved rather than trailing it by one.
	if self.fx then self.fx:update(dt) end

	-- ---- wave state machine
	if self.state == "intro" then
		if self.clock > self.stateUntil then self:startWave(1) end
	elseif self.state == "wave" then
		if self.spawnQueue > 0 and self.clock >= self.nextSpawn then
			self:spawnOne()
			self.spawnQueue = self.spawnQueue - 1
			self.nextSpawn = self.clock + self.spawnInterval
		elseif self.spawnQueue == 0 and self.enemies:aliveCount() == 0 then
			self.state = "break"
			self.stateUntil = self.clock + self.C.waveBreak
			self.doorTarget = 0.0
			if self.weapon then self.weapon:addAmmo(28) end
		end
	elseif self.state == "break" then
		if self.clock > self.stateUntil then self:startWave(self.wave + 1) end
	end

	if P and P.dead and self.state ~= "lost" then
		self.state = "lost"
		self.deadAt = self.clock
		self.enemies:clear()
		if self.fx then self.fx:clear() end
	elseif self.state == "lost" and P and self.clock - (self.deadAt or 0) > 3.0 then
		-- Back in, at the start of the wave that killed you. A wave-defence
		-- level with no respawn is over the first time you misjudge a corner.
		P:respawn()
		self.kills = self.kills
		self:startWave(math.max(1, self.wave))
	end

	self:updatePickups(dt)
	self:updateMood(dt)

	if FPS.hitMarker then
		FPS.hitMarker = FPS.hitMarker - dt
		if FPS.hitMarker <= 0 then FPS.hitMarker = nil end
	end
end

function Game:updatePickups(dt)
	local P = FPS.player
	for _, p in ipairs(self.pickups) do
		if not p.taken then
			p.obj:setPosition(Vec3.new(p.x, p.baseY + math.sin(self.clock * 2.2) * 0.06, p.z))
			p.obj:setRotation(Vec3.new(0, self.clock * 1.1, 0))
			p.obj:refreshTransformation()
			if P and not P.dead then
				local dx, dz = p.x - P.pos.x, p.z - P.pos.z
				if dx * dx + dz * dz < 1.1 * 1.1 then
					p.taken = true
					if p.rc then p.rc:disable() end
					if FPS.audio then FPS.audio:playAt("pickup", p.x, p.baseY, p.z) end
					if p.kind == "health" then P:heal(35)
					else self.weapon:addAmmo(42) end
				end
			end
		end
	end
end

function Game:updateMood(dt)
	-- fluorescents that never quite settled
	for _, f in ipairs(self.flicker) do
		if self.clock >= f.next then
			f.on = not f.on
			f.next = self.clock + (f.on and (0.5 + math.random() * 3.5) or (0.03 + math.random() * 0.12))
			f.light:setLightIntensity(f.on and f.base or f.base * 0.06)
		end
	end

	-- doors slide open while a wave is running and shut between them
	local speed = dt * 0.9
	for _, d in ipairs(self.doors) do
		if d.open ~= self.doorTarget then
			if d.open < self.doorTarget then
				d.open = math.min(self.doorTarget, d.open + speed)
			else
				d.open = math.max(self.doorTarget, d.open - speed)
			end
			d.obj:setPosition(Vec3.new(d.x + d.dir * d.open * self.C.trainDoorOpen, d.y, d.z))
			d.obj:refreshTransformation()
		end
	end
end

-- What the HUD needs, in one call.
function Game:status()
	local P = FPS.player
	local W = self.weapon
	return {
		health = P and math.floor(P.health + 0.5) or 0,
		maxHealth = self.C.player.maxHealth,
		ammo = W and W.ammo or 0,
		magSize = self.C.weapon.magSize,
		reserve = W and W.reserve or 0,
		reloading = W and W.reloading or false,
		wave = self.wave,
		waves = #self.C.waves,
		left = self.enemies:aliveCount() + self.spawnQueue,
		kills = self.kills,
		state = self.state,
		hit = FPS.hitMarker ~= nil,
		flash = P and P.flash or nil,
	}
end

return Game
