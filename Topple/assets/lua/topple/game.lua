-- assets/lua/topple/game.lua - the rules of Topple, the same in every level.
--
-- A level is a scene: its blocks, targets, shots, sling, lights, layers and
-- interface were all placed in the editor. This file reads that scene by
-- name and runs it:
--
--   B_<material>_<shape>_<n>   a block: takes damage from what hits it,
--                              chips, cracks and breaks
--   T_<colour>_<n>             a target: the level is won when none is left
--   A_<colour>_<n>             a shot, fired from the sling in order
--   D_<n>                      a pool of debris pieces, parked out of sight
--
-- A level's own script (scenes/<Level>.lua) is three lines: it loads this
-- and hands it what differs - the score each star takes and what comes next.

local FX = assert(loadfile(ASSETS_PATH .. "lua/topple/fx.lua"))()
local Sounds = assert(loadfile(ASSETS_PATH .. "lua/topple/sounds.lua"))()

local GRAVITY = -22.0
local PULL_MAX = 3.3           -- how far the pouch stretches
local POWER = 8.0              -- launch speed per unit of stretch
local GRAB = 1.5               -- how near the pouch a press has to be

-- What it takes to hurt each material, and how much it can take: a hit
-- softer than `tough` does nothing, and `hp` is for a 1 x 1 piece.
local MATERIAL = {
    wood  = { hp = 5, tough = 2.6, score = 100, colour = { 0.72, 0.47, 0.25 }, hit = { "wood_1", "wood_2", "wood_3" }, crack = "wood_break" },
    glass = { hp = 2.4, tough = 1.6, score = 80,  colour = { 0.82, 0.93, 1.00 }, hit = { "glass_1", "glass_2" }, crack = "glass_break" },
    stone = { hp = 11, tough = 3.6, score = 160, colour = { 0.66, 0.70, 0.70 }, hit = { "stone_1", "stone_2" }, crack = "stone_break" },
    metal = { hp = 40, tough = 6.5, score = 220, colour = { 0.75, 0.82, 0.86 }, hit = { "metal_1", "metal_2", "metal_3" }, crack = "metal_break" },
    tnt   = { hp = 5,  tough = 3.0, score = 150, colour = { 1.00, 0.80, 0.10 }, hit = { "metal_1" }, crack = "boom_1" },
}
local AREA = { sq = 1, block = 2, plank = 3.1, big = 4, slab = 6.3, post = 3.1, pillar = 2, ball = 0.8, tri = 1 }
local TARGET = { hp = 2.0, tough = 1.5, score = 1000 }
local SHOT_BONUS = 1500
-- what a second press does, said once when such a shot is first loaded
local HINT = { yellow = "TAP WHILE IT FLIES:  A BURST OF SPEED", blue = "TAP WHILE IT FLIES:  ONE BECOMES THREE",
               pink = "TAP WHILE IT FLIES:  BOOM" }
local TRAIL = { green = { 0.55, 0.95, 0.75 }, yellow = { 1.0, 0.9, 0.3 }, blue = { 0.55, 0.75, 1.0 },
                pink = { 1.0, 0.6, 0.75 }, beige = { 0.95, 0.9, 0.75 } }

local WORLDS = { "MEADOW", "DUNES", "GROVE", "KEEP", "MOONLIT" }
local PER_WORLD = 20
local LEVELS = #WORLDS * PER_WORLD

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- What is kept between one visit and the next: for every level won, its
-- stars and its best score. One line of text in the game's own store - a
-- file on a desktop, the browser's local storage on the web.
local function loadProgress()
    local p = { stars = {}, best = {} }
    local text = store and store.read("progress")
    if type(text) == "string" then
        for n, stars, best in text:gmatch("(%d+):(%d+):(%d+)") do
            p.stars[tonumber(n)], p.best[tonumber(n)] = tonumber(stars), tonumber(best)
        end
    end
    return p
