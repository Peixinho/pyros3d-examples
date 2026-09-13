-- assets/lua/fps/weapon.lua
-- The pistol: hitscan, recoil, reload, and the impact effects.
--
-- Every visual it uses (viewmodel, muzzle flash quad, muzzle light, impact
-- and blood emitters) is a real object placed in the scene, not something
-- built here - so all of it stays editable in PyrosBuilder and this file only
-- decides where things point and when they fire.

local Weapon = {}
Weapon.__index = Weapon

local function findObject(name)
	for _, o in ipairs(scene:getAllGameObjects()) do
		if o:getName() == name then return o end
		local c = o:findChild(name)
		if c then return c end
	end
	return nil
end
Weapon.find = findObject

function Weapon.new(C)
	local w = setmetatable({}, Weapon)
	w.C = C
	w.cfg = C.weapon
	w.ammo = w.cfg.magSize
	w.reserve = w.cfg.reserveStart
	w.nextFire = 0
	w.clock = 0
	w.reloading = false
	w.reloadEnd = 0
	w.kick = 0
	w.decals = 0
	w.flashTimer = 0
	w.shots = 0

	w.gun = findObject("Gun")
	w.flash = findObject("MuzzleFX")
	w.smoke = findObject("SmokeFX")
	w.flashQuad = findObject("MuzzleFlash")
	w.muzzleLight = findObject("MuzzleLight")
	w.impact = findObject("ImpactFX")
	w.blood = findObject("BloodFX")
	w.decalMat = nil

	if w.gun then w.gunBase = w.gun:getPosition() end
	-- The flash is a sprite quad for the bright core plus a one-shot particle
	-- burst for the spray. The quad is toggled through its RenderingComponent
	-- rather than by moving it, so it costs nothing while it is off.
	w.flashRC = w.flashQuad and w.flashQuad:getComponent("RenderingComponent") or nil
	if w.flashRC then w.flashRC:disable() end
	echo("[FPS] muzzle quad: " .. tostring(w.flashQuad ~= nil)
		.. " rc: " .. tostring(w.flashRC ~= nil))
	w.flashPS = w.flash and w.flash:getComponent("ParticleSystem") or nil
	w.smokePS = w.smoke and w.smoke:getComponent("ParticleSystem") or nil
	-- The muzzle light lives in the scene root, parked below the level, and is
	-- teleported to the muzzle for the length of a flash. Moving it beats
	-- fading it: the intensity stays authored in the editor, where it can be
	-- tuned without touching this file.
	--
	-- Note for anyone tempted to make the flash bigger: what floods this
	-- frame is the MuzzleFlash *quad*, not the light. A 0.33 m emissive quad
	-- 0.62 m from the eye fills most of a 68-degree view and reads as a
	-- full-screen orange wash for as long as the trigger is held. At 0.10 m
	-- it reads as a muzzle flash. Bisected by disabling the quad and firing:
	-- clean frame, with the light still on.
	w.muzzleParked = Vec3.new(0, -60, 0)
	if w.muzzleLight then
		w.muzzleLight:setPosition(w.muzzleParked)
		w.muzzleLight:refreshTransformation()
	end
	w.impactPS = w.impact and w.impact:getComponent("ParticleSystem") or nil
	w.bloodPS = w.blood and w.blood:getComponent("ParticleSystem") or nil

	-- The decal material. GenericShaderMaterial with just a colour map is
	-- enough; the decal geometry supplies the UVs.
	local ok = pcall(function()
		local tex = Texture.new()
		-- Mipmapping OFF, and a low cutoff. A decal is small on screen, so it
		-- samples a high mip - and averaging DOWN an alpha mask erodes it:
		-- the rim falls under the cutoff first, then the middle, and a round
		-- hole shrinks to a black splinter. Which is exactly what it did.
		tex:loadTexture(ASSETS_PATH .. "textures/bullet_hole.png", TextureType.Texture, false, 0)
		tex:setTransparency(TextureTransparency.Transparent)
		-- AlphaTest, not blending: a decal is drawn into the G-buffer, and the
		-- G-buffer does not blend. Without it the transparent border of
		-- bullet_hole.png writes black, so every hole rendered as a ragged
		-- black smear instead of a hole.
		local mat = GenericShaderMaterial.new(ShaderUsage.Color | ShaderUsage.Texture
			| ShaderUsage.Diffuse | ShaderUsage.AlphaTest
			| ShaderUsage.DeferredRenderer_Gbuffer)
		mat:setColorMap(tex)
		-- ShaderUsage.Color declares uColor and the shader MULTIPLIES by it,
		-- but GenericShaderMaterial's Kd starts at (0,0,0,0) and the uniform
		-- is only created by SetColor(). Leave it unset and every decal is
		-- black with zero alpha - invisible once AlphaTest is on, and a ragged
		-- black smear before that.
		mat:setColor(Vec4.new(1, 1, 1, 1))
		mat:setAlphaCutoff(0.12)
		w.decalMat = mat
	end)
	if not ok then echo("[FPS] decal material unavailable - bullet holes off") end

	echo("[FPS] weapon ready" .. (w.gun and " (viewmodel found)" or " (no viewmodel)"))
	return w
