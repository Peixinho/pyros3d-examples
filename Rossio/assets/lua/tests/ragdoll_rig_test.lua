-- assets/lua/tests/ragdoll_rig_test.lua
--
-- Rig discovery against real skeletons, with no engine in the loop.
--
--   lua assets/lua/tests/ragdoll_rig_test.lua
--
-- Discovery is the half of the ragdoll that has to work on a model nobody has
-- seen, so it is the half worth testing away from a render device. Each case
-- below is a skeleton as it actually ships - the bone list and the parent
-- links - and the expectation is which bone ends up playing which part.

local here = arg and arg[0] and arg[0]:match("^(.*)/tests/[^/]+$") or "."
local Ragdoll = dofile(here .. "/ragdoll.lua")

-- A skeleton is written as { name, parentName }, root first.
local function instance(list)
    local id, byName = {}, {}
    for i, e in ipairs(list) do
        id[e[1]] = i - 1
        byName[i - 1] = e
    end
    return {
        getNumberBones = function() return #list end,
        getBoneName = function(_, i) return byName[i][1] end,
        getBoneParent = function(_, i)
            local p = byName[i][2]
            return p and id[p] or -1
        end,
    }, id
end

-- ---------------------------------------------------------------- rigs

-- 3ds max Biped, as exported into projects/MetroStation/assets/models/human.p3dm
local BIPED = {
    { "Bip01" }, { "Bip01_Pelvis", "Bip01" },
    { "Bip01_Spine", "Bip01_Pelvis" }, { "Bip01_Spine1", "Bip01_Spine" },
    { "Bip01_Neck", "Bip01_Spine1" }, { "Bip01_Head", "Bip01_Neck" },
    { "Bip01_L_Clavicle", "Bip01_Spine1" }, { "Bip01_L_UpperArm", "Bip01_L_Clavicle" },
    { "Bip01_L_Forearm", "Bip01_L_UpperArm" }, { "Bip01_L_Hand", "Bip01_L_Forearm" },
    { "Bip01_L_Finger0", "Bip01_L_Hand" }, { "Bip01_L_Finger01", "Bip01_L_Finger0" },
    { "Bip01_R_Clavicle", "Bip01_Spine1" }, { "Bip01_R_UpperArm", "Bip01_R_Clavicle" },
    { "Bip01_R_Forearm", "Bip01_R_UpperArm" }, { "Bip01_R_Hand", "Bip01_R_Forearm" },
    { "Bip01_R_Finger0", "Bip01_R_Hand" },
    { "Bip01_L_Thigh", "Bip01_Pelvis" }, { "Bip01_L_Calf", "Bip01_L_Thigh" },
    { "Bip01_L_Foot", "Bip01_L_Calf" }, { "Bip01_L_Toe0", "Bip01_L_Foot" },
    { "Bip01_R_Thigh", "Bip01_Pelvis" }, { "Bip01_R_Calf", "Bip01_R_Thigh" },
    { "Bip01_R_Foot", "Bip01_R_Calf" }, { "Bip01_R_Toe0", "Bip01_R_Foot" },
}

-- Mixamo. "LeftArm" is the UPPER arm and "LeftLeg" is the CALF, which is the
-- trap this whole classifier exists for.
local MIXAMO = {
    { "mixamorig:Hips" },
    { "mixamorig:Spine", "mixamorig:Hips" },
    { "mixamorig:Spine1", "mixamorig:Spine" },
    { "mixamorig:Spine2", "mixamorig:Spine1" },
    { "mixamorig:Neck", "mixamorig:Spine2" },
    { "mixamorig:Head", "mixamorig:Neck" },
    { "mixamorig:HeadTop_End", "mixamorig:Head" },
    { "mixamorig:LeftShoulder", "mixamorig:Spine2" },
    { "mixamorig:LeftArm", "mixamorig:LeftShoulder" },
    { "mixamorig:LeftForeArm", "mixamorig:LeftArm" },
    { "mixamorig:LeftHand", "mixamorig:LeftForeArm" },
    { "mixamorig:LeftHandIndex1", "mixamorig:LeftHand" },
    { "mixamorig:LeftHandMiddle1", "mixamorig:LeftHand" },
    { "mixamorig:LeftHandThumb1", "mixamorig:LeftHand" },
    { "mixamorig:RightShoulder", "mixamorig:Spine2" },
    { "mixamorig:RightArm", "mixamorig:RightShoulder" },
    { "mixamorig:RightForeArm", "mixamorig:RightArm" },
    { "mixamorig:RightHand", "mixamorig:RightForeArm" },
    { "mixamorig:LeftUpLeg", "mixamorig:Hips" },
    { "mixamorig:LeftLeg", "mixamorig:LeftUpLeg" },
    { "mixamorig:LeftFoot", "mixamorig:LeftLeg" },
    { "mixamorig:LeftToeBase", "mixamorig:LeftFoot" },
    { "mixamorig:RightUpLeg", "mixamorig:Hips" },
    { "mixamorig:RightLeg", "mixamorig:RightUpLeg" },
    { "mixamorig:RightFoot", "mixamorig:RightLeg" },
    { "mixamorig:RightToeBase", "mixamorig:RightFoot" },
}

