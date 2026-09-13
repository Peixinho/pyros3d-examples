-- scenes/RagdollEnemyTest.lua
--
-- The metro game's own enemies, killed on a timer, so the death path can be
-- watched without playing the game.
--
-- This runs the real assets/lua/fps/enemies.lua - the same Enemy.new, spawn,
-- hurt, goRagdoll and park the firefight uses - against the real config. The
-- only thing it replaces is the shooting.

local Test = class('RagdollEnemyTest')

-- Set to a single { name, height } pair to test one aim point; nil cycles
-- head / chest / hip / thigh / shin.
PUNCH_SPOTS = nil

-- Freeze the corpse in its death pose with the collision bodies drawn, for
-- comparing the rig against the mesh it is supposed to fit.
FREEZE_RIG = false
-- Shoot enemy 1 without killing it, over and over, to watch the hit reaction
-- rather than the death.
FLINCH_ONLY = false
-- Walk the pool laterally across the view instead of killing anything, for
-- chasing "some enemies stop animating after lateral movement".
STRAFE = false
-- Draw the collision bodies over the mesh during a normal fall.
SHOW_RIG = false
-- Run the collapse in slow motion. This is a real time dilation, not slowed
-- playback: scaling gravity by 1/k^2 and every velocity and damping rate by
-- 1/k reproduces the SAME trajectory at 1/k speed, so a 30 fps capture of a 4x
-- slowdown shows the motion at an effective 120 fps. Nothing about the pose
-- the corpse passes through changes - only how long it takes to get there.
SLOWMO = 1.0

local function import(name)
	local path = ASSETS_PATH .. "lua/fps/" .. name .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. name .. ": " .. tostring(err)) end
	return chunk()
end

function Test:initialize()
	self.clock = 0
	self.ready = false
end

function Test:init(owner)
	FPS = FPS or {}

	local C = import("config")
	local Enemies = import("enemies")
	C.enemy.poolSize = 6
	-- Nothing to walk towards here, and a corpse that is recycled after nine
	-- seconds is gone before it has finished settling.
	C.enemy.speed = STRAFE and 1.8 or 0.0
	-- The corpse must outlive the collapse, and at SLOWMO the collapse takes
	-- SLOWMO times as long in wall-clock seconds.
	C.enemy.corpseTime = 3.6 * math.max(1.0, SLOWMO)
	self.C = C

	-- Debug: slow the hit reaction right down so its shape is visible at the
	-- few frames a second a viewport readback manages.
	-- normal speed: the whole-body lean is meant to read at full rate
	-- PUNCH_SPOTS pins the test to one aim point so a single reaction can be
	-- captured; nil cycles through all of them.
	PUNCH_SPOTS = PUNCH_SPOTS or nil

	self.enemies = Enemies.new(C, function(name)
		for _, o in ipairs(scene:getAllGameObjects()) do
			if o:getName() == name then return o end
			local c = o:findChild(name)
			if c then return c end
		end
		return nil
	end)
	if #self.enemies.pool == 0 then
		echo("[TEST] no enemies found in the scene")
		return
	end

	for i, e in ipairs(self.enemies.pool) do
		local sp = C.enemy.speed
		if i == 1 then e:spawn(0.0, 0.0, 3.0, sp)
		else e:spawn(-4.0 + (i - 2) * 1.6, 0.0, 0.0, sp) end
		table.insert(self.enemies.active, e)
	end
	-- SLOWMO dilates the PHYSICS. The walk clip has its own clock and does not
	-- care, so at an 8x slowdown played back at 8x the capture rate the corpse
	-- comes out at real speed and everyone still standing sprints. Scale the
	-- clip to match, or the recording lies about the one thing it is for.
	if SLOWMO > 1.0 then
		for _, e in ipairs(self.enemies.pool) do
			e.animSpeed = (e.animSpeed or 1.0) / SLOWMO
			if e.inst then e.inst:playClip("walk", -1, e.animSpeed, math.random()) end
		end
	end

	-- Rig primitives are attached at BUILD time, not at kill time: a
	-- RenderingComponent added to a GameObject the scene graph has already
	-- registered does not get picked up.
	if SHOW_RIG then
		for _, e in ipairs(self.enemies.pool) do
			if e.rag then e.rag:showBodies(true) end
		end
	end

	self.next = 1
	self.killAt = 1.2
	self.ready = true
end

