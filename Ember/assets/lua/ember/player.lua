-- assets/lua/ember/player.lua
--
-- Ember himself: a Box2D body, four sprite states, a light, and the twenty
-- lines of feel that decide whether a platformer is any good.
--
-- The body is a real dynamic body - it collides with the world, rides the
-- kinematic platforms and gets shoved by crates. What this file does NOT
-- leave to the solver is the arc of a jump: Box2D's gravity is -10, which at
-- this scale is a moon, so vertical motion is re-integrated here every frame
-- (RISE_G / FALL_G). That is also what makes the jump variable, and what a
-- gravity-scale setter would be doing if Physics2D exposed one.

local Player = {}
Player.__index = Player

-- Movement --------------------------------------------------------------
local RUN        = 7.0      -- top speed, units/s
local ACCEL      = 62.0     -- ground pickup
local AIR_ACCEL  = 26.0     -- you can steer in the air, but not like this is the ground
local FRICTION   = 52.0     -- stopping, when nothing is held
local JUMP_V     = 15.6     -- ~3.1 units of height with RISE_G
local FLARE_V    = 13.0     -- the mid-air second jump
local RISE_G     = 40.0     -- gravity going up ...
local FALL_G     = 56.0     -- ... and coming down. Heavier: the classic trick
local HANG_G     = 26.0     -- lighter near the apex, so the top of a jump reads
local CUT        = 0.42     -- release early and keep this much of the climb
local MAX_FALL   = 22.0
local COYOTE     = 0.11     -- still jumpable this long after walking off
local BUFFER     = 0.13     -- a jump pressed this early still fires on landing
local HALF_W     = 0.30     -- must match the body in the scene
local HALF_H     = 0.44

-- Flame -----------------------------------------------------------------
local DRAIN      = 0.021    -- fuel per second, just standing there
local FLARE_COST = 0.07
local HURT_COST  = 0.16
local SHARD_GAIN = 0.085
local MELT_GAIN  = 0.05

function Player.new(game, obj)
    local p = setmetatable({}, Player)
    p.game = game
    p.obj = obj
    p.body = obj:getComponent("Physics2D")
    p.light = nil
    p.trail = nil
    p.sprites = {}
    for _, s in ipairs(obj:getChildren()) do
        local n = s:getName()
        if n:find("EmberIdle") then p.sprites.idle = s
        elseif n:find("EmberRun") then p.sprites.run = s
        elseif n:find("EmberAir") then p.sprites.air = s
        elseif n:find("EmberHurt") then p.sprites.hurt = s end
        if p.light == nil then p.light = s:getComponent("PointLight") end
        if p.trail == nil then p.trail = s:getComponent("ParticleSystem") end
    end
    -- The base scale each sprite was authored at, so squash and stretch is
    -- relative to the artwork rather than accumulating.
    p.base = {}
    for k, s in pairs(p.sprites) do
        local sc = s:getScale()
        p.base[k] = Vec3.new(math.abs(sc.x), sc.y, sc.z)
    end

    p.face = 1
    p.state = "idle"
    p.grounded = false
    p.coyote = 0
    p.buffer = 0
    p.flared = false
    p.jumpHeld = false
    p.fuel = 0.72
    p.squash = 0        -- >0 landing squash, <0 launch stretch
    p.invuln = 0
    p.dead = false
    p.airTime = 0
    p.stepT = 0
    return p
end

function Player:pos() return self.obj:getPosition() end

function Player:vel()
    local v = self.body:getLinearVelocity()
    return v.x, v.y
end

function Player:setVel(x, y) self.body:setLinearVelocity(Vec2.new(x, y)) end

-- Where the feet are, and what they are standing on ----------------------
-- Done here rather than through contact callbacks because a callback says
-- "you touched something", and what a controller needs to know is "is there
-- floor under me RIGHT NOW" - including the frame a moving platform arrives.
function Player:probeGround(solids)
    local p = self:pos()
    local feet = p.y - HALF_H
    local best, bestTop = nil, nil
    for _, s in ipairs(solids) do
        local sp = s.obj:getPosition()
        local top = sp.y + s.hy
        if math.abs(p.x - sp.x) < s.hx + HALF_W * 0.75 then
            if feet <= top + 0.16 and feet >= top - 0.34 then
                if bestTop == nil or top > bestTop then best, bestTop = s, top end
            end
        end
    end
    return best, bestTop
end

