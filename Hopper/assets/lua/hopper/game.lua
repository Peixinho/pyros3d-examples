-- assets/lua/hopper/game.lua - the rules of Hopper.
--
-- A world is a scene (its sky, the hero, the interface, its music) and a
-- level is a prefab put into it: a tile map painted by terrain, a second
-- for the bridges, and what stands on them. Both were made in the editor.
-- This reads a level by its objects' names and runs it:
--
--   Coin_n  Gem_n  Key  Lock_n  Spring_n  Check_n  Goal  Sign_n  Torch_n      (under Things)
--   Slime_n  Snail_n  Bee_n  Fly_n  Mouse_n                                    (under Enemies)
--   Ferry_n  Lift_n  Plank_n                                                   (under Movers)
--
-- What it leans on in the engine, so that it can stay this short:
--   TileMap2D            ground with corners picked by the map; getTile / tileHasTag for ladders, spikes, water
--   map:findWalkPath     the mouse asks the map the way to the hero
--   Physics2D            one capsule for the hero; isGrounded, getGroundVelocity, one-way bridges
--   Joint2D break force  the planks: welds that give way under the hero
--   Sprite2D clips       walk / jump / climb, by name
--   Text2D               the "+1" that floats up, and what a sign says
--   tween                everything that eases: pickups, the card, the fades
--   lang / tr            English or Portuguese, by the device's language
--   touch, ui.stick      a thumb stick and a jump button, on a phone
--   store                stars kept between visits
--   Sound, AudioSource   .ogg effects and streamed music

local TILE = assert(loadfile(ASSETS_PATH .. "lua/hopper/tiles.lua"))()

local RUN, JUMP, CUT = 7.0, 16.5, 0.45
local COYOTE, BUFFER = 0.10, 0.13
local CLIMB = 4.5
local SPRING = 25.0
local BRIDGES = 2                 -- the collision layer the one-way bridges are on
local WORLDS = 5
local PER_WORLD = 10
local LEVELS = WORLDS * PER_WORLD

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function loadProgress()
    local p = { stars = {}, coins = 0 }
    local text = store and store.read("hopper")
    if type(text) == "string" then
        for n, stars in text:gmatch("(%d+):(%d+)") do p.stars[tonumber(n)] = tonumber(stars) end
    end
    return p
