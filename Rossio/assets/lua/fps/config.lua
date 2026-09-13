-- assets/lua/fps/config.lua
-- Every tunable for the Rossio firefight in one place, plus the static
-- collision the player is resolved against.
--
-- The blockers are declared rather than derived from the scene because the
-- engine has no collision query for render meshes: physics rayCast only sees
-- physics bodies, and screenPick() is a per-triangle ray that is far too
-- expensive to run four times a frame for character movement.

local C = {}

-- ---------------------------------------------------------------- layout
C.HALF_LEN = 24.0        -- station spans x in [-24, 24]
C.PLAT_HZ = 4.0          -- island platform half-width in z
C.TRACK_Z = 7.25
C.TRACK_Y = -1.45
C.CEIL_Y = 4.60
C.FLOOR_Y = 0.0

-- ---------------------------------------------------------------- player
C.player = {
	eyeHeight = 1.68,
	crouchHeight = 1.05,
	radius = 0.36,
	walkSpeed = 4.3,
	sprintSpeed = 7.0,
	crouchSpeed = 2.1,
	accel = 26.0,
	friction = 12.0,
	jumpSpeed = 4.6,
	gravity = -17.0,
	lookSensitivity = 0.115,
	maxHealth = 100,
	regenDelay = 4.0,
	regenRate = 14.0,
	bobRate = 11.0,
	bobAmount = 0.035,
	startPos = { -18.5, 0.0, 1.2 },
	startYaw = -90.0,      -- degrees; looking down the platform toward +x
}

-- ---------------------------------------------------------------- weapon
C.weapon = {
	name = "P-38",
	damage = 26,
	headshotMultiplier = 2.4,
	fireInterval = 0.14,
	magSize = 14,
	reserveStart = 84,
	reloadTime = 1.55,
	range = 90.0,
	spread = 0.0045,          -- radians, hip
	spreadMoving = 0.019,
	-- Peak intensity of the muzzle point light. See weapon.lua's comment:
	-- anything near 1.0 whites out the whole frame, not just the muzzle.
	muzzleLight = 1.1,
	recoilPitch = 2.7,        -- degrees per shot
	recoilYaw = 0.55,
	recoilRecover = 7.0,
	kickBack = 0.10,          -- metres the viewmodel travels
	kickRecover = 12.0,
	-- Decals are process-wide and only ever appended to, so the script keeps
	-- its own budget and calls clearDecals() when it runs out.
	decalBudget = 48,
	decalSize = 0.16,
}

