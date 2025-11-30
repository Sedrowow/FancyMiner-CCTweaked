-- Worker Turtle for Multi-Turtle Coordinated Quarry System
-- GPS-aware mining with resource queue management
-- Receives zone assignments from orchestration server

os.loadAPI("dig.lua")
os.loadAPI("flex.lua")

-- Load modules
local logger = require("modules.logger")
local gpsUtils = require("modules.gps_utils")
local gpsNav = require("modules.gps_navigation")
local stateModule = require("modules.state")
local communication = require("modules.communication")
local resourceMgr = require("modules.resource_manager")

-- Worker configuration
local config = {
    turtleID = os.getComputerID(),
    serverChannel = nil,
    broadcastChannel = 65535,
    zone = nil,
    gps_zone = nil,
    chestGPS = {
        fuel = nil,
        output = nil
    },
    isCoordinated = false,
    startGPS = nil,
    aborted = false,
    miningStarted = false
}

-- Initialize logger
logger.init(config.turtleID)
logger.section("Worker Turtle Started")

-- Save state to disk
local function saveState()
    stateModule.save(config.turtleID, config, dig, gpsNav)
end

-- Initialize modem early so it's available for all operations
local modem, err = communication.initModem()
if not modem then
    error(err)
end

-- Try to resume from saved state or server state
local function tryResumeJob()
    -- First try local state file
    local savedState = stateModule.load(config.turtleID)
    
    if savedState then
        config = savedState.config
        
        -- If coordinated worker, check if job is still active
        if config.isCoordinated and config.zone and config.serverChannel then
            logger.log("Checking job status with server...")
            
            -- Check job status
            local jobActive = communication.checkJobStatus(modem, config.serverChannel, config.turtleID, 30)
            
            if jobActive then
                logger.log("Job is active - restoring from local state")
                
                -- Restore position and state
                local success, err = stateModule.restore(savedState, dig, gpsNav, logger)
                if not success then
                    logger.error("Failed to restore state: " .. tostring(err))
                    return false
                end
                
                return true
            else
                logger.log("No active job - clearing saved state")
                stateModule.clear(config.turtleID)
            end
        end
    end
    
    -- No local state or job inactive - try to resume from server state
    if config.serverChannel then
        logger.log("No local state - checking server for active job...")
        return stateModule.tryResumeFromServer(
            modem, config, dig, gpsNav, logger, communication, gpsUtils, saveState
        )
    end
    
    return false
end

logger.log("Worker Turtle ID: " .. config.turtleID)

-- Send status update to server
local function sendStatusUpdate(status)
    if not config.isCoordinated or not config.serverChannel then
        return
    end
    
    local gpsPos = gpsNav.getPosition()
    
    communication.sendStatusUpdate(modem, config.serverChannel, config.turtleID,
        status or "mining",
        dig.location(),  -- Send full location array including r and cardinalDir
        gpsPos,
        turtle.getFuelLevel()
    )
end

-- Coordinated resource access wrapper
local function queuedResourceAccess(resourceType, returnPos)
    sendStatusUpdate("queued")
    local ok, err = pcall(function()
        resourceMgr.accessResource(resourceType, returnPos, modem, config.serverChannel,
            config.turtleID, config, dig, gpsNav, logger)
    end)
    if not ok then
        logger.warn("Resource access error: " .. tostring(err))
    end
    if not config.aborted then
        sendStatusUpdate("mining")
    else
        sendStatusUpdate("aborted")
    end
end

