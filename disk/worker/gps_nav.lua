-- GPS-based Navigation API
-- Provides simple navigation functions using absolute GPS coordinates
-- Uses dig.lua for all movement and direction tracking

os.loadAPI("dig.lua")

local startGPS = nil
local currentGPS = nil

-- Get GPS position with retries
local function getGPS(retries)
    retries = retries or 3
    for i = 1, retries do
        local x, y, z = gps.locate(5)
        if x then
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

-- Update current position from GPS
function updatePosition()
    local gps = getGPS(3)
    if gps then
        currentGPS = gps
    end
    return currentGPS
end

-- Get current GPS position
function getPosition()
    updatePosition()
    return {x = currentGPS.x, y = currentGPS.y, z = currentGPS.z}
end

-- Get starting GPS position
function getStart()
    return startGPS
end

-- Get the current GPS cardinal direction from dig.lua
function getCurrentDirection()
    return dig.getCardinalDir()
end

-- Movement functions using dig.lua's existing functions
function up()
    if dig.up() then
        currentGPS.y = currentGPS.y + 1
        return true
    end
    return false
end

function down()
    if dig.down() then
        currentGPS.y = currentGPS.y - 1
        return true
    end
    return false
end

-- Calculate turns needed between directions
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
    
    if rightTurns > 2 then
        return -(4 - rightTurns)
    else
        return rightTurns
    end
end

-- Turn to face a direction using dig.lua
local function turnToFace(currentFacing, targetFacing)
    local turns = calculateTurns(currentFacing, targetFacing)
    
    if turns > 0 then
        dig.right(turns)
    elseif turns < 0 then
        dig.left(-turns)
    end
    
    return targetFacing
end

-- Navigate to a GPS position
function goto(targetX, targetY, targetZ)
    if not targetX or not targetY or not targetZ then
        error("Invalid target coordinates")
    end
    
    print("GPS NAV: Going to (" .. targetX .. ", " .. targetY .. ", " .. targetZ .. ")")
    
    -- Get current facing from dig.lua (should be set by orchestration server)
    local facing = dig.getCardinalDir()
    if not facing then
        print("GPS NAV: Warning - Cardinal direction not set!")
        return false
    end
    
    -- Navigate Y first
    while currentGPS.y < targetY do
        if not up() then
            print("GPS NAV: Blocked going up")
            return false
        end
    end
    
    while currentGPS.y > targetY do
        if not down() then
            print("GPS NAV: Blocked going down")
            return false
        end
    end
    
    -- Navigate X and Z
    local maxAttempts = 500
    local attempts = 0
    
    while attempts < maxAttempts do
        local gps = getGPS(5)
        if not gps then
            print("GPS NAV: GPS unavailable")
            return false
        end
        currentGPS = gps
        
        local deltaX = targetX - currentGPS.x
        local deltaZ = targetZ - currentGPS.z
        
        -- Check if arrived
        if math.abs(deltaX) < 0.5 and math.abs(deltaZ) < 0.5 then
            print("GPS NAV: Arrived")
            return true
        end
        
        -- Determine direction to move
        local targetFacing = nil
        if math.abs(deltaX) >= math.abs(deltaZ) and math.abs(deltaX) >= 0.5 then
            targetFacing = (deltaX > 0) and "east" or "west"
        elseif math.abs(deltaZ) >= 0.5 then
            targetFacing = (deltaZ > 0) and "south" or "north"
        end
        
        if targetFacing then
            facing = turnToFace(facing, targetFacing)
            
            if not dig.fwd() then
                attempts = attempts + 1
            end
        else
            attempts = attempts + 1
        end
        
        sleep(0.1)
    end
    
    print("GPS NAV: Failed to reach target")
    return false
end

-- Face a cardinal direction
function faceDirection(direction)
    local currentFacing = dig.getCardinalDir()
    if not currentFacing then
        print("GPS NAV: Cardinal direction not set!")
        return false
    end
    
    if currentFacing == direction then
        return true
    end
    
    turnToFace(currentFacing, direction)
    return true
end

-- Return to starting position
function returnHome()
    if not startGPS then
        error("GPS navigation not initialized")
    end
    return goto(startGPS.x, startGPS.y, startGPS.z)
end