end
local function saveProgress(p)
    local parts = {}
    for n = 1, LEVELS do
        if p.stars[n] then parts[#parts + 1] = n .. ":" .. p.stars[n] end
    end
    if store then store.write("hopper", table.concat(parts, ",")) end
end
local function sceneOf(level) return "scenes/World" .. (math.floor((level - 1) / PER_WORLD) + 1) .. ".json" end

return function(cfg)

local Game = class(cfg.menu and 'HopperTitle' or ('HopperWorld' .. tostring(cfg.world)))

function Game:initialize()
    self.clock = 0
end

-- ----- starting up ---------------------------------------------------------------

function Game:init(owner)
    HOPPER = HOPPER or {}
    if not HOPPER.progress then HOPPER.progress = loadProgress() end
    -- The words: the device's language if there is a file for it.
    if HOPPER.lang then lang.load(HOPPER.lang) else HOPPER.lang = lang.loadBest({ "en", "pt" }) or "en" end

    self.sounds = {}
    for name, voices in pairs({ jump = 2, coin = 4, gem = 2, hurt = 2, bump = 3, magic = 2, select = 2, jump_high = 2,
                                disappear = 3, click = 2, confirm = 1, back = 1, win = 1 }) do
        local ok, s = pcall(function() return Sound.new(ASSETS_PATH .. "sounds/" .. name .. ".ogg", voices) end)
        if ok and s and s:isLoaded() then self.sounds[name] = s end
    end
    local music = scene:find("Music")
    local source = music and music:getComponent("AudioSource")
    if source and not source:isPlaying() then source:play() end

    self.ui = {}
    local function U(name) self.ui[name] = ui.find(scene, name) return self.ui[name] end
    U("Fade")
    if cfg.menu then
        self:initMenu(U)
    else
        for _, n in ipairs({ "CoinCount", "HudTitle", "Heart1", "Heart2", "Heart3", "Gem1", "Gem2", "Gem3", "BtnMenu", "BtnRetry",
                             "Stick", "StickKnob", "PadJump", "Card", "CardCoins", "CardStar1", "CardStar2", "CardStar3",
                             "CardMenu", "CardRetry", "CardNext" }) do U(n) end
        self.hero = scene:find("Hero")
        self.body = self.hero:getComponent("Physics2D")
        self.sprite = self.hero:getComponent("Sprite2D")
        self.floats = {}
        for i = 1, 6 do
            local go = scene:find("Float_" .. i)
            if go then self.floats[#self.floats + 1] = { go = go, text = go:getComponent("Text2D") } end
        end
        self.floatAt = 0
        local first = (cfg.world - 1) * PER_WORLD + 1
        local level = HOPPER.level
        if not level or level < first or level >= first + PER_WORLD then level = first end
        self:startLevel(level)
    end
    lang.apply(scene)
    -- In from black.
    -- (the scene keeps its Fade clear, so that it can be seen in the editor: black is put up here, and eased away)
    if self.ui.Fade then ui.setTint(self.ui.Fade, Vec4.new(0, 0, 0, 1)) end
    if self.ui.Fade then tween.tint(self.ui.Fade, 0, 0, 0, 0, 0.45, "out") end
end

function Game:play(name, volume, pitch)
    local s = self.sounds[name]
    if s then s:play(volume or 0.8, pitch or (0.95 + math.random() * 0.1)) end
end

-- Out to black, then whatever was asked for.
function Game:fadeThen(fn)
    if self.leaving then return end
    self.leaving = true
    if self.ui.Fade then tween.tint(self.ui.Fade, 0, 0, 0, 1, 0.3, "in", fn) else fn() end
end

-- ----- the menu --------------------------------------------------------------------

function Game:initMenu(U)
    for _, n in ipairs({ "Home", "Grid", "Play", "StarsTotal", "GridTitle", "GridBack", "Language", "Language_Label" }) do U(n) end
    for i = 1, PER_WORLD do
        U("Cell" .. i)
        U("Cell" .. i .. "_Number")
        for k = 1, 3 do U("Cell" .. i .. "_Star" .. k) end
    end
    for w = 1, WORLDS do U("World" .. w) U("World" .. w .. "_Stars") end
    self.mascot = scene:find("Mascot")
    self:refreshMenu()
    self:showGrid(HOPPER.grid)
end

function Game:refreshMenu()
    local U, total = self.ui, 0
    for w = 1, WORLDS do
        local got = 0
        for n = (w - 1) * PER_WORLD + 1, w * PER_WORLD do got = got + (HOPPER.progress.stars[n] or 0) end
        total = total + got
        if U["World" .. w .. "_Stars"] then ui.setText(U["World" .. w .. "_Stars"], got .. " / " .. PER_WORLD * 3) end
    end
    if U.StarsTotal then ui.setText(U.StarsTotal, total .. " / " .. LEVELS * 3) end
    if U.Language_Label then ui.setText(U.Language_Label, string.upper(HOPPER.lang)) end
end

function Game:showGrid(world)
    local U = self.ui
    self.gridWorld, HOPPER.grid = world, world
    if U.Home then ui.setVisible(U.Home, world == nil) end
    if U.Grid then ui.setVisible(U.Grid, world ~= nil) end
    if not world then return end
    if U.GridTitle then ui.setText(U.GridTitle, tr("world_" .. world)) end
    for i = 1, PER_WORLD do
        local n = (world - 1) * PER_WORLD + i
        if U["Cell" .. i .. "_Number"] then ui.setText(U["Cell" .. i .. "_Number"], tostring(i)) end
        for k = 1, 3 do
            local star = U["Cell" .. i .. "_Star" .. k]
            if star then ui.setVisible(star, (HOPPER.progress.stars[n] or 0) >= k) end
        end
    end
end

function Game:updateMenu(dt)
    local U = self.ui
    local function clicked(name) return U[name] and ui.wasClicked(U[name]) end
    local function go(level)
        self:play("confirm")
        HOPPER.level = level
        self:fadeThen(function() loadScene(sceneOf(level)) end)
    end
    if self.mascot then
        -- the hero walks on the spot, and bobs
        local p = self.mascot:getPosition()
        self.mascot:setPosition(Vec3.new(p.x, 2.0 + math.abs(math.sin(self.clock * 6)) * 0.12, p.z))
    end
    -- B held for a second, or F9: the game plays itself, from the first level.
    self.botHold = isKeyDown(Key.B) and (self.botHold or 0) + dt or 0
    if (self.botHold > 1 or isKeyDown(Key.F9)) and not self.leaving then
        HOPPER.bot = true
        go(tonumber(store and store.read("hopperbotfrom") or "") or 1)
        return
    end
    if not self.gridWorld then
        if clicked("Play") then
            local level = 1
            while level < LEVELS and HOPPER.progress.stars[level] do level = level + 1 end
            go(level)
        end
        for w = 1, WORLDS do
            if clicked("World" .. w) then self:play("click") self:showGrid(w) end
        end
        if clicked("Language") then
            -- The other language, where it stands: the same labels, by their keys.
            HOPPER.lang = (HOPPER.lang == "en") and "pt" or "en"
            lang.load(HOPPER.lang)
            lang.apply(scene)
            self:refreshMenu()
            self:play("select")
        end
    else
        if clicked("GridBack") then self:play("back") self:showGrid(nil) end
        for i = 1, PER_WORLD do
            if clicked("Cell" .. i) then go((self.gridWorld - 1) * PER_WORLD + i) end
        end
    end
end

-- ----- a level ----------------------------------------------------------------------

function Game:startLevel(level)
    if self.root then scene:remove(self.root) self.root = nil end
    HOPPER.level, self.level = level, level
    self.root = Prefab.instantiate(string.format("assets/prefabs/H%03d.prefab", level))
    if self.root then
        scene:add(self.root)
        local function settle(go)
            go:refreshTransformation()
            for _, child in ipairs(go:getChildren()) do settle(child) end
        end
        settle(self.root)
    end
    local function children(name)
        local parent = scene:find(name)
        return parent and parent:getChildren() or {}
    end
    local ground = scene:find("Ground")
    self.map = ground and ground:getComponent("TileMap2D")

    self.coins, self.gems, self.springs, self.checks, self.locks, self.torches = {}, {}, {}, {}, {}, {}
    self.goal, self.key, self.hasKey = nil, nil, false
    for _, go in ipairs(children("Things")) do
        local name = go:getName()
        local p = go:getPosition()
        local item = { go = go, sprite = go:getComponent("Sprite2D"), x = p.x, y = p.y, z = p.z }
        if name:match("^Coin_") then self.coins[#self.coins + 1] = item
        elseif name:match("^Gem_") then self.gems[#self.gems + 1] = item
        elseif name:match("^Spring_") then self.springs[#self.springs + 1] = item
        elseif name:match("^Check_") then self.checks[#self.checks + 1] = item
        elseif name:match("^Lock_") then self.locks[#self.locks + 1] = item
        elseif name:match("^Torch_") then self.torches[#self.torches + 1] = item
        elseif name == "Goal" then self.goal = item
        elseif name == "Key" then self.key = item end
    end
    self.enemies = {}
    for _, go in ipairs(children("Enemies")) do
        local kind = go:getName():match("^(%a+)_")
        local p = go:getPosition()
        self.enemies[#self.enemies + 1] = { go = go, sprite = go:getComponent("Sprite2D"), kind = kind, x = p.x, y = p.y, z = p.z,
                                            x0 = p.x, y0 = p.y, dir = -1, alive = true, seed = #self.enemies * 1.3, think = 0 }
    end
    self.movers = {}
    for _, go in ipairs(children("Movers")) do
        local kind = go:getName():match("^(%a+)_")
        local p = go:getPosition()
        if kind == "Ferry" or kind == "Lift" then
            self.movers[#self.movers + 1] = { go = go, body = go:getComponent("Physics2D"), kind = kind, x0 = p.x, y0 = p.y,
                                              seed = #self.movers * 1.9 }
        end
    end

    local start = scene:find("Start")
    local sp = start and start:getPosition() or Vec3.new(2, 2, 0)
    self.spawn = { x = sp.x, y = sp.y + 0.05 }
    self.levelStart = { x = self.spawn.x, y = self.spawn.y }
    self.hearts, self.coinCount, self.gemCount = 3, 0, 0
    self.state, self.won, self.cardUp = "play", false, false
    self.coyote, self.buffer, self.safe, self.climbing, self.jumpWasDown = 0, 0, 0, false, false
    self.moverT, self.safeSpot, self.lost, self.levelClock = 0, nil, 0, 0
    self:place(self.spawn.x, self.spawn.y)

    -- The view keeps to the level: its edges are the map's.
    local b = self.map and self.map:getTileBounds()
    if b then
        view.setBounds(b.minX, b.minY + 1.0, b.maxX + 1, b.maxY + 12)
        self.floor = b.minY - 4
    else
        self.floor = -6
    end
    view.setCenter(self.spawn.x + 4, self.spawn.y + 3)

    local U = self.ui
    if U.Card then ui.setVisible(U.Card, false) end
    if U.HudTitle then ui.setText(U.HudTitle, tr("level", tr("world_" .. cfg.world), (level - 1) % PER_WORLD + 1)) end
    self:refreshHud()
    lang.apply(scene)        -- the signs this level brought
end

function Game:refreshHud()
    local U = self.ui
    for i = 1, 3 do
        if U["Heart" .. i] then ui.setTint(U["Heart" .. i], Vec4.new(1, 1, 1, i <= self.hearts and 1 or 0.22)) end
        if U["Gem" .. i] then ui.setTint(U["Gem" .. i], Vec4.new(1, 1, 1, i <= self.gemCount and 1 or 0.25)) end
    end
    if U.CoinCount then ui.setText(U.CoinCount, tostring(self.coinCount)) end
end

function Game:place(x, y)
    self.hero:setPosition(Vec3.new(x, y, 0.5))
    self.body:setLinearVelocity(0, 0)
    self.body:setGravityScale(1)
    self.climbing = false
end

-- Words that float up off a place and fade: one of a few Text2D objects the
-- scene keeps for it.
function Game:float(text, x, y, r, g, b)
    if #self.floats == 0 then return end
    self.floatAt = self.floatAt % #self.floats + 1
    local f = self.floats[self.floatAt]
    f.text:setText(text)
    f.text:setColor(r or 1, g or 0.9, b or 0.3, 1)
    f.go:setPosition(Vec3.new(x, y, 2.0))
    tween.move(f.go, x, y + 1.6, 0.7, "out")
    tween.alpha(f.text, 0, 0.7, "in")
end

-- What a cell of the ground is to the hero.
function Game:cell(x, y)
    if not self.map then return -1 end
    local cx, cy = self.map:worldToTile(Vec2.new(x, y))
    return self.map:getTile(cx, cy), cx, cy
end
function Game:solid(x, y)
    local t = self:cell(x, y)
    return t ~= nil and t >= 0 and self.map:tileIsSolid(t)
end
function Game:tagged(x, y, tag)
    local t = self:cell(x, y)
    return t ~= nil and t >= 0 and self.map:tileHasTag(t, tag)
end

-- ----- the hero -----------------------------------------------------------------------

function Game:input()
    local move, vert = 0, 0
    if isKeyDown(Key.A) or isKeyDown(Key.Left) then move = move - 1 end
    if isKeyDown(Key.D) or isKeyDown(Key.Right) then move = move + 1 end
    if isKeyDown(Key.W) or isKeyDown(Key.Up) then vert = vert + 1 end
    if isKeyDown(Key.S) or isKeyDown(Key.Down) then vert = vert - 1 end
    local jump = isKeyDown(Key.Space)
    if gamepad.isConnected(0) then
        local ax, ay = gamepad.axis(0, GamepadAxis.LeftX), gamepad.axis(0, GamepadAxis.LeftY)
        if math.abs(ax) > 0.25 then move = ax end
        if math.abs(ay) > 0.5 then vert = ay > 0 and 1 or -1 end
        jump = jump or gamepad.isDown(0, GamepadButton.A)
    end
    -- Thumbs: a stick on the left, a button on the right - both at once,
    -- which is why these ask about every finger and not the pointer.
    local U = self.ui
    if touch.count() > 0 then HOPPER.touch = true end
    if U.Stick then
        ui.setVisible(U.Stick, HOPPER.touch == true)
        ui.setVisible(U.PadJump, HOPPER.touch == true)
    end
    if HOPPER.touch and U.Stick then
        local sx, sy, held = ui.stick(scene, U.Stick)
        if held then
            if math.abs(sx) > 0.25 then move = sx > 0 and 1 or -1 end
            if math.abs(sy) > 0.55 then vert = sy > 0 and 1 or -1 end
        end
        if U.StickKnob then ui.setOffsets(U.StickKnob, -42 + sx * 48, -42 - sy * 48, 42 + sx * 48, 42 - sy * 48) end
        if ui.isHeld(scene, U.PadJump) then jump = true end
    end
    return move, vert, jump
end

-- The game played by itself (hold B on the title, or F9): how every level
-- is checked to be one that can be finished. It runs right, and jumps what
-- is in the way - with the same body and the same keys' worth of input.
function Game:bot()
    local p = self.hero:getPosition()
    local x, y = p.x, p.y
    local grounded = self.body:isGrounded()
    local bridges = scene:find("Bridges")
    local bmap = bridges and bridges:getComponent("TileMap2D")
    local function support(wx)
        if self:solid(wx, y - 0.5) then return true end
        if bmap then
            local cx, cy = bmap:worldToTile(Vec2.new(wx, y - 0.5))
            if bmap:getTile(cx, cy) >= 0 then return true end
        end
        return false
    end
    local move, jump = 1, false
    -- a key up on its shelf, and a gate ahead: go up for it first
    local forKey = false
    if self.key and not self.key.taken then
        local dx = self.key.x - x
        if y > self.key.y - 1.6 then
            -- level with it: walk to it
            move, forKey = (dx > 0) and 1 or -1, true
        elseif grounded then
            -- below it: a run-up from the left, and a jump onto the shelf
            if dx < 2.6 then self.botBack = true elseif dx > 3.4 then self.botBack = false end
            if self.botBack then move, forKey = -1, true
            elseif dx < 3.6 then jump = true end
        end
    end
    if move > 0 and not forKey then
        if self:solid(x + 0.9, y + 0.5) or self:solid(x + 0.9, y + 1.4) then jump = true end
        if grounded and not support(x + 0.75) then
            -- nothing to stand on ahead: a ferry to wait for, or a jump
            local ferry
            for _, m in ipairs(self.movers) do
                if m.kind == "Ferry" and m.x0 > x - 8 and m.x0 < x + 4 then ferry = m end
            end
            if ferry then
                local fp = ferry.go:getPosition()
                local on = math.abs(fp.x - x) < 0.9 and y > fp.y
                if on then
                    move = (fp.x > ferry.x0 + 5.6) and 1 or 0          -- ride it across, then step off
                    if move == 1 then jump = true end
                elseif fp.x - 1.0 <= x + 1.6 then move, jump = 1, true   -- its near end is at the bank: hop on (it rides higher than the bank)
                else move = 0 end
            else
                jump = true
            end
        end
        for _, e in ipairs(self.enemies) do
            if e.alive and e.x - x > 0 and e.x - x < 2.3 and math.abs(e.y - (y + 0.5)) < 1.2 and grounded then jump = true end
        end
        if self:tagged(x + 1.0, y + 0.2, "hazard") then jump = true end
    end
    -- (a jump is held to its top: let go on the way down)
    if not grounded and self.body:getLinearVelocity().y > 0 then jump = true end
    return move, 0, jump
end

function Game:updateHero(dt)
    local move, vert, jumpDown = self:input()
    if HOPPER.bot then move, vert, jumpDown = self:bot() end
    local jumpPressed = jumpDown and not self.jumpWasDown
    self.jumpWasDown = jumpDown
    local p = self.hero:getPosition()
    local v = self.body:getLinearVelocity()
    local grounded = self.body:isGrounded()
    self.safe = math.max(0, self.safe - dt)

    -- A ladder: where the hero's middle is a ladder's cell, up or down
    -- takes hold of it; a jump, or its end, lets go.
    local onLadder = self:tagged(p.x, p.y + 0.6, "ladder") or self:tagged(p.x, p.y + 0.1, "ladder")
    if self.climbing and (not onLadder or jumpPressed) then
        self.climbing = false
        self.body:setGravityScale(1)
        if jumpPressed then v = Vec2.new(v.x, JUMP * 0.8) self:play("jump", 0.6) jumpPressed = false end
    elseif not self.climbing and onLadder and vert ~= 0 then
        self.climbing = true
        self.body:setGravityScale(0)
    end
    if self.climbing then
        self.body:setLinearVelocity(move * RUN * 0.45, vert * CLIMB)
        self.sprite:play("climb")
        if vert == 0 and move == 0 then self.sprite:pause() else self.sprite:resume() end
        return
    end

    local carry = self.body:getGroundVelocity()
    local vx, vy = move * RUN + carry.x, v.y
    self.coyote = grounded and COYOTE or math.max(0, self.coyote - dt)
    self.buffer = jumpPressed and BUFFER or math.max(0, self.buffer - dt)
    if self.buffer > 0 and self.coyote > 0 then
        vy = JUMP
        self.buffer, self.coyote = 0, 0
        self:play("jump", 0.6)
    elseif not jumpDown and vy > 0 and not grounded and not self.sprung then
        vy = vy * (1 - (1 - CUT) * math.min(1, dt * 30))
    end
    if vy <= 0 then self.sprung = false end
    -- Down on a bridge: stop touching bridges for a moment, and fall through.
    if vert < 0 and grounded and (self.drop or 0) <= 0 then self.drop = 0.25 end
    if (self.drop or 0) > 0 then
        self.drop = self.drop - dt
        self.body:setCollidesWith(BRIDGES, self.drop <= 0)
    end
    self.body:setLinearVelocity(vx, vy)

    -- Where the hero last stood on plain ground with ground either side:
    -- where a fall puts them back. Never far, never at an edge.
    if grounded and self:solid(p.x - 0.6, p.y - 0.5) and self:solid(p.x + 0.6, p.y - 0.5) and self:solid(p.x, p.y - 0.5) then
        self.safeSpot = { x = p.x, y = p.y + 0.05 }
    end

    if move ~= 0 then self.sprite:setFlipX(move < 0) end
    if self.safe > 0.9 then self.sprite:play("hit")
    elseif not grounded then self.sprite:play("jump")
    elseif move ~= 0 then self.sprite:play("walk") self.sprite:resume()
    else self.sprite:play("idle") end
    -- (struck, the hero flickers for as long as nothing can hurt)
    self.sprite:setAlpha((self.safe > 0 and math.floor(self.clock * 14) % 2 == 0) and 0.45 or 1)

    -- What is under and around: spikes, lava, water, the bottom of the world.
    if self:tagged(p.x, p.y + 0.2, "hazard") or self:tagged(p.x, p.y + 0.2, "water") or p.y < self.floor then
        self:hurt(true)
    end
end

function Game:hurt(respawn)
    if self.safe > 0 and not respawn then return end
    self.hearts = self.hearts - 1
    self.lost = (self.lost or 0) + 1
    self.safe = 1.4
    self:play("hurt")
    view.shake(0.25, 0.25)
    if self.hearts <= 0 then
        -- No game over: back to the start of the level, whole again.
        -- (the last flag passed, or the start)
        self.hearts = 3
        self.safeSpot = nil
        respawn = true
    end
    if respawn then
        local to = self.safeSpot or self.spawn
        self:place(to.x, to.y)
    else
        local v = self.body:getLinearVelocity()
        self.body:setLinearVelocity(-v.x, 9)
    end
    self:refreshHud()
end

-- ----- what is in the level --------------------------------------------------------------

-- A pickup goes: it swells and fades, and something floats up from it.
function Game:take(item, sound, words, r, g, b)
    item.taken = true
    self:play(sound)
    tween.scale(item.go, 1.8, 0.25, "out")
    tween.alpha(item.sprite, 0, 0.25, "in", function() item.sprite:setVisible(false) end)
    if words then self:float(words, item.x, item.y + 0.4, r, g, b) end
end

function Game:updateThings(dt)
    local p = self.hero:getPosition()
    local hx, hy = p.x, p.y + 0.75
    local function near(item, reach) return not item.taken and math.abs(item.x - hx) < reach and math.abs(item.y - hy) < reach + 0.35 end
    for _, c in ipairs(self.coins) do
        if not c.taken then
            c.go:setPosition(Vec3.new(c.x, c.y + math.sin(self.clock * 3 + c.x) * 0.08, c.z))
            if near(c, 0.75) then
                self.coinCount = self.coinCount + 1
                self:take(c, "coin", "+1")
                self:refreshHud()
            end
        end
    end
    for _, g in ipairs(self.gems) do
        if not g.taken then
            g.go:setPosition(Vec3.new(g.x, g.y + math.sin(self.clock * 2.4 + g.x) * 0.12, g.z))
            g.go:setRotation(Vec3.new(0, 0, math.sin(self.clock * 2 + g.x) * 0.2))
            if near(g, 0.8) then
                self.gemCount = self.gemCount + 1
                self:take(g, "gem", tostring(self.gemCount) .. " / 3", 0.5, 0.85, 1.0)
                self:refreshHud()
            end
        end
    end
    if self.key and near(self.key, 0.8) then
        self.hasKey = true
        self:take(self.key, "magic")
    end
    if self.hasKey and #self.locks > 0 then
        for _, l in ipairs(self.locks) do
            if math.abs(l.x - hx) < 1.6 and math.abs(l.y - hy) < 3.5 then
                -- The key opens the whole gate.
                self:play("disappear")
                for _, each in ipairs(self.locks) do
                    local parent = each.go:getParent()
                    if parent then parent:removeGameObject(each.go) end
                end
                self.locks = {}
                break
            end
        end
    end
    for _, s in ipairs(self.springs) do
        s.out = math.max(0, (s.out or 0) - dt)
        local v = self.body:getLinearVelocity()
        if math.abs(s.x - hx) < 0.6 and p.y > s.y - 0.3 and p.y < s.y + 0.45 and v.y <= 0.1 then
            self.body:setLinearVelocity(v.x, SPRING)
            self.sprung = true
            s.out = 0.25
            self:play("jump_high")
        end
        s.sprite:setFrame(s.out > 0 and "spring_out" or "spring")
    end
    for _, c in ipairs(self.checks) do
        if not c.lit and math.abs(c.x - hx) < 0.9 and math.abs(c.y - hy) < 1.6 then
            c.lit = true
            c.sprite:setFrame("flag_yellow_a")
            self.spawn = { x = c.x, y = c.y - 0.45 }
            self:play("select")
            self:float("OK", c.x, c.y + 0.8, 1, 0.9, 0.3)
        end
    end
    for _, t in ipairs(self.torches) do
        t.sprite:setFrame((math.floor(self.clock * 8 + t.x) % 2 == 0) and "torch_on_a" or "torch_on_b")
    end
    if self.goal then
        self.goal.sprite:setFrame((math.floor(self.clock * 5) % 2 == 0) and "flag_green_a" or "flag_green_b")
        if not self.won and math.abs(self.goal.x - hx) < 0.9 and math.abs(self.goal.y - hy) < 1.8 then self:win() end
    end
end

-- Platforms the script carries: kinematic bodies moved with moveTo, so
-- that what stands on them is carried.
function Game:updateMovers(dt)
    self.moverT = self.moverT + dt
    for _, m in ipairs(self.movers) do
        local k = (math.sin(self.moverT * 0.9 + m.seed) + 1) * 0.5
        if m.kind == "Ferry" then m.body:moveTo(Vec2.new(m.x0 + k * 6.0, m.y0), 0, dt)
        else m.body:moveTo(Vec2.new(m.x0, m.y0 + k * 4.6), 0, dt) end
    end
end

function Game:updateEnemies(dt)
    local p = self.hero:getPosition()
    local hx, hy = p.x, p.y + 0.75
    local v = self.body:getLinearVelocity()
    for _, e in ipairs(self.enemies) do
        if e.alive then
            if e.kind == "Slime" or e.kind == "Snail" then
                -- Along the ground, turning at a wall or an edge.
                local speed = (e.kind == "Slime") and 1.6 or 0.8
                local ahead = e.x + e.dir * 0.6
                if self:solid(ahead, e.y) or not self:solid(ahead, e.y - 1.0) then e.dir = -e.dir end
                e.x = e.x + e.dir * speed * dt
                e.sprite:setFlipX(e.dir > 0)
            elseif e.kind == "Bee" then
                e.x = e.x0 + math.sin(self.clock * 0.9 + e.seed) * 3.0
                e.y = e.y0 + math.sin(self.clock * 3.1 + e.seed) * 0.35
                e.sprite:setFlipX(math.cos(self.clock * 0.9 + e.seed) > 0)
            elseif e.kind == "Fly" then
                e.y = e.y0 + math.sin(self.clock * 1.4 + e.seed) * 1.6
            elseif e.kind == "Mouse" then
                self:updateMouse(e, dt, p)
            end
            e.go:setPosition(Vec3.new(e.x, e.y, e.z))
            if not self.won and math.abs(e.x - hx) < 0.72 and math.abs(e.y - hy) < 0.95 then
                if v.y < -0.5 and p.y > e.y - 0.15 then
                    -- From above: it is squashed, and the hero bounces.
                    e.alive = false
                    self:play("bump")
                    self.body:setLinearVelocity(v.x, 11)
                    tween.scale(e.go, 0.2, 0.25, "in")
                    tween.alpha(e.sprite, 0, 0.3, "in", function() e.sprite:setVisible(false) end)
                    self:float("!", e.x, e.y + 0.6, 1, 1, 1)
                else
                    self:hurt(false)
                end
            end
        end
    end
end

-- The mouse asks the tile map for the way to the hero - along, up by
-- jumping, down by dropping - a couple of times a second, and follows it.
function Game:updateMouse(e, dt, heroPos)
    e.think = e.think - dt
    local far = math.abs(heroPos.x - e.x) > 11
    if e.think <= 0 and self.map and not far then
        e.think = 0.5
        local cx, cy = self.map:worldToTile(Vec2.new(e.x, e.y))
        local hx, hy = self.map:worldToTile(Vec2.new(heroPos.x, heroPos.y + 0.5))
        local way = self.map:findWalkPath(cx, cy, hx, hy, { jump = 2, distance = 2, drop = 6, height = 1 })
        e.path, e.at = way, 2
    end
    local step = e.path and e.path[e.at]
    if step and not far then
        local tx, ty = step.x + 0.5, step.y + 0.5
        local dx, dy = tx - e.x, ty - e.y
        local d = math.sqrt(dx * dx + dy * dy)
        local go = 3.0 * dt
        if d <= go then e.x, e.y, e.at = tx, ty, e.at + 1
        else e.x, e.y = e.x + dx / d * go, e.y + dy / d * go end
        if math.abs(dx) > 0.01 then e.sprite:setFlipX(dx > 0) end
        e.sprite:resume()
    else
        e.sprite:pause()
    end
end

-- ----- the end of a level -----------------------------------------------------------------

function Game:win()
    self.won = true
    self.state = "won"
    self:play("win", 0.8)
    self.body:setLinearVelocity(0, 0)
    self.sprite:play("front")
    local stars = math.max(1, self.gemCount)
    if HOPPER.bot then
        print(string.format("[bot] level %d won in %.1fs coins %d/%d gems %d hurt %d", self.level, self.levelClock, self.coinCount,
                            #self.coins, self.gemCount, self.lost))
        tween.after(1.6, function()
            if self.level < LEVELS then self:goTo(self.level + 1) else print("[bot] all levels done") HOPPER.bot = false end
        end)
    end
    local P = HOPPER.progress
    if stars > (P.stars[self.level] or 0) then P.stars[self.level] = stars end
    saveProgress(P)
    local U = self.ui
    tween.after(0.9, function()
        self.cardUp = true
        if U.Card then ui.setVisible(U.Card, true) end
        for i = 1, 3 do if U["CardStar" .. i] then ui.setVisible(U["CardStar" .. i], false) end end
        if U.CardNext then ui.setVisible(U.CardNext, self.level < LEVELS) end
        if U.CardCoins then ui.setText(U.CardCoins, self.coinCount .. " / " .. #self.coins) end
        for i = 1, stars do
            tween.after(0.3 * i, function()
                if U["CardStar" .. i] then ui.setVisible(U["CardStar" .. i], true) end
                self:play("gem", 0.7, 0.9 + i * 0.12)
            end)
        end
    end)
end

function Game:goTo(level)
    self:fadeThen(function()
        if sceneOf(level) == cfg.scene then
            self:startLevel(level)
            self.leaving = false
            if self.ui.Fade then tween.tint(self.ui.Fade, 0, 0, 0, 0, 0.4, "out") end
        else
            HOPPER.level = level
            loadScene(sceneOf(level))
        end
    end)
end

function Game:updateButtons()
    local U = self.ui
    local function clicked(name) return U[name] and ui.wasClicked(U[name]) end
    local r = isKeyDown(Key.R)
    if clicked("BtnRetry") or clicked("CardRetry") or (self.rDown and not r) then
        self:play("click")
        self:goTo(self.level)
    elseif clicked("BtnMenu") or clicked("CardMenu") then
        self:play("back")
        HOPPER.grid = cfg.world
        self:fadeThen(function() loadScene("scenes/Title.json") end)
    elseif clicked("CardNext") and self.level < LEVELS then
        self:play("confirm")
        self:goTo(self.level + 1)
    end
    self.rDown = r
end

-- ----- one frame ---------------------------------------------------------------------------

function Game:update(dt)
    if dt <= 0 then return end
    dt = math.min(dt, 0.05)
    self.clock = self.clock + dt
    if cfg.menu then self:updateMenu(dt) return end
    if not self.hero then return end
    self:updateMovers(dt)
    self.levelClock = (self.levelClock or 0) + dt
    if HOPPER.bot and self.levelClock > 90 and not self.won and not self.leaving then
        local p = self.hero:getPosition()
        print(string.format("[bot] level %d STUCK at %.1f, %.1f hurt %d", self.level, p.x, p.y, self.lost))
        if self.level < LEVELS then self:goTo(self.level + 1) end
        self.levelClock = 0
    end
    if self.state == "play" and not self.leaving then
        self:updateHero(dt)
        self:updateThings(dt)
        self:updateEnemies(dt)
    elseif self.state == "won" then
        self:updateEnemies(dt)
    end
    self:updateButtons()
end

function Game:destroy()
    if self.root then scene:remove(self.root) self.root = nil end
end

return Game

end