-- Initialize worker - receive firmware and zone assignment
local function initializeWorker()
    logger.section("Worker Initialization")
    
    -- Read server channel from file saved by bootstrap
    if not fs.exists("server_channel.txt") then
        error("Server channel file not found! Worker must be initialized by bootstrap.")
    end
    
    local file = fs.open("server_channel.txt", "r")
    config.serverChannel = tonumber(file.readLine())
    file.close()
    
    if not config.serverChannel then
        error("Invalid server channel")
    end
    
    -- Open channels on modem
    communication.initModem(config.serverChannel)
    logger.log("Listening on server channel: " .. config.serverChannel)
    
    -- Try to resume from local state file or server state
    local gotAssignment = tryResumeJob()
    
    if gotAssignment then
        logger.log("Job resumed - ready to continue mining")
        
        -- Send ready signal to server so it knows we're back online
        if config.serverChannel then
            modem.transmit(config.serverChannel, config.serverChannel, {
                type = "worker_ready",
                turtle_id = config.turtleID
            })
        end
        
        -- Wait for start signal
        logger.log("Waiting for start signal...")
        while true do
            local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if type(message) == "table" and message.type == "start_mining" then
                logger.log("Start signal received!")
                config.miningStarted = true
                saveState()
                sendStatusUpdate("mining")
                break
            end
        end
        
        return -- Skip zone assignment, go straight to mining
    end
    
    logger.log("No existing job - waiting for zone assignment...")
    local initTimeout = os.startTimer(120)
    
    while not gotAssignment do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == initTimeout then
            error("Timeout waiting for zone assignment")
        elseif event == "modem_message" then
            local side, channel, replyChannel, message = p1, p2, p3, p4
            if type(message) == "table" then
                if message.type == "zone_assignment" and message.turtle_id == config.turtleID then
                    -- This zone assignment is for us!
                    local verifyGPS = gpsUtils.getGPS(5)
                    if not verifyGPS then
                        logger.warn("Could not verify GPS position")
                        verifyGPS = {x = 0, y = 0, z = 0}
                    end
                    
                    config.zone = message.zone
                    config.gps_zone = message.gps_zone
                    config.chestGPS = message.chest_gps
                    config.isCoordinated = true
                    config.startGPS = verifyGPS
                    
                    -- Initialize GPS navigation with calibration so we know true facing
                    gpsNav.init(true)

                    -- Calibrate actual physical facing by short forward/back probe
                    logger.log("Starting GPS facing probe...")
                    local function probeFacing()
                        local pos1 = gpsUtils.getGPS(4)
                        if not pos1 then 
                            logger.warn("Probe: Could not get initial GPS position")
                            return 
                        end
                        local moved, turns = false, 0
                        -- Try up to 4 orientations to find a free forward move

                        local triedDirs = {}
                        for i=1,4 do
                            local dir = ({"front","right","back","left"})[i]
                            table.insert(triedDirs, dir)
                            if turtle.forward() then
                                moved = true
                                logger.log("Probe: moved forward in direction " .. dir)
                                break
                            else
                                if turtle.dig() then
                                    sleep(0.2)
                                end
                                if turtle.forward() then
                                    moved = true
                                    logger.log("Probe: dug and moved forward in direction " .. dir)
                                    break
                                end
                                turtle.turnRight(); turns = turns + 1
                            end
                        end
                        if not moved then
                            logger.warn("Probe: could not move in any direction (tried: " .. table.concat(triedDirs,", ") .. ") - forcing forward dig/move")
                            if turtle.dig() then sleep(0.2) end
                            if turtle.forward() then
                                moved = true
                                logger.log("Probe: forcibly moved forward after digging")
                            else
                                logger.error("Probe: all movement attempts failed, facing detection skipped")
                                return
                            end
                        end
                        if moved then sleep(0.3) end
                        local pos2 = gpsUtils.getGPS(4)
                        if moved then 
                            turtle.back() 
                            sleep(0.2) 
                        end
                        -- Restore original rotation
                        for i=1,turns do turtle.turnLeft() end

                        if not (pos1 and pos2) then 
                            logger.warn("Probe: Could not get GPS positions for comparison")
                            return 
                        end
                        local dx = pos2.x - pos1.x
                        local dz = pos2.z - pos1.z
                        logger.log("Probe: GPS delta - dx=" .. dx .. ", dz=" .. dz)
                        if math.abs(dx) < 0.4 and math.abs(dz) < 0.4 then
                            logger.warn("Probe could not detect movement; keeping previous facing")
                            return
                        end
                        local dir
                        if math.abs(dx) > math.abs(dz) then
                            dir = (dx > 0) and "east" or "west"
                        else
                            dir = (dz > 0) and "south" or "north"
                        end
                        if dir then
                            dig.setCardinalDir(dir)
                            logger.log("Probe determined current facing: " .. dir)
                        end
                    end
                    if not dig.getCardinalDir() then 
                        probeFacing() 
                        logger.log("GPS facing probe completed")
                    else
                        logger.log("Skipping GPS probe - cardinal direction already set")
                    end

                    -- Handle orientation: desired_facing indicates the cardinal we want turtle to face physically.
                    logger.log("Starting orientation calibration...")
                    local facing = message.desired_facing or message.initial_direction
                    if facing then
                        logger.log("Desired facing: " .. tostring(facing))
                        -- Ensure cardinalDir is set (calibrated) and rotate to target via GPS-aware turns
                        local usedGPS = false
                        if gpsNav.faceDirection then
                            logger.log("Attempting GPS-based rotation to " .. facing)
                            local success = gpsNav.faceDirection(facing)
                            if success then
                                usedGPS = true
                                logger.log("Facing set to " .. facing .. " using GPS navigation")
                            else
                                logger.warn("GPS rotation failed, will use manual correction")
                            end
                        else
                            logger.warn("gpsNav.faceDirection not available")
                        end

                        -- Verify and correct if mismatch
                        local current = dig.getCardinalDir()
                        logger.log("Current cardinal direction: " .. tostring(current))
                        if not current then
                            -- Fallback: assume desired_facing if probe failed
                            dig.setCardinalDir(facing)
                            current = facing
                            logger.log("Fallback: assuming desired facing due to probe failure")
                        end
                        if current ~= facing then
                            logger.log("Correcting facing from " .. current .. " to " .. facing)
                            local order = {north=1,east=2,south=3,west=4}
                            local ci, ti = order[current], order[facing]
                            if ci and ti then
                                local diff = (ti - ci) % 4
                                if diff == 1 then dig.right(1)
                                elseif diff == 2 then dig.right(2)
                                elseif diff == 3 then dig.left(1)
                                end
                                current = dig.getCardinalDir()
                            else
                                -- Absolute last resort: spin until success
                                logger.warn("Manual rotation correction needed")
                                for _=1,4 do if dig.getCardinalDir()==facing then break end dig.left(1) end
                                current = dig.getCardinalDir()
                            end
                            logger.log("Post-correction facing (gps=" .. tostring(usedGPS) .. ") now=" .. tostring(current))
                        else
                            logger.log("Facing already correct: " .. facing)
                        end
                        logger.log("Orientation calibration complete!")
                    else
                        logger.warn("No facing information provided by server")
                    end
                    
                    -- Save initial state
                    saveState()
                    
                    logger.log("Zone assignment received!")
                    logger.log("Zone: X=" .. config.zone.xmin .. "-" .. config.zone.xmax)
                    logger.log("Chest positions (GPS coords):")
                    logger.log("  Output: " .. gpsUtils.formatGPS(config.chestGPS.output))
                    logger.log("  Fuel: " .. gpsUtils.formatGPS(config.chestGPS.fuel))
                    
                    -- Store desired facing for later use
                    config.desiredFacing = facing or message.initial_direction or "east"
                    
                    gotAssignment = true
                    os.cancelTimer(initTimeout)
                    
                    -- Send ready signal to server
                    logger.log("Sending worker_ready signal to server on channel " .. config.serverChannel)
                    logger.log("Modem available: " .. tostring(modem ~= nil))
                    if modem then
                        modem.transmit(config.serverChannel, config.serverChannel, {
                            type = "worker_ready",
                            turtle_id = config.turtleID
                        })
                        logger.log("worker_ready signal transmitted successfully!")
                    else
                        logger.error("ERROR: Modem is nil, cannot send ready signal!")
                    end
                    sleep(0.1)  -- Brief delay to ensure message transmission
                end
            end
        end
    end
    
    -- Wait for start signal with periodic ready signal resend
    logger.log("Waiting for start signal...")
    local readyResendTimer = os.startTimer(5)  -- Resend every 5 seconds
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == readyResendTimer then
            -- Resend ready signal in case it was missed
            logger.log("Resending worker_ready signal...")
            if modem then
                modem.transmit(config.serverChannel, config.serverChannel, {
                    type = "worker_ready",
                    turtle_id = config.turtleID
                })
            end
            readyResendTimer = os.startTimer(5)
            
        elseif event == "modem_message" then
            local side, channel, replyChannel, message = p1, p2, p3, p4
            if type(message) == "table" and message.type == "start_mining" then
                logger.log("Start signal received!")
                os.cancelTimer(readyResendTimer)
                config.miningStarted = true
                saveState()
                sendStatusUpdate("mining")
                break
            end
        end
    end
