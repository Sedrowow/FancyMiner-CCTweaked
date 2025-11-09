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
            -- Return raw GPS coordinates without rounding
            return {x = x, y = y, z = z}
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
-- Always fetches fresh GPS coordinates since turtle may have moved via dig.lua
function getPosition()
    updatePosition()
    return {x = currentGPS.x, y = currentGPS.y, z = currentGPS.z}
end

-- Get starting GPS position
function getStart()
    return startGPS
end

-- Determine current facing by test movement
-- Tries all directions if blocked, calculates original facing correctly
local function detectFacing()
    local gps1 = getGPS(5)
    if not gps1 then
        print("GPS NAV: detectFacing failed - no GPS")
        return nil
    end
    
    print("GPS NAV: detectFacing at " .. textutils.serialize(gps1))
    
    -- Try moving forward first
    if turtle.forward() then
        local gps2 = getGPS(5)
        turtle.back()
        
        if gps2 then
            local dx = gps2.x - gps1.x
            local dz = gps2.z - gps1.z
            print("GPS NAV: Moved fwd, delta X=" .. string.format("%.2f", dx) .. " Z=" .. string.format("%.2f", dz))
            
            local direction
            if math.abs(dx) > math.abs(dz) then
                direction = (dx > 0) and "east" or "west"
            else
                direction = (dz > 0) and "south" or "north"
            end
            print("GPS NAV: Facing " .. direction)
            return direction
        end
    end
    
    -- Blocked forward, try turning and testing
    print("GPS NAV: Blocked fwd, testing other directions")
    
    for i = 1, 4 do
        turtle.turnRight()  -- Turn right, updates dig.lua tracking
        
        if turtle.forward() then
            local gps2 = getGPS(5)
            turtle.back()
            
            if gps2 then
                local dx = gps2.x - gps1.x
                local dz = gps2.z - gps1.z
                print("GPS NAV: After " .. i .. " right turns, moved delta X=" .. string.format("%.2f", dx) .. " Z=" .. string.format("%.2f", dz))
                
                -- Determine which direction we just moved
                local movedDirection
                if math.abs(dx) > math.abs(dz) then
                    movedDirection = (dx > 0) and "east" or "west"
                else
                    movedDirection = (dz > 0) and "south" or "north"
                end
                
                print("GPS NAV: Moved " .. movedDirection .. " after " .. i .. " turns")
                
                -- Turn back to original (4-i more right turns completes the circle)
                for j = 1, 4 - i do
                    turtle.turnRight()
                end
                
                -- Calculate original direction: we turned right i times,
                -- so original was i positions counterclockwise from movedDirection
                local directions = {"north", "east", "south", "west"}
                local movedIdx
                for idx, dir in ipairs(directions) do
                    if dir == movedDirection then
                        movedIdx = idx
                        break
                    end
                end
                
                if movedIdx then
                    local originalIdx = ((movedIdx - 1 - i) % 4) + 1
                    local originalDirection = directions[originalIdx]
                    print("GPS NAV: Original facing was " .. originalDirection)
                    return originalDirection
                end
            end
        end
    end
    
    print("GPS NAV: Failed to detect facing after all attempts")
    return nil
end

-- Get the current GPS cardinal direction the turtle is facing
-- Returns: direction string ("north", "south", "east", "west") or nil if detection fails
function getCurrentDirection()
    return detectFacing()
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

-- Helper to calculate turns needed between two cardinal directions
-- Returns: number of right turns (positive) or left turns (negative) for minimum path
local function calculateTurns(currentDir, targetDir)
    local directions = {"north", "east", "south", "west"}
    local currentIdx, targetIdx
    
    for i, dir in ipairs(directions) do
        if dir == currentDir then currentIdx = i end
        if dir == targetDir then targetIdx = i end
    end
    
    if not currentIdx or not targetIdx then
        return 0
    end
    
    local rightTurns = (targetIdx - currentIdx) % 4
    
    -- If more than 2 right turns, turn left instead (more efficient)
    if rightTurns > 2 then
        return -(4 - rightTurns)  -- Negative means turn left
    else
        return rightTurns
    end
end