function Test:update(dt)
	if not self.ready then return end
	if dt <= 0 or dt > 0.25 then dt = 0.016 end
	self.clock = self.clock + dt
	if STRAFE then
		-- A target that swings side to side, so every enemy turns and walks
		-- laterally across the camera rather than straight at it.
		self.enemies:update(dt, math.sin(self.clock * 0.5) * 9.0, 1.6, 5.2)
	-- Frozen-skeleton detector: hash a bone's model position each sample and
	-- report any enemy whose pose has not changed since the last one.
	self.animAt = self.animAt or 0
	self.animPrev = self.animPrev or {}
	if self.clock >= self.animAt then
		self.animAt = self.clock + 0.6
		local frozen, live = {}, 0
		for i, e in ipairs(self.enemies.pool) do
			if e.inst then
				local h = 0
				pcall(function()
					local b = e.inst:getBoneIdByName("Bip01_L_Hand")
					if b and b >= 0 then
						local v = e.inst:getBonePosition(b)
						h = v.x + v.y * 3.0 + v.z * 7.0
					end
				end)
				local prev = self.animPrev[i]
				if prev and math.abs(h - prev) < 1e-4 then
					frozen[#frozen + 1] = string.format("%d%s", i - 1,
						e.alive and (e.dying and "d" or "A") or "p")
				else live = live + 1 end
				self.animPrev[i] = h
			end
		end
		echo(string.format("[ANIM] live %d frozen %d  %s", live, #frozen,
			table.concat(frozen, " ")))

		-- Facing vs travel. The root is rotated by (yaw + meshYawOffset) and
		-- the mesh's own forward axis is a property of the model, so the only
		-- way to know whether a character walks forwards is to compare where
		-- it is GOING with where its mesh is POINTING.
		local e = self.enemies.pool[2]
		if e and e.alive then
			self.prevPos = self.prevPos or {}
			local pp = self.prevPos[2]
			local dx, dz = e.x - (pp and pp[1] or e.x), e.z - (pp and pp[2] or e.z)
			self.prevPos[2] = { e.x, e.z }
			local m = math.sqrt(dx * dx + dz * dz)
			if m > 1e-3 then
				local travel = math.deg(math.atan(dx / m, dz / m))
				local face = e.yaw + (self.C.enemy.meshYawOffset or 0)
				local d = ((face - travel + 180) % 360) - 180
				-- Which way the CHARACTER faces, not which way its GameObject
				-- axis points: a foot points where a person walks, so the
				-- foot-to-toe vector is the model's own forward, whatever
				-- axis convention it was authored on.
				local fx, fz, okf = 0, 0, false
				pcall(function()
					local w = e.mesh:getWorldTransformation()
					local fb = e.inst:getBoneIdByName("Bip01_L_Foot")
					local tb = e.inst:getBoneIdByName("Bip01_L_Toe0")
					if fb >= 0 and tb >= 0 then
						local a = w * e.inst:getBoneGlobal(fb):getTranslation()
						local b = w * e.inst:getBoneGlobal(tb):getTranslation()
						fx, fz = b.x - a.x, b.z - a.z
						okf = true
					end
				end)
				local footDeg = "?"
				if okf then
					local fm = math.sqrt(fx * fx + fz * fz)
					if fm > 1e-5 then
						local fd = math.deg(math.atan(fx / fm, fz / fm))
						footDeg = string.format("%.0f (off travel %.0f)", fd,
							((fd - travel + 180) % 360) - 180)
					end
				end
				echo(string.format("[FACE] travel %.0f  yaw %.0f  root %.0f  rootVsTravel %.0f  toes %s",
					travel, e.yaw, face, d, footDeg))
			end
		end
	end

		return
	end

	-- The "player" is deliberately off-axis: the enemies turn to face it, so
	-- the corpse is built under a root yawed to an angle that is not a
	-- multiple of 90 degrees. That is the case that catches a bad decomposition
	-- of the owner's world matrix - at 0 or 180 degrees the rotation matrix is
	-- diagonal and a wrong decomposition still happens to work.
	self.enemies:update(dt, 6.0, 1.6, 7.0)

	local e1 = self.enemies.pool[1]
	if e1 and e1.rag and e1.rag.active and self.stretchAt and self.clock >= self.stretchAt then
		self.stretchAt = self.clock + 0.6
		e1.rag:stretch("enemy")
		e1.rag:jointError("enemy")
		e1.rag:jointAngles("enemy")
		e1.rag:goVsBody("enemy")
	end

	-- One enemy, killed over and over in front of the camera, with the rest
	-- of the pool standing behind it so the crowd path is exercised too.
	local e = self.enemies.pool[1]

	if FLINCH_ONLY then
		if e and e.alive and self.clock >= (self.killAt or 0) then
			self.killAt = self.clock + 1.1
			local SPOTS = PUNCH_SPOTS or {
				{ "head", 1.62 }, { "chest", 1.30 }, { "hip", 0.95 },
				{ "thigh", 0.72 }, { "shin", 0.38 },
			}
			local spot = SPOTS[(self.round or 0) % #SPOTS + 1]
			self.round = (self.round or 0) + 1
			echo("[TEST] non-fatal hit to the " .. spot[1])
			e:hurt(self.C.weapon and self.C.weapon.damage or 26,
				Vec3.new(e.x, spot[2], e.z + 2.0),
				Vec3.new(0.0, 0.0, -1.0), Vec3.new(e.x, spot[2], e.z))
			e.health = self.C.enemy.health   -- survive the loop
			echo("[AIM] aimed " .. spot[1] .. " -> flinch moved " ..
				tostring(e.rag and e.rag:punchedPart()))
			self.watch, self.watchSpot, self.peak = e, spot[1], nil
		end
		-- How far the head and the foot each move, relative to the hips, while
		-- the reaction plays. A leg hit must move the foot and leave the head
		-- alone; the whole complaint was that it did the opposite.
		if self.watch and self.watch.rag and self.watch.rag:isPunching() then
			pcall(function()
				local w = self.watch.mesh:getWorldTransformation()
				local I = self.watch.inst
				local function bp(n)
					local id = I:getBoneIdByName(n)
					return w * I:getBoneGlobal(id):getTranslation()
				end
				local hips, head, foot = bp("Bip01_Pelvis"), bp("Bip01_Head"), bp("Bip01_L_Foot")
				local hz, fz = head.z - hips.z, foot.z - hips.z
				self.peak = self.peak or { h = hz, f = fz, h0 = hz, f0 = fz }
				self.peak.h = math.max(self.peak.h, math.abs(hz - self.peak.h0) + self.peak.h0)
				if math.abs(hz - self.peak.h0) > math.abs(self.peak.h - self.peak.h0) then self.peak.h = hz end
				if math.abs(fz - self.peak.f0) > math.abs(self.peak.f - self.peak.f0) then self.peak.f = fz end
			end)
		elseif self.peak then
			echo(string.format("[MOVED] %-6s head %.3f m   foot %.3f m",
				self.watchSpot or "?", math.abs(self.peak.h - self.peak.h0),
				math.abs(self.peak.f - self.peak.f0)))
			self.peak = nil
		end
		return
	end

	if e and self.clock >= self.killAt then
		if e.alive and not e.dying then
			-- Cycle the hit through head, chest, hip and thigh so the reaction
			-- can be told apart from a plain fall: identical shot direction
			-- every time, a different place on the body.
			local SPOTS = {
				{ "head", 1.62 }, { "chest", 1.30 },
				{ "hip",  0.95 }, { "thigh", 0.62 },
			}
			local spot = SPOTS[(self.round or 0) % #SPOTS + 1]
			echo("[TEST] kill 1 - shot in the " .. spot[1])
			e:hurt(999, Vec3.new(e.x, spot[2], e.z + 2.0),
				Vec3.new(0.0, 0.0, -1.0),
				Vec3.new(e.x, spot[2], e.z))
			self.round = (self.round or 0) + 1
			self.killAt = self.clock + 5.0 * math.max(1.0, SLOWMO)
			if e.rag then
				e.rag:baselineLengths(); self.stretchAt = self.clock + 0.3
				echo("[TEST] impulse went into part: " .. tostring(e.rag.hitPart))
				if SLOWMO > 1.0 then
					local k = SLOWMO
					for _, part in ipairs(e.rag.parts) do
						part.body:setGravityScale((self.C.enemy.corpseGravity or 1.0) / (k * k))
						part.body:setLinearVelocity(part.body:getLinearVelocity() * (1.0 / k))
						part.body:setAngularVelocity(part.body:getAngularVelocity() * (1.0 / k))
						part.body:setLinearDamping((self.C.enemy.corpseLinearDamping or 0.35) / k)
						part.body:setAngularDamping((self.C.enemy.corpseAngularDamping or 0.25) / k)
					end
				end
				-- Draw the collision rig over the mesh and hold it in the pose
				-- it was built from, so the bodies can be compared against
				-- five identical characters standing right next to it.
				if FREEZE_RIG then
					for _, part in ipairs(e.rag.parts) do
						part.body:setGravityScale(0.0)
						part.body:setLinearVelocity(Vec3.new(0, 0, 0))
						part.body:setAngularVelocity(Vec3.new(0, 0, 0))
					end
				end
			end
		elseif not e.alive then
			e:spawn(0.0, 0.0, 3.0, self.C.enemy.speed)
			table.insert(self.enemies.active, e)
			self.killAt = self.clock + 1.4
		else
			self.killAt = self.clock + 0.5
		end
	end
end

function Test:destroy() end

return Test
