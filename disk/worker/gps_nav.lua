-- GPS-based Navigation API
-- Provides simple navigation functions using absolute GPS coordinates
-- No coordinate system confusion - just provide GPS coords and go there

local startGPS = nil
local currentGPS = nil

-- Get GPS position with retries
local function getGPS(retries)
    retries = retries or 3
    for i = 1, retries do
        local x, y, z = gps.locate(5)
        if x then
            return {x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5)}
        end
        sleep(0.5)
    end
    return nil
end

-- Initialize the GPS navigation system
function init()
    startGPS = getGPS(5)
    if not startGPS then
        error("Failed to initialize GPS navigation - could not get GPS position")
    end
    currentGPS = {x = startGPS.x, y = startGPS.y, z = startGPS.z}
    return startGPS
end

-- Update current position estimate
function updatePosition()
    local gps = getGPS(3)
    if gps then
        currentGPS = gps
    end
    return currentGPS
end

-- Get current GPS position (returns a copy to prevent external modification)
function getPosition()
    return {x = currentGPS.x, y = currentGPS.y, z = currentGPS.z}
end

-- Get starting GPS position
function getStart()
    return startGPS
end

-- Move forward, updating GPS estimate
function forward()
    if turtle.forward() then
        -- Update position estimate based on facing
        -- We'll verify with GPS periodically
        return true
    end
    return false
end

-- Move up, updating GPS estimate
function up()
    if turtle.up() then
        currentGPS.y = currentGPS.y + 1
        return true
    end
    return false
end

-- Move down, updating GPS estimate  
function down()
    if turtle.down() then
        currentGPS.y = currentGPS.y - 1
        return true
    end
    return false
end

-- Dig forward and move
function digForward()
    while turtle.detect() do
        if not turtle.dig() then
            return false
        end
        sleep(0.5)
    end
    return forward()
end

-- Dig up and move
function digUp()
    while turtle.detectUp() do
        if not turtle.digUp() then
            return false
        end
        sleep(0.5)
    end
    return up()
end

-- Dig down and move
function digDown()
    while turtle.detectDown() do
        if not turtle.digDown() then
            return false
        end
        sleep(0.5)
    end
    return down()
end

-- Navigate to a GPS position
-- This is the main function - just provide GPS coords and it goes there
function goto(targetX, targetY, targetZ)
    if not targetX or not targetY or not targetZ then
        error("Invalid target coordinates")
    end
    
    print("Navigating to GPS (" .. targetX .. ", " .. targetY .. ", " .. targetZ .. ")")
    
    -- Navigate Y first (vertical movement)
    while currentGPS.y < targetY do
        if not digUp() then
            print("Blocked going up")
            return false
        end
    end
    
    while currentGPS.y > targetY do
        if not digDown() then
            print("Blocked going down")
            return false
        end
    end
    
    -- Navigate X and Z using GPS feedback
    local maxAttempts = 500
    local attempts = 0
    
    while attempts < maxAttempts do
        -- Update position from GPS
        local gps = getGPS(5)
        if not gps then
            print("Warning: GPS unavailable, using estimate")
            gps = currentGPS
        else
            currentGPS = gps
        end
        
        local deltaX = targetX - currentGPS.x
        local deltaZ = targetZ - currentGPS.z
        
        print("Current: (" .. currentGPS.x .. ", " .. currentGPS.z .. ") Target: (" .. targetX .. ", " .. targetZ .. ") Delta: (" .. deltaX .. ", " .. deltaZ .. ")")
        
        -- Check if we've arrived (within 0.5 blocks to be safe)
        if math.abs(deltaX) < 0.5 and math.abs(deltaZ) < 0.5 then
            print("Arrived at target!")
            return true
        end
        
        -- Move toward target one block at a time
        -- Choose the axis with the larger distance
        if math.abs(deltaX) >= math.abs(deltaZ) and math.abs(deltaX) >= 0.5 then
            -- Move in X direction
            local targetFacing = (deltaX > 0) and "east" or "west"
            if not faceDirection(targetFacing) then
                print("Failed to face " .. targetFacing)
                return false
            end
            if not digForward() then
                print("Blocked moving in X direction")
                return false
            end
        elseif math.abs(deltaZ) >= 0.5 then
            -- Move in Z direction  
            local targetFacing = (deltaZ > 0) and "south" or "north"
            if not faceDirection(targetFacing) then
                print("Failed to face " .. targetFacing)
                return false
            end
            if not digForward() then
                print("Blocked moving in Z direction")
                return false
            end
        end
        
        attempts = attempts + 1
        
        -- Brief pause to let GPS update
        sleep(0.1)
    end
    
    print("Failed to reach target after " .. maxAttempts .. " attempts")
    return false
end

-- Face a cardinal direction (north, south, east, west)
function faceDirection(direction)
    -- Get current position to determine facing
    local gps1 = getGPS(5)
    if not gps1 then
        print("Warning: Cannot determine facing without GPS")
        return false
    end
    
    -- Move forward and check GPS to determine current facing
    local moved = turtle.forward()
    if not moved then
        -- Can't determine facing if can't move, just try turning
        for i = 1, 4 do
            if turtle.forward() then
                moved = true
                break
            end
            turtle.turnRight()
        end
        if not moved then
            return false -- Can't move at all
        end
    end
    
    local gps2 = getGPS(5)
    if not gps2 then
        -- Move back and give up
        turtle.back()
        return false
    end
    
    -- Determine current facing from movement
    local dx = gps2.x - gps1.x
    local dz = gps2.z - gps1.z
    
    local currentFacing
    if dx > 0 then
        currentFacing = "east"
    elseif dx < 0 then
        currentFacing = "west"
    elseif dz > 0 then
        currentFacing = "south"
    elseif dz < 0 then
        currentFacing = "north"
    end
    
    -- Update current position
    currentGPS = gps2
    
    -- Calculate turns needed
    local directions = {"north", "east", "south", "west"}
    local currentIdx, targetIdx
    
    for i, dir in ipairs(directions) do
        if dir == currentFacing then currentIdx = i end
        if dir == direction then targetIdx = i end
    end
    
    if not currentIdx or not targetIdx then
        return false
    end
    
    local turns = (targetIdx - currentIdx) % 4
    
    -- Execute turns
    for i = 1, turns do
        turtle.turnRight()
    end
    
    return true
end

-- Return to starting position
function returnHome()
    if not startGPS then
        error("GPS navigation not initialized")
    end
    return goto(startGPS.x, startGPS.y, startGPS.z)
end
