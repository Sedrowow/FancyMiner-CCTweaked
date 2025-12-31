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
                    
                    -- Handle orientation: desired_facing indicates the cardinal we want turtle to face physically.
                    local facing = message.desired_facing or message.initial_direction
                    if facing then
                        -- Try GPS-based facing first if navigation API supports it
                        if gpsNav.faceDirection and gpsNav.faceDirection(facing) then
                            logger.log("Rotated to face " .. facing .. " via GPS navigation API")
                        else
                            -- Fallback heuristic rotations assuming initial placement may differ.
                            -- We attempt minimal rotations by cycling through left turns until dig.getCardinalDir()==facing
                            local attempts = 0
                            while dig.getCardinalDir() ~= facing and attempts < 4 do
                                dig.left(1)
                                attempts = attempts + 1
                            end
                            logger.log("Heuristic rotation applied; current facing=" .. tostring(dig.getCardinalDir()))
                        end
                        -- Set internal cardinal reference for dig API to desired facing for consistent zone math.
                        dig.setCardinalDir(facing)
                        logger.log("Cardinal direction initialized: " .. facing)
                    else
                        logger.warn("No facing information provided by server")
                    end
                    
                    -- Initialize GPS navigation
                    gpsNav.init()
                    
                    -- CRITICAL: Set dig.lua coordinates to match zone position
                    -- Workers are placed at their zone.xmin position in the dig.lua coordinate system
                    dig.setx(config.zone.xmin)
                    dig.sety(0)
                    dig.setz(0)
                    dig.setr(180)  -- Workers start with rotation=180
                    logger.log("Initialized dig.lua position: (" .. config.zone.xmin .. ", 0, 0, 180)")
                    
                    -- Save initial state
                    saveState()
                    
                    logger.log("Zone assignment received!")
                    logger.log("Zone: X=" .. config.zone.xmin .. "-" .. config.zone.xmax)
                    logger.log("Chest positions (GPS coords):")
                    logger.log("  Output: " .. gpsUtils.formatGPS(config.chestGPS.output))
                    logger.log("  Fuel: " .. gpsUtils.formatGPS(config.chestGPS.fuel))
                    
                    gotAssignment = true
                    os.cancelTimer(initTimeout)
                    
                    -- Send ready signal
                    modem.transmit(config.serverChannel, config.serverChannel, {
                        type = "worker_ready",
                        turtle_id = config.turtleID
                    })
                end
            end
        end
    end
    
    -- Wait for start signal
    logger.log("Waiting for start signal...")
    communication.waitForStartSignal(modem)
    logger.log("Start signal received!")
    config.miningStarted = true
    saveState()
    sendStatusUpdate("mining")
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
    
    -- Quarry mining function with serpentine pattern
    local function mineQuarry()
        -- Resume from last position if available
        local startY = dig.gety()
        local startZ = dig.getz()
        local startX = dig.getx()
        
        logger.log("Quarry loop starting from position: " .. startX .. "," .. startY .. "," .. startZ)
        
        local xStep = -1
        for y = 0, -depth, -1 do
            if config.aborted then return end
            -- Skip layers above where we left off
            if y > startY then
                -- Skip this layer entirely
            elseif y <= -skip then
                for z = 0, length - 1 do
                    if config.aborted then return end
                    -- Skip rows before where we left off on the current layer
                    if y == startY and z < startZ then
                        -- Track xStep direction for this row
                        xStep = -xStep
                    else
                        local xStart = (xStep == -1) and 0 or -(width - 1)
                        local xEnd = (xStep == -1) and -(width - 1) or 0
                        
                        for x = xStart, xEnd, xStep do
                            if config.aborted then return end
                            -- Skip blocks before where we left off in the current row
                            if y == startY and z == startZ then
                                if (xStep == -1 and x > startX) or (xStep == 1 and x < startX) then
                                    goto continue
                                end
                            end
                            
                            checkFuel()
                            checkInv()
                            if not config.aborted then
                                dig.goto(x, y, z, 0)
                            else
                                return
                            end
                            
                            dig.blockLavaUp()
                            dig.blockLava()
                            dig.blockLavaDown()
                            
                            if turtle.detectDown() then
                                -- Check if it's a turtle before digging
                                local success, data = turtle.inspectDown()
                                if not (success and data.name and data.name:match("^computercraft:turtle")) then
                                    turtle.digDown()
                                end
                            end
                            
                            dig.blockLavaDown()
                            
                            ::continue::
                        end
                        
                        xStep = -xStep  -- Flip direction for next row
                    end
                end
            end
        end
        
        if not config.aborted then
            dig.goto(0, 0, 0, 0)
        end
    end
    
    -- Run the actual quarry operation with abort handling
    local miningSuccess, miningError = pcall(function()
        parallel.waitForAny(
            mineQuarry,
            abortListener,
            statusUpdater
        )
    end)
    
    -- Check if abort was triggered (regardless of pcall success)
    if config.aborted then
        logger.log("Abort received - dumping inventory and returning to start...")
        sendStatusUpdate("aborting")
        
        -- Use queuedResourceAccess to dump inventory, returning to starting position
        pcall(function()
            queuedResourceAccess("output", config.startGPS)
        end)
        
        -- Send abort acknowledgment
        local gpsPos = gpsUtils.getGPS(3)
        communication.sendAbortAck(modem, config.serverChannel, config.turtleID, gpsPos)
        
        logger.log("Abort complete - standing by at start position")
        sendStatusUpdate("aborted")
        
        -- Wait indefinitely so deployer can collect this turtle
        while true do
            os.sleep(1)
        end
    end
    
    -- Handle other errors
    if not miningSuccess then
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