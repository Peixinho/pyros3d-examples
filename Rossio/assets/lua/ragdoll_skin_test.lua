-- assets/lua/ragdoll_skin_test.lua
--
-- The ragdoll on a loop, so it can be watched rather than argued about.
--
-- Attach to a GameObject carrying a rigged model (scenes/RagdollSkinTest.json
-- puts it on `Body`). It walks the character, drops it, drives the mesh from
-- the physics rig for a few seconds, then stands it back up and does it again.
--
-- Everything about the rig itself lives in assets/lua/ragdoll.lua and is
-- discovered from the skeleton - this file knows no bone names.

local RagdollSkin = class('RagdollSkin')

-- Two switches for looking at the rig rather than the corpse. Both off = the
-- normal loop: walk, get knocked down, reset.
SHOW_RIG = false   -- draw the collision bodies over the mesh


local WALK_FOR = 2.2     -- seconds upright before it is knocked down
local FALL_FOR = 5.0     -- seconds of ragdoll before it is reset

function RagdollSkin:initialize() end

function RagdollSkin:init(owner)
	self.owner = owner
	self.clock = 0
	self.phase = "walk"
	self.nextAt = WALK_FOR

	local rc = owner:getComponent("RenderingComponent")
	if not rc or not physics then
		echo("[RAGDOLL] needs a RenderingComponent and a physics engine")
		return
	end

	local ok, err = pcall(function()
		self.anim = SekeletonAnimation.new()
		self.anim:loadAnimation(ASSETS_PATH .. "animations/walk.p3da")
		self.inst = self.anim:createInstance(rc)
	end)
	if not ok or not self.inst then
		echo("[RAGDOLL] animation failed: " .. tostring(err))
		return
	end
	self.inst:playClip("walk", -1, 1.0, math.random())

	-- A floor to land on. The scene's Ground is a render cube with no body.
	local g = physics:createBox(4.0, 0.10, 4.0, 0.0, false)
	if g then
		local go = GameObject.new()
		go:setName("RagdollTestFloor")
		go:setPosition(Vec3.new(0, -0.10, 0))
		go:refreshTransformation()
		go:addComponent(g)
		scene:add(go)
		self.floor = g
	end

	local chunk, lerr = loadfile(ASSETS_PATH .. "lua/ragdoll.lua")
	if not chunk then
		echo("[RAGDOLL] cannot load ragdoll.lua: " .. tostring(lerr))
		return
	end
	local Ragdoll = chunk()

	local rag, rerr = Ragdoll.build(self.inst, owner, { mass = 72.0 })
	if not rag then
		echo("[RAGDOLL] build failed: " .. tostring(rerr))
		return
	end
	self.rag = rag
	echo("[RAGDOLL] " .. rag:describe())
	rag:dumpBodies()
	-- SHOW_RIG draws the collision bodies over the mesh, in colour, so the rig
	-- can be compared against the character it is supposed to fit. Combine it
	-- with FREEZE below to hold the corpse in its death pose.
	if SHOW_RIG then rag:showBodies(true) end

end

-- FREEZE holds the rig in the pose it was built from, with no impulse and no
-- gravity, so the collision bodies can be compared against the mesh they are
-- supposed to stand for. Any capsule that is not inside its limb HERE is a
-- construction bug, not a simulation one.
local FREEZE = false

function RagdollSkin:knockDown()
	local a = math.random() * math.pi * 2
	if FREEZE then
		self.rag:activate({ spin = 0, gravityScale = 0.0 })
		return
	end
	self.rag:activate({
		impulse = Vec3.new(math.cos(a) * 17.0, 5.0, math.sin(a) * 17.0),
		at = "chest",
		spin = 1.1,
	})
	echo("[RAGDOLL] down: " .. self.rag:describe())
	self.rag:verify("just-activated")
	self.rag:baselineLengths()
	self.stretchAt = self.clock + 0.25
end

function RagdollSkin:update(dt)
	if not self.rag then return end
	if dt <= 0 or dt > 0.25 then dt = 0.016 end
	self.clock = self.clock + dt

	if self.phase == "walk" then
		if self.clock >= self.nextAt then
			self:knockDown()
			self.phase = "fallen"
			self.nextAt = self.clock + FALL_FOR
		end
	else
		self.rag:update()
		if self.stretchAt and self.clock >= self.stretchAt then
			self.stretchAt = self.clock + 0.5
			local tag = string.format("t+%.1f", self.clock - (self.nextAt - FALL_FOR))
			self.rag:stretch(tag)
			self.rag:jointError(tag)
		end
		if self.clock >= self.nextAt then
			self.rag:deactivate()
			self.inst:playClip("walk", -1, 1.0, math.random())
			self.phase = "walk"
			self.nextAt = self.clock + WALK_FOR
		end
	end
end

function RagdollSkin:destroy()
	if self.rag then self.rag:destroy(); self.rag = nil end
end

function RagdollSkin:serialize() return {} end
function RagdollSkin.deserialize(_) return RagdollSkin:new() end

return RagdollSkin
