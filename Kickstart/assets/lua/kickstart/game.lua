-- assets/lua/kickstart/game.lua - the rules of Kickstart.
--
-- A race along a motocross track, seen from the side, in 3D: the bikes are
-- 2D physics (a chassis and two wheels on sprung wheel joints, in the plane
-- of the screen) and the models are hung on those bodies. This turns the rear
-- wheel, leans the rider, and puts the fork, the swingarm and the rider's
-- arms and legs where the bodies say they are.
--
--   Bike<n>               the chassis body         Bike<n>_WR / _WF       the wheel bodies
--   Bike<n>_ForkLower, _Swingarm, _Rider_*         parts this script moves
--   Bike<n>_Roost         the dirt off the rear wheel   Bike<n>_Engine    its sound
--   Track                 the dirt: an Extrusion2D Start, Finish          where the race runs from and to
--   Cam                   the camera
--
-- What it leans on in the engine:
--   Physics2D in a 3D scene    bodies in the plane of the screen, models as their children
--   Joint2D wheel joints       suspension: a spring along one line, free to turn
--   applyTorque                the engine, the brakes, the rider's weight
--   ParticleSystem, Collide 2D dirt that lands on the track
--   AudioSource pitch          one engine loop, played at the revs
--   UI canvas, touch           the interface; pedals for thumbs
--   tween, lang, store         eased words, two languages, best times kept

local TRACKS = 3

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function clock(t)
    if not t then return "-:--.--" end
    local m = math.floor(t / 60)
    return string.format("%d:%05.2f", m, t - m * 60)
end
local function bestOf(track)
    local v = store and store.read("kickstart_time_" .. track)
    return tonumber(v or "")
end

return function(cfg)

-- The track is in the scene: "Track" is an Extrusion2D (its outline is the ground, and the
-- collider), and the race runs from the object "Start" to the object "Finish". Reshape the one
-- or move the others in the editor and this needs no telling.
local TRACK = { length = 400, start = 0 }
local GROUND, GROUND_X, GROUND_Y = nil, 0, 0

