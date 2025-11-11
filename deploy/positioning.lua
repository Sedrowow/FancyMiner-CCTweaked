-- GPS and Positioning for Deployment
-- Handles GPS coordinate retrieval and navigation helpers

local M = {}

-- Get GPS coordinates with retry logic
function M.getGPS(retries)
    retries = retries or 5
    for i = 1, retries do
        local x, y, z = gps.locate(5)
        if x then
            return {x = x, y = y, z = z}
        end
        sleep(1)
    end
    return nil, "Failed to get GPS after " .. retries .. " attempts"
end

-- Format GPS coordinates as a string
function M.formatGPS(gps)
    if not gps then return "No GPS" end
    return string.format("(%d, %d, %d)", gps.x, gps.y, gps.z)
end

-- Check if two GPS positions are equal
function M.equals(gps1, gps2)
    if not gps1 or not gps2 then return false end
    return gps1.x == gps2.x and gps1.y == gps2.y and gps1.z == gps2.z
end

-- Calculate distance between two GPS positions
function M.distance(gps1, gps2)
    if not gps1 or not gps2 then return nil end
    local dx = gps1.x - gps2.x
    local dy = gps1.y - gps2.y
    local dz = gps1.z - gps2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

return M
