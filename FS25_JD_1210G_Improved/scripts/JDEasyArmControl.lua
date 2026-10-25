--[[
JDEasyArmControl - easy crane control for cranes whose model does not fit the base game easyArmControl
(the base game requires the second boom joint to lie exactly on the axis of the first one).

With the game setting "easy crane control" on, the two boom axes move the grapple straight
up/down and in/out. Main boom, knuckle boom and telescope are solved together every frame
(damped least squares on the joint velocities), the slewing stays manual.

Author: NikGro (private edit of the JD 1210G by Rimvis)
]]

JDEasyArmControl = {}
JDEasyArmControl.MOD_NAME = g_currentModName
JDEasyArmControl.SPEC_TABLE_NAME = "spec_" .. g_currentModName .. ".jdEasyArmControl"
JDEasyArmControl.KEY = "vehicle.jdEasyArmControl"
-- the telescope takes a bigger share of in/out movements, like a real boom control system
JDEasyArmControl.TELESCOPE_WEIGHT = 4

function JDEasyArmControl.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Cylindered, specializations)
end

function JDEasyArmControl.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("JDEasyArmControl")
    local key = JDEasyArmControl.KEY
    schema:register(XMLValueType.NODE_INDEX, key .. "#slewNode", "Slewing column (reference frame of the crane plane)")
    schema:register(XMLValueType.NODE_INDEX, key .. "#boomNode", "Main boom moving tool node (x rotation)")
    schema:register(XMLValueType.NODE_INDEX, key .. "#jibNode", "Knuckle boom moving tool node (x rotation)")
    schema:register(XMLValueType.NODE_INDEX, key .. "#telescopeNode", "Telescope stage 1 moving tool node")
    schema:register(XMLValueType.NODE_INDEX, key .. "#telescope2Node", "Telescope stage 2 moving tool node (optional)")
    schema:register(XMLValueType.NODE_INDEX, key .. "#tipNode", "Crane tip (grapple joint)")
    schema:register(XMLValueType.FLOAT, key .. "#speed", "Tip speed at full input in m/s", 1.4)
    schema:register(XMLValueType.BOOL, key .. "#invertY", "Invert up/down", false)
    schema:register(XMLValueType.BOOL, key .. "#invertZ", "Invert in/out", false)
    schema:setXMLSpecializationType()
end

function JDEasyArmControl.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getMovingToolMoveValue", JDEasyArmControl.getMovingToolMoveValue)
end

function JDEasyArmControl.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", JDEasyArmControl)
    SpecializationUtil.registerEventListener(vehicleType, "onPreUpdate", JDEasyArmControl)
    SpecializationUtil.registerEventListener(vehicleType, "onVehicleSettingChanged", JDEasyArmControl)
end

-- ---------------------------------------------------------------- small vector helpers
local function cross(ax, ay, az, bx, by, bz)
    return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function sign(v)
    if v < 0 then return -1 end
    return 1
end

-- ---------------------------------------------------------------- load
function JDEasyArmControl:onPostLoad(savegame)
    local spec = self[JDEasyArmControl.SPEC_TABLE_NAME]
    spec.isValid = false
    spec.state = false
    spec.ikActive = false
    spec.moves = {}

    local ok, err = pcall(JDEasyArmControl.loadSetup, self, spec)
    if not ok then
        Logging.error("[JDEasyArmControl] %s", tostring(err))
        spec.isValid = false
    end
end

function JDEasyArmControl.loadSetup(self, spec)
    local xmlFile, key = self.xmlFile, JDEasyArmControl.KEY
    if not xmlFile:hasProperty(key) then
        return
    end

    local function tool(attr, required)
        local node = xmlFile:getValue(key .. "#" .. attr, nil, self.components, self.i3dMappings)
        local t = node ~= nil and self:getMovingToolByNode(node) or nil
        if t == nil and required then
            Logging.xmlWarning(xmlFile, "[JDEasyArmControl] '%s' is no moving tool", attr)
        end
        return t
    end

    spec.slewNode = xmlFile:getValue(key .. "#slewNode", nil, self.components, self.i3dMappings)
    spec.tipNode = xmlFile:getValue(key .. "#tipNode", nil, self.components, self.i3dMappings)
    spec.boom = tool("boomNode", true)
    spec.jib = tool("jibNode", true)
    spec.tel1 = tool("telescopeNode", false)
    spec.tel2 = tool("telescope2Node", false)
    spec.speed = xmlFile:getValue(key .. "#speed", 1.4) / 1000 -- m/ms
    spec.invertY = xmlFile:getValue(key .. "#invertY", false)
    spec.invertZ = xmlFile:getValue(key .. "#invertZ", false)

    if spec.slewNode == nil or spec.tipNode == nil or spec.boom == nil or spec.jib == nil
        or spec.boom.rotSpeed == nil or spec.jib.rotSpeed == nil then
        Logging.xmlWarning(xmlFile, "[JDEasyArmControl] incomplete setup, easy control disabled")
        return
    end
    if spec.tel1 ~= nil and spec.tel1.transSpeed == nil then spec.tel1 = nil end
    if spec.tel2 ~= nil and (spec.tel1 == nil or spec.tel2.transSpeed == nil) then spec.tel2 = nil end

    spec.isValid = true
    spec.stickY = JDEasyArmControl.getStickSigns(self, spec)