-- The bike, as tools/make_bike.py drew it (x forward, y up, from the bike's own origin).
local RA, FA = { -0.72, 0.33 }, { 0.76, 0.35 }
local PIVOT, GRIP, PEG = { -0.14, 0.44 }, { 0.36, 1.16 }, { -0.16, 0.42 }
local L_TORSO, L_UPPER, L_FORE, L_THIGH, L_SHIN = 0.50, 0.29, 0.27, 0.42, 0.44
local SWING_REST = math.atan(RA[2] - PIVOT[2], RA[1] - PIVOT[1])

local GRAVITY = -16.0
local DRIVE = 110.0           -- the torque the engine puts on the rear wheel
local TOP = 68.0              -- how fast the rear wheel will turn, radians a second
local BRAKE = 55.0
local LEAN_AIR, LEAN_GROUND = 15.0, 6.0
local SPIN_MAX = 5.5         -- leaning stops adding turn past this, radians a second: about a flip a second

-- Tricks: where the rider puts himself while the key is held, in the air. Hands and feet left
-- out stay on the bars and the pegs. (x forward, y up, from the bike's own origin.)
local TRICKS = {
    { key = "superman", hipX = -1.02, hipY = 1.42, lean = 1.50, feet = { -1.95, 1.52 }, points = 300 },
    { key = "nohander", hipX = -0.36, hipY = 1.04, lean = 0.06, hands = { -0.20, 2.12 }, points = 220 },
    { key = "cancan", hipX = -0.46, hipY = 1.10, lean = 0.22, feet = { 0.62, 1.46 }, points = 260 },
}

-- The ground's height at x: asked of the track's outline.
local function groundAt(x)
    if not GROUND then return 0 end
    return GROUND:heightAt(x - GROUND_X) + GROUND_Y
end
local function slopeAt(x) return math.atan(groundAt(x + 0.6) - groundAt(x - 0.6), 1.2) end

-- Two bones from a root reaching a target: their angles, from straight down, forward positive.
local function twoBone(rx, ry, tx, ty, l1, l2, bend)
    local dx, dy = tx - rx, ty - ry
    local d = clamp(math.sqrt(dx * dx + dy * dy), 1e-4, l1 + l2 - 1e-4)
    local base = math.atan(dx, -dy)
    local a = math.acos(clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1))
    local b = math.acos(clamp((l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2), -1, 1))
    local first = base + bend * a
    return first, first - bend * (math.pi - b)
end

local Game = class(cfg.menu and 'KickstartTitle' or ('Kickstart' .. tostring(cfg.track)))

function Game:initialize()
    self.clock = 0
end

-- ----- starting up ---------------------------------------------------------------------------

function Game:init(owner)
    KICK = KICK or {}
    if KICK.lang then lang.load(KICK.lang) else KICK.lang = lang.loadBest({ "en", "pt" }) or "en" end
    self.sounds = {}
    for name, voices in pairs({ ["beep.wav"] = 1, ["go.wav"] = 1, ["land.ogg"] = 3, ["land2.ogg"] = 2, ["crash.ogg"] = 2, ["thud.ogg"] = 2,
                                ["flip.ogg"] = 1, ["click.ogg"] = 2, ["confirm.ogg"] = 1, ["win.ogg"] = 1, ["lose.ogg"] = 1 }) do
        local ok, s = pcall(function() return Sound.new(ASSETS_PATH .. "sounds/" .. name, voices) end)
        if ok and s and s:isLoaded() then self.sounds[name:match("^(.-)%.")] = s end
    end
    local amb = scene:find("CrowdAmb")
    self.crowd = amb and amb:getComponent("AudioSource")
    if self.crowd and not self.crowd:isPlaying() then self.crowd:play() end
    self.cam = scene:find("Cam")
    self.ui = {}
    local function U(name) self.ui[name] = ui.find(scene, name) return self.ui[name] end
    U("Fade")
    if cfg.menu then
        for i = 1, TRACKS do U("Track" .. i) U("Track" .. i .. "_Best") end
        U("Language") U("Language_Label")
        self:refreshMenu()
        self.camX = 60
    else
        for _, n in ipairs({ "Pos", "Time", "Best", "Bar", "Dot0", "Dot1", "Dot2", "Dot3", "BtnMenu", "BtnRetry", "Big", "BigShade", "Hint",
                             "PadBack", "PadFwd", "PadBrake", "PadGas", "PadTrick", "Score", "Card", "CardTitle", "CardTime", "CardBest", "CardScore",
                             "CardMenu", "CardRetry", "CardNext" }) do U(n) end
        physics2d:setGravity(0, GRAVITY)
        local track, start, finish = scene:find("Track"), scene:find("Start"), scene:find("Finish")
        GROUND = track and track:getComponent("Extrusion2D")
        if track then local tp = track:getPosition() GROUND_X, GROUND_Y = tp.x, tp.y end
        TRACK.start = start and start:getPosition().x or 0
        TRACK.length = finish and finish:getPosition().x or 400
        self:findBikes()
        self:startRace()
    end
    lang.apply(scene)
    if not cfg.menu then self:refreshBest() end
    -- (the scene keeps its Fade clear, so that it can be seen in the editor: black is put up here, and eased away)
    if self.ui.Fade then ui.setTint(self.ui.Fade, Vec4.new(0, 0, 0, 1)) end
    if self.ui.Fade then tween.tint(self.ui.Fade, 0, 0, 0, 0, 0.5, "out") end
end

function Game:play(name, volume, pitch)
    local s = self.sounds[name]
    if s then s:play(volume or 0.8, pitch or 1.0) end
end

function Game:fadeThen(fn)
    if self.leaving then return end
    self.leaving = true
    if self.ui.Fade then tween.tint(self.ui.Fade, 0, 0, 0, 1, 0.3, "in", fn) else fn() end
end

-- ----- the menu ----------------------------------------------------------------------------------

function Game:refreshMenu()
    for i = 1, TRACKS do
        local b = bestOf(i)
        if self.ui["Track" .. i .. "_Best"] then ui.setText(self.ui["Track" .. i .. "_Best"], b and clock(b) or tr("nobest")) end
    end
    if self.ui.Language_Label then ui.setText(self.ui.Language_Label, string.upper(KICK.lang)) end
end

function Game:updateMenu(dt)
    -- the camera drifts along the empty track
    self.camX = self.camX + dt * 2.2
    if self.camX > 120 then self.camX = 30 end
    self.cam:setPosition(Vec3.new(self.camX, 4.2, 15))
    self.cam:setRotation(Vec3.new(-0.02, 0, 0))
    for i = 1, TRACKS do
        if self.ui["Track" .. i] and ui.wasClicked(self.ui["Track" .. i]) then
            self:play("confirm")
            self:fadeThen(function() loadScene("scenes/Track" .. i .. ".json") end)
        end
    end
    if self.ui.Language and ui.wasClicked(self.ui.Language) then
        KICK.lang = (KICK.lang == "en") and "pt" or "en"
        lang.load(KICK.lang)
        lang.apply(scene)
        self:refreshMenu()
        self:play("click")
    end
end

-- ----- the bikes ------------------------------------------------------------------------------------

function Game:findBikes()
    self.bikes = {}
    for i = 0, 3 do
        local n = "Bike" .. i
        local b = scene:find(n)
        if b then
            local bike = {
                index = i, go = b, body = b:getComponent("Physics2D"),
                wr = scene:find(n .. "_WR"), wf = scene:find(n .. "_WF"),
                fork = scene:find(n .. "_ForkLower"), swing = scene:find(n .. "_Swingarm"),
                torso = scene:find(n .. "_Rider_Torso"), head = scene:find(n .. "_Rider_Head"),
                upper = scene:find(n .. "_Rider_UpperArm"), fore = scene:find(n .. "_Rider_ForeArm"),
                thigh = scene:find(n .. "_Rider_Thigh"), shin = scene:find(n .. "_Rider_Shin"),
                ai = i > 0, rival = i > 0,
            }
            bike.rear = bike.wr:getComponent("Physics2D")
            bike.front = bike.wf:getComponent("Physics2D")
            local roost = scene:find(n .. "_Roost")
            bike.roost = roost and roost:getComponent("ParticleSystem")
            local eng = scene:find(n .. "_Engine")
            bike.engine = eng and eng:getComponent("AudioSource")
            if bike.engine and not bike.engine:isPlaying() then bike.engine:play() end
            self.bikes[#self.bikes + 1] = bike
        end
    end
    self.player = self.bikes[1]
end

function Game:startRace()
    -- how good the others are: a little slower than flat out, each differently, harder on later tracks
    local base = ({ 0.74, 0.85, 0.92 })[cfg.track] or 0.85
    for k, bike in ipairs(self.bikes) do
        bike.ai = bike.rival
        bike.lean, bike.crouch, bike.gas, bike.brake, bike.revs = 0, 0, 0, 0, 0
        bike.upside, bike.air, bike.turned, bike.finished, bike.place = 0, 0, 0, nil, nil
        bike.pose, bike.trick, bike.points, bike.done, bike.showoff = 0, 0, 0, {}, nil
        bike.skill = bike.rival and (base + (k - 2) * 0.045) or 1.0
        bike.boost = 0
        self:reset(bike, TRACK.start - 1.6)
    end
    self.state, self.count, self.time, self.finishers = "grid", 3.6, 0, 0
    self.score, self.jumps = 0, 0
    self.lastCount = 4
    self.camX, self.camY = self.player.go:getPosition().x + 3, 3
    local U = self.ui
    if U.Card then ui.setVisible(U.Card, false) end
    if U.Hint then ui.setVisible(U.Hint, not KICK.touch) end
    self:big("")
end

function Game:refreshBest()
    local b = bestOf(cfg.track)
    if self.ui.Best then ui.setText(self.ui.Best, b and tr("best", clock(b)) or tr("nobest")) end
end

-- The big words in the middle of the screen.
function Game:big(words, hold)
    local U = self.ui
    if U.Big then ui.setText(U.Big, words) ui.setText(U.BigShade, words) end
    self.bigFor = hold or 0
end

-- Put a bike on its wheels at x.
function Game:reset(bike, x)
    local y = groundAt(x) + 0.05
    local angle = slopeAt(x)
    local ca, sa = math.cos(angle), math.sin(angle)
    bike.body:setTransform(Vec2.new(x, y), angle)
    bike.rear:setTransform(Vec2.new(x + RA[1] * ca - RA[2] * sa, y + RA[1] * sa + RA[2] * ca), 0)
    bike.front:setTransform(Vec2.new(x + FA[1] * ca - FA[2] * sa, y + FA[1] * sa + FA[2] * ca), 0)
    for _, b in ipairs({ bike.body, bike.rear, bike.front }) do
        b:setLinearVelocity(0, 0)
        b:setAngularVelocity(0)
    end
    bike.upside, bike.air, bike.turned = 0, 0, 0
    bike.pose, bike.trick, bike.points, bike.done = 0, 0, 0, {}
end

function Game:input()
    local gas, brake, lean, trick = 0, 0, 0, 0
    if isKeyDown(Key.J) then trick = 1 elseif isKeyDown(Key.K) then trick = 2 elseif isKeyDown(Key.L) then trick = 3 end
    if isKeyDown(Key.W) or isKeyDown(Key.Up) then gas = 1 end
    if isKeyDown(Key.S) or isKeyDown(Key.Down) then brake = 1 end
    if isKeyDown(Key.A) or isKeyDown(Key.Left) then lean = lean + 1 end       -- back: the front comes up
    if isKeyDown(Key.D) or isKeyDown(Key.Right) then lean = lean - 1 end      -- forward: the front goes down
    if gamepad.isConnected(0) then
        gas = math.max(gas, gamepad.axis(0, GamepadAxis.RightTrigger), gamepad.isDown(0, GamepadButton.A) and 1 or 0)
        brake = math.max(brake, gamepad.axis(0, GamepadAxis.LeftTrigger))
        local ax = gamepad.axis(0, GamepadAxis.LeftX)
        if math.abs(ax) > 0.2 then lean = -ax end
        if gamepad.isDown(0, GamepadButton.X) then trick = 1 elseif gamepad.isDown(0, GamepadButton.Y) then trick = 2
        elseif gamepad.isDown(0, GamepadButton.B) then trick = 3 end
    end
    -- thumbs: two on the left to lean, two on the right for the pedals - any of them at once
    local U = self.ui
    if touch.count() > 0 and not KICK.touch then
        KICK.touch = true
        if U.Hint then ui.setVisible(U.Hint, false) end
    end
    for _, n in ipairs({ "PadBack", "PadFwd", "PadBrake", "PadGas", "PadTrick" }) do
        if U[n] then ui.setVisible(U[n], KICK.touch == true) end
    end
    if KICK.touch then
        if U.PadGas and ui.isHeld(scene, U.PadGas) then gas = 1 end
        if U.PadBrake and ui.isHeld(scene, U.PadBrake) then brake = 1 end
        if U.PadBack and ui.isHeld(scene, U.PadBack) then lean = lean + 1 end
        if U.PadFwd and ui.isHeld(scene, U.PadFwd) then lean = lean - 1 end
        -- one trick button: a different trick each jump
        if U.PadTrick and ui.isHeld(scene, U.PadTrick) then trick = (self.jumps or 0) % #TRICKS + 1 end
    end
    return gas, brake, lean, trick
end

-- A rider that is not you: gas, and the bike held at the angle of the ground it is on or coming down to.
function Game:think(bike)
    local p = bike.go:getPosition()
    local v = bike.body:getLinearVelocity()
    local angle = bike.body:getAngle()
    -- (in the air: where it will come down - as far ahead as it will fly before it meets the ground)
    local ahead = 0.8
    if not bike.grounded then
        local t, x, y, vy = 0, p.x, p.y, v.y
        while t < 3.0 do
            t = t + 0.08
            x, vy = x + v.x * 0.08, vy + GRAVITY * 0.08
            y = y + vy * 0.08
            if y <= groundAt(x) + 0.3 then break end
        end
        ahead = math.max(1.0, x - p.x)
    end
    local want = slopeAt(p.x + ahead)
    if not bike.grounded then want = want + 0.06 end
    local err = want - angle
    local spin = bike.body:getAngularVelocity()
    local lean = clamp(err * 5.0 - spin * 0.9, -1, 1)
    local gas = (math.abs(err) < 0.9) and 1 or 0.3
    if bike.grounded and v.x > 23 * bike.skill then gas = 0 end
    -- a long flight is a chance to show off: a trick through the middle of it, let go in good time
    local trick = 0
    if not bike.grounded and bike.air > 0.25 and bike.showoff then
        local t, x, y, vy = 0, p.x, p.y, v.y
        while t < 3.0 do
            t = t + 0.1
            x, vy = x + v.x * 0.1, vy + GRAVITY * 0.1
            y = y + vy * 0.1
            if y <= groundAt(x) + 0.4 then break end
        end
        if t > 0.55 then trick = bike.showoff end
    end
    return gas, 0, lean, trick
end

function Game:control(bike, dt)
    local gas, brake, lean, trick = 0, 0, 0, 0
    if self.state == "grid" then
        brake = 1
        if not bike.ai then gas = select(1, self:input()) end        -- (revving on the line: heard, and held by the brake)
    elseif bike.finished then
        brake = 1
    elseif bike.ai then
        gas, brake, lean, trick = self:think(bike)
        if bike == self.player then                       -- (on autopilot the trick keys are still yours)
            local _, _, _, mine = self:input()
            if mine > 0 then trick = mine end
        end
    else
        gas, brake, lean, trick = self:input()
    end
    bike.gas, bike.brake = gas, brake
    -- (the rider's weight moves over a moment, not at once: a tap is a nudge, a hold is a lean)
    bike.lean = lerp(bike.lean, lean, math.min(1, dt * (bike.ai and 10 or 4.5)))

    local rear, front, body = bike.rear, bike.front, bike.body
    local spin = rear:getAngularVelocity()           -- forward is clockwise: negative
    local grounded = rear:isGrounded() or front:isGrounded()
    -- The engine: a torque on the rear wheel that fades as the wheel nears its top speed,
    -- and the same torque the other way on the frame - which is what lifts the front under power.
    if gas > 0 and self.state ~= "grid" then
        -- (a rival has a little less of everything than you: that is all its "skill" is)
        local top = TOP * bike.skill * (1 + bike.boost * 0.25)
        -- (all of it up to two thirds of top speed, then less and less, and none at the top)
        local room = clamp((top + spin) / (top * 0.34), 0, 1)
        local t = DRIVE * gas * room * bike.skill * (1 + bike.boost * 0.4)
        rear:applyTorque(-t)
        if rear:isGrounded() then body:applyTorque(t * 0.09) end      -- (only against the ground: in the air the throttle does not pitch the bike)
    end
    if brake > 0 then
        rear:applyTorque(clamp(-spin * 6, -BRAKE, BRAKE) * brake)
        local fs = front:getAngularVelocity()
        front:applyTorque(clamp(-fs * 6, -BRAKE, BRAKE) * brake * 0.7)
    end
    -- The rider's weight: a turn on the frame, firmer in the air where there is nothing else to turn it.
    -- It fades as the bike is already turning that way, so holding a lean settles into a steady
    -- spin instead of winding up; and with no lean at all in the air the spin dies away.
    local turning = body:getAngularVelocity()
    local room = clamp(1 - (turning * (bike.lean >= 0 and 1 or -1)) / SPIN_MAX, 0, 1.5)
    body:applyTorque(bike.lean * (grounded and LEAN_GROUND or LEAN_AIR) * room)
    if not grounded and math.abs(lean) < 0.15 and not bike.ai then
        -- Left alone in the air, the bike eases itself towards the ground it is coming down to:
        -- enough that holding the gas over a jump is survivable, not so much that it lands itself.
        local p, v = bike.go:getPosition(), body:getLinearVelocity()
        local err = slopeAt(p.x + clamp(v.x * 0.5, 1, 10)) + 0.05 - body:getAngle()
        body:applyTorque(clamp(err * 4.0 - turning * 1.2, -1, 1) * LEAN_AIR * 0.55)
    end
    bike.boost = math.max(0, bike.boost - dt * 0.5)

    -- In the air: how far round it has turned, and what trick is being held. Coming down the
    -- right way up, hands and feet back where they belong, is worth what was done - points, and
    -- a burst of speed. Coming down still in a trick is a crash.
    local av = body:getAngularVelocity()
    if grounded then
        if bike.air > 0.25 then
            local flips = math.floor(math.abs(bike.turned) / (math.pi * 2) + 0.25)
            local straight = math.abs(body:getAngle() - slopeAt(bike.go:getPosition().x)) < 1.0
            if bike.pose > 0.45 then
                bike.upside = 1.0                                   -- (caught out: the reset below takes it from here)
                if bike == self.player then self:big(tr("bail"), 1.0) self:play("crash", 0.8) end
                bike.points = 0
            elseif straight and (flips >= 1 or bike.points > 60) then
                local total = math.floor(bike.points + flips * 500)
                bike.boost = clamp(total / 700, 0.3, 1.0)
                if bike == self.player then
                    local words = {}
                    for _, name in ipairs(bike.done) do words[#words + 1] = tr(name) end
                    if flips >= 1 then words[#words + 1] = (flips > 1 and (flips .. "x ") or "") .. tr(bike.turned > 0 and "backflip" or "frontflip") end
                    self.score = self.score + total
                    self:big(table.concat(words, " + ") .. "  +" .. total, 1.6)
                    self:play("flip", 0.8)
                end
            end
            if bike == self.player then
                self:play(bike.air > 0.9 and "land" or "land2", clamp(bike.air, 0.3, 0.9))
                self.jumps = (self.jumps or 0) + 1
            end
        end
        bike.air, bike.turned, bike.points, bike.done = 0, 0, 0, {}
        bike.showoff = (bike.ai and math.random() < 0.6) and math.random(1, #TRICKS) or nil
    else
        bike.air = bike.air + dt
        bike.turned = bike.turned + av * dt
        if trick > 0 and bike.air > 0.15 then
            if bike.trick ~= trick then
                bike.trick = trick
                local name, seen = TRICKS[trick].key, false
                for _, d in ipairs(bike.done) do if d == name then seen = true end end
                if not seen then bike.done[#bike.done + 1] = name end
            end
            if bike.pose > 0.8 then bike.points = bike.points + TRICKS[trick].points * dt end
        end
    end
    -- the pose eases to the trick held, and back
    local holding = (not grounded) and trick > 0
    bike.pose = clamp(bike.pose + (holding and dt * 5.5 or -dt * 6.5), 0, 1)
    if bike.pose <= 0 and not holding then bike.trick = 0 end
    bike.grounded = grounded

    -- What is heard and seen of the engine: revs follow the wheel, or the throttle when it is held on the line.
    local wheelRevs = clamp(-spin / TOP, 0, 1.2)
    local target = math.max(wheelRevs, (self.state == "grid" or not grounded) and gas * 0.8 or 0)
    bike.revs = lerp(bike.revs, target, math.min(1, dt * 7))
    if bike.engine then
        local near = 1 / (1 + math.abs(bike.go:getPosition().x - self.player.go:getPosition().x) * 0.12)
        bike.engine:setPitch(0.55 + bike.revs * 1.5 + gas * 0.08)
        bike.engine:setVolume((bike.ai and 0.16 or 0.34) * near * (0.55 + 0.45 * gas))
    end
    if bike.roost then
        local digging = (rear:isGrounded() and gas > 0.5 and self.state ~= "grid") and clamp(0.4 + (1 - wheelRevs), 0.3, 1) or 0
        bike.roost:setEmissionRate(digging * 70)
    end
end

-- The parts follow the bodies. Everything here is in the chassis's own space
-- (the parts are its children), so a part's place is where its body is, seen from the chassis.
function Game:dress(bike, dt)
    local p, a = bike.go:getPosition(), bike.body:getAngle()
    local ca, sa = math.cos(-a), math.sin(-a)
    local function toLocal(wx, wy)
        local dx, dy = wx - p.x, wy - p.y
        return dx * ca - dy * sa, dx * sa + dy * ca
    end
    local rp, fp = bike.wr:getPosition(), bike.wf:getPosition()
    local rx, ry = toLocal(rp.x, rp.y)
    local fx, fy = toLocal(fp.x, fp.y)
    bike.fork:setPosition(Vec3.new(fx, fy, 0))
    bike.swing:setRotation(Vec3.new(0, 0, math.atan(ry - PIVOT[2], rx - PIVOT[1]) - SWING_REST))

    -- The rider. Leaning back sits him over the rear wheel, leaning forward brings him over the bars;
    -- landing folds his legs.
    local squat = clamp((RA[2] - ry) * 2.2 + (FA[2] - fy) * 1.2, -0.4, 1.0)
    bike.crouch = lerp(bike.crouch, squat, math.min(1, dt * 12))
    local hipX = -0.40 - bike.lean * 0.16
    local hipY = 1.07 - math.max(0, bike.crouch) * 0.10 - math.abs(bike.lean) * 0.03
    local leanAngle = 0.60 - bike.lean * 0.30 + math.max(0, bike.crouch) * 0.12
    local handX, handY = GRIP[1] - 0.02, GRIP[2] + 0.04
    local footX, footY = PEG[1] - 0.03, PEG[2] + 0.11
    local t = TRICKS[bike.trick]
    if t and bike.pose > 0 then
        local k = bike.pose * bike.pose * (3 - 2 * bike.pose)
        hipX, hipY, leanAngle = lerp(hipX, t.hipX, k), lerp(hipY, t.hipY, k), lerp(leanAngle, t.lean, k)
        if t.hands then handX, handY = lerp(handX, t.hands[1], k), lerp(handY, t.hands[2], k) end
        if t.feet then footX, footY = lerp(footX, t.feet[1], k), lerp(footY, t.feet[2], k) end
    end
    bike.torso:setPosition(Vec3.new(hipX, hipY, 0))
    bike.torso:setRotation(Vec3.new(0, 0, -leanAngle))
    local shX, shY = hipX + math.sin(leanAngle) * L_TORSO * 0.94, hipY + math.cos(leanAngle) * L_TORSO * 0.94
    local nkX, nkY = hipX + math.sin(leanAngle) * (L_TORSO + 0.02), hipY + math.cos(leanAngle) * (L_TORSO + 0.02)
    bike.head:setPosition(Vec3.new(nkX, nkY, 0))
    bike.head:setRotation(Vec3.new(0, 0, -leanAngle * 0.35))
    local a1, a2 = twoBone(shX, shY, handX, handY, L_UPPER, L_FORE + 0.03, -1)
    bike.upper:setPosition(Vec3.new(shX, shY, 0))
    bike.upper:setRotation(Vec3.new(0, 0, a1))
    bike.fore:setPosition(Vec3.new(shX + math.sin(a1) * L_UPPER, shY - math.cos(a1) * L_UPPER, 0))
    bike.fore:setRotation(Vec3.new(0, 0, a2))
    local t1, t2 = twoBone(hipX, hipY, footX, footY, L_THIGH, L_SHIN, 1)
    bike.thigh:setPosition(Vec3.new(hipX, hipY, 0))
    bike.thigh:setRotation(Vec3.new(0, 0, t1))
    bike.shin:setPosition(Vec3.new(hipX + math.sin(t1) * L_THIGH, hipY - math.cos(t1) * L_THIGH, 0))
    bike.shin:setRotation(Vec3.new(0, 0, t2))
end

-- ----- the race --------------------------------------------------------------------------------------

function Game:finish(bike)
    self.finishers = self.finishers + 1
    bike.finished, bike.place = self.time, self.finishers
    if bike ~= self.player then return end
    self.state = "over"
    local best = bestOf(cfg.track)
    local isBest = (not best) or self.time < best
    if isBest and store then store.write("kickstart_time_" .. cfg.track, string.format("%.2f", self.time)) end
    self:play(bike.place == 1 and "win" or "lose", 0.8)
    local U = self.ui
    tween.after(1.0, function()
        if U.Card then ui.setVisible(U.Card, true) end
        if U.CardTitle then ui.setText(U.CardTitle, tr("place_" .. bike.place)) end
        if U.CardTime then ui.setText(U.CardTime, clock(self.time)) end
        if U.CardScore then ui.setText(U.CardScore, tr("tricks", self.score)) end
        if U.CardBest then ui.setText(U.CardBest, isBest and tr("newbest") or tr("best", clock(best))) end
        if U.CardNext then ui.setVisible(U.CardNext, cfg.track < TRACKS) end
        self:refreshBest()
    end)
end

function Game:updateRace(dt)
    if self.state == "grid" then
        self.count = self.count - dt
        local n = math.ceil(self.count)
        if n ~= self.lastCount then
            self.lastCount = n
            if n >= 1 and n <= 3 then self:big(tostring(n), 0.9) self:play("beep", 0.7)
            elseif n <= 0 then
                self.state = "race"
                self:big(tr("go"), 0.8)
                self:play("go", 0.8)
            end
        end
    elseif self.state == "race" then
        self.time = self.time + dt
    end
    if (self.bigFor or 0) > 0 then
        self.bigFor = self.bigFor - dt
        if self.bigFor <= 0 then self:big("") end
    end

    for _, bike in ipairs(self.bikes) do
        self:control(bike, dt)
        self:dress(bike, dt)
        local p, a = bike.go:getPosition(), bike.body:getAngle()
        -- on its back, or its rider's head in the dirt: after a moment, back on its wheels a little way back
        local headX, headY = p.x - math.sin(a) * 1.55, p.y + math.cos(a) * 1.55
        local down = headY < groundAt(headX) + 0.12 or p.y < groundAt(p.x) - 3
        if down and bike.upside == 0 and not bike.ai then self:play("crash", 0.7) end
        bike.upside = down and bike.upside + dt or 0
        if bike.upside > 0.6 then self:reset(bike, clamp(p.x - 3, TRACK.start - 1.6, TRACK.length + 20)) end
        -- a rival going nowhere (wedged against a face it came up short of) is set down again where it is
        if bike.ai and self.state == "race" and not bike.finished then
            bike.stall = (math.abs(bike.body:getLinearVelocity().x) < 1.0) and (bike.stall or 0) + dt or 0
            if bike.stall > 2.0 then self:reset(bike, p.x + 1.5) bike.stall = 0 end
        end
        if not bike.finished and self.state ~= "grid" and p.x >= TRACK.length then self:finish(bike) end
    end

    -- who is where
    local px = self.player.go:getPosition().x
    local place = 1
    for _, bike in ipairs(self.bikes) do
        if bike ~= self.player then
            if bike.finished and not self.player.finished then place = place + 1
            elseif not bike.finished and not self.player.finished and bike.go:getPosition().x > px then place = place + 1 end
        end
    end
    if self.player.place then place = self.player.place end
    local U = self.ui
    if U.Pos then ui.setText(U.Pos, tostring(place)) end
    if U.Time then ui.setText(U.Time, clock(self.time)) end
    if U.Score then ui.setText(U.Score, tostring(self.score)) end
    for _, bike in ipairs(self.bikes) do
        local dot = U["Dot" .. bike.index]
        if dot then
            local f = clamp((bike.go:getPosition().x - TRACK.start) / math.max(1, TRACK.length - TRACK.start), 0, 1) * 520
            local r = (bike == self.player) and 11 or 8
            ui.setOffsets(dot, f - r, -r, f + r, r)
        end
    end
    if self.crowd then
        -- the stand gets louder when someone is in the air
        local up = 0
        for _, bike in ipairs(self.bikes) do if bike.air > 0.4 then up = up + 1 end end
        self.cheer = lerp(self.cheer or 0, up > 0 and 1 or 0, math.min(1, dt * 2))
        self.crowd:setVolume(0.20 + self.cheer * 0.18)
    end

    -- The camera: ahead of the player, level with the ground he is over, further back the faster he goes.
    local p = self.player.go:getPosition()
    local v = self.player.body:getLinearVelocity()
    local wantX = p.x + 2.5 + clamp(v.x * 0.22, -2, 5)
    -- (in the air it backs off, to keep the bike and the ground it is going to in one picture)
    local high = math.max(0, p.y - groundAt(p.x))
    local wantY = lerp(groundAt(p.x) + 2.6, p.y + 1.6, 0.6)
    self.camX = lerp(self.camX, wantX, math.min(1, dt * 5))
    self.camY = lerp(self.camY, wantY, math.min(1, dt * 3.5))
    self.camBack = lerp(self.camBack or 16, 15.5 + clamp(math.abs(v.x) * 0.2, 0, 5) + clamp(high * 1.1, 0, 12), math.min(1, dt * 2.5))
    local back = self.camBack
    self.cam:setPosition(Vec3.new(self.camX, self.camY + 1.4, back))
    self.cam:setRotation(Vec3.new(-0.09, 0, 0))

    -- buttons
    local function clicked(name) return U[name] and ui.wasClicked(U[name]) end
    local r = isKeyDown(Key.R)
    if clicked("BtnRetry") or clicked("CardRetry") or (self.rDown and not r) then
        self:play("click")
        self:fadeThen(function()
            self:startRace()
            self.leaving = false
            if U.Fade then tween.tint(U.Fade, 0, 0, 0, 0, 0.4, "out") end
        end)
    elseif clicked("BtnMenu") or clicked("CardMenu") then
        self:play("click")
        self:fadeThen(function() loadScene("scenes/Title.json") end)
    elseif clicked("CardNext") and cfg.track < TRACKS then
        self:play("confirm")
        self:fadeThen(function() loadScene("scenes/Track" .. (cfg.track + 1) .. ".json") end)
    end
    self.rDown = r
    -- P: the player's bike rides itself (how a track is checked to be one that can be finished)
    local pk = isKeyDown(Key.P)
    if pk and not self.pDown then self.player.ai = not self.player.ai end
    self.pDown = pk
end

function Game:update(dt)
    if dt <= 0 then return end
    dt = math.min(dt, 0.05)
    self.clock = self.clock + dt
    if cfg.menu then self:updateMenu(dt) else self:updateRace(dt) end
end

return Game

end