function Player:jump(vy, sound)
    self:setVel(select(1, self:vel()), vy)
    self.squash = -1.0
    self.grounded = false
    self.coyote = 0
    self.buffer = 0
    self.game.audio:play(sound, 1.0)
end

function Player:update(dt, input, solids)
    if self.dead then return end

    -- Ground ------------------------------------------------------------
    local wasGrounded = self.grounded
    local vx, vy = self:vel()

    -- Last frame's position and fall speed, kept for the overlap tests the
    -- game does against enemies and pickups. Box2D runs a fixed 60Hz step
    -- and catches up to EIGHT of them in one frame, so a fast fall can move
    -- two metres between two script frames - and a test that only looks at
    -- where things are now misses the whole event. See Ember.lua's stomp.
    self.prevY = self.curY or self:pos().y
    self.prevVy = self.curVy or vy
    self.curY = self:pos().y
    self.curVy = vy
    local floor, top = self:probeGround(solids)
    self.grounded = (floor ~= nil) and vy <= 0.6
    if self.grounded then
        self.coyote = COYOTE
        self.flared = false
        self.airTime = 0
        if not wasGrounded then
            -- Landing: squash, dust, and a thud whose volume is the speed
            -- you arrived at.
            local hard = math.min(1.0, math.abs(vy) / 16.0)
            self.squash = 0.6 + 0.6 * hard
            self.game.audio:play("land", 0.35 + 0.55 * hard)
            self.game:puff(self:pos(), 10 + 14 * hard)
        end
    else
        self.coyote = math.max(0, self.coyote - dt)
        self.airTime = self.airTime + dt
    end

    -- Horizontal --------------------------------------------------------
    local move = 0
    if input.left then move = move - 1 end
    if input.right then move = move + 1 end
    if move ~= 0 then self.face = move end

    -- Ride what you are standing on, by doing the whole of the rest of this
    -- in the PLATFORM'S frame: subtract its velocity, run the controller on
    -- what is left, add it back at the end.
    --
    -- Adding the platform's speed on top at the end instead - the obvious
    -- way, and what this used to do - compounds. The velocity read from the
    -- body at the top of the next frame already contains the carry, ground
    -- friction only takes a fixed FRICTION*dt off it, and the carry is added
    -- again: standing still on a platform moving at 1.6 u/s gained about
    -- 0.7 u/s every frame and threw him off the far end at ten times its
    -- speed. Box2D's own friction cannot do this job either - Ember's
    -- material is frictionless on purpose, so that he does not stick to the
    -- wall of a ledge he is pressed against.
    local carry = 0.0
    if floor and floor.mover then carry = floor.body:getLinearVelocity().x end
    vx = vx - carry

    local a = self.grounded and ACCEL or AIR_ACCEL
    if move ~= 0 then
        local target = move * RUN
        if vx < target then vx = math.min(target, vx + a * dt)
        else vx = math.max(target, vx - a * dt) end
    elseif self.grounded then
        if vx > 0 then vx = math.max(0, vx - FRICTION * dt)
        else vx = math.min(0, vx + FRICTION * dt) end
    end

    vx = vx + carry

    -- Vertical ----------------------------------------------------------
    self.buffer = math.max(0, self.buffer - dt)
    if input.jumpPressed then self.buffer = BUFFER end

    if self.buffer > 0 and (self.grounded or self.coyote > 0) then
        self:jump(JUMP_V, "jump")
        vy = JUMP_V
    elseif input.jumpPressed and not self.flared and self.fuel > 0.05 then
        -- The flare: a second jump that BURNS fuel. It is the only thing in
        -- the game that spends your light on movement, which is what makes
        -- the long gaps a decision instead of a reflex.
        self.flared = true
        self:jump(FLARE_V, "flare")
        vy = FLARE_V
        self:addFuel(-FLARE_COST)
        self.game:flareBurst(self:pos())
    end

    if not input.jumpHeld and vy > 0 and not self.grounded then vy = vy * (1 - (1 - CUT) * math.min(1, dt * 30)) end

    if not self.grounded then
        local g = FALL_G
        if vy > 1.5 then g = RISE_G
        elseif vy > -1.5 then g = HANG_G end
        vy = math.max(-MAX_FALL, vy - g * dt)
    elseif vy < 0 then
        vy = 0
    end

    self:setVel(vx, vy)

    -- Fuel, and what it drives ------------------------------------------
    if not self.frozen then self:addFuel(-DRAIN * dt) end
    self.invuln = math.max(0, self.invuln - dt)

    -- Sprite state -------------------------------------------------------
    local st = "idle"
    if self.invuln > 0.75 then st = "hurt"
    elseif not self.grounded then st = "air"
    elseif math.abs(vx) > 0.6 then st = "run" end
    self:show(st, dt, vx, vy)

    -- Footsteps, paced by how fast he is actually moving.
    if self.grounded and math.abs(vx) > 1.0 then
        self.stepT = self.stepT - dt * math.abs(vx)
        if self.stepT <= 0 then
            self.stepT = 2.2
            self.game.audio:play("step", 0.30)
        end
    end

    if self.fuel <= 0 then self.game:extinguish("The dark got in.") end
    local p = self:pos()
    if p.y < -4.5 then self.game:extinguish("The cold took you.") end
