-- assets/lua/fps/enemies.lua
-- A fixed pool of scene-placed enemies, taken and returned rather than
-- created and destroyed.
--
-- The pool exists in the scene file: Enemy_00..Enemy_NN, each an empty root
-- with an Enemy_NN_Mesh child holding the rigged .p3dm. Spawning at runtime
-- would mean building materials in Lua and getting the deferred G-buffer
-- flags right by hand; parking them below the floor costs nothing and keeps
-- every enemy editable in PyrosBuilder.

-- The ragdoll is a general module, not part of this game: it reads the
-- skeleton it is handed and builds a rig from it, so the same file works for
-- any rigged character this project ever ships. See assets/lua/ragdoll.lua.
local Ragdoll
do
	local chunk, err = loadfile(ASSETS_PATH .. "lua/ragdoll.lua")
	if not chunk then
		echo("[FPS] cannot load ragdoll.lua: " .. tostring(err))
	else
		Ragdoll = chunk()
	end
end

local Enemies = {}
Enemies.__index = Enemies

local Enemy = {}
Enemy.__index = Enemy

local PARK_Y = -40.0

-- ------------------------------------------------------------------ one
function Enemy.new(root, mesh, C)
	local e = setmetatable({}, Enemy)
	e.C = C
	e.cfg = C.enemy
	e.root = root
	e.mesh = mesh
	e.alive = false
	e.x, e.y, e.z = 0, PARK_Y, 0
	e.yaw = 0
	e.health = 0
	e.nextAttack = 0
	e.deadAt = 0
	e.clock = 0
	e.speed = e.cfg.speed

	-- Each enemy needs its OWN SkeletonAnimation: the clip container carries
	-- the playback clock, so a shared one makes every enemy step in lockstep
	-- and restart together whenever any of them is re-spawned.
	local rc = mesh and mesh:getComponent("RenderingComponent") or nil
	e.rc = rc
	if rc then
		local ok, err = pcall(function()
			e.anim = SekeletonAnimation.new()
			e.anim:loadAnimation(ASSETS_PATH .. "animations/walk.p3da")
			e.inst = e.anim:createInstance(rc)
			-- Phase and speed jitter per enemy. playClip() used to force
			-- startTime 0 with speed 1, so every enemy in the pool walked the
			-- same cycle on the same frame and a crowd moved as one body.
			if e.inst then
				e.animSpeed = 0.85 + math.random() * 0.35
				e.inst:playClip("walk", -1, e.animSpeed, math.random())
			end
		end)
		if not ok then
			echo("[FPS] enemy anim FAILED: " .. tostring(err))
			e.anim, e.inst = nil, nil
		elseif not e.inst then
			echo("[FPS] enemy anim: createInstance returned nil (hasBones="
				.. tostring(rc:hasBones()) .. ")")
		end
	end
	-- The corpse rig. Built once per pooled enemy and left parked: its bodies
	-- are static and 900 m below the level until the enemy dies, so a pool of
	-- fourteen costs nothing to carry around.
	--
	-- Nothing here names a bone. The previous version of this listed five
	-- Bip01_* names, five boxes and four joints, which meant it modelled a
	-- pelvis, a chest, a head and two undifferentiated legs - no arms at all,
	-- no knees, no elbows - and only on this one model. Everything below the
	-- five named bones snapped to bind pose the moment the enemy died, which
	-- is why a corpse looked like a mannequin dropped down a stairwell.
	local c = e.cfg
	if Ragdoll and e.inst and physics then
		local rag, rerr = Ragdoll.build(e.inst, mesh, {
			mass = c.corpseMass or 70.0,
			linearDamping = c.corpseLinearDamping,
			angularDamping = c.corpseAngularDamping,
			gravityScale = c.corpseGravity,
		})
		if rag then
			e.rag = rag
			if not Enemy._loggedRig then
				Enemy._loggedRig = true
				echo("[FPS] ragdoll rig: " .. rag:describe())
			end
		else
			echo("[FPS] ragdoll build failed: " .. tostring(rerr))
		end
	end
	-- Used only by the no-physics fallback below.
	e.halfH = c.height * 0.36

	e:park()
	return e
end

function Enemy:park()
	self.alive = false
	self.ragdoll = false
	self.x, self.y, self.z = 0, PARK_Y, 0
	-- Joints dropped and every body back to static, or a corpse left dynamic
	-- keeps falling under the level while it waits in the pool and arrives at
	-- the next spawn carrying whatever velocity it accumulated down there.
	if self.rag then self.rag:deactivate() end
	self.root:setPosition(Vec3.new(0, PARK_Y, 0))
	self.root:setRotation(Vec3.new(0, 0, 0))
	self.root:refreshTransformation()
	if self.mesh then
		self.mesh:setPosition(Vec3.new(0, 0, 0))
		self.mesh:refreshTransformation()
	end
	if self.rc then self.rc:disable() end