end

-- Modified inventory check for coordinated mode
local function checkInv()
    if turtle.getItemCount(16) > 0 then
        if turtle.getItemCount(14) > 0 then
            queuedResourceAccess("output")
        end
    end
end

-- Fuel check for coordinated mode
local fuelThreshold = 1000

local function checkFuel()
    local current = turtle.getFuelLevel()
    
    if current < fuelThreshold then
        turtle.select(1)
        if turtle.getItemCount(1) > 1 and turtle.refuel(0) then
            logger.log("Using reserve fuel from slot 1...")
            while turtle.getFuelLevel() < fuelThreshold and turtle.getItemCount(1) > 1 do
                turtle.refuel(1)
            end
            logger.log("Refueled from reserve to " .. turtle.getFuelLevel() .. 
                ", " .. turtle.getItemCount(1) .. " items remain")
        end
        
        if turtle.getFuelLevel() < fuelThreshold then
            flex.send("Fuel low (" .. current .. "/" .. fuelThreshold .. 
                "), requesting access...", colors.yellow)
            queuedResourceAccess("fuel")
        end
    end
end



-- Main execution
initializeWorker()

if config.isCoordinated then
    -- Calculate fuel threshold based on zone dimensions
    fuelThreshold = resourceMgr.calculateFuelThreshold(config, logger)
    
    -- Override dig functions to use queued resource access
    local oldDropNotFuel = dig.dropNotFuel
    dig.dropNotFuel = function()
        queuedResourceAccess("output")
    end
    
    -- Set up dig API for zone-constrained mining
    dig.setFuelSlot(1)
    dig.setBlockSlot(2)
    dig.doBlacklist()
    dig.doAttack()
    
    -- Run quarry with zone constraints
    logger.section("Starting Zone Mining")
    local width = config.zone.xmax - config.zone.xmin + 1
    local length = config.zone.zmax - config.zone.zmin + 1
    local depth = math.abs(config.zone.ymin)
    local skip = config.zone.skip or 0
    
    logger.log("Zone dimensions: " .. width .. "x" .. length .. "x" .. depth)
    
    -- Set up periodic status updates and abort checking
    local lastStatusUpdate = os.clock()
    local statusUpdateInterval = 10 -- Send status every 10 seconds
    
    -- Wrap dig functions to include periodic status updates, fuel checks, and abort checks
    local originalFwd = dig.fwd
    local lastStateSave = os.clock()
    local stateSaveInterval = 30 -- Save state every 30 seconds
    
    dig.fwd = function()
        -- Graceful abort: just stop further movement without throwing
        if config.isCoordinated and config.aborted then
            return false
        end
        
        -- Check fuel level before moving
        checkFuel()
        
        local result = originalFwd()
        
        -- Send periodic status update
        if os.clock() - lastStatusUpdate > statusUpdateInterval then
            sendStatusUpdate("mining")
            lastStatusUpdate = os.clock()
        end
        
        -- Save state periodically
        if os.clock() - lastStateSave > stateSaveInterval then
            saveState()
            lastStateSave = os.clock()
        end
        
        return result
    end
    
    -- Set up parallel task to listen for abort
    local function abortListener()
        while not config.aborted do
            local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
            if type(message) == "table" and message.type == "abort_mining" then
                config.aborted = true
                logger.section("ABORT RECEIVED")
                break
            end
        end
    end
    
    -- Periodic status updater task
    local function statusUpdater()
        while not config.aborted do
            os.sleep(statusUpdateInterval)
            sendStatusUpdate("mining")
        end
    end
    
    -- Serpentine mining function: forward = zone length (z), lateral = zone width (x)
    local function mineQuarry()
        local zmin, zmax = config.zone.zmin, config.zone.zmax
        local xmin, xmax = config.zone.xmin, config.zone.xmax
        local length = (zmax - zmin + 1)   -- forward distance per row
        local width = (xmax - xmin + 1)    -- number of columns to traverse
        local forward = config.desiredFacing or "east"
        
        -- Helper functions for movement
        local function face(dir)
            if gpsNav.faceDirection then 
                gpsNav.faceDirection(dir) 
            else
                local order = {north=1,east=2,south=3,west=4}
                local ci, ti = order[dig.getCardinalDir() or dir], order[dir]
                if ci and ti then
                    local diff = (ti - ci) % 4
                    if diff == 1 then dig.right(1) 
                    elseif diff == 2 then dig.right(2) 
                    elseif diff == 3 then dig.left(1) 
                    end
                end
            end
            dig.setCardinalDir(dir)
        end

        local function stepForward()
            if config.aborted then return false end
            checkFuel()
            checkInv()
            if not turtle.forward() then 
                turtle.dig()
                if not turtle.forward() then return false end
            end
            return true
        end
        
        local function stepBack()
            if config.aborted then return false end
            if not turtle.back() then 
                dig.right(2)
                if not stepForward() then 
                    dig.right(2)
                    return false
                end
                dig.right(2) 
            end
            return true
        end
        
        local function lateralStep(side)
            if config.aborted then return false end
            if side == "left" then 
                dig.left(1)
                if not stepForward() then 
                    dig.right(1)
                    return false
                end
                dig.right(1) 
            else 
                dig.right(1)
                if not stepForward() then 
                    dig.left(1)
                    return false
                end
                dig.left(1) 
            end
            return true
        end
        
        face(forward)
        local depth = math.abs(config.zone.ymin)
        local skip = config.zone.skip or 0
        logger.log("Starting zone mine: " .. width .. " columns x " .. length .. " length x " .. depth .. " depth, facing " .. forward)
        
        -- Use dig.select() to mine the zone with proper depth handling
        dig.select(
            config.zone.xmin,
            config.zone.ymin,
            config.zone.zmin,
            width,
            length,
            depth,
            skip
        )
        
        logger.log("Mining complete!")
    end
    
    -- Run the actual quarry operation with abort handling
    local miningSuccess, miningError = pcall(function()
        parallel.waitForAny(
            mineQuarry,
            abortListener,
            statusUpdater
        )
    end)
    
    -- Handle abort (check config.aborted regardless of miningSuccess)
    if config.aborted then
        logger.log("Abort received - dumping inventory and returning to start...")
        sendStatusUpdate("aborting")
        
        -- Use queuedResourceAccess to dump inventory, returning to starting position
        queuedResourceAccess("output", config.startGPS)
        
        -- Send abort acknowledgment
        local gpsPos = gpsUtils.getGPS(3)
        communication.sendAbortAck(modem, config.serverChannel, config.turtleID, gpsPos)
        
        logger.log("Abort complete - standing by")
        sendStatusUpdate("aborted")
        return
    elseif not miningSuccess then
        error(miningError)
    end
    
else
    -- Run as standalone (not coordinated)
    logger.log("Running in standalone mode")
    logger.log("To use coordinated mode, deploy via orchestrate_deploy.lua")
end

-- Completion sequence
if config.isCoordinated then
    logger.section("Zone Mining Complete")
    
    -- Dump inventory and return to starting position in one operation
    queuedResourceAccess("output", config.startGPS)
    
    -- Send completion message
    sendStatusUpdate("complete")
    local gpsPos = gpsUtils.getGPS(3)
    communication.sendZoneComplete(modem, config.serverChannel, config.turtleID, gpsPos)
    
    -- Clean up state file since we're done
    stateModule.clear(config.turtleID)
    
    logger.log("Completion reported to server")
    logger.log("Worker standing by...")
end