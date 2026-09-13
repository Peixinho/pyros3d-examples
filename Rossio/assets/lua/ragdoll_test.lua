-- assets/lua/ragdoll_test.lua
-- A bench for the joints IPhysics grew: createSphericalJoint / createRevoluteJoint.
--
-- Attach to any GameObject in RagdollTest.json. It builds ONE ragdoll out of
-- five boxes and five joints, each part with its own visible mesh in its own
-- colour, and drops it every few seconds from a slightly different pose.
--
-- The point of the coloured boxes is that articulation is then something you
-- can SEE rather than something you have to infer: if the blue chest ends up
-- on the floor with the orange pelvis still in the air, the spine joint is
-- doing its job. A single rigid body cannot produce that picture.

local RagdollTest = class('RagdollTest')

-- name, half-extents (x,y,z), centre height, sideways offset, colour
local RIG = {
	{ "pelvis", 0.17, 0.14, 0.12, 0.86,  0.00, { 0.95, 0.45, 0.10 } },
	{ "chest",  0.20, 0.20, 0.13, 1.28,  0.00, { 0.15, 0.45, 0.95 } },
	{ "head",   0.10, 0.12, 0.10, 1.64,  0.00, { 0.95, 0.90, 0.20 } },
	{ "legL",   0.08, 0.29, 0.09, 0.32, -0.11, { 0.20, 0.80, 0.30 } },
	{ "legR",   0.08, 0.29, 0.09, 0.32,  0.11, { 0.85, 0.20, 0.35 } },
}

-- a, b, world Y of the anchor at rest, cone limit in radians
local JOINTS = {
	{ "pelvis", "chest", 1.06, 0.55 },   -- spine
	{ "chest",  "head",  1.50, 0.60 },   -- neck
	{ "pelvis", "legL",  0.63, 0.80 },   -- hips
	{ "pelvis", "legR",  0.63, 0.80 },
}

local DAMP = true
local TOTAL_MASS = 42.0
local SHARE = { pelvis = 0.30, chest = 0.34, head = 0.10, legL = 0.13, legR = 0.13 }

function RagdollTest:initialize() end

function RagdollTest:init(owner)
	self.owner = owner
	self.clock = 0
	self.nextDrop = 0.6
	self.parts = {}
	self.joints = {}

	if not physics then
		echo("ERROR: ragdoll_test needs the physics world (play mode)")
		return
	end

	-- Ground. Static, and its own body, so the test does not depend on
	-- anything else in the scene having a collider.
	-- A static box, not createStaticPlane: the plane's body never stopped
	-- anything here (the rig fell through it and kept accelerating past
	-- -900 m), and a box is the shape the rest of this project already
	-- trusts. HALF-extents, like every other box in this engine.
	local ground = physics:createBox(8.0, 0.10, 8.0, 0.0, false)
	if ground then
		local go = GameObject.new()
		go:setPosition(Vec3.new(0, -0.10, 0))
		go:refreshTransformation()
		go:addComponent(ground)
		scene:add(go)
		self.groundObject = go
	end

	-- Bodies first, every one attached to a GameObject: a physics component
	-- only joins the simulation when it is added to one, so a body left
	-- unattached is invisible to the solver AND to any joint naming it.
	for _, r in ipairs(RIG) do
		local body = physics:createBox(r[2], r[3], r[4], 0.0, false)
		local mat = GenericShaderMaterial.new(ShaderUsage.Color | ShaderUsage.Diffuse
			| ShaderUsage.DeferredRenderer_Gbuffer)
		mat:setColor(Vec4.new(r[7][1], r[7][2], r[7][3], 1.0))
		local go = GameObject.new()
		go:addComponent(RenderingComponent.new(Cube.new(r[2], r[3], r[4]), mat))
		go:addComponent(body)
		scene:add(go)
		self.parts[r[1]] = { body = body, go = go, dy = r[5], dx = r[6] }
	end

	-- Joints are NOT made here. Adding a physics component to a GameObject
	-- does not create its rigid body there and then - the body appears when
	-- the scene graph next registers the component, i.e. one frame later. A
	-- joint asked for before that names two bodies the solver has never heard
	-- of, and comes back 0 with nothing to show for it. So: bodies now, joints
	-- on the first update.
	-- Nothing is placed or joined here; see update()'s comment on ordering.
	self.phase = "place"
end