end

function Weapon:reload()
	if self.reloading or self.ammo >= self.cfg.magSize or self.reserve <= 0 then return end
	self.reloading = true
	self.reloadEnd = self.clock + self.cfg.reloadTime
	if FPS.audio then FPS.audio:play("reload") end
end

function Weapon:finishReload()
	local need = self.cfg.magSize - self.ammo
	local take = math.min(need, self.reserve)
	self.ammo = self.ammo + take
	self.reserve = self.reserve - take
	self.reloading = false
end

-- Screen-space offset in pixels for a given angular spread, so the world
-- pick and the enemy test disagree by less than a pixel.
function Weapon:spreadPixels(halfH, fovDeg)
	local p = self.C.player
	local moving = FPS.player and (math.abs(FPS.player.vel.x) + math.abs(FPS.player.vel.z)) > 1.2
	local ang = moving and self.cfg.spreadMoving or self.cfg.spread
	local a = (math.random() * 2 - 1) * ang
	local b = (math.random() * 2 - 1) * ang
	local k = halfH / math.tan(math.rad(fovDeg) * 0.5)
	return a * k, b * k
end

function Weapon:tryFire()
	if self.reloading or self.clock < self.nextFire then return end
	if self.ammo <= 0 then
		if FPS.audio then FPS.audio:play("dryfire") end
		if self.reserve > 0 then self:reload() end
		return
	end
	self.nextFire = self.clock + self.cfg.fireInterval
	if FPS.audio then FPS.audio:play("shot") end
	self.ammo = self.ammo - 1
	self.shots = self.shots + 1
	self:fire()
end

