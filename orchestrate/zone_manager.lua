-- Zone Management Module for Orchestration Server
-- Handles zone calculation and GPS zone assignment

local ZoneManager = {}

-- Calculate zone assignments based on quarry dimensions
function ZoneManager.calculateZones(width, length, depth, skip, numWorkers)
    local zones = {}
    local baseWidth = math.floor(width / numWorkers)
    
    for i = 1, numWorkers do
        local xmin = (i - 1) * baseWidth
        local xmax = xmin + baseWidth - 1
        
        -- Last worker gets any remainder
        if i == numWorkers then
            xmax = width - 1
        end
        
        zones[i] = {
            xmin = xmin,
            xmax = xmax,
            zmin = 0,
            zmax = length - 1,
            ymin = -depth,
            ymax = 0,
            skip = skip or 0
        }
    end
    
    return zones
end

-- Deployer faces a direction, workers face opposite (rotation 180)
-- dig.lua +X is to deployer's right, workers are placed along this axis
--   "north" = deployer's right is GPS +X (east)
--   "south" = deployer's right is GPS -X (west)
--   "east" = deployer's right is GPS +Z (south)
--   "west" = deployer's right is GPS -Z (north)
function ZoneManager.createGPSZones(zones, startGPS, initialDirection)
    if not zones then
        return nil, "zones is nil"
    end
    
    if not startGPS then
        return nil, "startGPS is nil"
    end
    
    if not initialDirection then
        return nil, "initialDirection is nil"
    end
    
    local gpsZones = {}
    for i, zone in ipairs(zones) do
        local gps_xmin, gps_xmax, gps_zmin, gps_zmax
        
        -- Transform dig.lua coordinates to GPS coordinates based on direction
        -- The deployer faces a direction, workers face opposite (rotation 180)
        -- dig.lua +X is to the deployer's right, workers are placed along this axis
        if initialDirection == "north" then
            -- Deployer faces north (-Z), workers face south (+Z)
            -- Deployer's right (dig.lua +X) is east (+X GPS)
            -- dig.lua +Z (forward for deployer) = north (-Z GPS)
            gps_xmin = startGPS.x + zone.xmin
            gps_xmax = startGPS.x + zone.xmax
            gps_zmin = startGPS.z - zone.zmax
            gps_zmax = startGPS.z - zone.zmin
        elseif initialDirection == "south" then
            -- Deployer faces south (+Z), workers face north (-Z)
            -- Deployer's right (dig.lua +X) is west (-X GPS)
            -- dig.lua +Z (forward for deployer) = south (+Z GPS)
            gps_xmin = startGPS.x - zone.xmax
            gps_xmax = startGPS.x - zone.xmin
            gps_zmin = startGPS.z + zone.zmin
            gps_zmax = startGPS.z + zone.zmax
        elseif initialDirection == "east" then
            -- Deployer faces east (+X), workers face west (-X)
            -- Deployer's right (dig.lua +X) is south (+Z GPS)
            -- dig.lua +Z (forward for deployer) = east (+X GPS)
            gps_xmin = startGPS.x + zone.zmin
            gps_xmax = startGPS.x + zone.zmax
            gps_zmin = startGPS.z + zone.xmin
            gps_zmax = startGPS.z + zone.xmax
        elseif initialDirection == "west" then
            -- Deployer faces west (-X), workers face east (+X)
            -- Deployer's right (dig.lua +X) is north (-Z GPS)
            -- Workers are physically deployed along dig.lua +X (width axis).
            -- Previous implementation incorrectly mapped width (zone.x) to GPS Z and length (zone.z) to GPS X,
            -- causing all west-facing workers to fall inside the first zone's Z range (duplicate zone assignment).
            -- Fix: Map width (zone.x) to the GPS X axis (negative direction for west) and length (zone.z) to GPS Z (negative for north).
            -- Width (dig +X) -> GPS -X; Length (dig +Z) -> GPS -Z
            gps_xmin = startGPS.x - zone.xmax
            gps_xmax = startGPS.x - zone.xmin
            gps_zmin = startGPS.z - zone.zmax
            gps_zmax = startGPS.z - zone.zmin
        else
            return nil, "Invalid initialDirection: " .. tostring(initialDirection)
        end
        
        gpsZones[i] = {
            gps_xmin = gps_xmin,
            gps_xmax = gps_xmax,
            gps_zmin = gps_zmin,
            gps_zmax = gps_zmax,
            gps_ymin = startGPS.y + zone.ymin,
            gps_ymax = startGPS.y + zone.ymax,
            assigned = false
        }
    end
    
    return gpsZones, nil
end

-- Find zone that contains a GPS position
-- For boundary positions, prefer the zone with the lower index
function ZoneManager.findZoneForPosition(gpsZones, workerGPS)
    if not gpsZones or not workerGPS then
        return nil
    end
    
    for i = 1, #gpsZones do
        local gpsZone = gpsZones[i]
        
        -- Check if worker's position is within this zone's boundaries
        -- Note: If a worker is exactly on the boundary between two zones,
        -- we'll assign them to the first matching zone (lower index)
        if workerGPS.x >= gpsZone.gps_xmin and workerGPS.x <= gpsZone.gps_xmax and
           workerGPS.z >= gpsZone.gps_zmin and workerGPS.z <= gpsZone.gps_zmax then
            return i, gpsZone
        end
    end
    
    return nil
end

-- Calculate initial cardinal direction based on chest positions
-- The deployer places chests with output at (0,0,0) and fuel at (+1,0,0) in dig.lua coords
-- Workers are placed at their zone's xmin (e.g., 0, 10, 20...) facing rotation 180 (opposite of +X)
-- Returns which cardinal direction corresponds to dig.lua +X axis
function ZoneManager.calculateInitialDirection(fuelChestGPS, outputChestGPS)
    if not fuelChestGPS or not outputChestGPS then
        return "east", "No chest positions provided, defaulting to east"
    end
    
    local deltaX = fuelChestGPS.x - outputChestGPS.x
    local deltaZ = fuelChestGPS.z - outputChestGPS.z
    
    -- Fuel chest is at dig.lua (+1, 0, 0) relative to output chest at (0, 0, 0)
    -- So the GPS difference tells us which cardinal direction is dig.lua +X
    if math.abs(deltaX) > math.abs(deltaZ) then
        if deltaX > 0 then
            -- Fuel is east (+X GPS) of output, so dig.lua +X = GPS +X = east
            return "east"
        else
            -- Fuel is west (-X GPS) of output, so dig.lua +X = GPS -X = west
            return "west"
        end
    else
        if deltaZ > 0 then
            -- Fuel is south (+Z GPS) of output, so dig.lua +X = GPS +Z = south
            return "south"
        else
            -- Fuel is north (-Z GPS) of output, so dig.lua +X = GPS -Z = north
            return "north"
        end
    end
end

return ZoneManager
