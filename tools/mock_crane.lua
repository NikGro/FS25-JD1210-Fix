-- minimal engine mock: scene graph (GIANTS-like euler, Y*X*Z), logging, specialization helpers
LOGS = {}
Logging = {
    error = function(f, ...) local m = string.format(f, ...) table.insert(LOGS, "ERROR " .. m) error(m) end,
    xmlWarning = function(_, f, ...) table.insert(LOGS, "WARN " .. string.format(f, ...)) end,
}
GameSettings = {SETTING = {EASY_ARM_CONTROL = "easyArm"}}
SpecializationUtil = {hasSpecialization = function() return true end}
Cylindered = {}

NODES = {}
local nextId = 1
function newNode(name, parent, t, r)
    nextId = nextId + 1
    NODES[nextId] = {name = name, parent = parent or 0, t = t or {0, 0, 0}, r = r or {0, 0, 0}}
    return nextId
end
function getRotation(n) local r = NODES[n].r return r[1], r[2], r[3] end
function setRotation(n, x, y, z) NODES[n].r = {x, y, z} end
function getTranslation(n) local t = NODES[n].t return t[1], t[2], t[3] end
function setTranslation(n, x, y, z) NODES[n].t = {x, y, z} end

local function mul(a, b)
    local c = {}
    for i = 1, 3 do c[i] = {} for j = 1, 3 do c[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end end
    return c
end
local function rot(rx, ry, rz)
    local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    return mul(mul({{cy, 0, sy}, {0, 1, 0}, {-sy, 0, cy}}, {{1, 0, 0}, {0, cx, -sx}, {0, sx, cx}}), {{cz, -sz, 0}, {sz, cz, 0}, {0, 0, 1}})
end
local function world(n)
    if n == 0 then return {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}, {0, 0, 0} end
    local pr, pt = world(NODES[n].parent)
    local t = NODES[n].t
    local wt = {}
    for i = 1, 3 do wt[i] = pt[i] + pr[i][1] * t[1] + pr[i][2] * t[2] + pr[i][3] * t[3] end
    return mul(pr, rot(NODES[n].r[1], NODES[n].r[2], NODES[n].r[3])), wt
end
function getWorldTranslation(n) local _, t = world(n) return t[1], t[2], t[3] end
function localDirectionToWorld(n, x, y, z)
    local r = world(n)
    return r[1][1] * x + r[1][2] * y + r[1][3] * z, r[2][1] * x + r[2][2] * y + r[2][3] * z, r[3][1] * x + r[3][2] * y + r[3][3] * z
end
function worldDirectionToLocal(n, x, y, z)
    local r = world(n) -- transpose
    return r[1][1] * x + r[2][1] * y + r[3][1] * z, r[1][2] * x + r[2][2] * y + r[3][2] * z, r[1][3] * x + r[2][3] * y + r[3][3] * z
end
function worldToLocal(n, x, y, z)
    local _, t = world(n)
    return worldDirectionToLocal(n, x - t[1], y - t[2], z - t[3])
end