function Weapon:fire()
	local P = FPS.player
	if not P then return end

	P:addRecoil(self.cfg.recoilPitch, (math.random() * 2 - 1) * self.cfg.recoilYaw)

	-- Park the muzzle light at the muzzle, in WORLD space, every shot.
	--
	-- It used to be a child of the Camera, which is the obvious way to do it
	-- and is wrong in this engine: a point light parented to the camera lights
	-- the ENTIRE frame - ceiling, far platform, everything - to a flat wash,
	-- and its radius makes no difference at all (measured at 3.2, 1.2 and
	-- 0.4; identical). The same light at a fixed world position with the same
	-- radius and intensity behaves normally. So it lives in the scene root
	-- and gets moved here.
	self.kick = self.cfg.kickBack
	self.flashTimer = 0.055
	if self.flashPS then self.flashPS:play() end
	if self.flashRC then self.flashRC:enable() end
	if self.smokePS and (self.shots % 3) == 1 then self.smokePS:play() end

	local eye = P:eyePosition()
	local fwd = P:forward()

	-- The flash light, at the muzzle, for as long as flashTimer runs. It is
	-- moved rather than faded because the light carries an authored intensity
	-- from the scene - one number to tune in the editor instead of two.
	if self.muzzleLight then
		self.muzzleLight:setPosition(Vec3.new(
			eye.x + fwd.x * 1.4, eye.y + fwd.y * 1.4 - 0.10, eye.z + fwd.z * 1.4))
		self.muzzleLight:refreshTransformation()
	end

	local w, h = 1280, 720
	if getWindowSize then w, h = getWindowSize() end
	local sx, sy = self:spreadPixels(h * 0.5, 68.0)

	-- ---- enemies first: an analytic capsule test is far cheaper than the
	-- per-triangle pick, and an enemy standing in front of a wall must win.
	local bestT, bestEnemy, bestHead = self.cfg.range, nil, false
	if FPS.enemies then
		for _, e in ipairs(FPS.enemies.active) do
			if e.alive then
				local t, head = e:rayHit(eye, fwd)
				if t and t < bestT then bestT, bestEnemy, bestHead = t, e, head end
			end
		end
	end

	-- ---- the world, through the engine's mesh-accurate pick
	local hit, hx, hy, hz, nx, ny, nz, hname, hdist = false
	if projection and scene then
		hit, hx, hy, hz, nx, ny, nz, hname, hdist =
			screenPick(w, h, w * 0.5 + sx, h * 0.5 + sy, P.owner, projection, scene)
	end

	if bestEnemy and (not hit or bestT < hdist) then
		local dmg = self.cfg.damage * (bestHead and self.cfg.headshotMultiplier or 1.0)
		-- The exact point the ray met the enemy. The ragdoll pushes the body
		-- part nearest it, at it, so where you hit is where it turns.
		bestEnemy:hurt(dmg, eye, fwd, Vec3.new(
			eye.x + fwd.x * bestT, eye.y + fwd.y * bestT, eye.z + fwd.z * bestT))
		if FPS.audio then
			FPS.audio:playAt("hitFlesh", eye.x + fwd.x * bestT,
				eye.y + fwd.y * bestT, eye.z + fwd.z * bestT)
		end
		self:spawnBlood(eye.x + fwd.x * bestT, eye.y + fwd.y * bestT, eye.z + fwd.z * bestT)
		FPS.hitMarker = 0.22
		return
	end

	if hit then
		self:spawnImpact(hx, hy, hz, nx, ny, nz)
		if FPS.audio then FPS.audio:playAt("hitStone", hx, hy, hz) end
		if self.decalMat and hdist < 40.0 then
			if self.decals >= self.cfg.decalBudget then
				-- process-wide and append-only; recycle rather than leak
				if clearDecals then clearDecals(scene) end
				self.decals = 0
			end
			local d = self.cfg.decalSize
			if placeDecalAtCursor(w, h, w * 0.5 + sx, h * 0.5 + sy, P.owner, projection,
				scene, self.decalMat, Vec3.new(d, d, d)) then
				self.decals = self.decals + 1
			end
		end
	end
end

function Weapon:spawnImpact(x, y, z, nx, ny, nz)
	if not self.impact then return end
	self.impact:setPosition(Vec3.new(x + nx * 0.05, y + ny * 0.05, z + nz * 0.05))
	self.impact:refreshTransformation()
	if self.impactPS then
		self.impactPS:setDirection(Vec3.new(nx, ny, nz))
		self.impactPS:play()
	end
end

function Weapon:spawnBlood(x, y, z)
	if not self.blood then return end
	self.blood:setPosition(Vec3.new(x, y, z))
	self.blood:refreshTransformation()
	if self.bloodPS then self.bloodPS:play() end
end

function Weapon:update(dt)
	self.clock = self.clock + dt
	if self.reloading and self.clock >= self.reloadEnd then self:finishReload() end

	-- viewmodel kick, plus a slow sway driven by the head bob
	self.kick = self.kick * (1 - math.min(1, self.cfg.kickRecover * dt))
	if self.gun and self.gunBase then
		local P = FPS.player
		local sway = P and math.sin(P.bobPhase * 0.5) * 0.006 or 0
		local rise = P and math.cos(P.bobPhase) * 0.004 or 0
		self.gun:setPosition(Vec3.new(self.gunBase.x + sway,
			self.gunBase.y + rise - self.kick * 0.35,
			self.gunBase.z + self.kick))
		self.gun:refreshTransformation()
	end

	if self.flashTimer > 0 then
		self.flashTimer = self.flashTimer - dt
		if self.flashTimer <= 0 then
			if self.muzzleLight then
				self.muzzleLight:setPosition(self.muzzleParked)
				self.muzzleLight:refreshTransformation()
			end
			if self.flashRC then self.flashRC:disable() end
		end
	end
end

function Weapon:addAmmo(n)
	self.reserve = self.reserve + n
end

return Weapon