end

-- One sprite visible at a time, squashed and stretched by what just
-- happened. RenderingComponent::IsActive() is honoured by the renderer, so
-- disabling the component really does stop it drawing.
function Player:show(st, dt, vx, vy)
    for k, s in pairs(self.sprites) do
        local rc = s:getComponent("RenderingComponent")
        if rc then
            if k == st then rc:enable() else rc:disable() end
        end
    end
    self.state = st

    self.squash = self.squash - self.squash * math.min(1, dt * 11.0)
    local sq = self.squash
    local sx, sy = 1.0, 1.0
    if sq > 0 then sx, sy = 1.0 + 0.30 * sq, 1.0 - 0.26 * sq      -- landed
    elseif sq < 0 then sx, sy = 1.0 + 0.26 * sq, 1.0 - 0.34 * sq end -- launched
    -- Air stretch follows the actual vertical speed, not a timer.
    if not self.grounded then
        local k = math.max(-1, math.min(1, vy / 14.0))
        sx = sx * (1.0 - 0.10 * k)
        sy = sy * (1.0 + 0.13 * k)
    end
    -- Size is the flame: a low tank is a small, feeble Ember.
    local fuelScale = 0.78 + 0.36 * self.fuel

    local s = self.sprites[st]
    local b = self.base[st]
    if s and b then
        s:setScale(Vec3.new(b.x * sx * fuelScale * self.face, b.y * sy * fuelScale, b.z))
        s:refreshTransformation()
    end
end

function Player:addFuel(d)
    self.fuel = math.max(0, math.min(1, self.fuel + d))
    if self.light then
        self.light:setLightRadius(5.5 + 7.5 * self.fuel)
        self.light:setLightIntensity(0.35 + 1.15 * self.fuel)
        -- Guttering low, the flame goes colder as well as smaller.
        local f = self.fuel
        self.light:setLightColor(Vec4.new(1.0, 0.42 + 0.22 * f, 0.14 + 0.16 * f, 1.0))
    end
    if self.trail then
        self.trail:setEmissionRate(10 + 52 * self.fuel)
    end
end

function Player:shard()
    self:addFuel(SHARD_GAIN)
    self.game.audio:play("pickup", 0.8)
end

function Player:melt()
    self:addFuel(MELT_GAIN)
    self:setVel(select(1, self:vel()), 12.2)   -- the stomp bounce
    self.squash = -0.9
    self.flared = false                        -- and it gives your flare back
end

function Player:hurt(fromX)
    if self.invuln > 0 then return false end
    self.invuln = 1.35
    self:addFuel(-HURT_COST)
    local dir = (self:pos().x < fromX) and -1 or 1
    -- Thrown clear, not nudged: a knockback that leaves you inside the
    -- frostling's patrol is a second hit 1.35 seconds later, for ever. But
    -- mostly UP, not sideways - a frostling patrolling near the lip of a
    -- platform would otherwise punt you straight into the pit behind it,
    -- with nothing you could have done about it. Up, you can steer out of.
    self:setVel(dir * 4.6, 9.2)
    self.game.audio:play("hurt", 0.9)
    return true
end

function Player:sweptY()
    -- The band of heights he occupied this frame, feet to head.
    local p = self:pos()
    local lo = math.min(p.y, self.prevY or p.y)
    local hi = math.max(p.y, self.prevY or p.y)
    return lo, hi
end

function Player:teleport(x, y)
    self.body:setTransform(Vec2.new(x, y), 0)
    self:setVel(0, 0)
    self.body:wake()
    self.obj:setPosition(Vec3.new(x, y, self.obj:getPosition().z))
    self.obj:refreshTransformation()
    self.curY, self.prevY = y, y
    self.curVy, self.prevVy = 0, 0
end

Player.HALF_W = HALF_W
Player.HALF_H = HALF_H
return Player
