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

-- Load state from disk and verify job status with server
local function loadState()
    local savedState = stateModule.load(config.turtleID)
    
    if not savedState then
        return false
    end
    
    config = savedState.config
    
    -- If coordinated worker, check if job is still active
    if config.isCoordinated and config.zone and config.serverChannel then
        logger.log("Checking job status with server...")
        
        local modem = peripheral.find("modem")
        if not modem then
            logger.error("No modem found")
            return false
        end
        
        if not modem.isOpen(config.serverChannel) then
            modem.open(config.serverChannel)
        end
        
        -- Check job status
        local jobActive = communication.checkJobStatus(modem, config.serverChannel, config.turtleID, 30)
        
        if jobActive then
            logger.log("Job is active - restoring state")
            
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
            return false
        end
    end
    
    return true
end

local modem, err = communication.initModem()
if not modem then
    error(err)
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
        {x = dig.getx(), y = dig.gety(), z = dig.getz()},
        gpsPos,
        turtle.getFuelLevel()
    )
end

-- Coordinated resource access wrapper
local function queuedResourceAccess(resourceType, returnPos)
    sendStatusUpdate("queued")
    resourceMgr.accessResource(resourceType, returnPos, modem, config.serverChannel,
        config.turtleID, config, dig, gpsNav, logger)
    sendStatusUpdate("mining")
end

-- Initialize worker - receive firmware and zone assignment
local function initializeWorker()
    logger.section("Worker Initialization")
    
    -- Check if we're restarting from previous state
    -- loadState() handles job verification and position restoration
    if loadState() then
        logger.log("State restored - ready to continue mining")
        
        -- Send ready signal to server so it knows we're back online
        local modem = peripheral.find("modem")
        if modem and config.serverChannel then
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
        
        return -- Skip initialization, go straight to mining
    end
    
    logger.log("Starting fresh initialization...")
    logger.log("Waiting for zone assignment...")
    
    modem.open(config.broadcastChannel)
    
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
    
    modem.open(config.serverChannel)
    logger.log("Listening on server channel: " .. config.serverChannel)
    
    -- Get GPS position and notify server we're ready for assignment
    local currentGPS = gpsUtils.getGPS(5)
    if not currentGPS then
        error("Failed to get GPS position for zone matching")
    end
    
    logger.log("Notifying server we're ready for assignment...")
    communication.sendReadyForAssignment(modem, config.serverChannel, config.turtleID, currentGPS)
    
    -- Wait for zone assignment
    local initTimeout = os.startTimer(120)
    local gotAssignment = false
    
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
                    
                    -- Set initial cardinal direction from server
                    if message.initial_direction then
                        dig.setCardinalDir(message.initial_direction)
                        logger.log("Initial direction set to: " .. message.initial_direction)
                    else
                        logger.warn("No initial direction provided by server")
                    end
                    
                    -- Initialize GPS navigation
                    gpsNav.init()
                    
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
        -- Check for abort command (non-blocking)
        if config.isCoordinated and config.aborted then
            error("Operation aborted by server")
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
    
    -- Quarry mining function with serpentine pattern
    local function mineQuarry()
        local xStep = -1
        for y = 0, -depth, -1 do
            if y <= -skip then
                for z = 0, length - 1 do
                    local xStart = (xStep == -1) and 0 or -(width - 1)
                    local xEnd = (xStep == -1) and -(width - 1) or 0
                    
                    for x = xStart, xEnd, xStep do
                        checkFuel()
                        checkInv()
                        dig.goto(x, y, z, 0)
                        
                        dig.blockLavaUp()
                        dig.blockLava()
                        dig.blockLavaDown()
                        
                        if turtle.detectDown() then
                            turtle.digDown()
                        end
                        
                        dig.blockLavaDown()
                    end
                    
                    xStep = -xStep  -- Flip direction for next row
                end
            end
        end
        
        dig.goto(0, 0, 0, 0)
    end
    
    -- Run the actual quarry operation with abort handling
    local miningSuccess, miningError = pcall(function()
        parallel.waitForAny(
            mineQuarry,
            abortListener
        )
    end)
    
    -- Handle abort
    if not miningSuccess and config.aborted then
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