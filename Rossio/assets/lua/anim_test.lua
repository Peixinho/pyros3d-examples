-- assets/lua/anim_test.lua
-- Bench for skeletal animation. Attach to a GameObject that has a rigged
-- model on it; it loads walk.p3da and plays it on a loop, and echoes the
-- clip's progress so "is it playing?" and "is it deforming?" stay separate
-- questions. They are separate bugs and were conflated for a long time.

local AnimTest = class('AnimTest')

function AnimTest:initialize() end

function AnimTest:init(owner)
	self.owner = owner
	self.clock = 0
	local rc = owner:getComponent("RenderingComponent")
	if not rc then
		echo("ERROR: anim_test - no RenderingComponent on " .. owner:getName())
		return
	end
	echo("[ANIM] hasBones=" .. tostring(rc:hasBones()))
	local ok, err = pcall(function()
		self.anim = SekeletonAnimation.new()
		self.anim:loadAnimation(ASSETS_PATH .. "animations/walk.p3da")
		self.inst = self.anim:createInstance(rc)
		if self.inst then
			-- phase and speed jitter: a crowd must not march in lockstep
			self.inst:playClip("walk", -1, 0.88 + math.random() * 0.28, math.random())
		end
	end)
	if not ok then
		echo("ERROR: anim_test - " .. tostring(err))
	elseif not self.inst then
		echo("ERROR: anim_test - createInstance returned nil")
	else
		echo("[ANIM] playing, bones=" .. tostring(self.inst:getNumberBones()))
	end
end

function AnimTest:update(dt)
	if dt <= 0 or dt > 0.25 then dt = 0.016 end
	self.clock = self.clock + dt
	-- No per-frame progress echo here: getAnimationCurrentProgress() takes a
	-- clip argument, and calling it bare throws out of update() every frame
	-- ("expected number, received no value"), which silently kills the rest
	-- of the component. Whether the mesh DEFORMS is the question anyway, and
	-- that is answered by counting changed pixels between frames.
end

function AnimTest:destroy() end
function AnimTest:serialize() return {} end
function AnimTest.deserialize(_) return AnimTest:new() end

return AnimTest