end

function Enemy:spawn(x, y, z, speed)
	self.alive = true
	self.dying = false
	self.x, self.y, self.z = x, y, z
	self.health = self.cfg.health
	self.speed = speed or self.cfg.speed
	self.clock = 0
	-- Stagger the first swing. Four enemies reaching the player on the same
	-- frame otherwise land four hits simultaneously, every interval, and the
	-- player dies to a burst they had no way to read.
	self.nextAttack = (self.cfg.attackStagger or 0) * math.random()
	self.sink = 0
	self.tilt = 0
	if self.rc then self.rc:enable() end
	self.ragdoll = false
	self.knockT, self.staggerT = 0, 0
	if self.rag then self.rag:deactivate(); self.rag:clearPunch() end
	-- Back from the pool: the clip was paused at death.
	if self.inst then
		pcall(function()
			self.inst:playClip("walk", -1, self.animSpeed or 1.0, math.random())
		end)
	end
	self.root:setPosition(Vec3.new(x, y, z))
	self.root:refreshTransformation()
	if FPS.audio then FPS.audio:playAt("alert", x, y + 1.4, z) end
end

-- Ray vs. a vertical capsule, in the cheap "closest approach to the axis"
-- form. Returns the distance along the ray and whether it was a head shot.
function Enemy:rayHit(origin, dir)
	local r = self.cfg.hitRadius
	local baseY = self.y
	local topY = self.y + self.cfg.height

	-- solve in the xz plane first: |o + t*d - c|^2 = r^2
	local ox, oz = origin.x - self.x, origin.z - self.z
	local a = dir.x * dir.x + dir.z * dir.z
	if a < 1e-8 then return nil end
	local b = 2 * (ox * dir.x + oz * dir.z)
	local c = ox * ox + oz * oz - r * r
	local disc = b * b - 4 * a * c
	if disc < 0 then return nil end
	local sq = math.sqrt(disc)
	local t = (-b - sq) / (2 * a)
	if t < 0 then t = (-b + sq) / (2 * a) end
	if t < 0 then return nil end

	local hy = origin.y + dir.y * t
	if hy < baseY or hy > topY then return nil end
	local head = hy > (topY - 0.30)
	return t, head
end

-- `hitPoint` is where the shot landed, in world space. Optional - a melee hit
-- or a script kill has no such point - and without it the rig falls back to
-- shoving the chest.
function Enemy:hurt(amount, fromPos, fromDir, hitPoint)
	if not self.alive or self.dying then return end
	self.health = self.health - amount
	if self.health > 0 then
		-- Still standing. Punch the torso away from the shot and shove the
		-- whole enemy back a little, both decaying over a fraction of a
		-- second. Before this a hit that did not kill produced no feedback of
		-- any kind - the enemy walked on as though nothing had touched it,
		-- and the only sign a shot had landed was a number going down.
		local c = self.cfg
		if self.rag and (c.hitPunch or 0) > 0 then
			pcall(function()
				self.rag:punch(hitPoint, fromDir,
					c.hitPunch * math.min(1.0, amount / math.max(1, c.health * 0.4)))
			end)
		end
		self.knockT = c.hitKnockTime or 0.18
		self.knockDX = (fromDir and fromDir.x or 0) * (c.hitKnockback or 0.55)
		self.knockDZ = (fromDir and fromDir.z or 0) * (c.hitKnockback or 0.55)
		-- Stop the advance for a moment. Without this the hit is invisible
		-- however hard it is: the AI keeps walking at 2.35 m/s and simply
		-- absorbs a 1.6 m/s shove, so the enemy strolls through the shot and
		-- the only thing that ever moved was a few bones for a third of a
		-- second. Being stopped in its tracks is most of what "it got hit"
		-- looks like from across a platform.
		self.staggerT = c.hitStagger or 0.22
		if FPS.audio then FPS.audio:playAt("hitFlesh", self.x, self.y + 1.3, self.z) end
		return
	end
	if self.health <= 0 then
		self.dying = true
		self.deadAt = self.clock
		self.knockX = fromDir.x
		self.knockZ = fromDir.z
		-- goRagdoll() stops the clip itself, and it must do so AFTER it has
		-- sampled the pose: the rig is built from where the limbs actually
		-- are at the moment of death, so a body caught mid-stride goes down
		-- mid-stride. The old code here paused and then reset to bind pose
		-- first, which threw that away - and had to, because only five bones
		-- were driven and the other forty would have kept the frozen walk.
		if self.rag then pcall(function() self.rag:clearPunch() end) end
		self:goRagdoll(fromDir, hitPoint)
		-- Smoke and arcing out of the wreck, from the shot that did it. Fired
		-- AFTER goRagdoll so the effect's first frame is already tracking the
		-- corpse's own position rather than the walking enemy's.
		if FPS.fx then pcall(function() FPS.fx:droidDeath(self, fromDir, hitPoint) end) end
		if FPS.audio then FPS.audio:playAt("death", self.x, self.y + 1.2, self.z) end
		if FPS.game then FPS.game:onEnemyKilled(self) end
	end