function RagdollTest:buildJoints()
	local made = 0
	for _, j in ipairs(JOINTS) do
		local h = physics:createSphericalJoint(self.parts[j[1]].body,
			self.parts[j[2]].body, Vec3.new(0, j[3], 0), j[4])
		if h ~= 0 then
			made = made + 1
			table.insert(self.joints, h)
		end
	end
	if made == #JOINTS then
		echo("[RAGDOLL] " .. #RIG .. " bodies, " .. made .. "/" .. #JOINTS
			.. " joints (after " .. (self.tries or 0) .. " frames)")
		return true
	end
	for _, h in ipairs(self.joints) do physics:destroyJoint(h) end
	self.joints = {}
	if (self.tries or 0) > 120 then
		echo("ERROR: ragdoll_test - only " .. made .. "/" .. #JOINTS .. " joints after 120 frames")
	end
	return false
end

-- Stand the rig back up, static and still.
function RagdollTest:reset()
	for _, p in pairs(self.parts) do
		p.body:setMass(0)
		p.body:cleanForces()
		p.body:setLinearVelocity(Vec3.new(0, 0, 0))
		p.body:setAngularVelocity(Vec3.new(0, 0, 0))
		-- Rotation too. UpdatePosition() deliberately preserves the body's
		-- current rotation, so a part that came to rest face-down stays
		-- face-down through the "reset" - and the joints are then built from
		-- a mangled rest pose and yank the rig apart on the next drop, which
		-- is what "the ragdoll is crazy fast" actually was.
		p.body:setRotation(Vec3.new(0, 0, 0))
		p.body:setPosition(Vec3.new(p.dx, p.dy, 0))
	end
end

-- Let go, with a shove through the chest - which is what makes a body fold
-- over its own hips instead of toppling like a plank.
function RagdollTest:drop()
	for name, p in pairs(self.parts) do
		p.body:setMass(TOTAL_MASS * (SHARE[name] or 0.2))
		-- Drag, so this reads as a body falling and not as a brick dropping.
		-- Set DAMP=false to see the difference: without it the rig is flat in
		-- about four frames.
		if DAMP then
			p.body:setLinearDamping(0.10)
			p.body:setAngularDamping(0.80)
			p.body:setGravityScale(1.0)
		else
			p.body:setLinearDamping(0.0)
			p.body:setAngularDamping(0.0)
			p.body:setGravityScale(1.0)
		end
		p.body:activate()
		p.body:setAngularVelocity(Vec3.new(
			(math.random() * 2 - 1) * 1.8,
			(math.random() * 2 - 1) * 1.2,
			(math.random() * 2 - 1) * 1.8))
	end
	local a = math.random() * math.pi * 2
	local push = 70.0
	self.parts.chest.body:applyCentralImpulse(
		Vec3.new(math.cos(a) * push, push * 0.35, math.sin(a) * push))
end

-- The order matters, and getting it wrong makes the solver explode rather
-- than fail: a joint records the two bodies' CURRENT transforms as its rest
-- frames, so it has to be created when the rig is already standing where it
-- belongs. Teleporting a body that is already jointed is the same mistake
-- from the other end - the constraint sees a huge violation and fires the
-- whole ragdoll off at a few hundred metres a second. Measured: parts at
-- y = -1500 within six seconds.
--
-- So the cycle is: place -> join -> drop -> unjoin -> place.
function RagdollTest:update(dt)
	if dt <= 0 or dt > 0.25 then dt = 0.016 end
	self.clock = self.clock + dt
	if not self.parts.pelvis then return end

	if self.phase == "place" then
		self:reset()
		self.phase = "join"
		return
	end

	if self.phase == "join" then
		self.tries = (self.tries or 0) + 1
		-- A physics component's rigid body is created by
		-- IPhysicsComponent::Register(), which the scene graph runs when it
		-- next picks the component up - not when addComponent() returns. How
		-- many frames that takes is not a script's business, so retry.
		if self:buildJoints() then
			self.phase = "hold"
			self.nextDrop = self.clock + 0.5
		elseif self.tries > 120 then
			echo("ERROR: ragdoll_test - joints never became creatable")
			self.phase = "hold"
			self.nextDrop = self.clock + 0.5
		end
		return
	end

	if self.phase == "hold" and self.clock >= self.nextDrop then
		self:drop()
		self.phase = "fallen"
		self.nextDrop = self.clock + 5.0
		return
	end

	if self.phase == "fallen" and self.clock >= self.nextDrop then
		for _, h in ipairs(self.joints) do physics:destroyJoint(h) end
		self.joints = {}
		self.tries = 0
		self.phase = "place"
	end
end

function RagdollTest:destroy() end
function RagdollTest:serialize() return {} end
function RagdollTest.deserialize(_) return RagdollTest:new() end

return RagdollTest
