-- assets/lua/topple/fx.lua - the particle effects.
--
-- A handful of emitters built once and moved to wherever something happens.
-- Each is a burst: it throws its particles and stops. They are made here
-- and not placed in the scene because there is nothing to place - an
-- emitter has no position until something breaks - and they are removed
-- again in destroy(), so stopping play leaves the scene as it was saved.

local FX = {}
FX.__index = FX

local PARK = Vec3.new(0, -90, 0)

local function texture(name)
    local t = Texture.new()
    t:loadTexture(ASSETS_PATH .. "textures/fx/" .. name .. ".png", TextureType.Texture, true, 0)
    t:setTransparency(TextureTransparency.Transparent)
    return t
end

function FX.new(scene)
    local self = setmetatable({ scene = scene, made = {}, pools = {}, turn = {} }, FX)
    self.tex = {}
    for _, n in ipairs({ "soft", "smoke_a", "smoke_b", "sparkle", "glow", "fire", "dirt", "burst", "twinkle" }) do
        self.tex[n] = texture(n)
    end
    local T = self.tex

    -- name, how many copies (so two hits in a frame do not share one), setup
    self:pool("chips", 4, function(d)
        d.maxParticles = 60; d.texture = T.soft; d.burstCount = 8
        d.minLifetime = 0.25; d.maxLifetime = 0.6
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 3.14159
        d.minSpeed = 1.5; d.maxSpeed = 6.5
        d.gravity = Vec3.new(0, -14, 0); d.damping = 1.2
        d.startSize = 0.22; d.endSize = 0.05
        d.fadeOutFraction = 0.4
    end)
    self:pool("burst", 4, function(d)
        d.maxParticles = 80; d.texture = T.dirt; d.burstCount = 16
        d.minLifetime = 0.35; d.maxLifetime = 0.9
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 3.14159
        d.minSpeed = 1.0; d.maxSpeed = 7.5
        d.gravity = Vec3.new(0, -9, 0); d.damping = 1.6
        d.startSize = 0.7; d.endSize = 0.25
        d.minRotationSpeed = -4; d.maxRotationSpeed = 4
        d.fadeOutFraction = 0.5
    end)
    self:pool("dust", 4, function(d)
        d.maxParticles = 60; d.texture = T.smoke_a; d.burstCount = 6
        d.minLifetime = 0.4; d.maxLifetime = 0.9
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 2.6
        d.minSpeed = 0.4; d.maxSpeed = 2.2
        d.gravity = Vec3.new(0, 0.6, 0); d.damping = 2.2
        d.startSize = 0.5; d.endSize = 1.5
        d.minRotationSpeed = -1.5; d.maxRotationSpeed = 1.5
        d.startColor = Vec4.new(0.95, 0.93, 0.88, 0.55); d.endColor = Vec4.new(0.9, 0.9, 0.9, 0.0)
        d.fadeOutFraction = 0.7
    end)
    self:pool("stars", 3, function(d)
        d.maxParticles = 60; d.texture = T.sparkle; d.burstCount = 14
        d.minLifetime = 0.45; d.maxLifetime = 0.95
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 3.14159
        d.minSpeed = 2.5; d.maxSpeed = 8.0
        d.gravity = Vec3.new(0, -6, 0); d.damping = 1.8
        d.startSize = 0.75; d.endSize = 0.1
        d.minRotationSpeed = -6; d.maxRotationSpeed = 6
        d.startColor = Vec4.new(1.0, 0.92, 0.35, 1.0); d.endColor = Vec4.new(1.0, 0.6, 0.1, 0.0)
        d.fadeOutFraction = 0.35
    end)
    self:pool("fire", 2, function(d)
        d.maxParticles = 90; d.texture = T.fire; d.burstCount = 34
        d.minLifetime = 0.25; d.maxLifetime = 0.7
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 3.14159
        d.minSpeed = 1.0; d.maxSpeed = 9.0
        d.gravity = Vec3.new(0, 2.5, 0); d.damping = 2.6
        d.startSize = 1.5; d.endSize = 2.6
        d.minRotationSpeed = -3; d.maxRotationSpeed = 3
        d.startColor = Vec4.new(1.0, 0.82, 0.35, 1.0); d.endColor = Vec4.new(0.9, 0.25, 0.05, 0.0)
        d.fadeOutFraction = 0.6
        d.blendMode = ParticleBlendMode.Additive
    end)
    self:pool("smoke", 2, function(d)
        d.maxParticles = 70; d.texture = T.smoke_b; d.burstCount = 22
        d.minLifetime = 0.9; d.maxLifetime = 2.0
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 3.14159
        d.minSpeed = 0.6; d.maxSpeed = 4.5
        d.gravity = Vec3.new(0, 1.6, 0); d.damping = 1.8
        d.startSize = 1.2; d.endSize = 3.8
        d.minRotationSpeed = -1; d.maxRotationSpeed = 1
        d.startColor = Vec4.new(0.28, 0.26, 0.26, 0.75); d.endColor = Vec4.new(0.5, 0.5, 0.52, 0.0)
        d.fadeInFraction = 0.1; d.fadeOutFraction = 0.75
    end)
    self:pool("sparks", 2, function(d)
        d.maxParticles = 80; d.texture = T.glow; d.burstCount = 30
        d.minLifetime = 0.3; d.maxLifetime = 0.9
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 3.14159
        d.minSpeed = 6.0; d.maxSpeed = 17.0
        d.gravity = Vec3.new(0, -16, 0); d.damping = 1.2
        d.startSize = 0.42; d.endSize = 0.05
        d.startColor = Vec4.new(1.0, 0.9, 0.55, 1.0); d.endColor = Vec4.new(1.0, 0.4, 0.1, 0.0)
        d.fadeOutFraction = 0.4
        d.blendMode = ParticleBlendMode.Additive
    end)
    self:pool("twinkle", 3, function(d)
        d.maxParticles = 40; d.texture = T.twinkle; d.burstCount = 10
        d.minLifetime = 0.35; d.maxLifetime = 0.8
        d.direction = Vec3.new(0, 1, 0); d.spreadAngle = 3.14159
        d.minSpeed = 0.8; d.maxSpeed = 3.5
        d.gravity = Vec3.new(0, 0, 0); d.damping = 2.0
        d.startSize = 0.7; d.endSize = 0.1
        d.minRotationSpeed = -3; d.maxRotationSpeed = 3
        d.fadeOutFraction = 0.5
        d.blendMode = ParticleBlendMode.Additive
    end)
    for i, c in ipairs({ { 1.0, 0.35, 0.4 }, { 0.35, 0.75, 1.0 }, { 1.0, 0.85, 0.25 }, { 0.5, 0.9, 0.45 } }) do
        self:pool("confetti" .. i, 1, function(d)
            d.maxParticles = 60; d.texture = T.soft; d.burstCount = 40
            d.minLifetime = 1.6; d.maxLifetime = 3.2
            d.direction = Vec3.new(0, -1, 0); d.spreadAngle = 2.4
            d.minSpeed = 1.0; d.maxSpeed = 9.0
            d.gravity = Vec3.new(0, -5, 0); d.damping = 1.4
            d.startSize = 0.32; d.endSize = 0.22
            d.startColor = Vec4.new(c[1], c[2], c[3], 1.0); d.endColor = Vec4.new(c[1], c[2], c[3], 0.0)
            d.fadeOutFraction = 0.3
        end)
    end
    return self
