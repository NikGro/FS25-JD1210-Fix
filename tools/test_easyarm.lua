-- crane geometry of the JD 1210G (dummy chain from 1210G.i3d)
local rad = math.rad
local root = newNode("component2", 0, {0, 0, 0})
local slew = newNode("arm Dummy", root, {0, 2.15644, 0.962581}, {0, rad(180), 0})
local boomN = newNode("arm 1Dummy", slew, {0, 1.283, -0.145689}, {rad(-5), 0, 0})
local jibN = newNode("arm 2 Dummy", boomN, {0, 0.0684221, 3.53878}, {rad(55), 0, 0})
local tel1N = newNode("extension arm 1", jibN, {0, 0, 0})
local tel2N = newNode("extension arm 2", tel1N, {0, 0, 0})
local tipN = newNode("clawColJoint", tel2N, {-0.005, 0.347813, 2.62004})

local function rotTool(node, speedDeg, minDeg, maxDeg)
    local rx, ry, rz = getRotation(node)
    return {node = node, rotSpeed = rad(speedDeg) / 1000, rotMin = rad(minDeg), rotMax = rad(maxDeg), rotationAxis = 1,
            curRot = {rx, ry, rz}, move = 0, externalMove = 0}
end
local function transTool(node, speed, mn, mx)
    local x, y, z = getTranslation(node)
    return {node = node, transSpeed = speed / 1000, transMin = mn, transMax = mx, translationAxis = 3,
            curTrans = {x, y, z}, move = 0, externalMove = 0}
end

local boom = rotTool(boomN, 29, -80, 25)
local jib = rotTool(jibN, 39, 7, 184.5)
local tel1 = transTool(tel1N, 0.5, 0, 1.9)
local tel2 = transTool(tel2N, 0.55, 0, 2.05)
local tools = {boom, jib, tel1, tel2}
local byNode = {[boomN] = boom, [jibN] = jib, [tel1N] = tel1, [tel2N] = tel2}

local attrs = {slewNode = slew, boomNode = boomN, jibNode = jibN, telescopeNode = tel1N, telescope2Node = tel2N, tipNode = tipN}
local xml = {
    hasProperty = function() return true end,
    getValue = function(_, key, default)
        local a = key:match("#(.+)$")
        if attrs[a] ~= nil then return attrs[a] end
        return default
    end
}

local v = {xmlFile = xml, isServer = true, components = {}, i3dMappings = {}}
v[JDEasyArmControl.SPEC_TABLE_NAME] = {}
v.getMovingToolByNode = function(_, n) return byNode[n] end
local base = function(_, t) return t.move + t.externalMove end
v.getMovingToolMoveValue = function(self, t) return JDEasyArmControl.getMovingToolMoveValue(self, base, t) end
local spec = v[JDEasyArmControl.SPEC_TABLE_NAME]

JDEasyArmControl.onPostLoad(v, nil)
assert(spec.isValid, "setup invalid")
print(string.format("stick signs: boomUp=%d jibOpen=%d", spec.signBoomUp, spec.signJibOpen))

-- one frame of Cylindered: pre update, then integrate every tool with its move value
local function frame(dt)
    JDEasyArmControl.onPreUpdate(v, dt)
    local moves = {}
    for _, t in ipairs(tools) do moves[t] = v:getMovingToolMoveValue(t) end
    tel2.externalMove = 0
    for _, t in ipairs(tools) do
        local m = moves[t]
        if t.rotSpeed then
            local r = math.max(t.rotMin, math.min(t.rotMax, t.curRot[1] + m * t.rotSpeed * dt))
            t.curRot[1] = r
            setRotation(t.node, r, 0, 0)
        else
            local z = math.max(t.transMin, math.min(t.transMax, t.curTrans[3] + m * t.transSpeed * dt))
            t.curTrans[3] = z
            setTranslation(t.node, 0, 0, z)
        end
    end
    tel2.externalMove = tel1.move -- dependent moving tool, as in Cylindered
end
local function tip()
    local _, y, z = worldToLocal(slew, getWorldTranslation(tipN))
    return y, math.abs(z)
