-- assets/lua/ember/world.lua
--
-- Reads the level out of the scene instead of restating it.
--
-- Everything the game needs to know about the level - where the floors are,
-- how wide they are, which torch is a checkpoint, where a frostling can walk
-- to - is already in the scene file, put there in the editor. This walks the
-- tree once and collects it by name and by component. The only thing that is
-- NOT derivable is where a moving platform travels to, so that (and only
-- that) is a table at the bottom.

local World = {}

local function walk(o, out)
    table.insert(out, o)
    for _, c in ipairs(o:getChildren()) do walk(c, out) end
end

function World.all(scene)
    local out = {}
    for _, r in ipairs(scene:getAllGameObjects()) do walk(r, out) end
    return out
end

-- Where each mover goes. Name -> {x0, y0, x1, y1, seconds one way, pause}.
World.MOVERS = {
    Mover0 = { 44.0, 2.7, 48.5, 2.7, 2.8, 0.7 },
    Lift0  = { 70.0, 1.7, 70.0, 5.7, 2.6, 1.2 },
}

function World.collect(scene)
    local w = {
        solids = {}, shards = {}, foes = {}, torches = {}, movers = {},
        layers = {}, player = nil, brazier = nil, brazierLight = nil,
        brazierFire = nil,
    }

    for _, o in ipairs(World.all(scene)) do
        local n = o:getName()
        local layer = o:getComponent("Layer2D")
        if layer then
            local p = o:getPosition()
            table.insert(w.layers, { obj = o, layer = layer, base = Vec3.new(p.x, p.y, p.z) })
        end

        if n == "Ember" then
            w.player = o
        elseif n:find("^Ground") or n:find("^Mover") or n:find("^Lift") then
            -- Walls are deliberately NOT in here: they are solid to Box2D
            -- and invisible to the ground probe, which is the whole point.
            local body = o:getComponent("Physics2D")
            if body then
                -- Half-extents straight off the body, so a platform resized
                -- in the editor moves the floor the controller stands on.
                local sz = body:getSize()
                local mover = World.MOVERS[n] ~= nil
                local s = { obj = o, body = body, hx = sz.x, hy = sz.y, mover = mover, name = n }
                table.insert(w.solids, s)
                if mover then
                    local m = World.MOVERS[n]
                    s.path = { x0 = m[1], y0 = m[2], x1 = m[3], y1 = m[4], secs = m[5], pause = m[6] }
                    s.t, s.dir, s.wait = 0, 1, 0
                    table.insert(w.movers, s)
                end
            end
        elseif n:find("^Shard%d") then
            table.insert(w.shards, { obj = o, taken = false, base = o:getPosition().y })
        elseif n:find("^Frost%d") then
            table.insert(w.foes, { obj = o, alive = true, name = n })
        elseif n:find("^TorchFire") then
            table.insert(w.torches, { fire = o, index = tonumber(n:match("%d+")) or 0 })
        elseif n == "Brazier" then
            w.brazier = o
        elseif n == "BrazierFire" then
            w.brazierFire = o
        end
    end

    -- Second pass: the pieces that are found by pairing two objects up.
    for _, o in ipairs(World.all(scene)) do
        local n = o:getName()
        if n:find("^TorchLight") then
            local idx = tonumber(n:match("%d+")) or 0
            for _, t in ipairs(w.torches) do
                if t.index == idx then
                    t.light = o:getComponent("PointLight")
                    t.obj = o
                    local p = o:getPosition()
                    t.x, t.y = p.x, p.y
                end
            end
        elseif n == "BrazierLight" then
            w.brazierLight = o:getComponent("PointLight")
        end
    end

    -- A frostling patrols a stretch of the platform it was placed on: find
    -- the floor under it, take RANGE either side of where it was authored,
    -- and clip that to the platform's edges. Nothing to author, and moving
    -- the platform in the editor moves the patrol with it.
    --
    -- The clip is the important half. Without the range, one frostling
    -- authored on a fourteen-unit plateau owns the whole plateau, and there
    -- is no way past it except through it.
    local RANGE = 2.6
    for _, f in ipairs(w.foes) do
        local p = f.obj:getPosition()
        f.y = p.y
        f.min, f.max = p.x - RANGE, p.x + RANGE
        for _, s in ipairs(w.solids) do
            local sp = s.obj:getPosition()
            local top = sp.y + s.hy
            if math.abs(p.x - sp.x) <= s.hx and math.abs((p.y - 0.55) - top) < 0.5 then
                f.min = math.max(f.min, sp.x - s.hx + 0.6)
                f.max = math.min(f.max, sp.x + s.hx - 0.6)
            end
        end
        if f.max < f.min then f.min, f.max = p.x, p.x end
        f.dir = 1
        f.base = p.y
        local sc = f.obj:getScale()
        f.scale = Vec3.new(math.abs(sc.x), sc.y, sc.z)
    end

    -- Torches, left to right: that order is the checkpoint order.
    table.sort(w.torches, function(a, b) return (a.x or 0) < (b.x or 0) end)
    return w
