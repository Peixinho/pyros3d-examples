-- scenes/Rossio.lua
-- Scene main script for the Rossio metro station firefight.
--
-- The level itself is entirely in Rossio.json - geometry, lights, props,
-- particle emitters, the enemy pool and the HUD canvas are all authored in
-- PyrosBuilder. This file only runs the game: it loads the modules, ticks the
-- director, and pushes numbers into HUD elements that already exist.
--
-- The camera carries assets/lua/fps/player.lua as a component; the two talk
-- through the global FPS table, because a scene main script and a
-- LuaComponent are separate Lua objects with no handle on each other.

local Rossio = class('Rossio')

local function import(name)
	local path = ASSETS_PATH .. "lua/fps/" .. name .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. name .. ": " .. tostring(err)) end
	local mod = chunk()
	if mod == nil then error("module " .. name .. " returned nothing") end
	return mod
end

function Rossio:initialize()
	self.clock = 0
	self.ready = false
end

function Rossio:init(owner)
	FPS = FPS or {}
	FPS.hitMarker = nil

	local C = import("config")
	local Enemies = import("enemies")
	local Weapon = import("weapon")
	local Game = import("game")
	self.C = C

	-- screenPick() and placeDecalAtCursor() both want a Projection, and the
	-- editor host does not hand one out. At the exact centre of the screen
	-- the ray is the camera forward whatever the fov is, so the only thing
	-- this has to get right is the aspect - and it only matters for the
	-- small spread offsets.
	local w, h = 1280, 720
	if getWindowSize then w, h = getWindowSize() end
	projection = Projection.new()
	projection:perspective(68.0, w / math.max(1, h), 0.05, 300.0)

	self.game = Game.new(C, Enemies, Weapon)

	-- HUD handles, resolved once. ui.find() searches every canvas in the
	-- scene, so nothing here needs to know the canvas name.
	local F = function(n) return ui.find(scene, n) end
	self.hud = {
		hp      = F("HPBar"),
		hpText  = F("HPLabel"),
		ammo    = F("AmmoLabel"),
		weapon  = F("WeaponLabel"),
		wave    = F("WaveLabel"),
		sub     = F("SubLabel"),
		big     = F("BigLabel"),
		damage  = F("Damage"),
		hit     = F("HitA"),
	}
	if self.hud.big then ui.setText(self.hud.big, "") end
	self.ready = true
	echo("[FPS] Rossio ready - W/A/S/D move, mouse look, LMB fire, R reload, C crouch, Tab frees the mouse")
end

function Rossio:hudUpdate(dt)
	local H = self.hud
	if not H then return end
	local s = self.game:status()

	if H.hp then ui.setFill(H.hp, s.health / s.maxHealth) end
	if H.hpText then ui.setText(H.hpText, tostring(s.health)) end
	if H.hp then
		-- the bar goes amber then red as it drops, so a glance is enough
		local f = s.health / s.maxHealth
		if f > 0.55 then ui.setTint(H.hp, Vec4.new(0.30, 0.72, 0.34, 0.95))
		elseif f > 0.25 then ui.setTint(H.hp, Vec4.new(0.85, 0.62, 0.16, 0.95))
		else ui.setTint(H.hp, Vec4.new(0.86, 0.16, 0.18, 0.95)) end
	end

	if H.ammo then
		if s.reloading then
			ui.setText(H.ammo, "-- / " .. s.reserve)
		else
			ui.setText(H.ammo, s.ammo .. " / " .. s.reserve)
		end
	end
	if H.weapon then
		ui.setText(H.weapon, s.reloading and "RELOADING" or self.C.weapon.name)
	end

	if H.wave then
		if s.state == "intro" then ui.setText(H.wave, "ROSSIO")
		elseif s.state == "wave" then ui.setText(H.wave, string.format("WAVE %d / %d", s.wave, s.waves))
		elseif s.state == "break" then ui.setText(H.wave, "PLATFORM CLEAR")
		elseif s.state == "won" then ui.setText(H.wave, "LAST TRAIN GONE")
		else ui.setText(H.wave, "") end
	end
	if H.sub then
		if s.state == "wave" then ui.setText(H.sub, s.left .. " hostiles")
		elseif s.state == "break" then ui.setText(H.sub, "next wave inbound")
		elseif s.state == "intro" then ui.setText(H.sub, "hold the platform")
		else ui.setText(H.sub, s.kills .. " down") end
	end
	if H.big then
		if s.state == "lost" then ui.setText(H.big, "YOU DIED")
		elseif s.state == "won" then ui.setText(H.big, "STATION HELD")
		else ui.setText(H.big, "") end
	end

	if H.damage then
		local a = (s.flash or 0) * 0.42
		ui.setTint(H.damage, Vec4.new(0.72, 0.03, 0.03, a))
	end
	if H.hit then
		local a = FPS.hitMarker and math.min(1.0, FPS.hitMarker * 4.0) or 0.0
		ui.setTint(H.hit, Vec4.new(1.0, 0.34, 0.26, a * 0.9))
	end
end

function Rossio:update(dt)
	if not self.ready then return end
	self.clock = self.clock + dt
	self.game:update(dt)
	self:hudUpdate(dt)
end

return Rossio