end
local function run(inY, inZ, ms)
    boom.move, jib.move = inY, inZ
    for _ = 1, ms / 16 do frame(16) end
    boom.move, jib.move = 0, 0
end

-- A: easy control off -> raw joint moves pass through
JDEasyArmControl.onVehicleSettingChanged(v, "easyArm", false)
local r0 = boom.curRot[1]
run(1, 0, 320)
assert(math.abs(boom.curRot[1] - r0) > 0.1, "A: boom must move directly when easy control is off")
print("A ok: off = single axes")

-- reset pose
local function reset()
    boom.curRot[1] = rad(-5) setRotation(boomN, rad(-5), 0, 0)
    jib.curRot[1] = rad(80) setRotation(jibN, rad(80), 0, 0)
    tel1.curTrans[3] = 0.5 setTranslation(tel1N, 0, 0, 0.5)
    tel2.curTrans[3] = 0.5 setTranslation(tel2N, 0, 0, 0.5)
end
JDEasyArmControl.onVehicleSettingChanged(v, "easyArm", true)

-- B: up only -> tip goes up, reach stays
reset()
local y0, z0 = tip()
run(spec.signBoomUp, 0, 800) -- stick in the direction that raises the main boom
local y1, z1 = tip()
print(string.format("B: up 0.8 s: dy=%.3f dz=%.3f", y1 - y0, z1 - z0))
assert(y1 - y0 > 0.5, "B: tip must rise")
assert(math.abs(z1 - z0) < 0.06 * (y1 - y0), "B: reach must stay nearly constant")

-- C: out only -> reach grows, height stays, telescope used
reset()
y0, z0 = tip()
local t0 = tel1.curTrans[3]
run(0, spec.signJibOpen, 800)
y1, z1 = tip()
print(string.format("C: out 0.8 s: dy=%.3f dz=%.3f telescope +%.2f m", y1 - y0, z1 - z0, tel1.curTrans[3] - t0))
assert(z1 - z0 > 0.5, "C: tip must move out")
assert(math.abs(y1 - y0) < 0.06 * (z1 - z0), "C: height must stay nearly constant")
assert(tel1.curTrans[3] - t0 > 0.15, "C: telescope should help")
assert(math.abs((tel2.curTrans[3] - 0.5) / (tel1.curTrans[3] - 0.5) - 0.55 / 0.5) < 1e-3, "C: both stages move together")

-- D: in + down, then full out to the limit: no NaN, stops at reach limit
reset()
run(-spec.signBoomUp, -spec.signJibOpen, 1500)
y1, z1 = tip()
assert(y1 == y1 and z1 == z1, "D: NaN")
run(0, spec.signJibOpen, 20000)
local yM, zM = tip()
print(string.format("D: max reach %.2f m (height %.2f)", zM, yM))
assert(zM > 8 and zM < 11.5, "D: max reach plausible")
for _, t in ipairs(tools) do
    if t.rotSpeed then
        assert(t.curRot[1] >= t.rotMin - 1e-6 and t.curRot[1] <= t.rotMax + 1e-6, "D: limit violated")
    end
end

-- E: no stick input in easy mode -> crane holds still even if raw .move is 0
reset()
local before = {boom.curRot[1], jib.curRot[1], tel1.curTrans[3]}
run(0, 0, 500)
assert(before[1] == boom.curRot[1] and before[2] == jib.curRot[1] and before[3] == tel1.curTrans[3], "E: crane must hold")

-- F: manual telescope in easy mode still works
reset()
t0 = tel1.curTrans[3]
tel1.move = 1
run(0, 0, 400)
tel1.move = 0
assert(tel1.curTrans[3] - t0 > 0.1, "F: manual telescope")
print("E/F ok: holds still, manual telescope works")

-- G: diagonal at speed: tip speed close to 1.4 m/s
reset()
y0, z0 = tip()
run(spec.signBoomUp * 0.7071, spec.signJibOpen * 0.7071, 500)
y1, z1 = tip()
local sp = math.sqrt((y1 - y0) ^ 2 + (z1 - z0) ^ 2) / 0.5
print(string.format("G: diagonal tip speed %.2f m/s", sp))
assert(sp > 0.7 and sp < 1.6, "G: speed")
