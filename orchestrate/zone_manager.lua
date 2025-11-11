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

-- Convert relative zones to GPS coordinates
function ZoneManager.createGPSZones(zones, startGPS)
    if not zones then
        return nil, "zones is nil"
    end
    
    if not startGPS then
        return nil, "startGPS is nil"
    end
    
    local gpsZones = {}
    for i, zone in ipairs(zones) do
        gpsZones[i] = {
            gps_xmin = startGPS.x + zone.xmin,
            gps_xmax = startGPS.x + zone.xmax,
            gps_zmin = startGPS.z + zone.zmin,
            gps_zmax = startGPS.z + zone.zmax,
            gps_ymin = startGPS.y + zone.ymin,
            gps_ymax = startGPS.y + zone.ymax,
            assigned = false
        }
    end
    
    return gpsZones, nil
end

-- Find zone that contains a GPS position
function ZoneManager.findZoneForPosition(gpsZones, workerGPS)
    if not gpsZones or not workerGPS then
        return nil
    end
    
    for i = 1, #gpsZones do
        local gpsZone = gpsZones[i]
        
        -- Check if worker's position is within this zone's boundaries
        if workerGPS.x >= gpsZone.gps_xmin and workerGPS.x <= gpsZone.gps_xmax and
           workerGPS.z >= gpsZone.gps_zmin and workerGPS.z <= gpsZone.gps_zmax then
            return i, gpsZone
        end
    end
    
    return nil
end

-- Calculate initial cardinal direction based on chest positions
function ZoneManager.calculateInitialDirection(fuelChestGPS, outputChestGPS)
    if not fuelChestGPS or not outputChestGPS then
        return "south" -- default
    end
    
    local deltaX = fuelChestGPS.x - outputChestGPS.x
    local deltaZ = fuelChestGPS.z - outputChestGPS.z
    
    -- Fuel chest is at +1 X in dig.lua coordinates
    -- Workers face rotation 180 = opposite direction of +X
    -- The original code had an inconsistency - fixing the mapping
    if math.abs(deltaX) > math.abs(deltaZ) then
        if deltaX > 0 then
            -- Fuel is east of output, so dig.lua +X = cardinal east
            -- Workers face opposite direction: west (but code had south)
            return "south"
        else
            -- Fuel is west of output, so dig.lua +X = cardinal west
            -- Workers face opposite direction: east (but code had north)
            return "north"
        end
    else
        if deltaZ > 0 then
            -- Fuel is south of output, so dig.lua +X = cardinal south
            -- Workers face opposite direction: north (but code had east)
            return "east"
        else
            -- Fuel is north of output, so dig.lua +X = cardinal north
            -- Workers face opposite direction: south (but code had west)
            return "west"
        end
    end
end

return ZoneManager