end

-- Parallax. offset = scroll * (factor - 1), always from the authored base so
-- it never accumulates. Factor 1 is exactly zero, which is why the gameplay
-- layer can share this loop without being special-cased.
function World.parallax(w, camX, camY)
    for _, L in ipairs(w.layers) do
        local f = L.layer:getParallax()
        L.obj:setPosition(Vec3.new(L.base.x + camX * (f.x - 1.0),
                                   L.base.y + camY * (f.y - 1.0),
                                   L.base.z))
        L.obj:refreshTransformation()
    end
end

function World.driveMovers(w, dt)
    for _, m in ipairs(w.movers) do
        local P = m.path
        if m.wait > 0 then
            m.wait = m.wait - dt
            m.body:setLinearVelocity(Vec2.new(0, 0))
        else
            m.t = m.t + dt * m.dir / P.secs
            if m.t >= 1 then m.t, m.dir, m.wait = 1, -1, P.pause
            elseif m.t <= 0 then m.t, m.dir, m.wait = 0, 1, P.pause end
            -- Driven by VELOCITY, not by teleporting the body: a kinematic
            -- body that is moved by setTransform has no velocity, so nothing
            -- riding it is carried and the contact solver fights it.
            --
            -- The velocity is the PATH's own speed plus a bounded pull back
            -- towards where the platform should be by now. It used to be the
            -- whole positional error divided by dt, which is a catastrophe
            -- here: physics runs a fixed 60Hz step, the script runs every
            -- render frame, and on a frame where no step happened the body
            -- did not move while the target did - so the error grew, the
            -- velocity with it, and the platform ended up reporting speeds
            -- ten times its own. The platform still LOOKED right (the error
            -- is corrected either way); what broke was everything that asks
            -- it how fast it is going, which is exactly how a rider is
            -- carried.
            local tx = P.x0 + (P.x1 - P.x0) * m.t
            local ty = P.y0 + (P.y1 - P.y0) * m.t
            local p = m.obj:getPosition()
            local sx = (P.x1 - P.x0) / P.secs * m.dir
            local sy = (P.y1 - P.y0) / P.secs * m.dir
            local CATCHUP = 4.0                     -- 1/s, not 1/dt
            local LIMIT = 1.6                       -- never more than this over the path speed
            local span = math.max(0.5, math.abs(sx) + math.abs(sy))
            local cx = math.max(-span * LIMIT, math.min(span * LIMIT, (tx - p.x) * CATCHUP))
            local cy = math.max(-span * LIMIT, math.min(span * LIMIT, (ty - p.y) * CATCHUP))
            m.body:setLinearVelocity(Vec2.new(sx + cx, sy + cy))
        end
    end
end

return World
