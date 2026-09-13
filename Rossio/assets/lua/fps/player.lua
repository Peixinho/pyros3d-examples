-- assets/lua/fps/player.lua
-- Attach to the scene Camera GameObject (Properties > Script).
--
-- Owns the eye: look, movement, collision, head bob and recoil. Everything
-- that needs to reach the player from elsewhere goes through the global FPS
-- table, which the scene script creates - a LuaComponent and the scene main
-- script are separate Lua objects with no reference to each other otherwise.

local Player = class('Player')

local function loadConfig()
	local chunk = loadfile(ASSETS_PATH .. "lua/fps/config.lua")
	return chunk and chunk() or nil
end

function Player:initialize()
	self.yaw, self.pitch = 0, 0
	self.recoilPitch, self.recoilYaw = 0, 0
	self.vel = { x = 0, y = 0, z = 0 }
	self.grounded = true
	self.bobPhase = 0
	self.captured = false
	self.health = 100
	self.lastHurt = -99
	self.crouch = false
	self.dead = false
	self.clock = 0
end

-- ------------------------------------------------------------------ util
-- Horizontal push-out against the declared static blockers. Resolved on the
-- axis of least penetration, which is what stops a player sliding along a
-- bench instead of being stopped dead by its end.
function Player:resolve(x, z)
	local C, r = self.C, self.C.player.radius
	for _, b in ipairs(C.blockBoxes) do
		local minx, minz, maxx, maxz = b[1] - r, b[2] - r, b[3] + r, b[4] + r
		if x > minx and x < maxx and z > minz and z < maxz then
			local dl, dr = x - minx, maxx - x
			local db, dt = z - minz, maxz - z
			local m = math.min(dl, dr, db, dt)
			if m == dl then x = minx
			elseif m == dr then x = maxx
			elseif m == db then z = minz
			else z = maxz end
		end
	end
	for _, c in ipairs(C.blockCylinders) do
		local dx, dz = x - c[1], z - c[2]
		local d = math.sqrt(dx * dx + dz * dz)
		local rr = c[3] + r
		if d < rr then
			if d < 1e-4 then dx, dz, d = 1, 0, 1 end
			x = c[1] + dx / d * rr
			z = c[2] + dz / d * rr
		end
	end
	-- the platform itself: you do not get to walk onto the tracks
	local lim = C.PLAT_HZ - 0.30
	if z < -lim then z = -lim end
	if z > lim then z = lim end
	local xl = C.HALF_LEN - 0.85
	if x < -xl then x = -xl end
	if x > xl then x = xl end
	return x, z
end

function Player:applyLook()
	local qPitch, qYaw = Quaternion.new(), Quaternion.new()
	qPitch:axisToQuaternion(Vec3.new(1, 0, 0), math.rad(self.pitch + self.recoilPitch))
	qYaw:axisToQuaternion(Vec3.new(0, 1, 0), math.rad(self.yaw + self.recoilYaw))
	self.owner:setRotation((qYaw * qPitch):getEulerRotation(0))
end

function Player:setCaptured(on)
	self.captured = on and true or false
	if setMouseCaptured then setMouseCaptured(self.captured) end
	if self.captured then
		if warpMouseToCenter then warpMouseToCenter() end
		self.lastX, self.lastY = nil, nil
		self.skipDelta = true
	else
		self.lastX, self.lastY = nil, nil
		self.f, self.b, self.l, self.r = false, false, false, false
		self.sprint = false
	end
end