end

-- Direction of the sticks: pushing the boom stick the way that raises the main boom raises the
-- grapple, pushing the knuckle stick the way that opens the knuckle moves the grapple out.
-- Both signs do not depend on the current crane pose.
function JDEasyArmControl.getStickSigns(self, spec)
    local s = spec.slewNode
    local function localPos(node) return worldToLocal(s, getWorldTranslation(node)) end
    local function localAxis(node) return worldDirectionToLocal(s, localDirectionToWorld(node, 1, 0, 0)) end

    local bx, by, bz = localPos(spec.boom.node)
    local jx, jy, jz = localPos(spec.jib.node)
    local tx, ty, tz = localPos(spec.tipNode)

    -- main boom: elevation change of the boom vector for move=+1
    local vx, vy, vz = jx - bx, jy - by, jz - bz
    local ax, ay, az = localAxis(spec.boom.node)
    local _, dvy, dvz = cross(ax, ay, az, vx, vy, vz)
    local horiz = sign(vz)
    -- elevation = atan2(vy, |vz|): d/dt = (|vz| dvy - vy * sign(vz) dvz) / |v|^2
    local dElev = (math.abs(vz) * dvy - vy * horiz * dvz) * spec.boom.rotSpeed
    spec.signBoomUp = sign(dElev)

    -- knuckle: opening angle between (boom pivot - jib pivot) and (tip - jib pivot)
    local ux, uy, uz = bx - jx, by - jy, bz - jz
    local wx, wy, wz = tx - jx, ty - jy, tz - jz
    local cx, cy, cz = localAxis(spec.jib.node)
    local dwx, dwy, dwz = cross(cx, cy, cz, wx, wy, wz)
    local lu = math.sqrt(ux * ux + uy * uy + uz * uz)
    local lw2 = wx * wx + wy * wy + wz * wz
    -- d(cos phi) = (u . dw) / (|u||w|) - (u . w)(w . dw) / (|u||w|^3); opening means cos decreases
    local udw = ux * dwx + uy * dwy + uz * dwz
    local uw = ux * wx + uy * wy + uz * wz
    local wdw = wx * dwx + wy * dwy + wz * dwz
    local lw = math.sqrt(lw2)
    local dCos = (udw / (lu * lw) - uw * wdw / (lu * lw * lw2)) * spec.jib.rotSpeed
    spec.signJibOpen = -sign(dCos)
    return true
end

function JDEasyArmControl:onVehicleSettingChanged(gameSettingId, state)
    if gameSettingId == GameSettings.SETTING.EASY_ARM_CONTROL then
        local spec = self[JDEasyArmControl.SPEC_TABLE_NAME]
        spec.state = state == true
        spec.ikActive = false
    end
end

-- ---------------------------------------------------------------- solver
local function toolMoveAllowed(tool, m)
    -- false if the tool is at a limit and m would push it further
    if tool.rotSpeed ~= nil then
        local r = tool.curRot[tool.rotationAxis]
        local d = m * tool.rotSpeed
        if tool.rotMax ~= nil and d > 0 and r >= tool.rotMax - 0.0001 then return false end
        if tool.rotMin ~= nil and d < 0 and r <= tool.rotMin + 0.0001 then return false end
    elseif tool.transSpeed ~= nil then
        local t = tool.curTrans[tool.translationAxis]
        local d = m * tool.transSpeed
        if tool.transMax ~= nil and d > 0 and t >= tool.transMax - 0.0001 then return false end
        if tool.transMin ~= nil and d < 0 and t <= tool.transMin + 0.0001 then return false end
    end
    return true
end

-- columns: {{y, z}, ...} tip velocity in m/ms per unit move; v: wanted tip velocity {y, z}
-- weights: preference per joint (higher = used more)
local function solve(cols, weights, enabled, vy, vz)
    local a, b, c = 0, 0, 0 -- J W J^T = [[a b] [b c]]
    for i, col in ipairs(cols) do
        if enabled[i] then
            local w = weights[i]
            a = a + w * col[1] * col[1]
            b = b + w * col[1] * col[2]
            c = c + w * col[2] * col[2]
        end
    end
    local lambda = 0.002 * (a + c) + 1e-12
    a, c = a + lambda, c + lambda
    local det = a * c - b * b
    if math.abs(det) < 1e-30 then
        return nil
    end
    local py = (c * vy - b * vz) / det
    local pz = (-b * vy + a * vz) / det
    local m = {}
    for i, col in ipairs(cols) do
        m[i] = enabled[i] and weights[i] * (col[1] * py + col[2] * pz) or 0
    end
    return m