end

function FX:pool(name, copies, setup)
    self.pools[name], self.turn[name] = {}, 0
    for i = 1, copies do
        local go = GameObject.new()
        go:setName("FX_" .. name .. "_" .. i)
        local d = ParticleSystemDesc.new()
        d.looping = false
        d.blendMode = ParticleBlendMode.AlphaBlend
        setup(d)
        local ps = ParticleSystem.new(d)
        go:addComponent(ps)
        go:setPosition(PARK)
        go:refreshTransformation()
        self.scene:add(go)
        self.made[#self.made + 1] = go
        self.pools[name][i] = { go = go, ps = ps }
    end
end

function FX:fire(name, x, y, count, c0, c1)
    local pool = self.pools[name]
    if not pool then return end
    self.turn[name] = self.turn[name] % #pool + 1
    local e = pool[self.turn[name]]
    e.go:setPosition(Vec3.new(x, y, 0.8))
    e.go:refreshTransformation()
    if count then e.ps:setBurstCount(count) end
    if c0 then e.ps:setColors(c0, c1 or c0) end
    e.ps:play()
end

local function tint(c, a0, a1, k)
    k = k or 1
    return Vec4.new(c[1] * k, c[2] * k, c[3] * k, a0), Vec4.new(c[1] * k * 0.8, c[2] * k * 0.8, c[3] * k * 0.8, a1)
end

-- what flies off a block that was hit
function FX:chips(x, y, colour, n)
    self:fire("chips", x, y, n, tint(colour, 1.0, 0.0))
end

-- a block breaking
function FX:burst(x, y, colour, n)
    self:fire("burst", x, y, n, tint(colour, 1.0, 0.0))
    self:fire("dust", x, y, 7)
end

function FX:puff(x, y, n)
    self:fire("dust", x, y, n)
end

-- a target going
function FX:pop(x, y)
    self:fire("stars", x, y, 16)
    self:fire("dust", x, y, 8)
end

function FX:blast(x, y)
    self:fire("smoke", x, y, 22)
    self:fire("fire", x, y, 34)
    self:fire("sparks", x, y, 30)
end

function FX:sparkle(x, y, colour)
    self:fire("twinkle", x, y, 10, tint(colour, 1.0, 0.0))
end

function FX:confetti(x, y)
    for i = 1, 4 do self:fire("confetti" .. i, x + (i - 2.5) * 5, y, 40) end
end

function FX:destroy()
    for _, go in ipairs(self.made) do self.scene:remove(go) end
    self.made = {}
end

return FX