-- ------------------------------------------------------------------ init
function Player:init(owner)
	self.owner = owner
	if not owner then
		error("player.lua needs a GameObject owner - attach it to the Camera")
	end
	self.C = loadConfig()
	if not self.C then error("player.lua: cannot load config.lua") end
	local P = self.C.player

	FPS = FPS or {}
	FPS.player = self

	-- Reset EVERY piece of runtime state here, not in initialize(). The editor
	-- re-runs init() on the same component instance for each play session
	-- (ResetLifecycle), so anything left in initialize() survives a Stop -
	-- self.dead in particular, which made the second play start on "YOU DIED".
	self.health = P.maxHealth
	self.dead = false
	self.crouch = false
	self.firing = false
	self.pendingShot = false
	self.wantJump = false
	self.flash = nil
	self.clock = 0
	self.lastHurt = -99
	self.bobPhase = 0
	self.grounded = true
	self.vel = { x = 0, y = 0, z = 0 }
	self.recoilPitch, self.recoilYaw = 0, 0
	self.lastStep = 0
	self.pos = { x = P.startPos[1], y = P.startPos[2], z = P.startPos[3] }
	self.yaw = P.startYaw
	self.pitch = 0
	self:applyLook()
	owner:setPosition(Vec3.new(self.pos.x, self.pos.y + P.eyeHeight, self.pos.z))
	owner:refreshTransformation()

	local input = Input.new()
	self.input = input
	local function bind(key, field)
		input:onKeyPressed(key, function() self[field] = true end)
		input:onKeyReleased(key, function() self[field] = false end)
	end
	bind(Key.W, "f"); bind(Key.S, "b"); bind(Key.A, "l"); bind(Key.D, "r")
	bind(Key.LShift, "sprint")
	input:onKeyPressed(Key.Space, function() self.wantJump = true end)
	input:onKeyPressed(Key.C, function() self.crouch = not self.crouch end)
	input:onKeyPressed(Key.R, function() if FPS.weapon then FPS.weapon:reload() end end)
	input:onKeyPressed(Key.Tab, function() self:setCaptured(not self.captured) end)

	-- `firing` is the held state, `pendingShot` is a latch. Input callbacks
	-- run on the event pump, update() runs once a frame: at 25 fps a frame is
	-- 40 ms and a normal click is shorter than that, so press AND release can
	-- both be delivered between two updates and the held flag is false again
	-- by the time anything looks at it. The click is then silently dropped -
	-- the weapon "shoots nothing" for exactly the taps a player makes when
	-- aiming carefully, while holding the button works fine.
	input:onMouseButtonPressed(MouseButton.Left, function()
		self.firing = true
		self.pendingShot = true
	end)
	input:onMouseButtonReleased(MouseButton.Left, function() self.firing = false end)

	input:onMouseMoved(function(x, y)
		if not self.captured then self.lastX = nil return end
		if self.skipDelta then
			self.skipDelta = false
			self.lastX, self.lastY = x, y
			return
		end
		if self.lastX then
			local dx, dy = x - self.lastX, y - self.lastY
			if dx ~= 0 or dy ~= 0 then
				local s = self.C.player.lookSensitivity
				self.yaw = self.yaw - dx * s
				self.pitch = self.pitch - dy * s
				if self.pitch < -85 then self.pitch = -85 end
				if self.pitch > 85 then self.pitch = 85 end
				self:applyLook()
				if warpMouseToCenter then warpMouseToCenter() end
				if getWindowSize then
					local w, h = getWindowSize()
					self.lastX, self.lastY = math.floor(w / 2), math.floor(h / 2)
				else
					self.lastX, self.lastY = x, y
				end
				return
			end
		end
		self.lastX, self.lastY = x, y
	end)

	-- editorAutoCapture only exists in the editor's play mode. In a built
	-- game nothing sets it, so this used to start with the mouse free and no
	-- way to look around until you found Tab. Capture unless something has
	-- explicitly forbidden it.
	if editorAutoCapture or allowMouseCapture ~= false then
		self:setCaptured(true)
	end
	echo("[FPS] player ready")
end

-- ---------------------------------------------------------------- damage
function Player:hurt(amount)
	if self.dead then return end
	self.health = self.health - amount
	self.lastHurt = self.clock
	self.flash = 1.0
	if FPS.audio then FPS.audio:play("hurt") end
	if self.health <= 0 then
		self.health = 0
		self.dead = true
		self:setCaptured(false)
		echo("[FPS] player down")
	end
end

-- Put the player back on their feet. Death with no way out is what made the
-- game look like the weapon had stopped working: you die about twenty seconds
-- in while finding your bearings, and from then on every click does nothing
-- with only a small label to say why.
function Player:respawn()
	local P = self.C.player
	self.dead = false
	self.health = P.maxHealth
	self.lastHurt = self.clock
	self.vel = { x = 0, y = 0, z = 0 }
	self.recoilPitch, self.recoilYaw = 0, 0
	self.flash = nil
	self.pos = { x = P.startPos[1], y = P.startPos[2], z = P.startPos[3] }
	self.yaw, self.pitch = P.startYaw, 0
	self:applyLook()
	self.owner:setPosition(Vec3.new(self.pos.x, self.pos.y + P.eyeHeight, self.pos.z))
	self.owner:refreshTransformation()
	self:setCaptured(true)
end

function Player:heal(amount)
	self.health = math.min(self.C.player.maxHealth, self.health + amount)
end

function Player:addRecoil(pitchDeg, yawDeg)
	self.recoilPitch = self.recoilPitch + pitchDeg
	self.recoilYaw = self.recoilYaw + yawDeg
end

function Player:eyePosition()
	local h = self.crouch and self.C.player.crouchHeight or self.C.player.eyeHeight
	return Vec3.new(self.pos.x, self.pos.y + h, self.pos.z)
end

-- Unit forward in world space. getDirection() points BACKWARDS out of the
-- camera in this engine (the camera world matrix is the inverse of a view
-- matrix), so the forward the game wants is its negation.
function Player:forward()
	local d = self.owner:getDirection()
	return Vec3.new(-d.x, -d.y, -d.z)