end

-- Hand the corpse to the physics engine.
--
-- Order matters and is the module's, not this file's: the rig samples the
-- current pose, places a body along every limb, joints them, and only then
-- releases. The impulse goes into the chest, which is above the rig's centre
-- of mass, so the body folds over its own hips instead of sliding off in one
-- piece.
function Enemy:goRagdoll(fromDir, hitPoint)
	if not self.rag then return end
	local c = self.cfg
	local push = c.corpseImpulse or 30.0
	local ok = pcall(function()
		self.rag:activate({
			-- Mostly horizontal. A big upward component pops the body into
			-- the air and it lands on its knees, which is the one pose a
			-- ragdoll can hold for ever.
			impulse = Vec3.new(
				(fromDir and fromDir.x or 0) * push,
				push * 0.12,
				(fromDir and fromDir.z or 0) * push),
			at = "chest",
			atPoint = hitPoint,
			-- Random spin exists to stop two kills in the same doorway landing
			-- identically. A real hit point supplies that rotation for itself,
			-- from where the bullet struck, so the jitter drops right down
			-- when there is one - otherwise it fights the hit it is meant to
			-- be dressing up.
			spin = (hitPoint and (c.corpseSpin or 1.1) * 0.3) or (c.corpseSpin or 1.1),
			tone = c.corpseTone,
			toneDamping = c.corpseToneDamping,
			linearDamping = c.corpseLinearDamping,
			angularDamping = c.corpseAngularDamping,
			gravityScale = c.corpseGravity,
		})
	end)
	self.ragdoll = ok and self.rag.active
end

function Enemy:update(dt, px, py, pz)
	if not self.alive then return end
	self.clock = self.clock + dt
	-- The clip is NOT ticked here. A scene-placed animated model is already
	-- driven by the scene's own SkeletonAnimation update, on the scene clock;
	-- ticking it again from a per-enemy clock that restarts at 0 on every
	-- spawn drives _startTimeClock to the wrong epoch and freezes the clip at
	-- a large negative currentTime. Play the clip and leave the clock alone.

	if self.dying and self.ragdoll then
		-- The rig owns the mesh now, bone by bone. The enemy's own root is NOT
		-- moved: setBoneWorld() writes world-space transforms through the
		-- owner's frame, so the root has to hold still or it would be applied
		-- twice. Only self.x/y/z follows the corpse, for the pool's benefit.
		self.rag:update()
		local p = self.rag:position()
		self.x, self.y, self.z = p.x, p.y, p.z
		if self.clock - self.deadAt > self.cfg.corpseTime then self:park() end
		return
	end

	if self.dying then
		-- Fallback for when no physics body could be made: tip over about the
		-- direction the shot came from, sink into the floor, then park.
		local t = (self.clock - self.deadAt) / self.cfg.deathTime
		self.tilt = math.min(1.0, t * 2.2) * 88.0
		self.sink = math.min(1.0, math.max(0.0, (t - 0.55) / 0.45)) * self.cfg.deathSink
		self.x = self.x + (self.knockX or 0) * dt * 0.7 * math.max(0, 1 - t * 3)
		self.z = self.z + (self.knockZ or 0) * dt * 0.7 * math.max(0, 1 - t * 3)
		self.root:setPosition(Vec3.new(self.x, self.y - self.sink, self.z))
		self.root:setRotation(Vec3.new(math.rad(self.tilt) * 0.0,
			math.rad(self.yaw), math.rad(self.tilt)))
		self.root:refreshTransformation()
		if self.clock - self.deadAt > self.cfg.corpseTime then self:park() end
		return
	end

	-- Impact reaction. Runs AFTER the scene graph has posed the skeleton from
	-- the walk clip (scene scripts tick after Scene.Update), so it layers on
	-- top of the animation rather than fighting it.
	if self.rag and self.rag:isPunching() then
		pcall(function() self.rag:updatePunch(dt) end)
	end
	if self.knockT and self.knockT > 0 then
		local k = self.knockT / (self.cfg.hitKnockTime or 0.18)
		self.x = self.x + self.knockDX * k * dt
		self.z = self.z + self.knockDZ * k * dt
		self.knockT = self.knockT - dt
	end
	if self.staggerT and self.staggerT > 0 then self.staggerT = self.staggerT - dt end

	local dx, dz = px - self.x, pz - self.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist > 0.001 then dx, dz = dx / dist, dz / dist end

	-- face the player, rate-limited so a turn reads as a turn
	local want = math.deg(math.atan(dx, dz))
	local diff = ((want - self.yaw + 180) % 360) - 180
	self.yaw = self.yaw + diff * math.min(1.0, self.cfg.turnRate * dt)

	local staggered = (self.staggerT or 0) > 0
	if staggered then
		-- held in place; the knockback above is the only thing moving it
	elseif dist > self.cfg.attackRange then
		local step = self.speed * dt
		local nx, nz = self.x + dx * step, self.z + dz * step
		nx, nz = self:avoid(nx, nz)
		self.x, self.z = nx, nz
	elseif self.clock >= self.nextAttack then
		self.nextAttack = self.clock + self.cfg.attackInterval
		if FPS.player then FPS.player:hurt(self.cfg.attackDamage) end
	end

	-- Tip the WHOLE character away from the shot while the reaction plays.
	-- Rotating bones moves the skin; rotating the root moves the silhouette,
	-- and at the range a firefight actually happens at, the silhouette is all
	-- there is to see. Measured: the bone reaction alone shifted the body by
	-- about 13 cm and was reported as not noticeable twice.
	local pitch, roll = 0, 0
	if self.rag and (self.cfg.hitLean or 0) > 0 and self.rag:isPunching() then
		local a, dx, dz = self.rag:punchAmount()
		if a > 0 then
			local yr = math.rad(self.yaw)
			local fx, fz = math.sin(yr), math.cos(yr)        -- facing
			local rx, rz = fz, -fx                           -- its right
			local lean = self.cfg.hitLean or 0.34
			pitch = (dx * fx + dz * fz) * a * lean
			roll  = (dx * rx + dz * rz) * a * lean
		end
	end
	self.root:setPosition(Vec3.new(self.x, self.y, self.z))
	self.root:setRotation(Vec3.new(pitch,
		math.rad(self.yaw + self.cfg.meshYawOffset), roll))
	self.root:refreshTransformation()
