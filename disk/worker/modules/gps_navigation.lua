-- GPS Navigation Module
-- Consolidated GPS-based navigation using dig.lua for movement
-- Combines gps_nav.lua functionality with gps_utils helpers

os.loadAPI("dig.lua")

local gpsUtils = require("modules.gps_utils")

local M = {}

local startGPS = nil
local currentGPS = nil

-- Determine current cardinal direction by moving and checking GPS
local function calibrateDirection()
    local pos1 = gpsUtils.getGPS(5)
    if not pos1 then
        return nil
    end
    
    -- Try to move forward
    if not turtle.forward() then
        turtle.dig()
        if not turtle.forward() then
            return nil
        end
    end
    
    local pos2 = gpsUtils.getGPS(5)
    if not pos2 then
        turtle.back()
        return nil
    end
    
    -- Calculate direction based on position change
    local deltaX = pos2.x - pos1.x
    local deltaZ = pos2.z - pos1.z
    
    local direction = nil
    if math.abs(deltaX) > math.abs(deltaZ) then
        direction = (deltaX > 0) and "east" or "west"
    else
        direction = (deltaZ > 0) and "south" or "north"
    end
    
    turtle.back()
    return direction
end

-- Initialize the GPS navigation system
function M.init(calibrate)
    startGPS = gpsUtils.getGPS(5)
    if not startGPS then
        error("Failed to initialize GPS navigation - could not get GPS position")
    end
    currentGPS = gpsUtils.copy(startGPS)
    
    -- Calibrate direction if requested and not already set
    if calibrate and not dig.getCardinalDir() then
        local direction = calibrateDirection()
        if direction then
            dig.setCardinalDir(direction)
            print("GPS NAV: Calibrated direction to " .. direction)
        else
            print("GPS NAV: Warning - Could not calibrate direction")
        end
    end
    
    return startGPS
end

-- Update current position from GPS
function M.updatePosition()
    local gps = gpsUtils.getGPS(3)
    if gps then
        currentGPS = gps
    end
    return currentGPS
end

-- Get current GPS position
function M.getPosition()
    M.updatePosition()
    return gpsUtils.copy(currentGPS)
end

-- Get starting GPS position
function M.getStart()
    return gpsUtils.copy(startGPS)
end

-- Get current cardinal direction
function M.getCurrentDirection()
    return dig.getCardinalDir()
end

-- Movement functions using dig.lua
function M.up()
    if dig.up() then
        currentGPS.y = currentGPS.y + 1
        return true
    end
    return false
end

function M.down()
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

-- Turn to face a direction
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
function M.goto(targetX, targetY, targetZ)
    if not targetX or not targetY or not targetZ then
        error("Invalid target coordinates")
    end
    
    print("GPS NAV: Going to (" .. targetX .. ", " .. targetY .. ", " .. targetZ .. ")")
    
    -- Get current facing
    local facing = dig.getCardinalDir()
    if not facing then
        print("GPS NAV: Warning - Cardinal direction not set!")
        return false
    end
    
    -- Navigate Y first
    while currentGPS.y < targetY do
        if not M.up() then
            print("GPS NAV: Blocked going up")
            return false
        end
    end
    
    while currentGPS.y > targetY do
        if not M.down() then
            print("GPS NAV: Blocked going down")
            return false
        end
    end
    
    -- Navigate X and Z
    local maxAttempts = 500
    local attempts = 0
    
    while attempts < maxAttempts do
        local gps = gpsUtils.getGPS(5)
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
function M.faceDirection(direction)
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
function M.returnHome()
    if not startGPS then
        error("GPS navigation not initialized")
    end
    return M.goto(startGPS.x, startGPS.y, startGPS.z)
end

return M