-- Unreal's mannequin, three spine bones and twist helpers.
local UE = {
    { "root" }, { "pelvis", "root" },
    { "spine_01", "pelvis" }, { "spine_02", "spine_01" }, { "spine_03", "spine_02" },
    { "neck_01", "spine_03" }, { "head", "neck_01" },
    { "clavicle_l", "spine_03" }, { "upperarm_l", "clavicle_l" },
    { "upperarm_twist_01_l", "upperarm_l" },
    { "lowerarm_l", "upperarm_l" }, { "lowerarm_twist_01_l", "lowerarm_l" },
    { "hand_l", "lowerarm_l" }, { "index_01_l", "hand_l" }, { "thumb_01_l", "hand_l" },
    { "clavicle_r", "spine_03" }, { "upperarm_r", "clavicle_r" },
    { "lowerarm_r", "upperarm_r" }, { "hand_r", "lowerarm_r" },
    { "thigh_l", "pelvis" }, { "thigh_twist_01_l", "thigh_l" },
    { "calf_l", "thigh_l" }, { "foot_l", "calf_l" }, { "ball_l", "foot_l" },
    { "thigh_r", "pelvis" }, { "calf_r", "thigh_r" }, { "foot_r", "calf_r" },
}

-- Blender Rigify's deform rig: dotted sides, and a spine chain that keeps
-- counting straight through the neck (spine.004) and the skull (spine.005).
-- Nothing in the NAMES says where the torso ends here.
local RIGIFY = {
    { "spine" }, { "spine.001", "spine" }, { "spine.002", "spine.001" },
    { "spine.003", "spine.002" }, { "spine.004", "spine.003" }, { "spine.005", "spine.004" },
    { "shoulder.L", "spine.003" }, { "upper_arm.L", "shoulder.L" },
    { "forearm.L", "upper_arm.L" }, { "hand.L", "forearm.L" },
    { "shoulder.R", "spine.003" }, { "upper_arm.R", "shoulder.R" },
    { "forearm.R", "upper_arm.R" }, { "hand.R", "forearm.R" },
    { "thigh.L", "spine" }, { "shin.L", "thigh.L" }, { "foot.L", "shin.L" }, { "toe.L", "foot.L" },
    { "thigh.R", "spine" }, { "shin.R", "thigh.R" }, { "foot.R", "shin.R" }, { "toe.R", "foot.R" },
}

-- DAZ/Poser: a bare lowercase side letter glued to a capitalised name.
local DAZ = {
    { "hip" }, { "abdomen", "hip" }, { "chest", "abdomen" },
    { "neck", "chest" }, { "head", "neck" },
    { "lCollar", "chest" }, { "lShldr", "lCollar" }, { "lForeArm", "lShldr" }, { "lHand", "lForeArm" },
    { "rCollar", "chest" }, { "rShldr", "rCollar" }, { "rForeArm", "rShldr" }, { "rHand", "rForeArm" },
    { "lThigh", "hip" }, { "lShin", "lThigh" }, { "lFoot", "lShin" },
    { "rThigh", "hip" }, { "rShin", "rThigh" }, { "rFoot", "rShin" },
}

-- examples/assets/Model.p3dm, bone-for-bone as the engine reports it. Not a
-- standard scheme at all: no pelvis bone (the legs hang off per-side "Ass"
-- bones), no hand bones (the fingers hang straight off the forearm), fingers
-- called "Indicator", and three mesh nodes sitting in the bone array. It is
-- here because it is real, and because every one of those is a way a rig can
-- differ from the one the code was written against.
local ODDBALL = {
    { "Scene" }, { "Cube_006", "Scene" }, { "Cube_005", "Scene" },
    { "Armature", "Scene" }, { "Spine", "Armature" },
    { "LeftShoulder", "Spine" }, { "LeftUpperArm", "LeftShoulder" },
    { "LeftArm", "LeftUpperArm" },
    { "LeftHandThumbUpperBone", "LeftArm" }, { "LeftHandThumbBone", "LeftHandThumbUpperBone" },
    { "LeftHandIndicatorUpperBone", "LeftArm" }, { "LeftHandIndicatorBone", "LeftHandIndicatorUpperBone" },
    { "LeftHandMiddleFingerUpperBone", "LeftArm" }, { "LeftHandMiddleFingerBone", "LeftHandMiddleFingerUpperBone" },
    { "LeftHandSmallFingerUpperBone", "LeftArm" }, { "LeftHandSmallFingerBone", "LeftHandSmallFingerUpperBone" },
    { "RightShoulder", "Spine" }, { "RightUpperArm", "RightShoulder" },
    { "RightArm", "RightUpperArm" },
    { "RightHandThumbUpperBone", "RightArm" },
    { "RightHandIndicatorUpperBone", "RightArm" },
    { "MouthTop", "Spine" }, { "MouthBottom", "Spine" }, { "Head", "Spine" },
    { "LeftAss", "Armature" }, { "LeftUpperLeg", "LeftAss" }, { "LeftLeg", "LeftUpperLeg" },
    { "RightAss", "Armature" }, { "RightUpperLeg", "RightAss" }, { "RightLeg", "RightUpperLeg" },
    { "Cylinder_003", "Scene" }, { "Cylinder_002", "Scene" },
}

