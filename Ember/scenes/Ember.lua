-- scenes/Ember.lua - the game.
--
-- The level is entirely in Ember.json: every platform, torch, frostling,
-- ember shard, parallax layer, light, emitter and HUD element was authored in
-- PyrosBuilder. This file does not build anything except the little pool of
-- effect emitters at the bottom - it reads the scene, runs the rules, and
-- pushes numbers into a HUD that already exists.
--
-- The rule the whole game is made of: your flame is your light, your health
-- and your clock. It burns down on its own. Ember shards feed it, frostlings
-- eat it, and the flare jump spends it - so being bright enough to see is
-- the same resource as being able to cross the next gap.

local Ember = class('Ember')

local function import(name)
    local path = ASSETS_PATH .. "lua/ember/" .. name .. ".lua"
    local chunk, err = loadfile(path)
    if not chunk then error("cannot load " .. name .. ": " .. tostring(err)) end
    local mod = chunk()
    if mod == nil then error("module " .. name .. " returned nothing") end
    return mod
end

local GOAL_X = 106.0     -- past this, the brazier is in reach
local FALL_Y = -4.5

function Ember:initialize()
    self.clock = 0
    self.ready = false
end

function Ember:init(owner)
    self.Player = import("player")
    self.World = import("world")
    self.audio = import("audio").new()

    self.w = self.World.collect(scene)
    if not self.w.player then
        echo("[Ember] no Ember object in the scene - nothing to play")
        return
    end

    self.player = self.Player.new(self, self.w.player)
    self.fx = self:buildFX()

    self.state = "intro"
    self.stateT = 0
    self.shards = 0
    self.melted = 0
    self.deaths = 0
    self.checkpoint = { x = 4.0, y = 1.6 }
    self.camX, self.camY = 4.0, 2.0

    -- Input. Held state is tracked from the press/release pair because the
    -- binding is event-based - there is no "is this key down" to poll.
    self.keys = { left = false, right = false, jump = false }
    self.input = Input.new()
    local K = self.keys
    local this = self
    local function bind(key, set)
        this.input:onKeyPressed(key, function() set(true) end)
        this.input:onKeyReleased(key, function() set(false) end)
    end
    bind(Key.A, function(v) K.left = v end)
    bind(Key.Left, function(v) K.left = v end)
    bind(Key.D, function(v) K.right = v end)
    bind(Key.Right, function(v) K.right = v end)
    local function jump(v)
        if v and not K.jump then this.jumpEdge = true end
        K.jump = v
    end
    bind(Key.Space, jump)
    bind(Key.W, jump)
    bind(Key.Up, jump)
    -- R: give up on where you are and go back to the last torch. It does
    -- NOT refill you - otherwise it is a fuel button.
    self.input:onKeyPressed(Key.R, function() this:respawn(true) end)

    -- The first torch is already burning - it is where you wake up.
    for i, t in ipairs(self.w.torches) do
        t.lit = (i == 1)
        if t.light then t.light:setLightIntensity(t.lit and 1.0 or 0.0) end
        if t.fire then
            local rc = t.fire:getComponent("RenderingComponent")
            if rc then if t.lit then rc:enable() else rc:disable() end end
        end
    end
    if self.w.brazierFire then
        local rc = self.w.brazierFire:getComponent("RenderingComponent")
        if rc then rc:disable() end
    end
    if self.w.brazierLight then self.w.brazierLight:setLightIntensity(0.0) end

    self.player:addFuel(0)      -- push the starting fuel into the light
    self:hudFind()
    self:say("EMBER", "wake up, and stay lit")

    -- X is the engine's: follow with lag, clamp to the bounds, done.
    -- Y is this script's, because a 2D view that tracks a jumping character
    -- one for one takes the floor off the bottom of the screen every time he
    -- jumps. What the camera wants is the height of the FLOOR he is on,
    -- which only the game knows.
    view.follow("Ember", 0.14)
    view.followAxes(true, false)
    self.anchorY = self.player:pos().y
    self.camY = self.anchorY + 0.35

    self.ready = true
    echo(string.format("[Ember] %d platforms, %d shards, %d frostlings, %d torches",
        #self.w.solids, #self.w.shards, #self.w.foes, #self.w.torches))
end

-- ------------------------------------------------------------------ HUD --
function Ember:hudFind()
    local F = function(n) return ui.find(scene, n) end
    self.hud = {
        fill = F("FuelFill"), fuelText = F("FuelLabel"), shards = F("ShardLabel"),
        big = F("BigLabel"), sub = F("SubLabel"), hint = F("HintLabel"),
        flash = F("Flash"),
    }
end

function Ember:say(big, sub, seconds)
    self.bigText, self.subText = big or "", sub or ""
    self.sayT = seconds or 2.6
end

function Ember:updateHUD(dt)
    local H = self.hud
    if not H then return end
    local f = self.player.fuel

    if H.fill then
        ui.setFill(H.fill, f)
        -- The bar is the flame: hot while you are healthy, blue when the
        -- cold is winning.
        if f > 0.55 then ui.setTint(H.fill, Vec4.new(1.0, 0.62, 0.20, 0.95))
        elseif f > 0.25 then ui.setTint(H.fill, Vec4.new(0.98, 0.40, 0.16, 0.95))
        else ui.setTint(H.fill, Vec4.new(0.40, 0.62, 0.95, 0.95)) end
    end
    if H.fuelText then ui.setText(H.fuelText, string.format("FLAME  %d%%", math.floor(f * 100 + 0.5))) end
    if H.shards then ui.setText(H.shards, string.format("EMBERS  %d / %d", self.shards, #self.w.shards)) end

    self.sayT = math.max(0, (self.sayT or 0) - dt)
    if H.big then ui.setText(H.big, self.sayT > 0 and self.bigText or "") end
    if H.sub then ui.setText(H.sub, self.sayT > 0 and self.subText or "") end
    if H.hint then
        ui.setVisible(H.hint, self.clock < 9.0)
        ui.setText(H.hint, "A / D  move      SPACE  jump      SPACE again  flare")
    end
    -- A red wash when you are hit, a blue one while you are out.
    if H.flash then
        local a = 0
        local c = Vec4.new(0.8, 0.2, 0.1, 0)
        if self.state == "dead" then
            a = 0.55 * math.min(1, self.stateT * 3)
            c = Vec4.new(0.20, 0.42, 0.85, a)
        elseif self.player.invuln > 0 then
            a = 0.34 * (self.player.invuln / 1.35)
            c = Vec4.new(0.75, 0.18, 0.10, a)
        end
        ui.setTint(H.flash, c)
    end
end

-- --------------------------------------------------------------- effects --
-- A small pool of emitters, built once and moved to wherever something
-- happens. Each is one-shot: looping=false plus a real burstCount, so a hit
-- is a puff and not a smoke machine left running at the last thing you hit.
function Ember:buildFX()
    local PARK = Vec3.new(0, -80, 0)
    local function tex(name)
        local t = Texture.new()
        t:loadTexture(ASSETS_PATH .. "textures/" .. name, TextureType.Texture, true, 0)
        t:setTransparency(TextureTransparency.Transparent)
        return t
    end
    local sparkTex, smokeTex, frostTex = tex("p_spark.png"), tex("p_smoke.png"), tex("p_frost.png")

    local made = {}
    local function emitter(name, build)
        local go = GameObject.new()
        -- Named, and removed again in destroy(): an object a script adds at
        -- run time is NOT part of the play-mode snapshot the editor restores
        -- on Stop, so anything left behind is in the scene file the next
        -- time it is saved - three more emitters per play session.
        go:setName(name)
        local d = ParticleSystemDesc.new()
        build(d)
        local ps = ParticleSystem.new(d)
        go:addComponent(ps)
        go:setPosition(PARK)
        go:refreshTransformation()
        scene:add(go)
        table.insert(made, go)
        return { go = go, ps = ps }
    end

    local fx = { made = made }
    fx.tex = { sparkTex, smokeTex, frostTex }   -- held: the desc shares them

    fx.spark = emitter("FX_Spark", function(d)
        d.maxParticles = 220; d.texture = sparkTex
        d.looping = false; d.burstCount = 18
        d.minLifetime = 0.25; d.maxLifetime = 0.65
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 3.14159
        d.minSpeed = 1.5; d.maxSpeed = 5.0
        d.gravity = Vec3.new(0, -4.0, 0); d.damping = 0.8
        d.startSize = 0.26; d.endSize = 0.01
        d.startColor = Vec4.new(1.0, 0.85, 0.45, 1.0)
        d.endColor = Vec4.new(0.95, 0.25, 0.08, 0.0)
        d.fadeOutFraction = 0.5
        -- AlphaBlend, not Additive: additive emitters measure fine and draw
        -- nothing (see the engine note on ParticleBlendMode).
        d.blendMode = ParticleBlendMode.AlphaBlend
    end)

    fx.dust = emitter("FX_Dust", function(d)
        d.maxParticles = 160; d.texture = smokeTex
        d.looping = false; d.burstCount = 12
        d.minLifetime = 0.3; d.maxLifetime = 0.7
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 2.4
        d.minSpeed = 0.6; d.maxSpeed = 2.0
        d.gravity = Vec3.new(0, -1.2, 0); d.damping = 2.0
        d.startSize = 0.18; d.endSize = 0.75
        d.startColor = Vec4.new(0.85, 0.62, 0.45, 0.55)
        d.endColor = Vec4.new(0.5, 0.4, 0.38, 0.0)
        d.blendMode = ParticleBlendMode.AlphaBlend
    end)

    fx.steam = emitter("FX_Steam", function(d)
        d.maxParticles = 200; d.texture = frostTex
        d.looping = false; d.burstCount = 26
        d.minLifetime = 0.45; d.maxLifetime = 1.1
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 1.5
        d.minSpeed = 1.0; d.maxSpeed = 3.2
        d.gravity = Vec3.new(0, 1.4, 0); d.damping = 1.6
        d.startSize = 0.22; d.endSize = 0.9
        d.startColor = Vec4.new(0.85, 0.95, 1.0, 0.9)
        d.endColor = Vec4.new(0.55, 0.75, 1.0, 0.0)
        d.blendMode = ParticleBlendMode.AlphaBlend
    end)

    return fx
end

function Ember:fire(e, at, count)
    if not e then return end
    e.go:setPosition(at)
    e.go:refreshTransformation()
    if count then e.ps:setBurstCount(count) end
    e.ps:play()
end

function Ember:puff(p, n)
    self:fire(self.fx.dust, Vec3.new(p.x, p.y - self.Player.HALF_H, 0.35), math.floor(n))
end

function Ember:flareBurst(p)
    self:fire(self.fx.spark, Vec3.new(p.x, p.y - 0.2, 0.35), 26)
end

-- ----------------------------------------------------------- the rules ---
function Ember:collect(dt)
    local p = self.player:pos()

    for _, s in ipairs(self.w.shards) do
        if not s.taken then
            local sp = s.obj:getPosition()
            -- Bob, so a shard reads as something to take rather than scenery.
            s.obj:setPosition(Vec3.new(sp.x, s.base + math.sin(self.clock * 3.0 + sp.x) * 0.10, sp.z))
            s.obj:refreshTransformation()
            if math.abs(sp.x - p.x) < 0.70 and math.abs(sp.y - p.y) < 0.85 then
                s.taken = true
                self.shards = self.shards + 1
                self.player:shard()
                self:fire(self.fx.spark, Vec3.new(sp.x, sp.y, 0.35), 12)
                local rc = s.obj:getComponent("RenderingComponent")
                if rc then rc:disable() end
            end
        end
    end

    for _, t in ipairs(self.w.torches) do
        if not t.lit and t.x and math.abs(t.x - p.x) < 1.1 and math.abs(t.y - p.y) < 2.4 then
            t.lit = true
            if t.light then t.light:setLightIntensity(1.0) end
            if t.fire then
                local rc = t.fire:getComponent("RenderingComponent")
                if rc then rc:enable() end
            end
            self.checkpoint = { x = t.x, y = t.y + 0.4 }
            self.player:addFuel(0.22)
            self.audio:play("torch", 0.9)
            self:fire(self.fx.spark, Vec3.new(t.x, t.y + 0.2, 0.35), 22)
            self:say("CHECKPOINT", "the torch is lit", 1.8)
        end
    end
end

function Ember:foes(dt)
    local p = self.player:pos()
    local PW, PH = self.Player.HALF_W, self.Player.HALF_H
    for _, f in ipairs(self.w.foes) do
        if f.alive then
            local fp = f.obj:getPosition()
            local x = fp.x + f.dir * 1.85 * dt
            if x > f.max then x, f.dir = f.max, -1 end
            if x < f.min then x, f.dir = f.min, 1 end
            local y = f.base + math.abs(math.sin(self.clock * 5.0 + fp.x)) * 0.07
            f.obj:setPosition(Vec3.new(x, y, fp.z))
            f.obj:setScale(Vec3.new(f.scale.x * f.dir, f.scale.y, f.scale.z))
            f.obj:refreshTransformation()

            -- Overlap, then decide by WHERE he is: coming down on top of one
            -- melts it, walking into one costs you.
            local lo, hi = self.player:sweptY()
            if math.abs(x - p.x) < 0.52 + PW and (lo - y) < 0.52 + PH and (hi - y) > -(0.52 + PH) then
                local _, vy = self.player:vel()
                -- Coming down on it from above melts it. Tested against the
                -- band of heights he passed through this frame, not just
                -- where he ended up: landing on a frostling from a long fall
                -- puts him ON THE FLOOR beside it by the time the overlap is
                -- first seen, and testing only the final position turns
                -- every stomp into a hit.
                -- FEET above its middle, and falling. Comparing centres
                -- instead needs a margin big enough to clear half a
                -- frostling, and a fast fall is already past that on the
                -- frame the overlap is first seen - which turned every
                -- stomp into a hit.
                local feet = math.max(p.y, hi) - PH
                local fell = math.min(vy, self.player.prevVy or vy)
                if feet > (y - 0.18) and fell < -0.5 then
                    f.alive = false
                    self.melted = self.melted + 1
                    local rc = f.obj:getComponent("RenderingComponent")
                    if rc then rc:disable() end
                    self.player:melt()
                    self.audio:play("melt", 0.9)
                    self:fire(self.fx.steam, Vec3.new(x, y, 0.35), 30)
                elseif self.player:hurt(x) then
                    self:fire(self.fx.steam, Vec3.new(p.x, p.y, 0.35), 14)
                end
            end
        end
    end
end

function Ember:extinguish(why)
    if self.state ~= "play" then return end
    self.state, self.stateT = "dead", 0
    self.deaths = self.deaths + 1
    self.audio:play("out", 1.0)
    local p = self.player:pos()
    self:fire(self.fx.steam, Vec3.new(p.x, p.y, 0.35), 40)
    self:say("OUT", why, 3.0)
    local rc = self.w.player and nil
    self.player.dead = true
    self.player:setVel(0, 0)
end

function Ember:respawn(keepFuel)
    self.player.dead = false
    if not keepFuel then
        self.player.fuel = 0.0
        self.player:addFuel(0.55)
    end
    self.player.invuln = 0.8
    self.player:teleport(self.checkpoint.x, self.checkpoint.y + 0.6)
    -- Snap the camera rather than letting it sail across the level.
    self.anchorY = self.checkpoint.y + 0.6
    self.camY = self.anchorY + 0.35
    self.state, self.stateT = "play", 0
    self:fire(self.fx.spark, Vec3.new(self.checkpoint.x, self.checkpoint.y + 0.6, 0.35), 20)
end

function Ember:win()
    if self.state == "won" then return end
    self.state, self.stateT = "won", 0
    self.audio:play("win", 1.0)
    if self.w.brazierLight then
        -- Bright, but not so bright that the ember crust saturates to flat
        -- yellow - this is the last thing anyone sees of the game.
        self.w.brazierLight:setLightIntensity(1.8)
        self.w.brazierLight:setLightRadius(16.0)
    end
    if self.w.brazierFire then
        local rc = self.w.brazierFire:getComponent("RenderingComponent")
        if rc then rc:enable() end
    end
    local b = self.w.brazier and self.w.brazier:getPosition() or self.player:pos()
    self:fire(self.fx.spark, Vec3.new(b.x, b.y + 1.6, 0.35), 90)

    -- Lighting the brazier ends the cold: every frostling still standing
    -- goes with it. This is not decoration - without it the survivors keep
    -- patrolling into a player who has won, and take bites out of him while
    -- the victory text is on screen. They are not counted: the ones you
    -- melted yourself are the ones the score is about.
    local left = 0
    for _, f in ipairs(self.w.foes) do
        if f.alive then
            f.alive = false
            left = left + 1
            local fp = f.obj:getPosition()
            local rc = f.obj:getComponent("RenderingComponent")
            if rc then rc:disable() end
            self:fire(self.fx.steam, Vec3.new(fp.x, fp.y, 0.35), 24)
        end
    end
    if left > 0 then self.audio:play("melt", 1.0) end

    -- The flame stops burning down too: a won game that puts you out ninety
    -- seconds later while you read your own score is a joke at your expense.
    self.player.frozen = true

    local function plural(n, one, many)
        return string.format("%d %s", n, n == 1 and one or many)
    end
    self:say("THE DARK IS OVER",
        table.concat({
            plural(self.shards, "ember", "embers"),
            plural(self.melted, "frostling melted", "frostlings melted"),
            plural(self.deaths, "time out", "times out"),
        }, "  -  "), 60)
end

-- ------------------------------------------------------------- the loop --
function Ember:update(dt)
    if not self.ready then return end
    if dt <= 0 or dt > 0.25 then dt = math.min(math.max(dt, 1 / 240), 0.05) end
    self.clock = self.clock + dt
    self.stateT = self.stateT + dt

    self.World.driveMovers(self.w, dt)

    if self.state == "intro" and self.stateT > 1.0 then
        self.state, self.stateT = "play", 0
    end

    if self.state == "play" or self.state == "won" then
        -- You keep the controls after winning: the level has walls at both
        -- ends, so there is nothing to fall off, and standing frozen in
        -- front of the thing you just lit is a worse ending than walking
        -- around it.
        local inp = {
            left = self.keys.left, right = self.keys.right,
            jumpHeld = self.keys.jump, jumpPressed = self.jumpEdge == true,
        }
        self.jumpEdge = false
        self.player:update(dt, inp, self.w.solids)
        self:collect(dt)
        self:foes(dt)
        if self.state == "play" and self.player:pos().x > GOAL_X then self:win() end
    elseif self.state == "dead" then
        self.jumpEdge = false
        if self.stateT > 1.4 then self:respawn() end
    end

    self:driveCamera(dt)

    -- Parallax is driven from where the CAMERA is, not from the player: the
    -- view lags him, and layers that track the player instead of the view
    -- slide by a frame whenever he changes direction.
    local cx, cy = view.center()
    self.World.parallax(self.w, cx, cy)

    self:updateHUD(dt)
end

-- The vertical half of the camera: hold the height of the floor he last
-- stood on, so a jump does not take the ground off the bottom of the screen.
--
-- The two windows are deliberately different sizes. Going UP is a jump, and a
-- jump should not move the view at all - that is the whole point of anchoring
-- to the floor. Going DOWN is a drop, and a drop is the one moment the player
-- NEEDS to see what is under him, so the anchor gives way almost at once and
-- a fall-speed lead pushes the view further ahead of him. With one symmetric
-- window the late descent was unplayable: standing on a roof you could not
-- see the next roof below, because the camera was still framing the one you
-- were standing on.
function Ember:driveCamera(dt)
    local UP, DOWN = 3.0, 0.8
    local p = self.player:pos()
    local _, vy = self.player:vel()

    if self.player.grounded then
        self.anchorY = p.y
    else
        if p.y - self.anchorY > UP then self.anchorY = p.y - UP end
        if self.anchorY - p.y > DOWN then self.anchorY = p.y + DOWN end
    end

    -- Look ahead of a fall, proportional to how fast it is. Clamped, and
    -- only downwards: leading a JUMP upwards hides the floor again.
    local lead = math.max(-2.6, math.min(0.0, vy * 0.14))
    -- Only a token bias above the floor. A bigger one buys headroom for a
    -- jump - which the anchor already provides - and pays for it with the
    -- ground below, which is where the next platform is in every descending
    -- section of this level.
    local want = self.anchorY + 0.35 + lead

    -- Catches up quickly on the way down, calmly on the way back up.
    local tau = (want < self.camY) and 0.18 or 0.30
    local t = 1.0 - math.pow(0.001, dt / tau)
    self.camY = self.camY + (want - self.camY) * t
    local cx = select(1, view.center())
    view.setCenter(cx, self.camY)
end

function Ember:destroy()
    -- Hand back what init() added to the scene.
    if self.fx and self.fx.made then
        for _, go in ipairs(self.fx.made) do
            if go then scene:remove(go) end
        end
        self.fx.made = {}
    end
end

return Ember