end

function JDEasyArmControl.computeMoves(self, spec)
    local boom, jib, tel1, tel2 = spec.boom, spec.jib, spec.tel1, spec.tel2

    local inY = boom.move or 0
    local inZ = jib.move or 0
    local manualTelescope = tel1 ~= nil and (tel1.move or 0) ~= 0
    for _, t in ipairs({boom, jib, tel1, tel2}) do
        spec.moves[t] = 0
    end
    if inY == 0 and inZ == 0 then
        return false
    end

    local s = spec.slewNode
    local tx, ty, tz = worldToLocal(s, getWorldTranslation(spec.tipNode))

    local function rotColumn(tool)
        local px, py, pz = worldToLocal(s, getWorldTranslation(tool.node))
        local ax, ay, az = worldDirectionToLocal(s, localDirectionToWorld(tool.node, 1, 0, 0))
        local _, dy, dz = cross(ax, ay, az, tx - px, ty - py, tz - pz)
        return {dy * tool.rotSpeed, dz * tool.rotSpeed}
    end

    local cols, tools, weights = {rotColumn(boom), rotColumn(jib)}, {boom, jib}, {1, 1}
    if tel1 ~= nil and not manualTelescope then
        local _, dy, dz = worldDirectionToLocal(s, localDirectionToWorld(tel1.node, 0, 0, 1))
        local speed = tel1.transSpeed
        if tel2 ~= nil then
            speed = speed + tel2.transSpeed
        end
        table.insert(cols, {dy * speed, dz * speed})
        table.insert(tools, tel1)
        table.insert(weights, JDEasyArmControl.TELESCOPE_WEIGHT)
    end

    -- wanted tip velocity in the crane plane; z sign so that "out" moves away from the column
    local uy = inY * spec.signBoomUp * (spec.invertY and -1 or 1)
    local uz = inZ * spec.signJibOpen * (spec.invertZ and -1 or 1)
    local len = math.sqrt(uy * uy + uz * uz)
    if len > 1 then
        uy, uz = uy / len, uz / len
    end
    local vy = uy * spec.speed
    local vz = uz * spec.speed * sign(tz)

    local enabled = {}
    for i = 1, #cols do enabled[i] = true end

    local m
    for _ = 1, 3 do
        m = solve(cols, weights, enabled, vy, vz)
        if m == nil then
            return false
        end
        local blocked = false
        for i, tool in ipairs(tools) do
            if enabled[i] and not toolMoveAllowed(tool, m[i]) then
                enabled[i] = false
                blocked = true
            end
        end
        if not blocked then
            break
        end
    end

    -- keep the direction, respect the max speed of every joint
    local maxM = 0
    for i = 1, #m do
        maxM = math.max(maxM, math.abs(m[i]))
    end
    local scale = maxM > 1 and 1 / maxM or 1
    for i, tool in ipairs(tools) do
        spec.moves[tool] = m[i] * scale
    end
    if tel2 ~= nil and spec.moves[tel1] ~= nil then
        spec.moves[tel2] = spec.moves[tel1]
    end
    return true
end

function JDEasyArmControl:onPreUpdate(dt)
    local spec = self[JDEasyArmControl.SPEC_TABLE_NAME]
    if not self.isServer or not spec.isValid then
        return
    end
    spec.ikActive = false
    if spec.state then
        local ok, res = pcall(JDEasyArmControl.computeMoves, self, spec)
        if ok then
            spec.ikActive = res
        else
            Logging.error("[JDEasyArmControl] %s", tostring(res))
            spec.isValid = false
        end
    end
end

function JDEasyArmControl:getMovingToolMoveValue(superFunc, movingTool)
    local spec = self[JDEasyArmControl.SPEC_TABLE_NAME]
    if spec ~= nil and spec.isValid and spec.state then
        if movingTool == spec.boom or movingTool == spec.jib then
            -- the stick values are the wanted grapple direction, never a raw joint move
            return (spec.ikActive and spec.moves[movingTool] or 0) + movingTool.externalMove
        end
        if spec.ikActive and (movingTool == spec.tel1 or movingTool == spec.tel2) then
            local m = spec.moves[movingTool] or 0
            if m ~= 0 then
                return m
            end
        end
    end
    return superFunc(self, movingTool)
end