-- --------------------------------------------------------------- driver

local failures, checks = 0, 0
local function expect(rigName, got, want, what)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("  FAIL %-8s %-14s got %-26s want %s",
            rigName, what, tostring(got), tostring(want)))
    end
end

local function run(rigName, list, want)
    local inst, id = instance(list)
    local rig, err = Ragdoll._discover(inst)
    if not rig then
        failures = failures + 1
        print(string.format("  FAIL %-8s discover returned nil: %s", rigName, tostring(err)))
        return
    end
    local names = {}
    for role, bid in pairs(rig.found) do names[role] = rig.bones[bid].name end
    for role, wantName in pairs(want) do
        expect(rigName, names[role], wantName ~= false and wantName or nil, role)
    end
    local shown = {}
    for role, n in pairs(names) do shown[#shown + 1] = role .. "=" .. n end
    table.sort(shown)
    print(string.format("  %-8s %s", rigName, table.concat(shown, " ")))
end

print("rig discovery")

run("biped", BIPED, {
    hips = "Bip01_Pelvis", spine = "Bip01_Spine", chest = "Bip01_Spine1",
    neck = "Bip01_Neck", head = "Bip01_Head",
    ["upperarm.L"] = "Bip01_L_UpperArm", ["forearm.L"] = "Bip01_L_Forearm",
    ["hand.L"] = "Bip01_L_Hand", ["clavicle.R"] = "Bip01_R_Clavicle",
    ["thigh.R"] = "Bip01_R_Thigh", ["calf.R"] = "Bip01_R_Calf", ["foot.R"] = "Bip01_R_Foot",
})

run("mixamo", MIXAMO, {
    hips = "mixamorig:Hips", spine = "mixamorig:Spine", chest = "mixamorig:Spine2",
    neck = "mixamorig:Neck", head = "mixamorig:Head",
    ["clavicle.L"] = "mixamorig:LeftShoulder",
    ["upperarm.L"] = "mixamorig:LeftArm",
    ["forearm.L"] = "mixamorig:LeftForeArm",
    ["hand.L"] = "mixamorig:LeftHand",
    ["thigh.R"] = "mixamorig:RightUpLeg",
    ["calf.R"] = "mixamorig:RightLeg",
    ["foot.R"] = "mixamorig:RightFoot",
})

run("unreal", UE, {
    hips = "pelvis", spine = "spine_01", chest = "spine_03",
    neck = "neck_01", head = "head",
    ["clavicle.L"] = "clavicle_l", ["upperarm.L"] = "upperarm_l",
    ["forearm.L"] = "lowerarm_l", ["hand.L"] = "hand_l",
    ["thigh.L"] = "thigh_l", ["calf.L"] = "calf_l", ["foot.L"] = "foot_l",
})

run("rigify", RIGIFY, {
    -- the chest is where the shoulders hang from, not the end of the chain
    hips = "spine", spine = "spine.001", chest = "spine.003",
    neck = "spine.004", head = "spine.005",
    ["clavicle.L"] = "shoulder.L", ["upperarm.L"] = "upper_arm.L",
    ["forearm.L"] = "forearm.L", ["hand.L"] = "hand.L",
    ["thigh.R"] = "thigh.R", ["calf.R"] = "shin.R", ["foot.R"] = "foot.R",
})

run("daz", DAZ, {
    -- DAZ's "lShldr" is the upper arm; its clavicle is "lCollar".
    hips = "hip", spine = "abdomen", chest = "chest", neck = "neck", head = "head",
    ["clavicle.L"] = "lCollar", ["upperarm.L"] = "lShldr",
    ["forearm.L"] = "lForeArm", ["hand.L"] = "lHand",
    ["thigh.R"] = "rThigh", ["calf.R"] = "rShin", ["foot.R"] = "rFoot",
})

run("oddball", ODDBALL, {
    -- the legs share no parent, so the pelvis is their lowest common ancestor
    hips = "Armature", chest = "Spine", head = "Head",
    ["clavicle.L"] = "LeftShoulder", ["upperarm.L"] = "LeftUpperArm",
    -- "LeftArm" is the FOREARM here: the upper arm already has a name
    ["forearm.L"] = "LeftArm",
    -- and there is no hand bone at all, so there had better not be one
    ["hand.L"] = false, ["hand.R"] = false,
    ["thigh.R"] = "RightUpperLeg", ["calf.R"] = "RightLeg",
    ["foot.L"] = false,
})

-- A rig that is not a biped at all must be refused, not half-built.
do
    local CRATE = { { "root" }, { "lid", "root" }, { "hinge", "lid" }, { "handle", "lid" } }
    local rig, err = Ragdoll._discover((instance(CRATE)))
    checks = checks + 1
    if rig then
        failures = failures + 1
        print("  FAIL crate    discover accepted a non-character rig")
    else
        print("  crate    refused: " .. tostring(err))
    end
end

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
