-- GPS Utilities Module
-- Provides GPS coordinate retrieval, formatting, and navigation helpers
-- Consolidates GPS functions used across worker system

local M = {}

-- Get GPS coordinates with retry logic
-- Returns: GPS table {x, y, z} or nil, error message
function M.getGPS(retries, timeout)
    retries = retries or 5
    timeout = timeout or 5
    
    for i = 1, retries do
        local x, y, z = gps.locate(timeout)
        if x then
            return {x = x, y = y, z = z}
        end
        sleep(0.5)
    end
    
    return nil, "Failed to get GPS after " .. retries .. " attempts"
end

-- Format GPS coordinates as a string
function M.formatGPS(gps)
    if not gps then return "No GPS" end
    return string.format("(%d, %d, %d)", gps.x, gps.y, gps.z)
end

-- Check if two GPS positions are equal (with optional tolerance)
function M.equals(gps1, gps2, tolerance)
    if not gps1 or not gps2 then return false end
    tolerance = tolerance or 0.5
    
    return math.abs(gps1.x - gps2.x) < tolerance and
           math.abs(gps1.y - gps2.y) < tolerance and
           math.abs(gps1.z - gps2.z) < tolerance
end

-- Calculate Manhattan distance between two GPS positions
function M.manhattanDistance(gps1, gps2)
    if not gps1 or not gps2 then return nil end
    return math.abs(gps1.x - gps2.x) + 
           math.abs(gps1.y - gps2.y) + 
           math.abs(gps1.z - gps2.z)
end

-- Calculate Euclidean distance between two GPS positions
function M.distance(gps1, gps2)
    if not gps1 or not gps2 then return nil end
    local dx = gps1.x - gps2.x
    local dy = gps1.y - gps2.y
    local dz = gps1.z - gps2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Copy GPS table
function M.copy(gps)
    if not gps then return nil end
    return {x = gps.x, y = gps.y, z = gps.z}
end

-- Validate GPS table structure
function M.isValid(gps)
    return type(gps) == "table" and
           type(gps.x) == "number" and
           type(gps.y) == "number" and
           type(gps.z) == "number"
end

return M