-- ---------------------------------------------------------------- enemies
C.enemy = {
	poolSize = 14,
	health = 46,
	speed = 2.35,
	sprintSpeed = 3.35,
	turnRate = 4.5,
	attackStagger = 0.55,   -- random spread on the first swing
	attackRange = 1.75,
	attackDamage = 9.0,
	attackInterval = 1.35,
	hitRadius = 0.42,
	height = 1.78,
	-- the human .p3dm is authored Z-up at 10x, so the mesh child carries
	-- rot(-90,0,0) and scale 0.1 and the root only ever yaws
	meshScale = 0.1,
	meshYawOffset = 0.0,
	-- Getting hit while still standing. All OFF: force belongs to the killing
	-- shot, not to every graze. The reaction itself exists and works - set any
	-- of these above zero to bring it back.
	--   hitPunch     bone flinch on the limb that was hit (see Ragdoll:punch)
	--   hitLean      how far the whole body tips away, radians
	--   hitKnockback shove along the shot, m/s at the start
	--   hitStagger   how long the advance is interrupted, seconds
	hitPunch = 0.0,
	hitLean = 0.0,
	hitKnockback = 0.0,
	hitKnockTime = 0.22,
	hitStagger = 0.0,
	-- Corpse physics. On death the rig in assets/lua/ragdoll.lua lays a body
	-- along every limb of the skeleton, joints them, and takes the mesh over
	-- bone by bone. These numbers are the whole ragdoll's, not one box's: the
	-- module splits the mass over the parts by anthropometric share, so the
	-- chest gets about a fifth of it and a hand about half a percent.
	corpseMass = 70.0,
	-- Applied to the CHEST, which sits above the rig's centre of mass, so a
	-- hit folds the body over its hips rather than sliding it. 30 on a ~14 kg
	-- chest is about 2 m/s - a shove, not a launch. Small on purpose: the
	-- floor collider only spans the platform, and a corpse thrown past its
	-- edge falls for ever (measured, at the old one-box impulse of 70:
	-- y going -6 -> -154 and still accelerating).
	corpseImpulse = 80.0,
	-- Drag and gravity for the corpse rig. With none, a 1.7 m body is flat in
	-- about four frames - technically correct free fall, and it reads as a
	-- snap rather than a fall. Angular damping is the one that matters most
	-- with fifteen joints: without it the limbs whip.
	-- Linear damping stops the corpse skidding a metre across the platform;
	-- ANGULAR damping is the one that must stay low, because that is what
	-- lets the body crumple instead of holding the shape it first landed in.
	corpseLinearDamping = 1.60,
	corpseAngularDamping = 0.25,
	corpseGravity = 1.0,
	-- Random spin at the moment of death, rad/s. A corpse that only pitches
	-- backwards reads as a hinge; this is the jitter that makes two kills in
	-- the same doorway land differently.
	corpseSpin = 1.1,
	-- Muscle tone: a soft spring on every joint pulling back toward the pose
	-- the enemy died in, in Hz. Zero is a completely limp rag, which reads as
	-- laundry rather than a body; too much and the corpse holds its death pose
	-- like a mannequin. The rig scales this per joint - a neck holds a head up
	-- harder than a wrist holds a hand.
	corpseTone = 1.6,
	corpseToneDamping = 1.0,
	deathSink = 0.55,
	deathTime = 2.6,
	corpseTime = 9.0,
}

-- The enemies are droids, not people: same rig and the same walk, but what
-- comes out of one when it dies is smoke and a shorting bus, not blood. This
-- flag is what deathfx.lua is gated on - turn it off and a kill is just the
-- ragdoll again, with no effect on top.
C.enemy.droid = true

-- ------------------------------------------------------------- death FX
-- See assets/lua/fps/deathfx.lua. Two emitters and a light per slot, taken
-- from a ring when a droid dies and handed back a few seconds later.
C.deathFX = {
	-- More slots than deaths that can plausibly overlap. Wave 5 sends twelve
	-- droids at once, but they die a shot apart and an effect only lasts
	-- about three seconds, so six is comfortable - and taking the oldest slot
	-- back is handled anyway (see DeathFX:take).
	slots = 6,
	-- Where on the corpse this comes out of. The ragdoll reports the HIPS
	-- position; the chest is roughly this far above it, and a plume from the
	-- chest is the one that reads as a hole in the torso.
	chestHeight = 0.35,

	-- Smoke. It runs for smokeTime and is then stopped, which lets the last
	-- of the plume age out instead of popping off.
	smokeTime = 2.60,
	smokeRate = 24.0,          -- particles/second while it runs

	-- Arcs. The first one is the blowout at the moment of death - wide, fast
	-- and along the shot; the rest are narrow whips off random points on the
	-- wreck, at intervals between arcMin and arcMax.
	arcTime = 1.90,
	arcMin = 0.05,
	arcMax = 0.18,
	arcCount = 14,              -- sparks per whip
	arcSpread = 0.30,          -- cone half-angle, radians
	arcSpeed = 5.0,
	blowCount = 30,
	blowSpeed = 9.0,
	jitter = 0.45,             -- metres a whip can start from the chest

	-- The arc light. Strobed by the whips rather than held on - a steady blue
	-- glow next to a spark shower reads as a lamp, not as a short. Intensity
	-- is in the same units as the station's fluorescents (1.25) and the
	-- muzzle flash (1.10).
	light = true,
	lightRadius = 2.60,
	lightIntensity = 1.35,
	lightDecay = 3.2,          -- how fast one crack fades, 1/seconds

	-- Held for this long after the last of it, so a slot is not recycled
	-- while its own smoke is still in the air.
	tail = 2.20,
}

