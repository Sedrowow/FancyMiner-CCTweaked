-- State Management for Worker Turtles
-- Handles saving and loading worker state for recovery after restart

local M = {}

-- Create state file name for a turtle
local function getStateFile(turtleID)
    return "quarry_state_" .. turtleID .. ".cfg"
end

-- Save worker state to disk
function M.save(turtleID, state, digAPI, gpsNavAPI)
    local stateFile = getStateFile(turtleID)
    
    local saveData = {
        config = state,
        digLocation = digAPI.location(),
        lastGPS = gpsNavAPI.getPosition(),
        lastCardinalDir = digAPI.getCardinalDir()
    }
    
    local file = fs.open(stateFile, "w")
    if not file then
        return false, "Failed to open state file for writing"
    end
    
    file.write(textutils.serialize(saveData))
    file.close()
    return true
end

-- Load worker state from disk
function M.load(turtleID)
    local stateFile = getStateFile(turtleID)
    
    if not fs.exists(stateFile) then
        return nil
    end
    
    local file = fs.open(stateFile, "r")
    if not file then
        return nil, "Failed to open state file for reading"
    end
    
    local data = file.readAll()
    file.close()
    
    local state = textutils.unserialize(data)
    return state
end

-- Delete state file
function M.clear(turtleID)
    local stateFile = getStateFile(turtleID)
    if fs.exists(stateFile) then
        fs.delete(stateFile)
        return true
    end
    return false
end

-- Check if state file exists
function M.exists(turtleID)
    return fs.exists(getStateFile(turtleID))
end

-- Restore worker position and state from saved data
function M.restore(savedState, digAPI, gpsNavAPI, logger)
    if not savedState then
        return false, "No saved state provided"
    end
    
    -- Re-initialize GPS navigation and calibrate current facing direction
    if savedState.config and savedState.config.startGPS then
        gpsNavAPI.init(true)
        logger.log("GPS initialized and calibrated - preserved start position: " .. 
            savedState.config.startGPS.x .. "," .. 
            savedState.config.startGPS.y .. "," .. 
            savedState.config.startGPS.z)
        logger.log("Current facing direction: " .. tostring(digAPI.getCardinalDir()))
    end
    
    -- Navigate to last GPS position first
    if savedState.lastGPS then
        logger.log("Navigating to last GPS position: " .. 
            textutils.serialize(savedState.lastGPS))
        
        local navSuccess = gpsNavAPI.goto(
            savedState.lastGPS.x,
            savedState.lastGPS.y,
            savedState.lastGPS.z
        )
        
        if navSuccess then
            logger.log("Successfully navigated to last position")
        else
            logger.warn("Failed to navigate to last GPS position")
        end
        
        -- Restore cardinal direction
        if savedState.lastCardinalDir then
            logger.log("Turning to face saved direction: " .. savedState.lastCardinalDir)
            
            if gpsNavAPI.faceDirection(savedState.lastCardinalDir) then
                logger.log("Direction restored to: " .. savedState.lastCardinalDir)
            else
                logger.warn("Failed to turn to saved direction")
            end
        end
    end
    
    -- Load dig.lua position
    if savedState.digLocation then
        logger.log("Loading dig coordinate system: " .. 
            textutils.serialize(savedState.digLocation))
        
        local loc = savedState.digLocation
        digAPI.setx(loc[1])
        digAPI.sety(loc[2])
        digAPI.setz(loc[3])
        digAPI.setr(loc[4])
        if loc[15] then digAPI.setlast(loc[15]) end
        if loc[17] then digAPI.setBlocksProcessedTotal(loc[17]) end
    end
    
    return true
end

return M