-- Helper to turn to face a direction (assumes we know current facing)
local function turnToFace(currentFacing, targetFacing)
    local turns = calculateTurns(currentFacing, targetFacing)
    
    if turns > 0 then
        -- Turn right
        for i = 1, turns do
            turtle.turnRight()
        end
    elseif turns < 0 then
        -- Turn left
        for i = 1, -turns do
            turtle.turnLeft()
        end
    end
    -- If turns == 0, already facing correct direction
    
    return targetFacing
end

-- Navigate to a GPS position
-- This is the main function - just provide GPS coords and it goes there
function goto(targetX, targetY, targetZ)
    if not targetX or not targetY or not targetZ then
        error("Invalid target coordinates")
    end
    
    print("GPS NAV: Starting navigation to (" .. targetX .. ", " .. targetY .. ", " .. targetZ .. ")")
    print("GPS NAV: Current position: " .. textutils.serialize(currentGPS))
    
    -- Determine facing once at start for efficiency during this navigation session
    local facing = detectFacing()
    if facing then
        print("GPS NAV: Current facing: " .. facing)
    else
        print("GPS NAV: Warning - Could not detect facing, will use GPS checks")
    end
    
    -- Navigate Y first (vertical movement)
    while currentGPS.y < targetY do
        print("GPS NAV: Moving up (Y: " .. currentGPS.y .. " -> " .. targetY .. ")")
        if not digUp() then
            print("GPS NAV: ERROR - Blocked going up")
            return false
        end
    end
    
    while currentGPS.y > targetY do
        print("GPS NAV: Moving down (Y: " .. currentGPS.y .. " -> " .. targetY .. ")")
        if not digDown() then
            print("GPS NAV: ERROR - Blocked going down")
            return false
        end
    end
    
    print("GPS NAV: Y navigation complete, starting X/Z navigation")
    
    -- Navigate X and Z using GPS feedback
    local maxAttempts = 500
    local attempts = 0
    
    while attempts < maxAttempts do
        -- Update position from GPS
        local gps = getGPS(5)
        if not gps then
            print("Warning: GPS unavailable")
            return false
        end
        currentGPS = gps
        
        local deltaX = targetX - currentGPS.x
        local deltaZ = targetZ - currentGPS.z
        
        -- Check if we've arrived (within 0.5 blocks)
        if math.abs(deltaX) < 0.5 and math.abs(deltaZ) < 0.5 then
            print("Arrived!")
            return true
        end
        
        -- Determine which direction to move (prefer larger delta)
        local targetFacing = nil
        if math.abs(deltaX) >= math.abs(deltaZ) and math.abs(deltaX) >= 0.5 then
            targetFacing = (deltaX > 0) and "east" or "west"
        elseif math.abs(deltaZ) >= 0.5 then
            targetFacing = (deltaZ > 0) and "south" or "north"
        end
        
        if targetFacing then
            -- Turn to face the target direction
            if facing then
                -- Use tracked facing for efficiency
                facing = turnToFace(facing, targetFacing)
            else
                -- Fall back to GPS-based facing detection
                if not faceDirection(targetFacing) then
                    print("Failed to face " .. targetFacing)
                    return false
                end
            end
            
            -- Move forward
            if not digForward() then
                print("Blocked, retrying...")
                attempts = attempts + 1
            end
        else
            attempts = attempts + 1
        end
        
        sleep(0.1)
    end
    
    print("Failed to reach target after " .. maxAttempts .. " attempts")
    return false
end

-- Face a cardinal direction (north, south, east, west)
-- Uses GPS test movement to determine current facing, then turns
function faceDirection(direction)
    local currentFacing = detectFacing()
    if not currentFacing then
        print("Warning: Cannot determine facing")
        return false
    end
    
    -- Already facing the right direction?
    if currentFacing == direction then
        return true
    end
    
    -- Calculate and execute turns (positive = right, negative = left)
    local turns = calculateTurns(currentFacing, direction)
    
    if turns > 0 then
        -- Turn right
        for i = 1, turns do
            turtle.turnRight()
        end
    elseif turns < 0 then
        -- Turn left
        for i = 1, -turns do
            turtle.turnLeft()
        end
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