end
local function saveProgress(p)
    local parts = {}
    for n = 1, LEVELS do
        if p.stars[n] then parts[#parts + 1] = n .. ":" .. p.stars[n] .. ":" .. math.floor(p.best[n] or 0) end
    end
    if store then store.write("progress", table.concat(parts, ",")) end
end
local function sceneOf(level) return "scenes/World" .. (math.floor((level - 1) / PER_WORLD) + 1) .. ".json" end
local function lerp(a, b, t) return a + (b - a) * t end

return function(cfg)

local Game = class(cfg.menu and 'ToppleTitle' or ('ToppleWorld' .. tostring(cfg.world)))

function Game:initialize()
    self.clock = 0
    self.state = "intro"
    self.score, self.shown = 0, 0
end

-- ----- reading the scene -----------------------------------------------------

function Game:init(owner)
    TOPPLE = TOPPLE or {}
    if not TOPPLE.progress then TOPPLE.progress = loadProgress() end
    physics2d:setGravity(0, GRAVITY)

    self.sounds = Sounds.new()
    self.fx = FX.new(scene)

    local function children(name)
        local parent = scene:find(name)
        return parent and parent:getChildren() or {}
    end
    self.debris, self.dots = {}, {}
    self.blocks, self.targets, self.shots, self.spares, self.all, self.ropes, self.dead = {}, {}, {}, {}, {}, {}, {}
    for _, go in ipairs(children("Debris")) do
        self.debris[#self.debris + 1] = { go = go, body = go:getComponent("Physics2D"), sprite = go:getComponent("Sprite2D"),
                                          park = go:getPosition(), life = 0 }
    end
    for _, go in ipairs(children("Dots")) do
        local sp = go:getComponent("Sprite2D")
        sp:setVisible(false)
        self.dots[#self.dots + 1] = { go = go, sprite = sp }
    end

    local pouch = scene:find("Pouch")
    local p = pouch:getPosition()
    self.rest = { x = p.x, y = p.y }
    self.bands = {}
    for _, name in ipairs({ "BandFar", "BandNear" }) do
        local go = scene:find(name)
        if go then self.bands[#self.bands + 1] = go:getComponent("Line2D") end
    end
    self.shock = scene:find("Shock")
    self.shockSprite = self.shock and self.shock:getComponent("Sprite2D")
    if self.shockSprite then self.shockSprite:setVisible(false) end
    self.flash = scene:find("Flash")
    self.flashLight = self.flash and self.flash:getComponent("PointLight")
    if self.flashLight then self.flashLight:setLightIntensity(0) end
    self.flashT, self.shockT = 0, 0

    self.clouds = children("Clouds")

    self.fireflies = {}
    for i, go in ipairs(children("Fireflies")) do
        local p = go:getPosition()
        self.fireflies[i] = { go = go, sprite = go:getComponent("Sprite2D"), x = p.x, y = p.y, z = p.z, seed = i * 1.7 }
    end

    -- the interface
    self.ui = {}
    for _, name in ipairs({ "HudScore", "HudHint", "HudHintPlate", "HudTitle", "BtnRetry", "BtnMenu", "Card", "CardTitle", "CardScore", "CardBest",
                            "CardStar1", "CardStar2", "CardStar3", "CardMenu", "CardRetry", "CardNext" }) do
        self.ui[name] = ui.find(scene, name)
    end
    if self.ui.Card then ui.setVisible(self.ui.Card, false) end

    -- The title screen is a level nobody is playing: the same scene
    -- objects and the same rules, with the sling firing by itself and the
    -- level buttons on top.
    if cfg.menu then
        self.drops = {}
        for i = 1, 3 do
            local go = scene:find("Drop_" .. i)
            if go then
                local s = { go = go, body = go:getComponent("Physics2D"), sprite = go:getComponent("Sprite2D"), colour = "green" }
                s.body.onContact = function(other, point, normal, speed) self:shotHit(s, other, point, speed) end
                self.drops[#self.drops + 1] = s
                self.all[#self.all + 1] = s
            end
        end
        self.mascot = scene:find("Mascot")
        self.dropT, self.dropN = 2.0, 0
        local U = self.ui
        for _, name in ipairs({ "Home", "Grid", "Play", "StarsTotal", "GridTitle", "GridBack" }) do U[name] = ui.find(scene, name) end
        local total = 0
        for w = 1, #WORLDS do
            U["World" .. w] = ui.find(scene, "World" .. w)
            local got = 0
            for n = (w - 1) * PER_WORLD + 1, w * PER_WORLD do got = got + (TOPPLE.progress.stars[n] or 0) end
            total = total + got
            local label = ui.find(scene, "World" .. w .. "_Stars")
            if label then ui.setText(label, got .. " / " .. PER_WORLD * 3) end
        end
        if U.StarsTotal then ui.setText(U.StarsTotal, total .. " / " .. LEVELS * 3) end
        for i = 1, PER_WORLD do
            U["Cell" .. i] = ui.find(scene, "Cell" .. i)
            U["CellNumber" .. i] = ui.find(scene, "Cell" .. i .. "_Number")
            for k = 1, 3 do U["CellStar" .. i .. "_" .. k] = ui.find(scene, "Cell" .. i .. "_Star" .. k) end
        end
        self:showGrid(TOPPLE.grid)
        self.state = "menu"
    end

    self.cam = { x = 3.0, y = 6.2, zoom = 8.0 }
    self.wasDown = false
    if cfg.menu then
        self:readLevel()            -- the title's own tower, placed in its scene
        self.next, self.settle = 1, 0
    else
        local first = (cfg.world - 1) * PER_WORLD + 1
        local level = TOPPLE.level
        if not level or level < first or level >= first + PER_WORLD then level = first end
        self:startLevel(level)
    end
    view.setCenter(self.cam.x, self.cam.y)
    view.setZoom(self.cam.zoom)
end

-- A world's scene holds no level. The level is a prefab - made in the
-- editor like the scene - and is put into it here; the one before it is
-- taken out. Starting a level again, or the next of the same world, is
-- this and not a scene load: nothing else in the scene changes.
function Game:startLevel(level)
    if self.root then scene:remove(self.root) self.root = nil end
    for _, d in ipairs(self.debris) do
        d.life = 0
        d.sprite:setVisible(false)
        d.body:setBodyType(BodyType2D.Kinematic)
        d.body:setLinearVelocity(0, 0)
        d.go:setPosition(d.park)
    end
    self:showDots(0, 0, 0, 0, false)
    TOPPLE.level, self.level = level, level
    self.root = Prefab.instantiate(string.format("assets/prefabs/L%03d.prefab", level))
    if self.root then
        scene:add(self.root)
        -- Where everything in it is, worked out now and not at the scene's
        -- next update: the bodies are made from where their objects are,
        -- and made before that update they were all made in one place.
        local function settle(go)
            go:refreshTransformation()
            for _, child in ipairs(go:getChildren()) do settle(child) end
        end
        settle(self.root)
    end
    self:readLevel()

    self.score, self.shown, self.scoreText = 0, 0, nil
    self.state, self.introT, self.settle, self.clock = "intro", TOPPLE.bot and 0.7 or 2.0, 0, 0
    self.next, self.current, self.flight, self.dragging, self.snap = 1, nil, nil, false, nil
    self.won, self.cardUp, self.overT, self.bonusLeft, self.earned, self.starsShown = nil, nil, nil, nil, nil, 0
    self.botLeft, self.botTry, self.hintT, self.fired = nil, 0, nil, 0
    self.shockT, self.flashT = 0, 0
    if self.shockSprite then self.shockSprite:setVisible(false) end
    if self.flashLight then self.flashLight:setLightIntensity(0) end
    self:setPouch(self.rest.x, self.rest.y)
    local U = self.ui
    if U.Card then ui.setVisible(U.Card, false) end
    if U.HudTitle then ui.setText(U.HudTitle, WORLDS[cfg.world] .. "  " .. level) end
    if U.HudHint then
        ui.setText(U.HudHint, "DRAG THE ALIEN BACK AND LET GO")
        ui.setVisible(U.HudHintPlate or U.HudHint, level <= 3)
    end
    self.cam.x, self.cam.zoom = self:targetsCentre(), 6.0
    self.sounds:play("start", 0.5)
end

-- Reads what is in the scene now: the blocks, targets, shots and ropes.
function Game:readLevel()
    local function children(name)
        local parent = scene:find(name)
        return parent and parent:getChildren() or {}
    end
    self.blocks, self.targets, self.shots, self.spares, self.all, self.dead = {}, {}, {}, {}, {}, {}
    local function children(name)
        local parent = scene:find(name)
        return parent and parent:getChildren() or {}
    end
    for _, go in ipairs(children("Blocks")) do
        local mat, shape = go:getName():match("^B_(%a+)_(%a+)_")
        local M = mat and MATERIAL[mat]
        if M then
            local b = { go = go, body = go:getComponent("Physics2D"), sprite = go:getComponent("Sprite2D"),
                        mat = mat, shape = shape, M = M, stage = 0 }
            b.max = M.hp * (0.55 + 0.45 * (AREA[shape] or 1))
            b.hp = b.max
            b.body.onContact = function(other, point, normal, speed) self:struck(b, other, point, speed) end
            self.blocks[#self.blocks + 1] = b
        end
    end
    for _, go in ipairs(children("Targets")) do
        local t = { go = go, body = go:getComponent("Physics2D"), sprite = go:getComponent("Sprite2D"),
                    hp = TARGET.hp, target = true, blink = math.random() * 3 }
        t.body.onContact = function(other, point, normal, speed) self:struck(t, other, point, speed) end
        self.targets[#self.targets + 1] = t
    end
    self.targetCount = #self.targets
    for _, go in ipairs(children("Ammo")) do
        local colour = go:getName():match("^A_(%a+)_")
        local s = { go = go, body = go:getComponent("Physics2D"), sprite = go:getComponent("Sprite2D"), colour = colour,
                    home = go:getPosition() }
        local trail = scene:find(go:getName() .. "_Trail")
        s.trail = trail and trail:getComponent("Line2D")
        if s.trail then
            s.trail:setEmitting(false)
            local c = TRAIL[colour] or { 1, 1, 1 }
            s.trail:setColors(Vec4.new(c[1], c[2], c[3], 0.85), Vec4.new(c[1], c[2], c[3], 0.0))
        end
        s.body.onContact = function(other, point, normal, speed) self:shotHit(s, other, point, speed) end
        self.shots[#self.shots + 1] = s
        self.all[#self.all + 1] = s
    end
    -- S_<colour>_<n>_<k>: the two extra bodies a blue shot splits into
    for _, go in ipairs(children("Spares")) do
        local colour, n = go:getName():match("^S_(%a+)_(%d+)_")
        local s = { go = go, body = go:getComponent("Physics2D"), sprite = go:getComponent("Sprite2D"), colour = colour,
                    spare = true, of = "A_" .. tostring(colour) .. "_" .. tostring(n) }
        s.sprite:setVisible(false)
        local trail = scene:find(go:getName() .. "_Trail")
        s.trail = trail and trail:getComponent("Line2D")
        if s.trail then s.trail:setEmitting(false) end
        s.body.onContact = function(other, point, normal, speed) self:shotHit(s, other, point, speed) end
        self.spares[#self.spares + 1] = s
        self.all[#self.all + 1] = s
    end
    -- Ropes: lines whose ends are tied to things. R_<Object> ties its last
    -- point; RR_<A>__<B> its first to A and its last to B. Where on the
    -- object is read from how the line was drawn.
    self.ropes = {}
    for _, go in ipairs(children("Ropes")) do
        local line = go:getComponent("Line2D")
        local name = go:getName()
        local a, b = name:match("^RR_(.+)__(.+)$")
        if not a then b = name:match("^R_(.+)$") end
        local pts = line and line:getPoints() or {}
        local function tie(objName, index)
            local obj = objName and scene:find(objName)
            if not obj or not pts[index] then return nil end
            local p = obj:getPosition()
            return { obj = obj, name = objName, index = index, dx = pts[index].x - p.x, dy = pts[index].y - p.y }
        end
        local r = { line = line, ties = {} }
        r.ties[#r.ties + 1] = tie(a, 1)
        r.ties[#r.ties + 1] = tie(b, #pts)
        if line and #r.ties > 0 then self.ropes[#self.ropes + 1] = r end
    end
    for _, d in ipairs(self.drops or {}) do self.all[#self.all + 1] = d end
end

function Game:targetsCentre()
    local x, n = 0, 0
    for _, t in ipairs(self.targets) do
        if not t.gone then x, n = x + t.go:getPosition().x, n + 1 end
    end
    return n > 0 and x / n or 8
end

-- ----- damage -------------------------------------------------------------------

-- Something hit `thing` at `speed`. How hard that is depends on how heavy
-- the other body is: the ground and anything far heavier count as the
-- thing's own weight, since it is the thing that stops.
function Game:struck(thing, other, point, speed)
    if thing.gone or self.clock < 0.6 then return end
    local own = thing.body:getMass()
    local m = other and other:getMass() or 0
    if own <= 0 then own = math.max(m, 0.3) end        -- nailed down: it is the other that stops
    if m <= 0 or m > own * 3 then m = own * 3 end
    local force = speed * math.sqrt(m)
    local tough = thing.target and TARGET.tough or thing.M.tough
    if force < tough then return end
    thing.hp = thing.hp - (force - tough * 0.6)
    local loud = clamp(force / 16, 0.15, 1.0)
    if thing.target then
        self.sounds:play("thud_1", loud)
        if thing.hp <= 0 then self.dead[#self.dead + 1] = thing end
        return
    end
    local M = thing.M
    self.sounds:play(M.hit[math.min(#M.hit, 1 + math.floor(force / 9))], loud)
    self.fx:chips(point.x, point.y, M.colour, math.floor(clamp(force * 0.6, 3, 12)))
    if thing.hp <= 0 then
        self.dead[#self.dead + 1] = thing
    else
        local stage = (thing.hp < thing.max * 0.38) and 2 or ((thing.hp < thing.max * 0.75) and 1 or 0)
        if stage ~= thing.stage then
            thing.stage = stage
            thing.sprite:setFrame(thing.mat .. "_" .. thing.shape .. "_" .. stage)
            self:add(10)
        end
    end
end

function Game:add(points)
    self.score = self.score + points
end

-- Takes the broken thing out of the scene and leaves what a break leaves:
-- pieces, dust, a sound, points - and for a crate of explosive, the blast.
function Game:shatter(thing)
    if thing.gone then return end
    thing.gone = true
    local p = thing.go:getPosition()
    local v = thing.body:getLinearVelocity()
    if thing.target then
        self.sounds:play("pop", 0.9)
        self.sounds:play("squeak", 0.5, 0.9 + math.random() * 0.3)
        self.fx:pop(p.x, p.y)
        self:add(TARGET.score)
        self.targetCount = self.targetCount - 1
        view.shake(0.12, 0.25)
    else
        local M = thing.M
        self.sounds:play(M.crack, 0.8)
        self.fx:burst(p.x, p.y, M.colour, 10 + math.floor((AREA[thing.shape] or 1) * 4))
        self:add(M.score)
        local pieces = (thing.mat == "tnt") and 0 or math.min(5, 2 + math.floor((AREA[thing.shape] or 1)))
        for i = 1, pieces do self:throwDebris(thing.mat, p.x, p.y, v.x, v.y) end
    end
    -- a rope tied to it has nothing to hang from
    for _, r in ipairs(self.ropes) do
        for _, t in ipairs(r.ties) do
            if t.obj == thing.go or t.name == thing.go:getName() then r.cut = true end
        end
        if r.cut and not r.cleared then r.cleared = true r.line:clearPoints() end
    end
    local parent = thing.go:getParent()
    if parent then parent:removeGameObject(thing.go) end
    if thing.mat == "tnt" then self:explode(p.x, p.y, 4.6, 26) end
end

function Game:throwDebris(mat, x, y, vx, vy)
    local d
    for _, c in ipairs(self.debris) do
        if c.life <= 0 then d = c break end
    end
    if not d then return end
    d.life = 2.2 + math.random() * 0.8
    d.sprite:setFrame("debris_" .. mat .. "_" .. math.random(1, 3))
    d.sprite:setColor(1, 1, 1, 1)
    d.sprite:setVisible(true)
    d.go:setPosition(Vec3.new(x + (math.random() - 0.5) * 0.8, y + (math.random() - 0.5) * 0.8, 0.2))
    d.go:setRotation(Vec3.new(0, 0, math.random() * 6.28))
    d.body:setBodyType(BodyType2D.Dynamic)
    d.body:setLinearVelocity(vx * 0.5 + (math.random() - 0.5) * 9, vy * 0.5 + math.random() * 8 + 2)
    d.body:setAngularVelocity((math.random() - 0.5) * 16)
end

-- A blast: everything within reach is thrown outwards and hurt, nearest
-- most; the view jolts, a ring runs out and a light goes off.
function Game:explode(x, y, radius, power)
    self.sounds:play("boom_1", 1.0, 0.9 + math.random() * 0.2)
    self.sounds:play("boom_low", 0.9)
    self.fx:blast(x, y)
    view.shake(0.55, 0.5)
    self.shockT, self.shockAt = 0.45, { x, y }
    self.flashT = 0.5
    if self.flash then self.flash:setPosition(Vec3.new(x, y, 2.0)) end
    local function push(thing, hurt)
        if thing.gone or not thing.body then return end
        local p = thing.go:getPosition()
        local dx, dy = p.x - x, p.y - y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > radius then return end
        local k = 1 - d / radius
        if d < 0.001 then dx, dy, d = 0, 1, 1 end
        local m = thing.body:getMass()
        thing.body:wake()
        thing.body:applyImpulse(dx / d * power * k * math.min(m, 2.5), (dy / d * 0.8 + 0.35) * power * k * math.min(m, 2.5))
        if hurt then
            thing.hp = thing.hp - 34 * k * k
            if thing.hp <= 0 then self.dead[#self.dead + 1] = thing
            elseif not thing.target then
                local stage = (thing.hp < thing.max * 0.38) and 2 or ((thing.hp < thing.max * 0.75) and 1 or 0)
                if stage ~= thing.stage then
                    thing.stage = stage
                    thing.sprite:setFrame(thing.mat .. "_" .. thing.shape .. "_" .. stage)
                end
            end
        end
    end
    for _, b in ipairs(self.blocks) do push(b, true) end
    for _, t in ipairs(self.targets) do push(t, true) end
    for _, s in ipairs(self.all) do if s.flying then push(s, false) end end
end

-- ----- the shot --------------------------------------------------------------------

function Game:shotHit(s, other, point, speed)
    if not s.flying then return end
    if not s.touched then
        s.touched = true
        s.touchT = 0
        if s.trail then s.trail:setEmitting(false) end
    end
    if speed > 3 then
        self.sounds:play(speed > 12 and "thud_2" or "thud_1", clamp(speed / 20, 0.2, 0.9))
        self.fx:puff(point.x, point.y, math.floor(clamp(speed * 0.4, 2, 8)))
        if speed > 9 then view.shake(clamp(speed * 0.012, 0.05, 0.3), 0.2) end
    end
end

-- What a second press does while the shot is in the air.
function Game:ability(s)
    if s.used then return end
    s.used = true
    local p, v = s.go:getPosition(), s.body:getLinearVelocity()
    if s.colour == "yellow" then
        local len = math.max(0.01, math.sqrt(v.x * v.x + v.y * v.y))
        s.body:setLinearVelocity(v.x / len * math.max(len * 1.9, 26), v.y / len * math.max(len * 1.9, 26))
        self.sounds:play("whoosh", 0.9, 1.3)
        self.fx:sparkle(p.x, p.y, { 1.0, 0.9, 0.3 })
    elseif s.colour == "pink" then
        self:explode(p.x, p.y, 3.6, 20)
        self:retire(s)
    elseif s.colour == "blue" then
        local n = 0
        for _, spare in ipairs(self.spares) do
            if spare.of == s.go:getName() and not spare.flying and not spare.spent then
                n = n + 1
                local up = (n == 1) and 1 or -1
                self:fly(spare, p.x, p.y + up * 0.6, v.x * 0.98 - v.y * 0.16 * up, v.y * 0.98 + v.x * 0.16 * up + up * 1.5)
                spare.used, spare.touchT = true, 0
            end
        end
        self.sounds:play("pluck", 0.9, 1.2)
        self.fx:sparkle(p.x, p.y, { 0.5, 0.75, 1.0 })
    else
        s.used = false
    end
end

function Game:fly(s, x, y, vx, vy)
    s.go:setPosition(Vec3.new(x, y, 0.3))
    s.body:setBodyType(BodyType2D.Dynamic)
    s.body:setLinearVelocity(vx, vy)
    s.body:setAngularVelocity(-vx * 0.35)
    s.sprite:setVisible(true)
    s.flying, s.touched, s.age, s.slow = true, false, 0, 0
    if s.trail then s.trail:setEmitting(true) end
end

-- A shot that has done its work puffs away.
function Game:retire(s)
    if s.spent then return end
    s.spent, s.flying = true, false
    local p = s.go:getPosition()
    self.fx:puff(p.x, p.y, 10)
    s.sprite:setVisible(false)
    if s.trail then s.trail:setEmitting(false) end
    s.body:setBodyType(BodyType2D.Kinematic)
    s.body:setLinearVelocity(0, 0)
    s.go:setPosition(Vec3.new(-60, -30, 0))
end

function Game:loadNext()
    local s = self.shots[self.next]
    self.next = self.next + 1
    self.current = s
    if s then
        s.hop = 0
        s.from = s.go:getPosition()
        self.sounds:play("cloth", 0.5)
        TOPPLE.told = TOPPLE.told or {}
        if HINT[s.colour] and not TOPPLE.told[s.colour] and self.ui.HudHint then
            TOPPLE.told[s.colour] = true
            ui.setText(self.ui.HudHint, HINT[s.colour])
            ui.setVisible(self.ui.HudHintPlate or self.ui.HudHint, true)
            self.hintT = 6
        end
    end
    return s
end

function Game:shotsLeft()
    return math.max(0, #self.shots - self.next + 1)
end

function Game:setPouch(x, y)
    for _, band in ipairs(self.bands) do band:setPoint(2, x, y) end
end

function Game:aim(dt, mx, my, down, pressed)
    local s = self.current
    if not s then return end
    local rx, ry = self.rest.x, self.rest.y
    if s.hop then
        -- from the queue to the pouch, in an arc
        s.hop = math.min(1, s.hop + dt * 2.6)
        local t = s.hop
        local e = t * t * (3 - 2 * t)
        s.go:setPosition(Vec3.new(lerp(s.from.x, rx, e), lerp(s.from.y, ry, e) + math.sin(t * math.pi) * 1.6, 0.3))
        s.go:setRotation(Vec3.new(0, 0, -t * 6.2832))
        if t >= 1 then s.hop = nil end
        return
    end
    if not self.dragging then
        s.go:setPosition(Vec3.new(rx, ry + math.sin(self.clock * 3) * 0.03, 0.3))
        self:setPouch(rx, ry)
        local dx, dy = mx - rx, my - ry
        if pressed and dx * dx + dy * dy < GRAB * GRAB then
            self.dragging = true
            self.sounds:play("stretch", 0.6)
        end
        return
    end
    -- held: the shot goes where the pointer is, as far as the bands stretch
    local dx, dy = mx - rx, my - ry
    local len = math.sqrt(dx * dx + dy * dy)
    if len > PULL_MAX then dx, dy, len = dx / len * PULL_MAX, dy / len * PULL_MAX, PULL_MAX end
    if ry + dy < 0.55 then dy = 0.55 - ry end
    local px, py = rx + dx, ry + dy
    s.go:setPosition(Vec3.new(px, py, 0.3))
    s.go:setRotation(Vec3.new(0, 0, math.atan(dy, dx)))
    self:setPouch(px, py)
    local vx, vy = -dx * POWER, -dy * POWER
    self:showDots(px, py, vx, vy, len > 0.5)
    if not down then
        self.dragging = false
        self:showDots(0, 0, 0, 0, false)
        if len > 0.5 then
            self:fly(s, px, py, vx, vy)
            self.sounds:play("whoosh", clamp(len / PULL_MAX, 0.4, 1.0), 0.9 + math.random() * 0.2)
            self.snap = 0.25
            self.snapFrom = { px, py }
            self.flight = s
            self.current = nil
            self.state = "flight"
            self.fired = (self.fired or 0) + 1
            if self.ui.HudHint and not self.hintT then ui.setVisible(self.ui.HudHintPlate or self.ui.HudHint, false) end
        end
    end
end

-- The path the shot would take, as a row of dots that thin out.
function Game:showDots(x, y, vx, vy, on)
    for i, d in ipairs(self.dots) do
        local t = i * 0.085
        local py = y + vy * t + 0.5 * GRAVITY * t * t
        local show = on and py > 0.2
        d.sprite:setVisible(show)
        if show then
            d.go:setPosition(Vec3.new(x + vx * t, py, 0.25))
            local s = 1.0 - i / (#self.dots + 4)
            d.go:setScale(Vec3.new(s, s, 1))
        end
    end
end

-- ----- one frame -----------------------------------------------------------------------

function Game:update(dt)
    if dt <= 0 or not self.dead then return end
    dt = math.min(dt, 0.05)
    -- (a level asked for is started here, between frames' work, and not
    -- from inside whatever asked)
    if self.pendingLevel then
        local level = self.pendingLevel
        self.pendingLevel = nil
        self:startLevel(level)
        return
    end
    self.clock = self.clock + dt
    self.sounds.now = self.clock

    for _, thing in ipairs(self.dead) do self:shatter(thing) end
    self.dead = {}

    local mx, my = view.mouseWorld()
    local down = isMouseButtonDown(MouseButton.Left)
    local pressed = down and not self.wasDown
    self.wasDown = down

    if self.state == "intro" then
        self.introT = self.introT - dt
        if self.introT <= 0 or pressed then
            self.state = "aim"
            self:loadNext()
        end
    elseif self.state == "aim" then
        if TOPPLE.bot then self:botAim(dt) else self:aim(dt, mx, my, down, pressed) end
    elseif self.state == "flight" then
        self:flying(dt, pressed)
    elseif self.state == "settle" then
        self:settling(dt)
    elseif self.state == "menu" then
        self:menu(dt)
    end

    -- the bands spring back after a release
    if self.snap then
        self.snap = self.snap - dt
        local t = clamp(self.snap / 0.25, 0, 1)
        local wob = math.sin((1 - t) * 18) * t * 0.5
        self:setPouch(lerp(self.rest.x, self.snapFrom[1], t * t) + wob * 0.3, lerp(self.rest.y, self.snapFrom[2], t * t) + wob * 0.2)
        if self.snap <= 0 then self.snap = nil self:setPouch(self.rest.x, self.rest.y) end
    end

    self:updateDebris(dt)
    self:updateBlast(dt)
    self:updateTargets(dt)
    self:updateCamera(dt)
    self:updateInterface(dt)
    if self.hintT then
        self.hintT = self.hintT - dt
        if self.hintT <= 0 then
            self.hintT = nil
            if self.ui.HudHint then ui.setVisible(self.ui.HudHintPlate or self.ui.HudHint, false) end
        end
    end
    for _, r in ipairs(self.ropes) do
        for _, t in ipairs(r.cut and {} or r.ties) do
            local p = t.obj:getPosition()
            local a = t.obj:getRotation().z
            local ca, sa = math.cos(a), math.sin(a)
            r.line:setPoint(t.index, p.x + t.dx * ca - t.dy * sa, p.y + t.dx * sa + t.dy * ca)
        end
    end
    for _, f in ipairs(self.fireflies) do
        local t = self.clock * 0.6 + f.seed
        f.go:setPosition(Vec3.new(f.x + math.sin(t) * 1.6 + math.sin(t * 2.3) * 0.5, f.y + math.cos(t * 1.3) * 0.9, f.z))
        f.sprite:setAlpha(0.35 + 0.65 * math.max(0, math.sin(t * 3.1 + f.seed)))
    end
    for i, c in ipairs(self.clouds) do
        local p = c:getPosition()
        local x = p.x + dt * (0.25 + (i % 3) * 0.12)
        if x > 46 then x = -34 end
        c:setPosition(Vec3.new(x, p.y, p.z))
    end
end

function Game:flying(dt, pressed)
    local s = self.flight
    local busy = false
    for _, shot in ipairs(self.all) do
        if shot.flying then
            shot.age = shot.age + dt
            local p, v = shot.go:getPosition(), shot.body:getLinearVelocity()
            local speed = math.sqrt(v.x * v.x + v.y * v.y)
            shot.slow = (speed < 0.6) and (shot.slow + dt) or 0
            if shot.touched then shot.touchT = (shot.touchT or 0) + dt end
            -- (the game playing itself does not wait to watch a shot roll to a stop)
            local patience = TOPPLE.bot and 2.2 or 5
            if p.x < -30 or p.x > 38 or p.y < -6 or shot.slow > 0.9 or shot.age > 11 or (shot.touchT or 0) > patience then
                self:retire(shot)
            else
                busy = true
            end
        end
    end
    if TOPPLE.bot and s and s.flying and not s.touched and not s.used and s.age > 0.45 and s.colour ~= "pink" then pressed = true end
    if pressed and s and s.flying and not s.touched then self:ability(s) end
    -- a bomb goes off by itself a moment after it lands
    if s and s.flying and s.colour == "pink" and not s.used and (s.touchT or 0) > 0.9 then self:ability(s) end
    if not busy then
        self.flight = nil
        self.state = "settle"
        self.settle = 0
    end
end

-- The title screen: a shot every few seconds, lobbed at the tower, until
-- there is nothing left to hit - then the scene is loaded again, whole.
function Game:menu(dt)
    for _, shot in ipairs(self.all) do
        if shot.flying then
            shot.age = shot.age + dt
            local p, v = shot.go:getPosition(), shot.body:getLinearVelocity()
            shot.slow = (v.x * v.x + v.y * v.y < 0.4) and (shot.slow + dt) or 0
            if p.x < -30 or p.x > 38 or p.y < -6 or shot.slow > 0.8 or shot.age > 8 then
                self:retire(shot)
                shot.spent = false
            end
        end
    end
    if self.targetCount <= 0 then
        self.doneT = (self.doneT or 0) + dt
        if self.doneT > 3.5 and not self.leaving then self.leaving = true loadScene(cfg.scene) end
    else
        self.dropT = self.dropT - dt
        if self.dropT <= 0 and #self.drops > 0 then
            self.dropT = 3.4
            self.dropN = self.dropN % #self.drops + 1
            local s = self.drops[self.dropN]
            if not s.flying then
                local power = 0.86 + math.random() * 0.2
                self:fly(s, self.rest.x, self.rest.y, 17.5 * power, (8.5 + math.random() * 4.5) * power)
                self.snap, self.snapFrom = 0.25, { self.rest.x - 2.2, self.rest.y - 1.2 }
                self.sounds:play("whoosh", 0.35)
            end
        end
    end
    if self.mascot then
        local wait = clamp(self.dropT / 3.4, 0, 1)
        local pull = (wait < 0.35) and (1 - wait / 0.35) or 0
        self.mascot:setPosition(Vec3.new(self.rest.x - pull * 2.2, self.rest.y - pull * 1.2, 0.3))
        if not self.snap then self:setPouch(self.rest.x - pull * 2.2, self.rest.y - pull * 1.2) end
    end
    local U = self.ui
    local function clicked(name) return U[name] and ui.wasClicked(U[name]) end
    local function go(level)
        if self.leaving then return end
        self.leaving = true
        self.sounds:play("confirm", 0.7)
        TOPPLE.level = level
        loadScene(sceneOf(level))
    end
    if not self.gridWorld then
        if clicked("Play") then
            -- on from where they are: the first level not yet won
            local level = 1
            while level < LEVELS and TOPPLE.progress.stars[level] do level = level + 1 end
            go(level)
        end
        for w = 1, #WORLDS do
            if clicked("World" .. w) then self.sounds:play("click", 0.7) self:showGrid(w) end
        end
    else
        if clicked("GridBack") then self.sounds:play("back", 0.7) self:showGrid(nil) end
        for i = 1, PER_WORLD do
            if clicked("Cell" .. i) then go((self.gridWorld - 1) * PER_WORLD + i) end
        end
    end
    -- F9, or B held for a second: the game plays itself, every level in turn, and writes down how it
    -- went (store "bot"). How the levels were checked to be winnable.
    self.botHold = isKeyDown(Key.B) and ((self.botHold or 0) + dt) or 0
    if (isKeyDown(Key.F9) or self.botHold > 1.0) and not self.leaving then
        -- (store "botlist", if there is one: only those levels, e.g. "9,16,70")
        TOPPLE.bot = { results = {}, list = {} }
        local only = store and store.read("botlist")
        if type(only) == "string" then
            for n in only:gmatch("%d+") do TOPPLE.bot.list[#TOPPLE.bot.list + 1] = tonumber(n) end
        end
        go(table.remove(TOPPLE.bot.list, 1) or 1)
    end
end

-- The game playing itself (F9 on the title). It aims the way a child
-- would: at the nearest target still standing, straight first and then
-- over the top. Each level's outcome is written to the store as it ends.
function Game:botAim(dt)
    local s = self.current
    if not s then return end
    local rx, ry = self.rest.x, self.rest.y
    if s.hop then
        s.hop = math.min(1, s.hop + dt * 6)
        if s.hop >= 1 then s.hop = nil end
        return
    end
    local best, bx
    for _, t in ipairs(self.targets) do
        if not t.gone then
            local p = t.go:getPosition()
            if not bx or p.x < bx then best, bx = p, p.x end
        end
    end
    if not best then return end
    self.botTry = (self.botTry or 0) + 1
    local v = POWER * PULL_MAX * (0.94 + 0.06 * math.random())
    -- at it, then at what is over it, then dropped on it from above
    local kind = self.botTry % 3
    local x, y, g = best.x - rx + (math.random() - 0.5) * 0.4, best.y - ry + (kind == 2 and 1.6 or 0), -GRAVITY
    local d = v ^ 4 - g * (g * x * x + 2 * y * v * v)
    local lob = (kind == 0)
    local a = math.atan(v * v + (lob and 1 or -1) * math.sqrt(math.max(d, 0)), g * x)
    self:fly(s, rx, ry, math.cos(a) * v, math.sin(a) * v)
    self.flight, self.current, self.state = s, nil, "flight"
end

function Game:botDone()
    local B = TOPPLE.bot
    local line = string.format("%d %s %d/%d %d", self.level, self.won and "won" or "LOST", self.usedShots or 0, #self.shots, self.score)
    B.results[#B.results + 1] = line
    if store then store.write("bot", table.concat(B.results, "\n")) end
    echo("[bot] " .. line)
    local nextLevel = self.level + 1
    if B.only or #B.list > 0 then B.only = true nextLevel = table.remove(B.list, 1) or (LEVELS + 1) end
    if nextLevel <= LEVELS then
        self:goTo(nextLevel)
    else
        TOPPLE.bot = nil
        loadScene("scenes/Title.json")
    end
end

function Game:goTo(level)
    if sceneOf(level) == cfg.scene then self.pendingLevel = level
    else TOPPLE.level = level loadScene(sceneOf(level)) end
end

-- The menu's two pages: the worlds, or one world's twenty levels.
function Game:showGrid(world)
    local U = self.ui
    self.gridWorld, TOPPLE.grid = world, world
    if U.Home then ui.setVisible(U.Home, world == nil) end
    if U.Grid then ui.setVisible(U.Grid, world ~= nil) end
    if not world then return end
    if U.GridTitle then ui.setText(U.GridTitle, WORLDS[world]) end
    for i = 1, PER_WORLD do
        local n = (world - 1) * PER_WORLD + i
        if U["CellNumber" .. i] then ui.setText(U["CellNumber" .. i], tostring(n)) end
        for k = 1, 3 do
            local star = U["CellStar" .. i .. "_" .. k]
            if star then ui.setVisible(star, (TOPPLE.progress.stars[n] or 0) >= k) end
        end
    end
end

-- After a shot: wait for the pile to stop moving, then either the level is
-- over or the next shot hops up.
function Game:settling(dt)
    self.settle = self.settle + dt
    local moving = false
    if self.settle < (TOPPLE.bot and 4 or 6) then
        for _, b in ipairs(self.blocks) do
            if not b.gone then
                local v = b.body:getLinearVelocity()
                if v.x * v.x + v.y * v.y > 0.25 then moving = true break end
            end
        end
        for _, t in ipairs(self.targets) do
            if not t.gone then
                local v = t.body:getLinearVelocity()
                if v.x * v.x + v.y * v.y > 0.25 then moving = true break end
            end
        end
    end
    if self.settle < 0.7 or moving then return end
    if self.targetCount <= 0 then
        self:finish(true)
    elseif self:shotsLeft() <= 0 then
        self:finish(false)
    else
        self.state = "aim"
        self:loadNext()
    end
end

function Game:updateDebris(dt)
    for _, d in ipairs(self.debris) do
        if d.life > 0 then
            d.life = d.life - dt
            if d.life < 0.5 then d.sprite:setAlpha(math.max(0, d.life / 0.5)) end
            if d.life <= 0 then
                d.sprite:setVisible(false)
                d.body:setBodyType(BodyType2D.Kinematic)
                d.body:setLinearVelocity(0, 0)
                d.body:setAngularVelocity(0)
                d.go:setPosition(d.park)
            end
        end
    end
end

function Game:updateBlast(dt)
    if self.shockT > 0 and self.shock then
        self.shockT = self.shockT - dt
        local t = 1 - clamp(self.shockT / 0.45, 0, 1)
        local s = 1.5 + t * 9
        self.shock:setPosition(Vec3.new(self.shockAt[1], self.shockAt[2], 0.6))
        self.shock:setScale(Vec3.new(s, s, 1))
        self.shockSprite:setVisible(self.shockT > 0)
        self.shockSprite:setColor(1, 0.9, 0.7, (1 - t) * 0.9)
    end
    if self.flashT > 0 and self.flashLight then
        self.flashT = self.flashT - dt
        local t = clamp(self.flashT / 0.5, 0, 1)
        self.flashLight:setLightIntensity(t * t * 5.0)
    end
end

-- The targets are alive: they bob a little, and look at a shot coming.
function Game:updateTargets(dt)
    for _, t in ipairs(self.targets) do
        if not t.gone then
            local v = t.body:getLinearVelocity()
            if v.x * v.x + v.y * v.y < 0.05 then
                local k = 1 + math.sin(self.clock * 3.2 + t.blink) * 0.035
                t.go:setScale(Vec3.new(2 - k, k, 1))
            end
        end
    end
end

-- The view is the script's: a wide look at the targets to begin with, the
-- sling while aiming, the shot while it flies - eased, never cut.
function Game:updateCamera(dt)
    local c = self.cam
    -- How much is in view depends on the window's shape: the sling is kept
    -- a sixth of the way in from the left, whatever that is.
    local l, _, r = view.visibleRect()
    local wide = (r - l) / math.max(c.zoom, 0.01)       -- view widths per unit of zoom
    local function slingAt(zoom) return self.rest.x + wide * zoom * 0.34 end
    local centre = self:targetsCentre()
    local tx, ty, tz, rate = c.x, 6.2, 8.0, 2.2
    if self.state == "menu" then
        tx, tz = slingAt(8.0) + 1.5, 8.0
    elseif self.state == "intro" then
        tx, tz, rate = centre, 6.0, 1.0
        if self.introT < 1.3 then tx, tz, rate = slingAt(8.0), 8.0, 2.4 end
    elseif self.state == "aim" then
        tx = slingAt(8.0)
        if self.dragging then tx, tz = slingAt(8.4) - 0.6, 8.4 end
    elseif self.state == "flight" and self.flight and self.flight.flying then
        local p = self.flight.go:getPosition()
        tx, ty, tz, rate = clamp(p.x + 2.5, slingAt(7.6), math.max(slingAt(7.6), centre)), clamp(p.y * 0.35 + 4.5, 6.0, 9.5), 7.6, 3.2
    elseif self.state == "settle" or self.state == "flight" then
        tx, tz = math.max(slingAt(7.4), centre - 2), 7.4
    elseif self.state == "over" then
        tx, tz, rate = math.max(slingAt(7.8), centre - 2), 7.8, 1.2
    end
    local k = 1 - math.exp(-rate * dt)
    c.x, c.y, c.zoom = lerp(c.x, tx, k), lerp(c.y, ty, k), lerp(c.zoom, tz, k)
    view.setCenter(c.x, c.y)
    view.setZoom(c.zoom)
end

-- ----- the end of a level -----------------------------------------------------------------

function Game:finish(won)
    self.state = "over"
    self.won = won
    self.overT = 0
    self.usedShots = #self.shots - self:shotsLeft()
    if won then
        -- Stars are for shots not needed: half of them left is three, any
        -- left is two, and winning at all is one.
        local left, all = self:shotsLeft(), #self.shots
        self.earned = (left * 2 >= all - 1) and 3 or ((left >= 1) and 2 or 1)
        self.bonus = self:shotsLeft() * SHOT_BONUS
        self.bonusLeft = self:shotsLeft()
        self.bonusT = 0.5
    end
    self.starsShown = 0
    if self.ui.CardTitle then ui.setText(self.ui.CardTitle, won and "LEVEL CLEAR" or "OUT OF SHOTS") end
    for i = 1, 3 do
        if self.ui["CardStar" .. i] then ui.setVisible(self.ui["CardStar" .. i], false) end
    end
    if not won then self.earned = 0 end
    -- (a level that will not fall can be passed over: NEXT is there either way)
    if self.ui.CardNext then ui.setVisible(self.ui.CardNext, self.level ~= nil and self.level < LEVELS) end
    self.sounds:play(won and "win" or "lose", 0.8)
    if won then self.fx:confetti(self.cam.x, self.cam.y + 5) end
end

function Game:updateOver(dt)
    self.overT = self.overT + dt
    if TOPPLE.bot and not self.botLeft then self.botLeft = true self:botDone() return end
    -- each shot not needed is worth a bonus, counted out one at a time
    if self.won and self.bonusLeft and self.bonusLeft > 0 then
        self.bonusT = self.bonusT - dt
        if self.bonusT <= 0 then
            self.bonusT = 0.35
            self.bonusLeft = self.bonusLeft - 1
            self:add(SHOT_BONUS)
            self.sounds:play("coins", 0.7, 1.0 + (self:shotsLeft() - self.bonusLeft) * 0.08)
            local s = self.shots[self.next + self.bonusLeft]
            if s and not s.spent then
                local p = s.go:getPosition()
                self.fx:sparkle(p.x, p.y, { 1.0, 0.85, 0.3 })
            end
        end
        return
    end
    if not self.cardUp and self.overT > 1.0 then
        self.cardUp = true
        if self.ui.Card then ui.setVisible(self.ui.Card, true) end
        self.sounds:play("open", 0.6)
        local P, n = TOPPLE.progress, self.level
        local best = n and P.best[n] or 0
        if self.won and n then
            if self.score > best then P.best[n] = self.score end
            if self.earned > (P.stars[n] or 0) then P.stars[n] = self.earned end
            saveProgress(P)
        end
        if self.ui.CardBest then ui.setText(self.ui.CardBest, "BEST  " .. math.max(best, self.won and self.score or 0)) end
        self.starT = 0.45
    end
    if self.cardUp and self.starsShown < self.earned then
        self.starT = self.starT - dt
        if self.starT <= 0 then
            self.starT = 0.42
            self.starsShown = self.starsShown + 1
            local star = self.ui["CardStar" .. self.starsShown]
            if star then ui.setVisible(star, true) end
            self.sounds:play("star_" .. self.starsShown, 0.8)
        end
    end
end

function Game:updateInterface(dt)
    if self.state == "over" then self:updateOver(dt) end
    -- the score counts up to what it is
    if self.shown < self.score then
        self.shown = math.min(self.score, self.shown + math.max(10, (self.score - self.shown) * 6 * dt))
        self.tickT = (self.tickT or 0) - dt
    end
    local text = tostring(math.floor(self.shown))
    if text ~= self.scoreText then
        self.scoreText = text
        if self.ui.HudScore then ui.setText(self.ui.HudScore, text) end
        if self.ui.CardScore then ui.setText(self.ui.CardScore, text) end
    end
    local U = self.ui
    local function clicked(name) return U[name] and ui.wasClicked(U[name]) end
    if clicked("BtnRetry") or clicked("CardRetry") or (self.rDown and not isKeyDown(Key.R)) then
        self.sounds:play("click", 0.7)
        if self.level then self:goTo(self.level) else loadScene(cfg.scene) end
    elseif clicked("BtnMenu") or clicked("CardMenu") then
        self.sounds:play("back", 0.7)
        TOPPLE.grid = cfg.world
        loadScene("scenes/Title.json")
    elseif clicked("CardNext") and self.level and self.level < LEVELS then
        self.sounds:play("confirm", 0.7)
        self:goTo(self.level + 1)
    end
    self.rDown = isKeyDown(Key.R)
    -- K: break whatever is under the pointer. Not part of the game - it is
    -- for trying a level's machines without having to hit them.
    local k = isKeyDown(Key.K)
    if k and not self.kDown then
        local mx, my = view.mouseWorld()
        local best, bestD = nil, 0.9
        local function near(list)
            for _, t in ipairs(list) do
                if not t.gone then
                    local p = t.go:getPosition()
                    local d = math.sqrt((p.x - mx) ^ 2 + (p.y - my) ^ 2)
                    if d < bestD then best, bestD = t, d end
                end
            end
        end
        near(self.blocks) near(self.targets)
        if best then self.dead[#self.dead + 1] = best end
    end
    self.kDown = k
end

function Game:destroy()
    if self.fx then self.fx:destroy() end
    -- (a level put into the scene by this script is taken out again by it:
    -- Stop in the editor leaves the world's scene as it was saved)
    if self.root then scene:remove(self.root) self.root = nil end
end

return Game

end