C.waves = {
	{ count = 3,  interval = 2.40, speed = 1.70 },
	{ count = 6,  interval = 1.05, speed = 2.35 },
	{ count = 8,  interval = 0.90, speed = 2.55 },
	{ count = 10, interval = 0.75, speed = 2.80 },
	{ count = 12, interval = 0.60, speed = 3.05 },
}
C.waveBreak = 6.0

-- ------------------------------------------------------------- collision
-- Boxes are { minX, minZ, maxX, maxZ } in world space; cylinders are
-- { x, z, radius }. Only the horizontal footprint matters - nothing in the
-- station is low enough to walk over and high enough to walk under.
local function box(cx, cz, sx, sz)
	return { cx - sx * 0.5, cz - sz * 0.5, cx + sx * 0.5, cz + sz * 0.5 }
end

C.blockBoxes = {}
C.blockCylinders = {}

-- columns down the centre line
for _, x in ipairs({ -21, -15, -9, -3, 3, 9, 15, 21 }) do
	table.insert(C.blockCylinders, { x, 0.0, 0.62 })
end
-- benches, back to back either side of the columns
for _, x in ipairs({ -19.5, -13.5, -7.5, 1.5, 7.5, 13.5 }) do
	table.insert(C.blockBoxes, box(x, -1.55, 2.30, 0.70))
	table.insert(C.blockBoxes, box(x, 1.55, 2.30, 0.70))
end
-- bins
for _, x in ipairs({ -17.0, -5.0, 5.0, 17.0 }) do
	table.insert(C.blockBoxes, box(x, -2.6, 0.60, 0.80))
end
for _, x in ipairs({ -11.0, 11.0 }) do
	table.insert(C.blockBoxes, box(x, 2.6, 0.60, 0.80))
end
-- ticket hall
table.insert(C.blockBoxes, box(15.4, -1.3, 0.34, 1.60))
table.insert(C.blockBoxes, box(15.4, 0.0, 0.34, 1.60))
table.insert(C.blockBoxes, box(15.4, 1.3, 0.34, 1.60))
table.insert(C.blockBoxes, box(13.0, 3.55, 0.80, 0.58))
table.insert(C.blockBoxes, box(12.0, 3.55, 0.80, 0.58))
table.insert(C.blockBoxes, box(10.4, 3.6, 1.10, 0.76))
table.insert(C.blockBoxes, box(10.4, -3.6, 1.10, 0.76))
table.insert(C.blockBoxes, box(20.6, -2.2, 5.20, 3.40))   -- stairs
table.insert(C.blockBoxes, box(20.2, 2.4, 5.20, 1.40))    -- escalator
-- barriers and crates (cover)
table.insert(C.blockBoxes, box(-15.0, -3.0, 2.00, 0.36))
table.insert(C.blockBoxes, box(-8.0, 3.0, 2.00, 0.36))
table.insert(C.blockBoxes, box(2.0, -3.0, 2.00, 0.36))
table.insert(C.blockBoxes, box(-21.5, 1.6, 0.36, 2.00))
table.insert(C.blockBoxes, box(-16.2, 2.7, 1.60, 1.40))
table.insert(C.blockBoxes, box(5.0, 2.95, 1.80, 1.00))
table.insert(C.blockBoxes, box(-2.5, -3.1, 0.95, 0.85))

-- ---------------------------------------------------------------- mood
C.flickerLights = { "L_4", "L_9", "L_15", "L_21", "LT_26", "L_2" }
C.trainDoorOpen = 0.62      -- metres each leaf slides

return C