end

-- ---------------------------------------------------------------- update
function Player:update(dt)
	if dt <= 0 or dt > 0.25 then dt = 0.016 end
	self.clock = self.clock + dt
	local P = self.C.player

	-- recoil always decays, even while dead, so the view settles. The rate
	-- belongs to the weapon, not the player - the player just holds the value.
	local rec = math.min(1.0, self.C.weapon.recoilRecover * dt)
	self.recoilPitch = self.recoilPitch * (1 - rec)
	self.recoilYaw = self.recoilYaw * (1 - rec)
	if self.flash then
		self.flash = self.flash - dt * 1.8
		if self.flash <= 0 then self.flash = nil end
	end

	if self.dead then
		self:applyLook()
		return
	end

	if self.clock - self.lastHurt > P.regenDelay and self.health < P.maxHealth then
		self:heal(P.regenRate * dt)
	end

	-- ---- horizontal movement, in camera-relative axes
	local speed = P.walkSpeed
	if self.crouch then speed = P.crouchSpeed
	elseif self.sprint and self.f then speed = P.sprintSpeed end

	local yr = math.rad(self.yaw)
	local fx, fz = -math.sin(yr), -math.cos(yr)
	local rx, rz = math.cos(yr), -math.sin(yr)
	local wx, wz = 0, 0
	if self.f then wx = wx + fx; wz = wz + fz end
	if self.b then wx = wx - fx; wz = wz - fz end
	if self.r then wx = wx + rx; wz = wz + rz end
	if self.l then wx = wx - rx; wz = wz - rz end
	local wl = math.sqrt(wx * wx + wz * wz)
	if wl > 0.0001 then wx, wz = wx / wl, wz / wl end

	local target = { x = wx * speed, z = wz * speed }
	local a = (wl > 0.0001) and P.accel or P.friction
	local k = math.min(1.0, a * dt)
	self.vel.x = self.vel.x + (target.x - self.vel.x) * k
	self.vel.z = self.vel.z + (target.z - self.vel.z) * k

	-- ---- vertical
	if self.wantJump and self.grounded then
		self.vel.y = P.jumpSpeed
		self.grounded = false
	end
	self.wantJump = false
	self.vel.y = self.vel.y + P.gravity * dt

	local nx = self.pos.x + self.vel.x * dt
	local nz = self.pos.z + self.vel.z * dt
	nx, nz = self:resolve(nx, nz)
	-- kill the velocity component that was cancelled, or the player keeps
	-- pressing into a wall and shoots off sideways the moment it clears
	if math.abs(nx - self.pos.x) < math.abs(self.vel.x * dt) * 0.5 then self.vel.x = 0 end
	if math.abs(nz - self.pos.z) < math.abs(self.vel.z * dt) * 0.5 then self.vel.z = 0 end
	self.pos.x, self.pos.z = nx, nz

	self.pos.y = self.pos.y + self.vel.y * dt
	if self.pos.y <= self.C.FLOOR_Y then
		self.pos.y = self.C.FLOOR_Y
		self.vel.y = 0
		self.grounded = true
	end

	-- ---- head bob
	local hspeed = math.sqrt(self.vel.x ^ 2 + self.vel.z ^ 2)
	if self.grounded and hspeed > 0.4 then
		self.bobPhase = self.bobPhase + dt * P.bobRate * (hspeed / P.walkSpeed)
	else
		self.bobPhase = self.bobPhase * (1 - math.min(1, dt * 6))
	end
	-- Footsteps ride the bob rather than a timer, so the sound lands with the
	-- dip of the head instead of drifting out of phase with it.
	local step = math.floor(self.bobPhase / math.pi)
	if self.grounded and hspeed > 0.9 and step ~= self.lastStep then
		self.lastStep = step
		if FPS.audio then FPS.audio:play("step", self.sprint and 1.25 or 1.0) end
	elseif hspeed <= 0.9 then
		self.lastStep = step
	end

	local bob = math.sin(self.bobPhase) * P.bobAmount * math.min(1, hspeed / P.walkSpeed)
	local eye = (self.crouch and P.crouchHeight or P.eyeHeight) + bob

	self.owner:setPosition(Vec3.new(self.pos.x, self.pos.y + eye, self.pos.z))
	self:applyLook()
	self.owner:refreshTransformation()

	if (self.firing or self.pendingShot) and FPS.weapon then
		FPS.weapon:tryFire()
	end
	self.pendingShot = false
end

function Player:destroy()
	self:setCaptured(false)
	self.input = nil
	if FPS then FPS.player = nil end
end

function Player:serialize() return {} end
function Player.deserialize(_) return Player:new() end

return Player
