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

-- Internal helper to navigate to GPS position and restore direction
local function navigateAndRestoreDirection(gpsPos, cardinalDir, gpsNavAPI, digAPI, logger, fallbackDir)
    if not gpsPos then
        return false
    end
    
    logger.log("Navigating to position: " .. textutils.serialize(gpsPos))
    local navSuccess = gpsNavAPI.goto(gpsPos.x, gpsPos.y, gpsPos.z)
    
    if navSuccess then
        logger.log("Successfully navigated to position")
    else
        logger.warn("Failed to navigate to position")
        return false
    end
    
    -- Restore cardinal direction (with fallback)
    local dirToUse = cardinalDir or fallbackDir
    if dirToUse then
        logger.log("Turning to face direction: " .. dirToUse .. (cardinalDir and "" or " (fallback)"))
        
        if gpsNavAPI.faceDirection(dirToUse) then
            digAPI.setCardinalDir(dirToUse)
            logger.log("Direction set to: " .. dirToUse)
        else
            logger.warn("Failed to turn to direction")
            return false
        end
    end
    
    return true
end

-- Internal helper to restore dig coordinates
local function restoreDigCoordinates(digLocation, digAPI, logger, resetRotation)
    if not digLocation then
        return false
    end
    
    logger.log("Restoring dig coordinates: " .. textutils.serialize(digLocation))
    
    local loc = digLocation
    digAPI.setx(loc[1] or 0)
    digAPI.sety(loc[2] or 0)
    digAPI.setz(loc[3] or 0)
    digAPI.setr(resetRotation and 0 or (loc[4] or 0))
    if loc[15] then digAPI.setlast(loc[15]) end
    if loc[17] then digAPI.setBlocksProcessed(loc[17]) end
    
    logger.log("Dig coordinates set: " .. (loc[1] or 0) .. "," .. (loc[2] or 0) .. "," .. (loc[3] or 0) .. 
        " r=" .. (resetRotation and 0 or (loc[4] or 0)))
    
    return true
end

-- Internal helper to restore state with fallback support
local function restoreStateWithFallback(savedState, digAPI, gpsNavAPI, logger, fallbackDir)
    -- Check if turtle is in its assigned zone
    local currentGPS = gpsNavAPI.getPosition()
    if currentGPS and savedState.config and savedState.config.gps_zone then
        local zone = savedState.config.gps_zone
        local inZone = (currentGPS.x >= zone.gps_xmin and currentGPS.x <= zone.gps_xmax and
                        currentGPS.z >= zone.gps_zmin and currentGPS.z <= zone.gps_zmax)
        
        if not inZone then
            logger.warn("Turtle is outside assigned zone! Current: (" .. currentGPS.x .. "," .. currentGPS.z .. 
                       ") Zone: X[" .. zone.gps_xmin .. "-" .. zone.gps_xmax .. "] Z[" .. zone.gps_zmin .. "-" .. zone.gps_zmax .. "]")
            logger.log("Resetting to zone start position instead of resuming from saved location")
            
            -- Navigate to zone start (startGPS) and reset dig coordinates to 0,0,0
            if savedState.config.startGPS then
                gpsNavAPI.init(true)
                logger.log("Navigating back to zone start: (" .. 
                          savedState.config.startGPS.x .. "," .. 
                          savedState.config.startGPS.y .. "," .. 
                          savedState.config.startGPS.z .. ")")
                gpsNavAPI.gotoGPS(savedState.config.startGPS.x, savedState.config.startGPS.y, savedState.config.startGPS.z)
                
                -- Reset dig coordinates to zone origin
                digAPI.reset(0, 0, 0, 0)
                if savedState.config.desiredFacing then
                    digAPI.setCardinalDir(savedState.config.desiredFacing)
                    gpsNavAPI.faceDirection(savedState.config.desiredFacing)
                end
                logger.log("Position reset to zone start - ready to mine from beginning")
                return true
            end
        end
    end
    
    -- Re-initialize GPS navigation
    if savedState.config and savedState.config.startGPS then
        gpsNavAPI.init(true)
        logger.log("GPS initialized and calibrated - preserved start position: " .. 
            savedState.config.startGPS.x .. "," .. 
            savedState.config.startGPS.y .. "," .. 
            savedState.config.startGPS.z)
        logger.log("Current facing direction: " .. tostring(digAPI.getCardinalDir()))
    end
    
    -- Extract cardinal direction and rotation from digLocation array
    local loc = savedState.digLocation
    local cardinalDir = loc and loc[18]  -- Index 18 has cardinal direction
    local rotation = loc and loc[4]      -- Index 4 has rotation
    
    -- Check if we have full state or need to use fallback
    local useFallback = not cardinalDir or not rotation
    if useFallback then
        logger.warn("State missing cardinal direction or rotation - using fallback values")
    end
    
    -- Navigate to last GPS position and restore direction
    navigateAndRestoreDirection(
        savedState.lastGPS,
        cardinalDir,
        gpsNavAPI,
        digAPI,
        logger,
        fallbackDir
    )
    
    -- Restore dig coordinates (reset rotation to 0 if using fallback)
    restoreDigCoordinates(loc, digAPI, logger, useFallback)
    
    return true
end

-- Restore worker position and state from saved data
function M.restore(savedState, digAPI, gpsNavAPI, logger)
    if not savedState then
        return false, "No saved state provided"
    end
    
    return restoreStateWithFallback(savedState, digAPI, gpsNavAPI, logger, nil)
end

-- Try to resume job from server state or request new assignment
function M.tryResumeFromServer(modem, config, digAPI, gpsNavAPI, logger, communication, gpsUtils, saveStateFn)
    -- Check if we have an existing job on the server (even without local state file)
    logger.log("Checking for existing job on server...")
    local jobStatus = communication.checkJobStatusDetailed(modem, config.serverChannel, config.turtleID, 10)
    
    if jobStatus and jobStatus.job_active and jobStatus.last_state then
        logger.log("Found active job on server - resuming from last known state")
        
        -- Restore config from server
        config.zone = jobStatus.last_state.zone
        config.gps_zone = jobStatus.last_state.gps_zone
        config.chestGPS = jobStatus.last_state.chestGPS
        config.isCoordinated = true
        config.startGPS = jobStatus.last_state.startGPS
        
        -- Convert server state to savedState format and restore with fallback
        local savedState = {
            config = config,
            digLocation = jobStatus.last_state.digLocation,
            lastGPS = jobStatus.last_state.lastGPS
        }
        
        local fallbackDir = config.gps_zone and config.gps_zone.initial_direction
        restoreStateWithFallback(savedState, digAPI, gpsNavAPI, logger, fallbackDir)
        
        -- Save state locally
        saveStateFn()
        
        logger.log("Job resumed from server state")
        config.miningStarted = true
        return true  -- Got assignment from server resume
    else
        logger.log("No existing job found - requesting new assignment")
        
        -- Get GPS position and notify server we're ready for assignment
        local currentGPS = gpsUtils.getGPS(5)
        if not currentGPS then
            error("Failed to get GPS position for zone matching")
        end
        
        logger.log("Notifying server we're ready for assignment...")
        communication.sendReadyForAssignment(modem, config.serverChannel, config.turtleID, currentGPS)
        return false  -- Need to wait for zone assignment
    end
end

return M