end

-- Push out of the columns only. Enemies walking through a bench looks worse
-- than enemies walking round one, but pathing round every prop needs a
-- navmesh the engine does not have, and columns are the ones that read.
function Enemy:avoid(x, z)
	local r = self.cfg.hitRadius + 0.35
	for _, c in ipairs(self.C.blockCylinders) do
		local dx, dz = x - c[1], z - c[2]
		local d = math.sqrt(dx * dx + dz * dz)
		local rr = c[3] + r
		if d < rr then
			if d < 1e-4 then dx, dz, d = 1, 0, 1 end
			-- slide around rather than stopping dead against it
			local tx, tz = -dz / d, dx / d
			x = c[1] + dx / d * rr + tx * 0.06
			z = c[2] + dz / d * rr + tz * 0.06
		end
	end
	local lim = self.C.PLAT_HZ - 0.25
	if z < -lim then z = -lim end
	if z > lim then z = lim end
	return x, z
end

-- ----------------------------------------------------------------- pool
function Enemies.new(C, findObject)
	local E = setmetatable({}, Enemies)
	E.C = C
	E.pool = {}
	E.active = {}
	for i = 0, C.enemy.poolSize - 1 do
		local n = string.format("Enemy_%02d", i)
		local root = findObject(n)
		local mesh = findObject(n .. "_Mesh")
		if root and mesh then
			table.insert(E.pool, Enemy.new(root, mesh, C))
		end
	end
	echo("[FPS] enemy pool: " .. #E.pool)
	return E
end

function Enemies:spawn(x, y, z, speed)
	for _, e in ipairs(self.pool) do
		if not e.alive then
			e:spawn(x, y, z, speed)
			table.insert(self.active, e)
			return e
		end
	end
	return nil
end

function Enemies:aliveCount()
	local n = 0
	for _, e in ipairs(self.active) do
		if e.alive and not e.dying then n = n + 1 end
	end
	return n
end

function Enemies:update(dt, px, py, pz)
	for i = #self.active, 1, -1 do
		local e = self.active[i]
		e:update(dt, px, py, pz)
		if not e.alive then table.remove(self.active, i) end
	end
end

function Enemies:clear()
	for _, e in ipairs(self.pool) do e:park() end
	self.active = {}
end

return Enemies
