-- assets/lua/ragdoll.lua
--
-- A skeletal ragdoll built from whatever skeleton it is handed.
--
-- Nothing here knows the name "Bip01". The rig is discovered: bone names are
-- matched against the naming schemes rigs actually ship with (3ds max Biped,
-- Mixamo, Unreal's mannequin, Rigify, DAZ), the spine is found by walking the
-- hierarchy rather than by guessing how many "SpineN" bones there are, and
-- every dimension - segment length, limb radius, hip width, shoulder width,
-- which way the knee bends - is measured off the pose in front of it. Hand it
-- a different character and it builds a different ragdoll.
--
-- USE
--
--   local Ragdoll = <loadfile assets/lua/ragdoll.lua>()
--   local rag = Ragdoll.build(inst, meshGameObject, { mass = 70 })
--   ...
--   rag:activate({ impulse = Vec3.new(...), at = "chest" })  -- on death
--   rag:update()                                             -- every frame after
--   rag:deactivate()                                         -- when recycled
--
-- `inst` is the SekeletonAnimationInstance driving `meshGameObject`'s rig.
-- build() is cheap to keep around: the bodies it makes are static and parked
-- until activate(), so a pool of characters can each own one from birth.
--
-- HOW THE MESH FOLLOWS THE BODIES
--
-- Each body records, at activation, where its bone sits IN THE BODY'S OWN
-- FRAME: an offset vector L and a rotation D such that
--
--     boneWorldPos = bodyPos + bodyRot * L
--     boneWorldRot = bodyRot * D
--
-- and setBoneWorld() turns that into the bone-local transform the skinning
-- wants. Capturing L and D is the whole trick, and the thing the previous
-- implementation here got wrong: it fed the BODY's own position and rotation
-- straight to setBoneWorld, which is only correct if every body happens to be
-- born exactly on its bone and aligned with it. They were born axis-aligned at
-- the joint, so the first frame of every ragdoll snapped the whole mesh into
-- garbage. With L and D the body can be anywhere, any orientation, any shape -
-- a capsule lying along the limb, which is what a limb wants.

local Ragdoll = {}
Ragdoll.__index = Ragdoll

local PARK = -900.0      -- where an inactive rig's bodies wait

-- ---------------------------------------------------------------- naming
--
-- Everything in this block is guesswork about names, and it is kept together
-- so it is obvious where to add a scheme that is not covered.

-- "mixamorig:LeftArm" / "Armature|Hips" -> the part after the namespace
local function baseName(name)
	return name:match("[:|]([^:|]+)$") or name
end

local function flatten(name)
	return (baseName(name):lower():gsub("[^%a%d]", ""))
end

-- Which half of the body a bone belongs to, or nil for the centre line.
--
-- Five conventions in the wild: "Left"/"Right" words (Mixamo, Blender),
-- an L/R token between separators (Bip01_L_Calf), an L/R suffix (thigh_l,
-- thigh.L), and a bare lowercase l/r stuck on the front of a capitalised
-- name (DAZ's lShldr).
local function sideOf(name)
	local o = baseName(name)
	local n = o:lower()
	if n:find("left", 1, true) then return "L" end
	if n:find("right", 1, true) then return "R" end
	if o:match("^[lL]%u") then return "L" end
	if o:match("^[rR]%u") then return "R" end
	if n:match("^l[^%a]") or n:match("[^%a]l[^%a]") or n:match("[^%a]l$") then return "L" end
	if n:match("^r[^%a]") or n:match("[^%a]r[^%a]") or n:match("[^%a]r$") then return "R" end
	return nil
end

-- Bones a ragdoll must never build a body for. Fingers and toes are too small
-- to matter and would each become a body; twist/roll bones are helpers that
-- share a position with a real bone, so a body on one would sit inside a body
-- on the other and the solver would push them apart.
local SKIP = {
	"finger", "thumb", "index", "pinky", "twist", "roll", "helper", "nub",
	"eye", "jaw", "tongue", "teeth", "breast", "tail", "ponytail",
	"ik", "pole", "target", "ctrl", "null", "prop", "socket", "attach",
}

local function isSkipped(flat)
	for _, s in ipairs(SKIP) do
		if flat:find(s, 1, true) then return true end
	end
	-- Mixamo and Blender both end helper chains with "_end" / "End".
	if flat:sub(-3) == "end" then return true end
	return false
end

-- The role a bone plays, or nil. Order is load-bearing: "forearm" and
-- "upperarm" both contain "arm", "upleg" contains "leg", and Mixamo names the
-- upper arm plain "LeftArm" and the CALF plain "LeftLeg" - so the bare
-- "arm"/"leg" cases are left deliberately ambiguous here ("arm?"/"leg?") and
-- resolved against the hierarchy afterwards.
-- How much name is left after the last occurrence of `token`. A bone NAMED
-- after a body part carries little else: "LeftHand" has nothing after "hand",
-- "hand_l" has one character. A bone named after something ATTACHED to that
-- part carries a lot: "LeftHandIndicatorUpperBone" has twenty. The distinction
-- matters because a rig need not have a hand bone at all - the fingers can
-- hang straight off the forearm (examples/assets/Model.p3dm) - and without
-- this the ragdoll gives the corpse a wrist made out of one finger.
local function tailAfter(flat, token)
	local last = nil
	local i = 1
	while true do
		local a, b = flat:find(token, i, true)
		if not a then break end
		last = b; i = a + 1
	end
	if not last then return nil end
	return #flat - last
end

local function roleOf(flat, side)
	local function has(s) return flat:find(s, 1, true) ~= nil end
	-- named AFTER the part, not after something hanging off it
	local function isNamed(s, slack)
		local t = tailAfter(flat, s)
		return t ~= nil and t <= (slack or 4)
	end
	if has("head") then return "head" end
	if has("neck") then return "neck" end
	if has("clavicle") or has("collar") or (side and has("shoulder")) then return "clavicle" end
	if has("forearm") or has("lowerarm") or has("elbow") then return "forearm" end
	-- "shldr" is DAZ/Poser's UPPER ARM (its clavicle is "lCollar"), while
	-- Mixamo's "Shoulder" is the clavicle. Two different abbreviations of the
	-- same English word meaning two different bones - so they are matched
	-- separately and neither is allowed to stand in for the other.
	if has("upperarm") or has("shldr") then return "upperarm" end
	if isNamed("hand") or isNamed("wrist") then return "hand" end
	if has("foot") or has("ankle") then return "foot" end
	if has("calf") or has("shin") or has("lowerleg") or has("knee") then return "calf" end
	if has("thigh") or has("upleg") or has("upperleg") then return "thigh" end
	if side and has("arm") then return "arm?" end
	if side and has("leg") then return "leg?" end
	if has("chest") or has("ribcage") or has("torso") then return "chest" end
	if has("spine") or has("abdomen") or has("waist") then return "spine" end
	if has("pelvis") or has("hips") or has("hip") then return "hips" end
	return nil
end

-- ------------------------------------------------------------ small math

local function v3(x, y, z) return Vec3.new(x, y, z) end

local function sub(a, b) return v3(a.x - b.x, a.y - b.y, a.z - b.z) end
local function add(a, b) return v3(a.x + b.x, a.y + b.y, a.z + b.z) end
local function mul(a, s) return v3(a.x * s, a.y * s, a.z * s) end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function cross(a, b)
	return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end
local function len(a) return math.sqrt(dot(a, a)) end
local function norm(a)
	local m = len(a)
	if m < 1e-8 then return v3(0, 1, 0), 0 end
	return mul(a, 1.0 / m), m
end

-- The rotation taking `from` onto `to`, both unit.
local function swing(from, to)
	local d = dot(from, to)
	if d > 0.99999 then return Quaternion.new() end
	if d < -0.99999 then
		-- opposite: any perpendicular axis will do
		local axis = cross(from, v3(1, 0, 0))
		if len(axis) < 1e-4 then axis = cross(from, v3(0, 0, 1)) end
		-- norm() returns the unit vector AND the length; the extra return has
		-- to be dropped here or it lands in the angle argument.
		local unit = norm(axis)
		return Quaternion.new(unit, math.pi)
	end
	local axis, s = norm(cross(from, to))
	return Quaternion.new(axis, math.atan(s, d))
end

-- A rotation matrix's columns, as a quaternion. Mirrors
-- Matrix::ConvertToQuaternion exactly (that one reads m[0],m[4],m[8] as the
-- first ROW, i.e. the storage is column-major), but takes the basis vectors
-- directly so nothing has to reach into the matrix's element array - which
-- Lua cannot do.
local function quatFromBasis(X, Y, Z)
	local m11, m21, m31 = X.x, X.y, X.z
	local m12, m22, m32 = Y.x, Y.y, Y.z
	local m13, m23, m33 = Z.x, Z.y, Z.z
	local tr = m11 + m22 + m33
	if tr > 0 then
		local s = 0.5 / math.sqrt(tr + 1.0)
		return Quaternion.new(0.25 / s, (m32 - m23) * s, (m13 - m31) * s, (m21 - m12) * s)
	elseif m11 > m22 and m11 > m33 then
		local s = 2.0 * math.sqrt(1.0 + m11 - m22 - m33)
		return Quaternion.new((m32 - m23) / s, 0.25 * s, (m12 + m21) / s, (m13 + m31) / s)
	elseif m22 > m33 then
		local s = 2.0 * math.sqrt(1.0 + m22 - m11 - m33)
		return Quaternion.new((m13 - m31) / s, (m12 + m21) / s, 0.25 * s, (m23 + m32) / s)
	end
	local s = 2.0 * math.sqrt(1.0 + m33 - m11 - m22)
	return Quaternion.new((m21 - m12) / s, (m13 + m31) / s, (m23 + m32) / s, 0.25 * s)
end

-- World transform of a bone: the owner's world matrix times the bone's
-- model-space one, decomposed into a position in metres and a pure rotation.
--
-- Decomposed BY HAND, because the two matrix accessors that look like they do
-- this do not. Matrix::GetScale() returns the diagonal and Matrix::GetRotation()
-- divides by whatever it is handed - correct only for a matrix with no
-- rotation in it. A bone matrix is nothing but rotation, and the diagonal of a
-- rotation matrix is three cosines: for this project's own rig they read as
-- low as 0.000, so "dividing the scale out" divided by zero, the quaternion
-- came back NaN, and the first setBoneWorld() call turned the entire skeleton
-- into NaN. The mesh then renders as nothing at all - no warning, no error,
-- just a character that stops existing the instant it dies.
--
-- A column's LENGTH is its scale. Transforming the basis vectors recovers the
-- columns, since Matrix * Vec3 is the full affine transform.
local function boneWorld(inst, ownerWorld, boneId)
	local m = ownerWorld * inst:getBoneGlobal(boneId)
	local o = m:getTranslation()
	local X, lx = norm(sub(m * v3(1, 0, 0), o))
	local Y, ly = norm(sub(m * v3(0, 1, 0), o))
	local Z, lz = norm(sub(m * v3(0, 0, 1), o))
	if lx < 1e-6 or ly < 1e-6 or lz < 1e-6 then
		-- A collapsed frame. Some exporters leave scene nodes in the bone
		-- array (this project's own .p3dm carries three, one of them a light),
		-- and they have no basis at all.
		return o, Quaternion.new(), false
	end
	return o, quatFromBasis(X, Y, Z), true
end

-- ------------------------------------------------------------------ rig
--
-- The layout a ragdoll is made of. `parent` is the part a joint hangs it from,
-- `tip` the part (or bone role) whose origin marks the far end of the segment,
-- and the rest is how the joint is allowed to move. Cone and twist are
-- radians; a "hinge" part uses a revolute joint with a one-way limit, which is
-- what makes a knee read as a knee and not as a squid.
-- `tip` names the parts whose bone marks the far end of this segment (first
-- one that exists wins); `tipRole` does the same for a bone that never gets a
-- body of its own, like the neck. A part with neither is a leaf - a head, a
-- hand, a foot - and its far end is measured from whatever hangs below it in
-- the skeleton.
--
-- The cones are wide on purpose, and the test for "wide enough" is measurable:
-- jointAngles() counts how many joints come to rest AT their stop. Every one
-- that does is a joint whose LIMIT is holding the corpse's shape instead of
-- gravity, and that is what a stiff-looking body is. At 0.55 on the chest and
-- 0.85 on the neck, four or five of fifteen sat on their stops in every
-- settled corpse measured - the torso and the neck among them, which are the
-- two a viewer reads first.
--
-- The other reason they are wide: a joint's limit is measured from the pose it
-- was BUILT in, and that pose is whatever the character was doing when it was
-- killed - mid-stride, usually, not a neutral. A rig limited to what a living
-- hip can do from anatomical neutral also finds a stable tripod and kneels on
-- it: knees down, one hand down, torso up, until it is recycled.
local LAYOUT = {
	{ part = "hips",      role = "hips",     parent = nil,        shape = "box",     mass = 0.14,  tip = { "spine", "chest" } },
	{ part = "spine",     role = "spine",    parent = "hips",     shape = "box",     mass = 0.14,  tip = { "chest" },  cone = 1.00, twist = 0.80, tone = 1.4 },
	{ part = "chest",     role = "chest",    parent = "spine",    shape = "box",     mass = 0.20,  tipRole = { "neck", "head" }, cone = 0.95, twist = 0.75, tone = 1.4 },
	{ part = "head",      role = "head",     parent = "chest",    shape = "capsule", mass = 0.08,  cone = 1.25, twist = 1.10, tone = 1.2 },
	{ part = "upperarm",  role = "upperarm", parent = "chest",    shape = "capsule", mass = 0.028, tip = { "forearm" }, cone = 1.90, twist = 1.20, sided = true },
	{ part = "forearm",   role = "forearm",  parent = "upperarm", shape = "capsule", mass = 0.022, tip = { "hand" },    hinge = 2.40, hingeForward = true, cone = 0.80, sided = true },
	{ part = "hand",      role = "hand",     parent = "forearm",  shape = "capsule", mass = 0.006, cone = 1.30, twist = 0.80, tone = 0.5, sided = true },
	{ part = "thigh",     role = "thigh",    parent = "hips",     shape = "capsule", mass = 0.10,  tip = { "calf", "foot" }, cone = 1.90, twist = 0.80, sided = true },
	{ part = "calf",      role = "calf",     parent = "thigh",    shape = "capsule", mass = 0.045, tip = { "foot" },    hinge = 2.40, cone = 0.80, sided = true },
	{ part = "foot",      role = "foot",     parent = "calf",     shape = "capsule", mass = 0.014, cone = 1.50, twist = 0.70, sided = true },
}

-- Limb radius as a fraction of the segment's own length. Human proportions:
-- a 0.42 m thigh at 0.20 gives an 8 cm radius, which is about right.
local RADIUS = {
	head = 0.50, upperarm = 0.17, forearm = 0.13, hand = 0.38,
	thigh = 0.20, calf = 0.14, foot = 0.30,
}

-- A floor on each radius, as a fraction of the character's measured stature,
-- because a segment's own length is not always a fair measure of its
-- thickness. The head is the case that proves it: a head bone's segment has to
-- be EXTRAPOLATED (nothing hangs below a skull), and on this project's rig the
-- neck-to-head bone distance is 6 cm, so the extrapolation produced a head
-- capsule of radius 0.014 m carrying 5.8 kg - a marble with the mass of a
-- head. No volume to rest on, and an inertia tensor so small that the neck
-- joint flailed it. That one number is most of what "the ragdoll looks wrong"
-- was.
local MIN_RADIUS = {
	head = 0.090, upperarm = 0.040, forearm = 0.035, hand = 0.030,
	thigh = 0.070, calf = 0.050, foot = 0.040,
}

-- Bodies are built slightly shorter than the bone they stand for so that two
-- neighbours meeting at a joint do not start the simulation already touching.
-- A stack of boxes sharing a face jitters.
local SHRINK = 0.86

-- -------------------------------------------------------------- discovery

local function discover(inst)
	local n = inst:getNumberBones()
	if not n or n < 4 then return nil, "skeleton has " .. tostring(n) .. " bones" end

	local bones = {}
	for i = 0, n - 1 do
		local name = inst:getBoneName(i)
		bones[i] = {
			id = i,
			name = name,
			parent = inst:getBoneParent(i),
			flat = flatten(name),
			side = sideOf(name),
		}
	end

	-- depth, so ambiguities can be settled by "the one nearer the root"
	local function depthOf(i)
		local d, guard = 0, 0
		local p = bones[i].parent
		while p and p >= 0 and guard < 256 do
			d = d + 1; p = bones[p].parent; guard = guard + 1
		end
		return d
	end
	local children = {}
	for i = 0, n - 1 do
		bones[i].depth = depthOf(i)
		local p = bones[i].parent
		if p and p >= 0 then
			children[p] = children[p] or {}
			table.insert(children[p], i)
		end
	end

	-- role -> bone id, shallowest wins. "LeftHandIndex1" also matches "hand",
	-- so without the depth rule a rig could end up with five left hands.
	local found = {}
	local ambiguous = { ["arm?"] = {}, ["leg?"] = {} }
	local function key(role, side) return side and (role .. "." .. side) or role end

	for i = 0, n - 1 do
		local b = bones[i]
		if not isSkipped(b.flat) then
			local role = roleOf(b.flat, b.side)
			if role == "arm?" or role == "leg?" then
				local list = ambiguous[role]
				list[b.side or "?"] = list[b.side or "?"] or {}
				table.insert(list[b.side or "?"], i)
			elseif role then
				local k = key(role, b.side)
				if not found[k] or b.depth < bones[found[k]].depth then found[k] = i end
			end
		end
	end

	-- Mixamo: "LeftArm" is the upper arm; "LeftLeg" is the CALF, because the
	-- thigh is already spoken for by "LeftUpLeg". So a bare arm/leg fills
	-- whichever of the pair is still empty, shallowest first.
	for role, bySide in pairs(ambiguous) do
		for side, list in pairs(bySide) do
			table.sort(list, function(a, b) return bones[a].depth < bones[b].depth end)
			local slots = (role == "arm?") and { "upperarm", "forearm" } or { "thigh", "calf" }
			for _, id in ipairs(list) do
				for _, slot in ipairs(slots) do
					local k = key(slot, side)
					if not found[k] then found[k] = id break end
				end
			end
		end
	end

	-- The spine, walked rather than named. Start at the hips and follow the
	-- one child that is still torso; stop where the arms and the neck branch
	-- off. This is what makes Bip01 (Spine, Spine1) and Unreal (spine_01..03)
	-- and Rigify (spine, spine.001..005) all come out as "an abdomen and a
	-- chest" instead of needing a table per rig.
	local hips = found["hips"]
	if not hips then
		-- No bone said "pelvis". Whatever the two legs have in common IS the
		-- pelvis, anatomically, so take their lowest common ancestor. Their
		-- immediate parent is not enough: a rig can put a buttock bone on each
		-- side between the spine and the thigh (examples/assets/Model.p3dm
		-- does exactly that, "LeftAss"/"RightAss"), and then the thighs share
		-- no parent at all.
		local lt, rt = found["thigh.L"], found["thigh.R"]
		if lt and rt then
			local seen, c, guard = {}, lt, 0
			while c and c >= 0 and guard < 64 do seen[c] = true; c = bones[c].parent; guard = guard + 1 end
			c, guard = rt, 0
			while c and c >= 0 and guard < 64 do
				if seen[c] then hips = c break end
				c = bones[c].parent
				guard = guard + 1
			end
			-- the ancestor must not BE one of the legs
			if hips == lt or hips == rt then hips = bones[hips].parent end
		end
	end
	if not hips or hips < 0 then return nil, "no pelvis bone (and no pair of thighs to infer one from)" end

	local chain = {}
	local cur = hips
	for _ = 1, 16 do
		local nextId = nil
		for _, c in ipairs(children[cur] or {}) do
			local b = bones[c]
			if not isSkipped(b.flat) then
				local r = roleOf(b.flat, b.side)
				if r == "spine" or r == "chest" then nextId = c break end
			end
		end
		if not nextId then break end
		table.insert(chain, nextId)
		cur = nextId
	end

	-- Where the spine stops being a spine. Naming cannot answer this: Rigify
	-- calls the neck and the skull "spine.004" and "spine.005", so following
	-- the chain to its end puts the chest inside the head. The arms answer it
	-- structurally - the chest is, by definition, the bone the shoulders hang
	-- from - so walk up from an arm and take the first chain bone it meets.
	local inChain = {}
	for i, b in ipairs(chain) do inChain[b] = i end
	local chestIdx = #chain
	for _, k in ipairs({ "clavicle.L", "clavicle.R", "upperarm.L", "upperarm.R" }) do
		local arm = found[k]
		if arm then
			local cur, guard = bones[arm].parent, 0
			while cur and cur >= 0 and guard < 32 do
				if inChain[cur] then chestIdx = math.min(chestIdx, inChain[cur]) break end
				if cur == hips then chestIdx = 0 break end
				cur = bones[cur].parent
				guard = guard + 1
			end
		end
	end

	local chest = (chestIdx >= 1) and chain[chestIdx] or hips
	local spine = (chestIdx >= 2) and chain[1] or nil
	found["chest"] = chest
	found["spine"] = spine
	found["hips"] = hips

	-- Chain bones ABOVE the chest are the neck and the head, whatever they
	-- are called. This is the other half of the Rigify case: without it a
	-- spine.004/spine.005 rig gets no head body at all and the corpse's skull
	-- stays welded to its ribcage.
	if chestIdx < #chain then
		found["neck"] = found["neck"] or chain[chestIdx + 1]
		found["head"] = found["head"] or chain[#chain]
		if found["head"] == found["neck"] and #chain > chestIdx + 1 then
			found["head"] = chain[#chain]
		end
	end

	return { bones = bones, children = children, found = found, count = n }
end

-- Which bone marks the far end of a part's segment, from the LAYOUT entry.
-- Resolved once, at build time, and remembered: deriving it by scanning for
-- "some part whose parent is me" made the pelvis's far end depend on table
-- iteration order, and a pelvis that points down a thigh instead of up the
-- spine is a torso lying on its side.
local function tipBoneFor(e, side, resolved, found)
	for _, want in ipairs(e.tip or {}) do
		local k = side and (want .. "." .. side) or want
		if resolved[k] then return resolved[k] end
		if resolved[want] then return resolved[want] end
	end
	for _, role in ipairs(e.tipRole or {}) do
		local k = side and (role .. "." .. side) or role
		if found[k] then return found[k] end
	end
	return nil
end

-- The far end of a bone: the origin of the part that hangs off it, or - for a
-- head, a hand, a foot - the farthest child bone there is, or failing that an
-- extrapolation along the bone's own length.
local function tipOf(rig, inst, ownerWorld, boneId, childBoneId)
	local p0 = select(1, boneWorld(inst, ownerWorld, boneId))
	if childBoneId then
		return select(1, boneWorld(inst, ownerWorld, childBoneId))
	end
	local best, bestD = nil, 0
	for _, c in ipairs(rig.children[boneId] or {}) do
		local p = select(1, boneWorld(inst, ownerWorld, c))
		local d = len(sub(p, p0))
		if d > bestD then best, bestD = p, d end
	end
	if best and bestD > 1e-4 then return best end
	-- Nothing below it. Point it away from its parent by a quarter of the
	-- parent segment, which is roughly what a head or a foot is.
	local parent = rig.bones[boneId].parent
	if parent and parent >= 0 then
		local pp = select(1, boneWorld(inst, ownerWorld, parent))
		local d, m = norm(sub(p0, pp))
		if m > 1e-4 then return add(p0, mul(d, m * 0.35)) end
	end
	return add(p0, v3(0, 0.08, 0))
end

-- ------------------------------------------------------------------ build

-- Build the bodies. They come out static and parked; activate() is what puts
-- them on the character and hands them to the solver.
function Ragdoll.build(inst, owner, opts)
	opts = opts or {}
	if not inst or not owner then return nil, "need an animation instance and its GameObject" end
	if not physics then return nil, "no physics engine" end

	local rig, err = discover(inst)
	if not rig then return nil, err end

	local self = setmetatable({}, Ragdoll)
	self.inst = inst
	self.owner = owner
	self.rig = rig
	self.parts = {}          -- parent-first
	self.byName = {}
	self.joints = {}
	self.active = false
	self.totalMass = opts.mass or 70.0
	self.park = opts.park or PARK
	self.opts = opts

	local ownerWorld = owner:getWorldTransformation()
	local found = rig.found

	-- which bone each layout entry resolves to, per side
	local resolved = {}      -- partName -> boneId
	local sides = { "L", "R" }
	local order = {}

	local function partKey(e, side) return e.sided and (e.part .. "." .. side) or e.part end
	local function boneFor(e, side)
		if e.sided then return found[e.role .. "." .. side] end
		-- A rig with a neck and no head still gets a head body; it is the one
		-- substitution worth making, because a torso that ends at the
		-- shoulders looks decapitated the moment it falls over.
		if e.role == "head" then return found["head"] or found["neck"] end
		return found[e.role]
	end

	-- One body per bone. Two parts can land on the same bone - a rig whose
	-- arms hang straight off the pelvis has no chest of its own, so the chest
	-- resolves to the pelvis - and building both would put two bodies in the
	-- same place and then joint them to each other. LAYOUT order decides which
	-- one wins, so the torso keeps the pelvis and the chest is simply absent;
	-- everything that hung from the chest re-hangs on the pelvis below.
	local claimed = {}
	for _, e in ipairs(LAYOUT) do
		if e.sided then
			for _, s in ipairs(sides) do
				local b = boneFor(e, s)
				if b and not claimed[b] then
					claimed[b] = true
					resolved[partKey(e, s)] = b
					table.insert(order, { e = e, side = s })
				end
			end
		else
			local b = boneFor(e, nil)
			if b and not claimed[b] then
				claimed[b] = true
				resolved[e.part] = b
				table.insert(order, { e = e, side = nil })
			end
		end
	end

	if not resolved["hips"] then return nil, "no pelvis" end
	if #order < 4 then return nil, "only " .. #order .. " usable parts" end

	-- A part whose layout parent was not found re-hangs on the nearest
	-- ancestor that was, so a rig with no separate abdomen still joints its
	-- chest to its hips instead of floating.
	local function parentKeyOf(e, side)
		local p = e.parent
		local guard = 0
		while p and guard < 8 do
			local pe
			for _, x in ipairs(LAYOUT) do if x.part == p then pe = x break end end
			if not pe then return nil end
			local k = pe.sided and (p .. "." .. side) or p
			if resolved[k] then return k end
			p = pe.parent
			guard = guard + 1
		end
		return nil
	end

	-- the character's own left-right axis, for hinge fallbacks and box widths
	local hipSep = 0.0
	if resolved["thigh.L"] and resolved["thigh.R"] then
		local pl = select(1, boneWorld(inst, ownerWorld, resolved["thigh.L"]))
		local pr = select(1, boneWorld(inst, ownerWorld, resolved["thigh.R"]))
		hipSep = len(sub(pr, pl))
	end
	local shoulderSep = 0.0
	if resolved["upperarm.L"] and resolved["upperarm.R"] then
		local pl = select(1, boneWorld(inst, ownerWorld, resolved["upperarm.L"]))
		local pr = select(1, boneWorld(inst, ownerWorld, resolved["upperarm.R"]))
		shoulderSep = len(sub(pr, pl))
	end

	-- A stature that does not change with the pose: down one leg plus up the
	-- spine. Used only to keep a rig with no arms or no legs from producing
	-- nonsense widths.
	local stature = 0.0
	do
		local hp = select(1, boneWorld(inst, ownerWorld, resolved["hips"]))
		-- chest may be absent on a rig whose torso is a single bone
		local top = resolved["chest"] or found["head"] or found["neck"] or resolved["hips"]
		local cp = select(1, boneWorld(inst, ownerWorld, top))
		stature = len(sub(cp, hp))
		if resolved["thigh.L"] and resolved["calf.L"] then
			local a = select(1, boneWorld(inst, ownerWorld, resolved["thigh.L"]))
			local b = select(1, boneWorld(inst, ownerWorld, resolved["calf.L"]))
			stature = stature + len(sub(b, a))
			if resolved["foot.L"] then
				local f = select(1, boneWorld(inst, ownerWorld, resolved["foot.L"]))
				stature = stature + len(sub(f, b))
			end
		end
	end
	if stature < 1e-3 then return nil, "degenerate skeleton (zero size)" end
	if hipSep < 1e-4 then hipSep = stature * 0.18 end
	if shoulderSep < 1e-4 then shoulderSep = hipSep * 1.25 end
	self.stature = stature
	self.hipSep = hipSep
	self.shoulderSep = shoulderSep

	-- Now the bodies. Segment lengths are pose-invariant (a bone is rigid), so
	-- measuring them off whatever pose the character happens to be in right
	-- now is exact, not an approximation.
	for _, o in ipairs(order) do
		local e, side = o.e, o.side
		local key = partKey(e, side)
		local boneId = resolved[key]
		local pkey = parentKeyOf(e, side)

		local tipBone = tipBoneFor(e, side, resolved, found)

		local p0 = select(1, boneWorld(inst, ownerWorld, boneId))
		local p1 = tipOf(rig, inst, ownerWorld, boneId, tipBone)
		local dir, segLen = norm(sub(p1, p0))
		if segLen < 1e-4 then segLen = stature * 0.05 end

		local body, halfLen, radius, boxW, boxD, capH
		if e.shape == "box" then
			local halfW = (e.part == "chest") and (shoulderSep * 0.44) or (hipSep * 0.62)
			local halfD = hipSep * 0.42
			-- The pelvis box spans only pelvis-to-abdomen, which on most rigs
			-- is a few centimetres; floor it so a corpse has a backside to
			-- rest on rather than balancing on its spine.
			halfLen = math.max(segLen * 0.5 * SHRINK, halfW * 0.75)
			body = physics:createBox(halfW, halfLen, halfD, 0.0, false)
			radius = halfW
			boxW, boxD = halfW, halfD
		else
			radius = math.max(segLen * (RADIUS[e.part] or 0.15),
				stature * (MIN_RADIUS[e.part] or 0.022))
			-- A skull is not a segment between two joints, so its length comes
			-- from its own girth: the capsule spans a head's width along the
			-- neck-to-head direction, which also puts the body's centre in the
			-- middle of the head instead of at its base.
			if e.part == "head" then segLen = math.max(segLen, radius * 1.9) end
			local h = math.max(segLen * SHRINK - 2.0 * radius, segLen * 0.10)
			halfLen = h * 0.5 + radius
			capH = h
			body = physics:createCapsule(radius, h, 0.0, false)
		end
		if not body then return nil, "createBody failed for " .. key end

		local go = GameObject.new()
		go:setName("ragdoll_" .. key)
		go:setPosition(v3(0, self.park, 0))
		go:refreshTransformation()
		go:addComponent(body)
		scene:add(go)

		local p = {
			key = key, part = e.part, side = side, layout = e,
			bone = boneId, body = body, go = go, tipBone = tipBone,
			halfW = boxW, halfD = boxD, capsuleH = capH,
			parentKey = pkey,
			segLen = segLen, radius = radius, halfLen = halfLen,
			drive = { { bone = boneId } },
		}
		self.parts[#self.parts + 1] = p
		self.byName[key] = p
	end

	-- Bones with no body of their own that sit BETWEEN two parts - a neck
	-- between chest and head, a clavicle between chest and upper arm, the
	-- second of three spine bones - are pinned to the parent part. Left alone
	-- they would keep whatever local transform the animation stopped at, and
	-- the mesh would stretch across them; pinned to the parent they behave
	-- like the rigid piece of anatomy they are.
	local owned = {}
	for _, p in ipairs(self.parts) do owned[p.bone] = p end
	for _, p in ipairs(self.parts) do
		local parent = p.parentKey and self.byName[p.parentKey] or nil
		local stop = parent and parent.bone or -1
		local cur = rig.bones[p.bone].parent
		local guard = 0
		while cur and cur >= 0 and cur ~= stop and not owned[cur] and guard < 8 do
			local host = parent or p
			table.insert(host.drive, { bone = cur })
			owned[cur] = host
			cur = rig.bones[cur].parent
			guard = guard + 1
		end
	end
	-- ...and anything above the pelvis (a root bone carrying root motion)
	-- rides with the pelvis.
	do
		local hipsPart = self.byName["hips"]
		local cur = rig.bones[hipsPart.bone].parent
		local guard = 0
		while cur and cur >= 0 and not owned[cur] and guard < 8 do
			table.insert(hipsPart.drive, { bone = cur })
			owned[cur] = hipsPart
			cur = rig.bones[cur].parent
			guard = guard + 1
		end
	end

	-- Parents before children, always - and the parent that matters is the
	-- one in the SKELETON, not the one in the rig.
	--
	-- setBoneWorld() solves a bone's LOCAL transform against its parent's
	-- current global, so writing an ancestor AFTER a descendant drags the
	-- descendant off the body that was supposed to own it: its local is
	-- already fixed, and its parent has just moved. Ordering by rig depth is
	-- not enough, because the two hierarchies disagree - on this project's own
	-- human the thighs hang off Bip01_Spine while the ragdoll hangs them off
	-- the pelvis, so `thigh` and `spine` are both rig-depth 1 and table.sort
	-- put them in whichever order it felt like. Measured: the thigh bone
	-- ending up wherever the spine body had dragged it, so the thigh-to-calf
	-- distance - a rigid bone - wandered between 0.33 m and 0.48 m against a
	-- rest length of 0.42. That is what a limb coming off its socket looks
	-- like, and the joints were holding to half a millimetre the whole time.
	--
	-- So flatten every (body, bone) write into one list ordered by BONE depth.
	self.writes = {}
	for _, p in ipairs(self.parts) do
		for _, d in ipairs(p.drive) do
			self.writes[#self.writes + 1] = { part = p, entry = d, depth = rig.bones[d.bone].depth }
		end
	end
	table.sort(self.writes, function(a, b) return a.depth < b.depth end)

	-- Parts are still walked parent-first for jointing, which is a rig-tree
	-- question, not a skeleton one.
	local depthOfPart = {}
	local function partDepth(p)
		if depthOfPart[p.key] then return depthOfPart[p.key] end
		local d = 0
		if p.parentKey and self.byName[p.parentKey] then d = partDepth(self.byName[p.parentKey]) + 1 end
		depthOfPart[p.key] = d
		return d
	end
	table.sort(self.parts, function(a, b) return partDepth(a) < partDepth(b) end)

	-- Mass shares are renormalised over the parts that actually exist, so a
	-- rig with no arms still weighs what the caller asked for.
	local shareSum = 0
	for _, p in ipairs(self.parts) do shareSum = shareSum + (p.layout.mass or 0.05) end
	for _, p in ipairs(self.parts) do
		p.mass = self.totalMass * (p.layout.mass or 0.05) / shareSum
	end

	self:place(0, self.park, 0)
	return self
end

-- ------------------------------------------------------------- activation

-- The character's forward, taken from its feet. A foot points where a person
-- faces, in every rig, in every pose that is not mid-cartwheel - which makes
-- it the one direction a ragdoll can recover without being told the model's
-- authoring convention. It is needed to know which way a knee bends.
function Ragdoll:facing(ownerWorld)
	local sum, n = v3(0, 0, 0), 0
	for _, s in ipairs({ "L", "R" }) do
		local f = self.byName["foot." .. s]
		if f then
			local p0 = select(1, boneWorld(self.inst, ownerWorld, f.bone))
			local p1 = tipOf(self.rig, self.inst, ownerWorld, f.bone, nil)
			local d = sub(p1, p0)
			d.y = 0
			if len(d) > 1e-4 then sum = add(sum, d); n = n + 1 end
		end
	end
	if n == 0 then return nil end
	local d, m = norm(sum)
	if m < 1e-4 then return nil end
	return d
end

-- Put every body where the current pose says it belongs, and remember where
-- its bones sit inside it.
function Ragdoll:capture()
	local ownerWorld = self.owner:getWorldTransformation()
	local inst = self.inst

	for _, p in ipairs(self.parts) do
		local p0, boneRot = boneWorld(inst, ownerWorld, p.bone)

		local p1 = tipOf(self.rig, inst, ownerWorld, p.bone, p.tipBone)
		local dir, segLen = norm(sub(p1, p0))
		if segLen < 1e-5 then dir = v3(0, 1, 0) end
		-- Same override build() used, so the body is centred on the shape that
		-- was actually created rather than on the bone's tiny raw segment.
		if p.part == "head" then segLen = math.max(segLen, p.radius * 1.9) end

		-- Body pose: centred on the segment, long axis (+Y, which is how
		-- Box3D lays a capsule out and how the box half-extents are ordered)
		-- along the bone.
		local centre = add(p0, mul(dir, segLen * 0.5))
		local rot = swing(v3(0, 1, 0), dir)

		-- Roll the body about its own long axis so that its local +X points
		-- along the character's left-right line. Only the boxes care - a
		-- capsule is round - but a torso box that is deep where it should be
		-- wide reads as a plank.
		if self.sideAxis then
			local xAfter = rot * v3(1, 0, 0)
			local ref = self.sideAxis
			local proj = sub(ref, mul(dir, dot(ref, dir)))
			if len(proj) > 1e-4 then
				local r = norm(proj)
				local ang = math.atan(dot(cross(xAfter, r), dir), dot(xAfter, r))
				rot = Quaternion.new(dir, ang) * rot
			end
		end

		p.dir = dir
		p.origin = p0
		p.bodyPos = centre
		p.bodyRot = rot

		-- L and D: where each driven bone sits in this body's frame. A bone
		-- whose frame will not decompose is dropped rather than written: one
		-- bad quaternion through setBoneWorld propagates down the whole
		-- hierarchy and the mesh vanishes.
		local inv = rot:inverse()
		for _, d in ipairs(p.drive) do
			local bp, br, ok = boneWorld(inst, ownerWorld, d.bone)
			d.L = inv * sub(bp, centre)
			d.D = inv * br
			d.dead = not ok
		end
	end
end

-- Hand the rig to the solver.
--
--   opts.impulse   world-space push, applied to opts.at
--   opts.at        part key to push ("chest" by default)
--   opts.spin      extra angular jitter, rad/s (default 0.6)
function Ragdoll:activate(opts)
	opts = opts or {}
	if self.active then return true end
	if #self.parts == 0 then return false end

	local ownerWorld = self.owner:getWorldTransformation()

	-- the left-right axis, used for box roll and as a hinge fallback
	local tl, tr = self.byName["thigh.L"], self.byName["thigh.R"]
	if tl and tr then
		local pl = select(1, boneWorld(self.inst, ownerWorld, tl.bone))
		local pr = select(1, boneWorld(self.inst, ownerWorld, tr.bone))
		local d, m = norm(sub(pr, pl))
		if m > 1e-4 then self.sideAxis = d end
	end
	self.fwd = self:facing(ownerWorld)

	self:capture()

	-- Dynamic FIRST. A static body's transform is overwritten from its
	-- GameObject every frame (IPhysicsComponent::Update -> UpdateTransformations,
	-- which treats the GameObject as authoritative for anything with zero
	-- mass), so a rig placed while static is silently dragged back to wherever
	-- its parked GameObjects are as soon as the frame ends.
	for _, p in ipairs(self.parts) do
		p.body:setMass(p.mass)
		p.body:setRotationQuat(p.bodyRot)
		p.body:setPosition(p.bodyPos)
		-- Damping takes the brittleness off a fall, and too much of it holds a
		-- corpse in whatever shape it first landed in. 0.9 angular was enough
		-- to freeze a body on its knees.
		p.body:setLinearDamping(opts.linearDamping or self.opts.linearDamping or 0.35)
		p.body:setAngularDamping(opts.angularDamping or self.opts.angularDamping or 0.25)
		p.body:setGravityScale(opts.gravityScale or self.opts.gravityScale or 1.0)
		p.go:setPosition(p.bodyPos)
		p.go:refreshTransformation()
		p.body:activate()
	end

	-- Joints second: a joint records the two bodies' CURRENT transforms as its
	-- rest frames, so every body has to be in place before any of them exists.
	self.joints = {}
	self.jointsMade, self.jointsWanted = 0, 0
	local tone = opts.tone or self.opts.tone or 0.0
	local toneDamping = opts.toneDamping or self.opts.toneDamping or 1.0
	for _, p in ipairs(self.parts) do
		local parent = p.parentKey and self.byName[p.parentKey] or nil
		if parent then
			self.jointsWanted = self.jointsWanted + 1
			local anchor = p.origin           -- the joint is the bone's own origin
			local e = p.layout
			local h = 0
			if e.hinge then
				-- A knee or an elbow. The hinge axis is perpendicular to both
				-- segments, which a bent limb gives for free; the current bend
				-- angle then says how much travel is left in each direction,
				-- because the solver measures the limit from the pose the
				-- joint was created in, not from straight.
				local axis, s = norm(cross(parent.dir, p.dir))
				local bend = math.atan(s, dot(parent.dir, p.dir))
				if s < 0.15 then
					-- A straight limb: the cross product says nothing about
					-- which way it hinges, so fall back on anatomy. Rotating
					-- a segment about (fwd x dir) swings it BACKWARDS, since
					-- (fwd x dir) x dir = -fwd, and that is a knee. An elbow
					-- goes the other way - the hand comes up in front - so the
					-- arm flips the axis.
					if self.fwd then
						local a = cross(self.fwd, p.dir)
						if e.hingeForward then a = cross(p.dir, self.fwd) end
						axis = norm(a)
						bend = 0
					else
						axis = nil
					end
				end
				if axis then
					h = physics:createRevoluteJoint(parent.body, p.body, anchor, axis,
						-bend - 0.10, math.max(e.hinge - bend, 0.20))
				end
				if h == 0 then
					-- No usable axis. A tight cone is a worse knee than a
					-- hinge and a much better one than nothing.
					h = physics:createSphericalJoint(parent.body, p.body, anchor,
						e.cone or 0.6, p.dir, -0.4, 0.4)
				end
			else
				local twist = e.twist or 0
				h = physics:createSphericalJoint(parent.body, p.body, anchor,
					e.cone or 0.8, p.dir, -twist, twist)
			end
			-- Where this joint's anchor sits in each body's own frame. The
			-- solver is supposed to keep these two points on top of each
			-- other for ever; jointError() below says whether it does.
			local ip = parent.bodyRot:inverse()
			p.anchorInParent = ip * sub(anchor, parent.bodyPos)
			p.anchorInSelf = p.bodyRot:inverse() * sub(anchor, p.bodyPos)
			-- the child's long axis in the parent's frame, at rest
			p.restSwing = ip * (p.bodyRot * v3(0, 1, 0))
			if h ~= 0 then
				-- Muscle tone. A corpse is not a bag of loose sticks: a body
				-- resists its own joints for a while after it stops driving
				-- them, and without any of that the limbs swing through their
				-- whole range on the first bounce and the thing reads as
				-- laundry. A soft spring back toward the pose it died in is
				-- the standard way to buy that back, and it costs one call.
				if tone > 0 then physics:setJointSpring(h, tone * (e.tone or 1.0), toneDamping) end
				self.jointsMade = self.jointsMade + 1
				table.insert(self.joints, h)
			end
		end
	end

	-- The animation must stop, or SkeletonAnimation::Update() will overwrite
	-- every bone this rig writes. A paused instance is skipped entirely.
	pcall(function() self.inst:pause() end)

	-- Push.
	--
	-- `atPoint` is where the shot actually landed, and it changes the whole
	-- character of the result: the impulse goes into the part nearest that
	-- point, AT that point, so it turns the body about the hit instead of
	-- shoving it uniformly. A head shot snaps the head round and the body
	-- follows; a hit to the hip spins the corpse down on that side. Pushing
	-- the chest through its centre of mass every time - which is all this
	-- could do before - reads as "fell over", never as "was shot".
	self.hitPart = nil
	if opts.impulse then
		local target, point = nil, opts.atPoint
		if point then
			-- Nearest by VOLUME, not by centre. A body is a capsule or a box
			-- lying along its limb, so the distance that matters is to its
			-- axis and then minus its radius: measuring to centres alone hands
			-- a chest shot to whichever arm happens to be swinging past, since
			-- an arm's centre can sit closer to the impact than the middle of
			-- a long torso box does.
			local bestD
			for _, p in ipairs(self.parts) do
				local half = math.max((p.halfLen or 0) - (p.radius or 0), 0)
				local rel = sub(point, p.bodyPos)
				local t = dot(rel, p.dir)
				if t > half then t = half elseif t < -half then t = -half end
				local d = len(sub(rel, mul(p.dir, t))) - (p.radius or 0)
				if not bestD or d < bestD then bestD, target = d, p end
			end
		end
		target = target or self.byName[opts.at or "chest"] or self.byName["chest"] or self.parts[1]
		self.hitPart = target.key
		if point then
			target.body:applyImpulseAtPoint(opts.impulse, point)
		else
			target.body:applyCentralImpulse(opts.impulse)
		end
	end
	local spin = opts.spin or 0.6
	if spin > 0 then
		for _, p in ipairs(self.parts) do
			p.body:setAngularVelocity(v3(
				(math.random() * 2 - 1) * spin,
				(math.random() * 2 - 1) * spin * 0.7,
				(math.random() * 2 - 1) * spin))
		end
	end

	self.active = true
	self:update()
	return true
end

-- Copy every body's pose onto the bones it carries. Call once a frame while
-- active; nothing else moves the mesh.
function Ragdoll:update()
	if not self.active then return end
	local inst = self.inst
	local w = self.writes
	local lastPart, P, R = nil, nil, nil
	for i = 1, #w do
		local it = w[i]
		-- One body read per run of writes that share a body. The list is
		-- ordered by bone depth, so a body with several bones is usually
		-- contiguous, and re-reading it would cost two round trips per bone.
		if it.part ~= lastPart then
			lastPart = it.part
			P = it.part.body:getPosition()
			R = it.part.body:getRotation()
		end
		local e = it.entry
		if not e.dead then
			inst:setBoneWorld(e.bone, add(P, R * e.L), R * e.D)
		end
	end
	inst:refreshSkinning()
end

-- Does what update() writes actually land where it was asked to? Compares, per
-- part, the bone transform reconstructed from the body against the one the
-- skeleton reports after the write. Anything above a millimetre means the
-- capture or setBoneWorld disagree about a space, which is invisible in a
-- screenshot (the mesh just stops existing) and obvious here.
-- Bone lengths are invariant: a bone is a rigid stick between two joints, so
-- the distance from any bone to its parent must be exactly what it was in the
-- rest pose, in every frame, for ever. Anything else IS a detached limb -
-- "parts of the body aren't tied to the body" is a measurable statement, and
-- this measures it.
--
-- Call baselineLengths() once at activation and stretch() any frame after.
function Ragdoll:baselineLengths()
	local ownerWorld = self.owner:getWorldTransformation()
	self.rest = {}
	for i = 0, self.rig.count - 1 do
		local parent = self.rig.bones[i].parent
		if parent and parent >= 0 then
			local a = select(1, boneWorld(self.inst, ownerWorld, i))
			local b = select(1, boneWorld(self.inst, ownerWorld, parent))
			self.rest[i] = len(sub(a, b))
		end
	end
end

function Ragdoll:stretch(tag)
	if not self.rest then return 0 end
	local ownerWorld = self.owner:getWorldTransformation()
	local worst, worstName, worstRest, worstNow = 0, "-", 0, 0
	local total, n = 0, 0
	for i = 0, self.rig.count - 1 do
		local r = self.rest[i]
		if r and r > 1e-4 then
			local parent = self.rig.bones[i].parent
			local a = select(1, boneWorld(self.inst, ownerWorld, i))
			local b = select(1, boneWorld(self.inst, ownerWorld, parent))
			local now = len(sub(a, b))
			local e = math.abs(now - r)
			total = total + e; n = n + 1
			if e > worst then
				worst, worstName, worstRest, worstNow = e, self.rig.bones[i].name, r, now
			end
		end
	end
	echo(string.format("[STRETCH] %s worst %s rest %.3f now %.3f (off %.3f m) mean %.4f over %d bones",
		tostring(tag), worstName, worstRest, worstNow, worst, n > 0 and total / n or 0, n))
	return worst
end

-- How far the two bodies sharing a joint have drifted apart at that joint.
-- This is the number that separates "the solver is not holding the rig
-- together" from "the rig is held together and my bone offsets are wrong":
-- a bone length that changes while this stays at zero means the offsets.
function Ragdoll:jointError(tag)
	local worst, worstKey = 0, "-"
	for _, p in ipairs(self.parts) do
		local parent = p.parentKey and self.byName[p.parentKey] or nil
		if parent and p.anchorInParent then
			local a = add(parent.body:getPosition(), parent.body:getRotation() * p.anchorInParent)
			local b = add(p.body:getPosition(), p.body:getRotation() * p.anchorInSelf)
			local e = len(sub(a, b))
			if e > worst then worst, worstKey = e, p.key end
		end
	end
	echo(string.format("[JOINTERR] %s worst %s %.4f m", tostring(tag), worstKey, worst))
	return worst
end

function Ragdoll:verify(tag)
	local ownerWorld = self.owner:getWorldTransformation()
	local worst, worstKey, worstRot, n = -1, "-", 0, 0
	for _, p in ipairs(self.parts) do
		local P = p.body:getPosition()
		local R = p.body:getRotation()
		for _, d in ipairs(p.drive) do
		  if not d.dead then
			n = n + 1
			local wantPos = add(P, R * d.L)
			local wantRot = R * d.D
			local gotPos, gotRot = boneWorld(self.inst, ownerWorld, d.bone)
			local e = len(sub(gotPos, wantPos))
			local dotq = math.abs(wantRot.w * gotRot.w + wantRot.x * gotRot.x
				+ wantRot.y * gotRot.y + wantRot.z * gotRot.z)
			if e > worst then worst, worstKey, worstRot = e, self.rig.bones[d.bone].name, dotq end
		  end
		end
	end
	echo(string.format("[RAGDOLL] verify %s: %d bones, worst %s off by %.4f m (|q.q|=%.4f)",
		tostring(tag), n, worstKey, worst, worstRot))
	return worst
end

-- Where the rig ended up, so a caller can keep its own idea of the corpse's
-- position (for culling, for a pool, for a footstep sound) in step.
function Ragdoll:position()
	local p = self.byName["hips"] or self.parts[1]
	if not p then return v3(0, 0, 0) end
	return p.body:getPosition()
end

-- ------------------------------------------------------------------ impact
--
-- A hit on a character that is still ALIVE. The ragdoll only ever answered the
-- question "what does a body do when it stops being driven"; this answers the
-- other one, which is what a player actually sees most of the time - four
-- hits landing before the fifth kills. Without it a shot enemy keeps walking
-- as though nothing touched it, and the only feedback in the whole game is
-- the health bar going down.
--
-- It is not physics. The clip keeps playing and owns the pose; this leans the
-- torso away from the shot on top of it, hard on the attack and softer coming
-- back, with the head whipping a little further when the hit was high. Bones
-- below a written bone follow it for free - their locals are untouched - so
-- writing the spine and the chest carries the arms and the head with them.

local PUNCH_ATTACK = 0.045   -- seconds to reach full lean
local PUNCH_DECAY  = 0.34    -- and to come back out of it
local MAX_PUNCH    = 0.80    -- radians at full strength, before per-bone weight

-- Debug only, and a GLOBAL on purpose: every loadfile() of this module returns
-- a fresh table, so a field on the module would not be shared with the copy
-- enemies.lua holds. Slows the reaction down so its shape can be seen - a hit
-- lasts about a third of a second, which a 4 fps viewport readback resolves as
-- a single frame and a still cannot show at all.

-- Which part of the rig a world point is nearest, using the LIVE pose - the
-- bodies' own positions are only meaningful once the ragdoll has been
-- activated, and this has to work on a character that is still walking.
function Ragdoll:nearestPartAt(point)
	local ownerWorld = self.owner:getWorldTransformation()
	local best, bestD
	for _, p in ipairs(self.parts) do
		local p0 = select(1, boneWorld(self.inst, ownerWorld, p.bone))
		local p1 = tipOf(self.rig, self.inst, ownerWorld, p.bone, p.tipBone)
		local seg = sub(p1, p0)
		local L2 = dot(seg, seg)
		local t = (L2 > 1e-8) and (dot(sub(point, p0), seg) / L2) or 0
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
		local d = len(sub(point, add(p0, mul(seg, t)))) - (p.radius or 0)
		if not bestD or d < bestD then bestD, best = d, p end
	end
	return best
end

-- What moves when a given part is hit. Each entry is a bone role and how hard
-- it turns, parent first; every bone rotates about its OWN joint, so whatever
-- hangs below it follows.
--
-- This table is the whole point of the feature. An earlier version leaned the
-- torso no matter where the bullet landed, which meant that from any distance
-- the only thing you ever saw move was the head - shoot someone in the leg,
-- watch their head snap. A hit has to move the thing that was hit.
local PUNCH_CHAINS = {
	head     = { { "head", 1.00 }, { "chest", 0.28 } },
	neck     = { { "head", 1.00 }, { "chest", 0.28 } },
	chest    = { { "chest", 0.85 }, { "spine", 0.45 }, { "head", 0.40 } },
	spine    = { { "spine", 0.85 }, { "chest", 0.35 }, { "head", 0.25 } },
	hips     = { { "hips", 0.55 }, { "spine", 0.40 } },
	upperarm = { { "upperarm", 1.00 }, { "forearm", 0.55 }, { "chest", 0.22 } },
	forearm  = { { "forearm", 1.00 }, { "upperarm", 0.45 } },
	hand     = { { "hand", 1.00 }, { "forearm", 0.55 } },
	thigh    = { { "thigh", 1.00 }, { "calf", 0.60 }, { "hips", 0.22 } },
	calf     = { { "calf", 1.00 }, { "thigh", 0.45 } },
	foot     = { { "foot", 1.00 }, { "calf", 0.40 } },
}

-- `dir` is the direction the shot was travelling, `strength` roughly 0..1.
function Ragdoll:punch(hitPoint, dir, strength)
	if self.active then return end          -- dead; physics owns the bones
	local d = norm(v3(dir.x, 0, dir.z))
	if len(d) < 1e-4 then return end

	-- Which part took it. Without a hit point there is nothing to aim at, so
	-- fall back to the chest.
	local part = hitPoint and self:nearestPartAt(hitPoint) or self.byName["chest"]
	if not part then return end
	local chain = PUNCH_CHAINS[part.part]
	if not chain then return end

	-- Resolve the roles to bone ids once, on the side that was hit, and drop
	-- anything this rig does not have.
	self.punch_bones = {}
	for _, e in ipairs(chain) do
		local key = e[1]
		local p = self.byName[key] or (part.side and self.byName[key .. "." .. part.side])
		if not p and part.side then p = self.byName[key .. "." .. part.side] end
		if p then
			self.punch_bones[#self.punch_bones + 1] =
				{ bone = p.bone, w = e[2], depth = self.rig.bones[p.bone].depth }
		end
	end
	if #self.punch_bones == 0 then return end
	-- Parents before children: setBoneWorld solves a bone against its parent's
	-- CURRENT transform, so a child written first is solved against a parent
	-- that then turns out from under it.
	table.sort(self.punch_bones, function(x, y) return x.depth < y.depth end)

	self.punch_t = 0
	self.punch_dir = d
	self.punch_str = math.max(0.0, math.min(1.5, strength or 1.0))
	self.punch_key = part.key
end

function Ragdoll:isPunching() return self.punch_t ~= nil end
function Ragdoll:punchedPart() return self.punch_key end

-- The reaction's current strength, 0..1-ish, for anything outside the skeleton
-- that wants to move with it - a whole-body lean, a camera shake, a light.
-- Bone rotation alone is close to invisible on a character twenty metres away;
-- the silhouette has to move.
function Ragdoll:punchAmount()
	if self.punch_t == nil then return 0, 0, 0 end
	local t, env = self.punch_t, 0
	if t < PUNCH_ATTACK then
		env = t / PUNCH_ATTACK
	else
		local k = (t - PUNCH_ATTACK) / PUNCH_DECAY
		if k >= 1.0 then return 0, 0, 0 end
		env = math.exp(-3.4 * k) * (1.0 + 0.22 * math.sin(k * 11.0))
	end
	local d = self.punch_dir or v3(0, 0, 1)
	return env * (self.punch_str or 0), d.x, d.z
end

-- Call every frame while the character is alive. Returns true while a hit is
-- still playing out.
function Ragdoll:updatePunch(dt)
	if self.punch_t == nil or self.active then return false end
	self.punch_t = self.punch_t + dt * (RAGDOLL_PUNCH_SPEED or 1.0)
	local t = self.punch_t

	local env
	if t < PUNCH_ATTACK then
		env = t / PUNCH_ATTACK
	else
		local k = (t - PUNCH_ATTACK) / PUNCH_DECAY
		if k >= 1.0 then self.punch_t = nil; return false end
		-- Exponential fall-off with a wobble too weak to change the sign. An
		-- earlier version used (1-k)*cos(4.2k), which crosses zero at k=0.37 and
		-- then spends most of the reaction NEGATIVE - the body leaned INTO the
		-- shot, and the real peak lasted about 50 ms. Measured as env=-0.29
		-- through the middle of every hit.
		env = math.exp(-3.4 * k) * (1.0 + 0.22 * math.sin(k * 11.0))
	end

	local amount = env * self.punch_str * MAX_PUNCH
	local ownerWorld = self.owner:getWorldTransformation()
	-- Turn about the horizontal axis perpendicular to the shot, so everything
	-- travels the way the bullet was travelling.
	local axis = norm(cross(v3(0, 1, 0), self.punch_dir))
	if len(axis) < 1e-4 then return true end

	-- Each bone turns about its OWN joint, which is what a joint does; the
	-- bone does not move, and everything below it swings with it.
	for _, e in ipairs(self.punch_bones) do
		local q = Quaternion.new(axis, amount * e.w)
		local p, r = boneWorld(self.inst, ownerWorld, e.bone)
		self.inst:setBoneWorld(e.bone, p, q * r)
	end
	self.inst:refreshSkinning()
	return true
end

function Ragdoll:clearPunch() self.punch_t = nil end

-- ---------------------------------------------------------------- teardown

-- Move every body somewhere as a rigid group, static. Used for parking.
function Ragdoll:place(x, y, z)
	for _, p in ipairs(self.parts) do
		p.body:setMass(0)
		p.body:cleanForces()
		p.body:setLinearVelocity(v3(0, 0, 0))
		p.body:setAngularVelocity(v3(0, 0, 0))
		p.go:setPosition(v3(x, y, z))
		p.go:setRotation(v3(0, 0, 0))
		p.go:refreshTransformation()
		p.body:setRotation(v3(0, 0, 0))
		p.body:setPosition(v3(x, y, z))
	end
end

function Ragdoll:deactivate()
	for _, h in ipairs(self.joints or {}) do physics:destroyJoint(h) end
	self.joints = {}
	self:place(0, self.park, 0)
	self.active = false
end

function Ragdoll:destroy()
	self:deactivate()
	for _, p in ipairs(self.parts) do
		pcall(function()
			p.go:removeComponent(p.body)
			scene:remove(p.go)
		end)
	end
	self.parts = {}
	self.byName = {}
end

-- What the rig came out as, for a log line. Worth printing once per model:
-- it is the fastest way to see that a skeleton was read the way you meant.
-- Every body's actual dimensions, which is the thing a screenshot cannot tell
-- you: the mesh follows the bodies exactly, so if the corpse looks wrong while
-- the bone lengths are rigid, the BODIES are the wrong size or in the wrong
-- place.
-- How far each joint has actually swung from the pose it was built in, against
-- the cone it was given. Bone lengths being rigid only says the rig is not
-- coming apart; this says whether it is bending into shapes a body cannot make.
-- A body's long axis is +Y in its own frame by construction, so the swing is
-- the angle between the child's axis now and at rest, both measured in the
-- PARENT's frame - exactly the quantity b3's cone limit constrains.
function Ragdoll:jointAngles(tag)
	local worst, worstKey, worstCone = -1, "-", 0
	local atLimit, total = 0, 0
	local lines = {}
	for _, p in ipairs(self.parts) do
		local parent = p.parentKey and self.byName[p.parentKey] or nil
		if parent and p.restSwing then
			local vNow = parent.body:getRotation():inverse() * (p.body:getRotation() * v3(0, 1, 0))
			local d = dot(vNow, p.restSwing)
			if d > 1 then d = 1 elseif d < -1 then d = -1 end
			local swing = math.acos(d)
			local cone = p.layout.hinge and (p.layout.hinge + 0.2) or (p.layout.cone or 0.8)
			local over = swing - cone
			lines[#lines + 1] = string.format("%s %.2f/%.2f", p.key, swing, cone)
			-- A joint resting AT its stop means the limit is holding the
			-- corpse's shape, not gravity. That reads as a stiff body, and it
			-- is the one thing in this rig that a screenshot cannot show but a
			-- number can. A hinge sitting at 0 (a straight knee) is fine; a
			-- cone sitting at its maximum is not.
			if not p.layout.hinge and swing > cone - 0.05 then atLimit = atLimit + 1 end
			total = total + 1
			if over > worst then worst, worstKey, worstCone = over, p.key, cone end
		end
	end
	echo(string.format("[SWING] %s AT-LIMIT %d/%d | worst %s over by %.2f rad (limit %.2f) | %s",
		tostring(tag), atLimit, total, worstKey, worst, worstCone, table.concat(lines, " ")))
	return atLimit
end

-- Draw the collision bodies themselves, as primitives parented to the same
-- GameObjects the solver drives. The editor's own physics debug draw goes into
-- a forward overlay that a deferred viewport never composites, so this is the
-- only way to SEE the rig - and seeing it is the difference between "the
-- corpse looks wrong" and "the head body is a 1.4 cm marble".
--
-- Half-extents and capsule dimensions here are the same numbers handed to
-- physics:createBox/createCapsule, so anything that does not line up with the
-- mesh is a real mismatch, not an artefact of the drawing.
function Ragdoll:showBodies(on)
	if on == false then
		for _, p in ipairs(self.parts) do
			if p.debugRC then pcall(function() p.go:removeComponent(p.debugRC) end); p.debugRC = nil end
		end
		return
	end
	local COLOUR = {
		hips = { 0.95, 0.45, 0.10 }, spine = { 0.95, 0.70, 0.10 }, chest = { 0.15, 0.45, 0.95 },
		head = { 0.95, 0.90, 0.20 }, upperarm = { 0.20, 0.80, 0.30 }, forearm = { 0.10, 0.95, 0.75 },
		hand = { 0.85, 0.20, 0.35 }, thigh = { 0.60, 0.30, 0.90 }, calf = { 0.90, 0.35, 0.70 },
		foot = { 0.40, 0.40, 0.95 },
	}
	for _, p in ipairs(self.parts) do
		if not p.debugRC then
			local c = COLOUR[p.part] or { 1, 1, 1 }
			local mat = GenericShaderMaterial.new(ShaderUsage.Color | ShaderUsage.Diffuse
				| ShaderUsage.DeferredRenderer_Gbuffer)
			mat:setColor(Vec4.new(c[1], c[2], c[3], 1.0))
			local shape
			if p.layout.shape == "box" then
				shape = Cube.new(p.halfW or p.radius, p.halfLen, p.halfD or p.radius)
			else
				-- Capsule's `height` is the span between the cap centres, the same
				-- convention Box3DPhysics uses when it builds the collision shape.
				shape = Capsule.new(p.radius, p.capsuleH or (p.halfLen * 2 - p.radius * 2), 6, 10, 6, true)
			end
			p.debugRC = RenderingComponent.new(shape, mat)
			p.go:addComponent(p.debugRC)
		end
	end
end

-- Does the GameObject the solver writes back to actually match the body?
-- Box3DPhysics::UpdateTransformations pushes a dynamic body's pose into its
-- GameObject as EULER ANGLES (FromB3Quat(q).GetEulerFromQuaternion()), and the
-- GameObject rebuilds a matrix from those. If that round trip is lossy, then
-- anything drawn from the GameObject - including showBodies() - is in a
-- different place from the body it claims to show, while the mesh (driven
-- straight off body:getRotation()) is fine. Worth knowing which of the two is
-- lying before believing a picture.
function Ragdoll:goVsBody(tag)
	local worstP, worstA, keyP, keyA = 0, 0, "-", "-"
	for _, p in ipairs(self.parts) do
		local bp = p.body:getPosition()
		local gp = p.go:getWorldPosition()
		local dp = len(sub(bp, gp))
		if dp > worstP then worstP, keyP = dp, p.key end
		-- angle between the two orientations, via the axis each maps +Y to
		local bq = p.body:getRotation()
		local gm = p.go:getWorldTransformation()
		local o = gm:getTranslation()
		local gy = norm(sub(gm * v3(0, 1, 0), o))
		local by = bq * v3(0, 1, 0)
		local d = dot(gy, by)
		if d > 1 then d = 1 elseif d < -1 then d = -1 end
		local ang = math.acos(d)
		if ang > worstA then worstA, keyA = ang, p.key end
	end
	echo(string.format("[GOVSBODY] %s worst pos %s %.4f m | worst angle %s %.3f rad (%.1f deg)",
		tostring(tag), keyP, worstP, keyA, worstA, worstA * 180 / math.pi))
	return worstP, worstA
end

function Ragdoll:dumpBodies()
	for _, p in ipairs(self.parts) do
		echo(string.format("[BODY] %-10s %-8s seg %.3f  radius %.3f  halfLen %.3f  mass %.2f  bone %s",
			p.key, p.layout.shape, p.segLen, p.radius, p.halfLen, p.mass,
			self.rig.bones[p.bone].name))
	end
	echo(string.format("[BODY] stature %.3f hipSep %.3f shoulderSep %.3f",
		self.stature or 0, self.hipSep or 0, self.shoulderSep or 0))
end

function Ragdoll:describe()
	local t = {}
	for _, p in ipairs(self.parts) do
		t[#t + 1] = string.format("%s<%s>", p.key, self.rig.bones[p.bone].name)
	end
	return string.format("%d bodies, %d/%d joints, stature %.2f: %s",
		#self.parts, self.jointsMade or 0, self.jointsWanted or 0,
		self.stature or 0, table.concat(t, " "))
end

-- Exposed for testing: rig discovery is the part that has to work on a
-- skeleton nobody here has seen, and it needs no physics, no GameObject and no
-- render device to exercise - just bone names and parents. See
-- assets/lua/tests/ragdoll_rig_test.lua.
Ragdoll._discover = discover
Ragdoll._sideOf = sideOf
Ragdoll._roleOf = roleOf
Ragdoll._flatten = flatten

return Ragdoll
