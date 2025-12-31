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

-- Transform dig.lua local coordinates to GPS world coordinates
-- 
-- COORDINATE SYSTEM MAPPING:
-- - dig.lua: local coordinate system starting at deployer's initial position (0,0,0)
--   - dig.lua +X: workers spread along this axis (width dimension)
--   - dig.lua +Z: mining forward direction (length dimension)  
--   - dig.lua rotation=0: initial facing direction (points toward dig.lua +Z)
--
-- - GPS: world coordinates (North=-Z, East=+X, South=+Z, West=-X in Minecraft)
--
-- - initialDirection: which GPS cardinal direction dig.lua +X axis points toward
--   (determined by observing chest GPS positions after deployer moves to dig.lua (1,0,0))
--
-- - dig.lua +Z is always 90° clockwise from dig.lua +X (when viewed from above, Y+)
--
-- ROTATION SYSTEM (dig.lua, clockwise positive):
--   rotation=0   → faces dig.lua +Z
--   rotation=90  → faces dig.lua +X  
--   rotation=180 → faces dig.lua -Z (workers start with this)
--   rotation=270 → faces dig.lua -X
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
        
        -- Transform dig.lua coordinates to GPS based on which direction dig.lua +X points
        -- dig.lua +Z (rotation=0) is 90° COUNTER-clockwise from dig.lua +X (rotation=90)
        -- This is because turning RIGHT (clockwise) from +Z gets you to +X
        
        if initialDirection == "north" then
            -- dig.lua +X → GPS North (GPS -Z)
            -- dig.lua +Z → GPS West (GPS -X) [90° counter-clockwise from North]
            gps_xmin = startGPS.x - zone.zmax
            gps_xmax = startGPS.x - zone.zmin
            gps_zmin = startGPS.z - zone.xmax
            gps_zmax = startGPS.z - zone.xmin
        elseif initialDirection == "south" then
            -- dig.lua +X → GPS South (GPS +Z)
            -- dig.lua +Z → GPS East (GPS +X) [90° counter-clockwise from South]
            gps_xmin = startGPS.x + zone.zmin
            gps_xmax = startGPS.x + zone.zmax
            gps_zmin = startGPS.z + zone.xmin
            gps_zmax = startGPS.z + zone.xmax
        elseif initialDirection == "east" then
            -- dig.lua +X → GPS East (GPS +X)
            -- dig.lua +Z → GPS North (GPS -Z) [90° counter-clockwise from East]
            gps_xmin = startGPS.x + zone.xmin
            gps_xmax = startGPS.x + zone.xmax
            gps_zmin = startGPS.z - zone.zmax
            gps_zmax = startGPS.z - zone.zmin
        elseif initialDirection == "west" then
            -- dig.lua +X → GPS West (GPS -X)
            -- dig.lua +Z → GPS South (GPS +Z) [90° counter-clockwise from West]
            gps_xmin = startGPS.x - zone.xmax
            gps_xmax = startGPS.x - zone.xmin
            gps_zmin = startGPS.z + zone.zmin
            gps_zmax = startGPS.z + zone.zmax
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

-- Calculate which GPS cardinal direction dig.lua +X axis points toward
-- The deployer places chests with output at dig.lua (0,0,0) and fuel at dig.lua (1,0,0)
-- By observing the GPS positions, we can deduce the coordinate system mapping
-- Returns: GPS cardinal direction that dig.lua +X points toward
function ZoneManager.calculateInitialDirection(fuelChestGPS, outputChestGPS)
    if not fuelChestGPS or not outputChestGPS then
        return "south", "No chest positions provided, defaulting to south"
    end
    
    local deltaX = fuelChestGPS.x - outputChestGPS.x
    local deltaZ = fuelChestGPS.z - outputChestGPS.z
    
    -- Fuel chest is at dig.lua (1, 0, 0) relative to output chest at (0, 0, 0)
    -- The GPS delta tells us which GPS direction is dig.lua +X
    if math.abs(deltaX) > math.abs(deltaZ) then
        if deltaX > 0 then
            return "east"   -- dig.lua +X → GPS +X (East)
        else
            return "west"   -- dig.lua +X → GPS -X (West)
        end
    else
        if deltaZ > 0 then
            return "south"  -- dig.lua +X → GPS +Z (South)
        else
            return "north"  -- dig.lua +X → GPS -Z (North)
        end
    end
end

-- Calculate which GPS cardinal direction workers should face
-- Workers are placed with dig.lua rotation=180, which means they face dig.lua -Z
-- Since dig.lua +Z is 90° counter-clockwise from dig.lua +X,
-- dig.lua -Z is 90° clockwise from dig.lua +X
function ZoneManager.calculateWorkerFacing(initialDirection)
    -- dig.lua -Z (rotation=180) is 90° clockwise from dig.lua +X (rotation=90)
    if initialDirection == "north" then
        return "east"   -- dig.lua +X→North, so -Z→East (90° clockwise)
    elseif initialDirection == "south" then
        return "west"   -- dig.lua +X→South, so -Z→West (90° clockwise)
    elseif initialDirection == "east" then
        return "south"  -- dig.lua +X→East, so -Z→South (90° clockwise)
    elseif initialDirection == "west" then
        return "north"  -- dig.lua +X→West, so -Z→North (90° clockwise)
    else
        return "north"  -- fallback
    end
end

return ZoneManager
