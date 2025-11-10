-- Worker Turtle for Multi-Turtle Coordinated Quarry System
-- GPS-aware mining with resource queue management
-- Receives zone assignments from orchestration server

os.loadAPI("dig.lua")
os.loadAPI("flex.lua")
os.loadAPI("gps_nav.lua")

-- Worker configuration
local STATE_FILE = "quarry_state_" .. os.getComputerID() .. ".cfg"

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

-- Save state to disk
local function saveState()
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialize({
        config = config,
        digLocation = dig.location()
    }))
    file.close()
end

-- Load state from disk
local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        local data = file.readAll()
        file.close()
        local state = textutils.unserialize(data)
        if state then
            config = state.config
            if state.digLocation then
                dig.goto(state.digLocation)
            end
            return true
        end
    end
    return false
end

-- Persistent logging function
local logFile = "worker_" .. os.getComputerID() .. ".log"
local function log(message)
    -- Print to screen (use write/print directly, not log)
    print(message)
    
    -- Append to log file
    local file = fs.open(logFile, "a")
    if file then
        file.writeLine("[" .. os.date("%H:%M:%S") .. "] " .. tostring(message))
        file.close()
    end
end

-- Clear old log on startup
if fs.exists(logFile) then
    fs.delete(logFile)
end
log("=== Worker Turtle Started ===")

local modem = peripheral.find("ender_modem")
if not modem then
    modem = peripheral.find("modem")
end

if not modem then
    error("No modem found! Worker requires an ender modem.")
end

log("Worker Turtle ID: " .. config.turtleID)

-- GPS functions
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

-- Zone validation removed - GPS navigation inherently bounds movement to zone

-- Send status update to server
local function sendStatusUpdate(status)
    if not config.isCoordinated or not config.serverChannel then
        return
    end
    
    modem.transmit(config.serverChannel, config.serverChannel, {
        type = "status_update",
        turtle_id = config.turtleID,
        status = status or "mining",
        position = {
            x = dig.getx(),
            y = dig.gety(),
            z = dig.getz()
        },
        fuel = turtle.getFuelLevel()
    })
end

-- Resource access functions
local function requestResourceAccess(resourceType)
    if not config.isCoordinated then
        return true -- Not in coordinated mode
    end
    
    log("Requesting " .. resourceType .. " access...")
    
    sendStatusUpdate("queued")
    
    -- Send request to server
    modem.transmit(config.serverChannel, config.serverChannel, {
        type = "resource_request",
        turtle_id = config.turtleID,
        resource = resourceType
    })
    
    -- Wait for grant
    local timeout = os.startTimer(300) -- 5 minute timeout
    local granted = false
    local chestPos = nil
    local approachDir = nil
    
    while not granted do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == timeout then
            log("Timeout waiting for " .. resourceType .. " access")
            return false
        elseif event == "modem_message" then
            local side, channel, replyChannel, message, distance = p1, p2, p3, p4, p5
            if type(message) == "table" then
                if message.type == "resource_granted" and 
                   message.turtle_id == config.turtleID and
                   message.resource == resourceType then
                    granted = true
                    chestPos = message.chest_gps
                    approachDir = message.approach_direction
                    os.cancelTimer(timeout)
                elseif message.type == "queue_position" and
                       message.turtle_id == config.turtleID then
                    log("Queue position: " .. message.position)
                end
            end
        end
    end
    
    return true, chestPos, approachDir
end

local function releaseResource(resourceType)
    if not config.isCoordinated then
        return
    end
    
    modem.transmit(config.serverChannel, config.serverChannel, {
        type = "resource_released",
        turtle_id = config.turtleID,
        resource = resourceType
    })
    
    log("Released " .. resourceType .. " access")
end

-- Coordinated resource operations
-- Optional returnPos parameter allows specifying a GPS position to return to after resource access
-- If nil, returns to the saved position (current position before accessing resource)
local function queuedResourceAccess(resourceType, returnPos)
    if not config.isCoordinated then
        -- Fall back to normal operation
        if resourceType == "output" then
            dig.dropNotFuel()
        elseif resourceType == "fuel" then
            dig.refuel(1000)
        end
        return
    end
    
    -- Save current position AND direction
    local savedPos = gps_nav.getPosition()
    local savedRotation = dig.getr()
    local savedDirection = dig.getCardinalDir()
    
    -- Use custom return position if provided, otherwise use saved position
    local targetReturnPos = returnPos or savedPos
    
    log("Saving position: " .. textutils.serialize(savedPos) .. 
          " dig.lua rotation=" .. savedRotation .. 
          " direction=" .. tostring(savedDirection))
    
    if returnPos then
        log("Will return to custom position: " .. textutils.serialize(returnPos))
    end
    
    -- Request access
    local success, chestPos, approachDir = requestResourceAccess(resourceType)
    if not success then
        log("Failed to get " .. resourceType .. " access")
        return
    end
    
    log("Access granted, navigating to chest...")
    
    -- Navigate to position below the chest using GPS coordinates
    -- Chests are accessed from one block below to use turtle.suckUp/dropUp
    local chestGPS = config.chestGPS[resourceType]
    if not chestGPS then
        log("Error: Unknown resource type " .. resourceType)
        releaseResource(resourceType)
        return
    end
    
    -- Navigate to position below the chest
    gps_nav.goto(chestGPS.x, chestGPS.y - 1, chestGPS.z)
    
    -- Perform operation
    if resourceType == "output" then
        -- Output chest is above at Y=1, access from below at Y=0
        turtle.select(1)
        for slot = 1, 16 do
            if slot ~= 1 and turtle.getItemCount(slot) > 0 then
                turtle.select(slot)
                turtle.dropUp()
            end
        end
        turtle.select(1)
        log("Inventory dumped")
    elseif resourceType == "fuel" then
        -- Fuel chest is above at Y=1, access from below at Y=0
        turtle.select(1)
        
        -- Suck up fuel items
        while turtle.suckUp() do
            sleep(0.05)
        end
        
        -- Refuel to maximum capacity, keeping 64 items in slot 1
        local fuelLimit = turtle.getFuelLimit()
        while turtle.getFuelLevel() < fuelLimit and turtle.getItemCount(1) > 64 do
            turtle.refuel(1)
        end
        
        -- If we're at max fuel but have less than 64 items, try to get more
        if turtle.getItemCount(1) < 64 then
            while turtle.suckUp() and turtle.getItemCount(1) < 64 do
                sleep(0.05)
            end
        end
        
        log("Refueled to " .. turtle.getFuelLevel() .. "/" .. fuelLimit .. 
              ", holding " .. turtle.getItemCount(1) .. " fuel items")
    end
    
    log("Operation complete, returning to position...")
    log("Target position: " .. textutils.serialize(targetReturnPos))
    log("Current position before return: " .. textutils.serialize(gps_nav.getPosition()))
    
    -- Return to target position using GPS navigation
    local returnSuccess = gps_nav.goto(targetReturnPos.x, targetReturnPos.y, targetReturnPos.z)
    
    if not returnSuccess then
        log("ERROR: Failed to return to target position!")
        log("Current position: " .. textutils.serialize(gps_nav.getPosition()))
        log("Target was: " .. textutils.serialize(targetReturnPos))
        -- Still try to restore direction
    else
        log("Successfully arrived at saved GPS position")
    end
    log("Current dig.lua rotation after navigation: " .. dig.getr())
    
    -- Restore the original facing direction
    if savedDirection then
        log("Restoring direction to: " .. savedDirection .. " (dig.lua rotation=" .. savedRotation .. ")")
        
        -- Use gps_nav to turn to face the saved cardinal direction
        if gps_nav.faceDirection(savedDirection) then
            -- Override dig.lua's rotation to the exact saved value
            dig.setr(savedRotation)
            log("Direction restored: dig.lua rotation=" .. dig.getr() .. " direction=" .. savedDirection)
        else
            log("Warning: Failed to restore direction, setting dig.lua rotation anyway")
            dig.setr(savedRotation)
        end
    else
        log("Warning: No saved direction, restoring dig.lua rotation only")
        dig.setr(savedRotation)
        log("dig.lua rotation set to: " .. dig.getr())
    end
    
    -- Release resource
    releaseResource(resourceType)
    
    -- Send status update after returning to mining
    sendStatusUpdate("mining")
end

-- Initialize worker - receive firmware and zone assignment
local function initializeWorker()
    log("\n=== Worker Initialization ===")
    
    -- Check if we're restarting from previous state
    if loadState() then
        log("Found previous state - resuming from saved position")
        log("Position: X=" .. dig.getx() .. " Y=" .. dig.gety() .. " Z=" .. dig.getz())
        log("Rotation: " .. dig.getr())
        if dig.getCardinalDir() then
            log("Direction: " .. dig.getCardinalDir())
        end
        
        if config.isCoordinated and config.zone then
            modem.open(config.broadcastChannel)
            modem.open(config.serverChannel)
            
            -- Re-initialize GPS navigation - gps_nav.init() will get current GPS
            -- but we keep our original startGPS from the saved state
            if config.startGPS then
                gps_nav.init()
                log("GPS initialized - preserved start position: " .. 
                    config.startGPS.x .. "," .. config.startGPS.y .. "," .. config.startGPS.z)
            end
            
            log("State restored - ready to continue mining")
            return -- Skip initialization, go straight to mining
        end
    end
    
    log("Starting fresh initialization...")
    log("Waiting for zone assignment...")
    
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
    log("Listening on server channel: " .. config.serverChannel)
    
    -- Get GPS position and notify server we're ready for assignment
    local currentGPS = getGPS(5)
    if not currentGPS then
        error("Failed to get GPS position for zone matching")
    end
    
    log("Notifying server we're ready for assignment...")
    modem.transmit(config.serverChannel, config.serverChannel, {
        type = "ready_for_assignment",
        turtle_id = config.turtleID,
        gps_position = currentGPS
    })
    
    local initTimeout = os.startTimer(120) -- 2 minute timeout
    local gotAssignment = false
    
    while not gotAssignment do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == initTimeout then
            error("Timeout waiting for zone assignment")
        elseif event == "modem_message" then
            local side, channel, replyChannel, message, distance = p1, p2, p3, p4, p5
            if type(message) == "table" then
                if message.type == "zone_assignment" and message.turtle_id == config.turtleID then
                    -- This zone assignment is for us!
                    local currentGPS = getGPS(5)
                    if not currentGPS then
                        log("Warning: Could not verify GPS position")
                        currentGPS = {x = 0, y = 0, z = 0} -- Use default if GPS fails
                    end
                    
                    config.zone = message.zone
                    config.gps_zone = message.gps_zone
                    config.chestGPS = message.chest_gps
                    config.isCoordinated = true
                    config.startGPS = currentGPS
                    
                    -- Set initial cardinal direction from server
                    if message.initial_direction then
                        dig.setCardinalDir(message.initial_direction)
                        log("Initial direction set to: " .. message.initial_direction)
                    else
                        log("Warning: No initial direction provided by server")
                    end
                    
                    -- Initialize GPS navigation
                    gps_nav.init()
                    
                    -- Save initial state
                    saveState()
                    
                    log("Zone assignment received!")
                    log("Zone: X=" .. config.zone.xmin .. "-" .. config.zone.xmax)
                    log("Chest positions (GPS coords):")
                    log("  Output: (" .. config.chestGPS.output.x .. ", " .. config.chestGPS.output.y .. ", " .. config.chestGPS.output.z .. ")")
                    log("  Fuel: (" .. config.chestGPS.fuel.x .. ", " .. config.chestGPS.fuel.y .. ", " .. config.chestGPS.fuel.z .. ")")
                    
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
    log("Waiting for start signal...")
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if type(message) == "table" and message.type == "start_mining" then
            log("Start signal received!")
            config.miningStarted = true
            saveState()
            sendStatusUpdate("mining")
            break
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

-- Modified fuel check for coordinated mode
local fuelThreshold = 1000 -- Will be calculated based on zone distance

local function checkFuel()
    local current = turtle.getFuelLevel()
    
    if current < fuelThreshold then
        -- First try to use reserve fuel in slot 1 (keep at least 1 item to reserve the slot)
        turtle.select(1)
        if turtle.getItemCount(1) > 1 and turtle.refuel(0) then
            -- We have fuel items in slot 1, consume them to reach threshold (keeping 1 item)
            log("Using reserve fuel from slot 1...")
            while turtle.getFuelLevel() < fuelThreshold and turtle.getItemCount(1) > 1 do
                turtle.refuel(1)
            end
            log("Refueled from reserve to " .. turtle.getFuelLevel() .. ", " .. turtle.getItemCount(1) .. " items remain")
        end
        
        -- If still below threshold after using reserve, go to chest
        if turtle.getFuelLevel() < fuelThreshold then
            flex.send("Fuel low (" .. current .. "/" .. fuelThreshold .. "), requesting access...", colors.yellow)
            queuedResourceAccess("fuel")
        end
    end
end

-- Calculate fuel threshold based on maximum distance from fuel chest
local function calculateFuelThreshold()
    if not config.isCoordinated or not config.chestGPS.fuel or not config.gps_zone then
        return 1000 -- Default fallback
    end
    
    -- Calculate maximum possible distance from fuel chest to any corner of the zone
    local fuelX = config.chestGPS.fuel.x
    local fuelY = config.chestGPS.fuel.y
    local fuelZ = config.chestGPS.fuel.z
    
    -- Check all corners of the zone and all Y levels
    local maxDist = 0
    local corners = {
        {config.gps_zone.gps_xmin, config.gps_zone.gps_ymin, config.gps_zone.gps_zmin},
        {config.gps_zone.gps_xmin, config.gps_zone.gps_ymin, config.gps_zone.gps_zmax},
        {config.gps_zone.gps_xmax, config.gps_zone.gps_ymin, config.gps_zone.gps_zmin},
        {config.gps_zone.gps_xmax, config.gps_zone.gps_ymin, config.gps_zone.gps_zmax},
        {config.gps_zone.gps_xmin, config.gps_zone.gps_ymax, config.gps_zone.gps_zmin},
        {config.gps_zone.gps_xmin, config.gps_zone.gps_ymax, config.gps_zone.gps_zmax},
        {config.gps_zone.gps_xmax, config.gps_zone.gps_ymax, config.gps_zone.gps_zmin},
        {config.gps_zone.gps_xmax, config.gps_zone.gps_ymax, config.gps_zone.gps_zmax}
    }
    
    for _, corner in ipairs(corners) do
        -- Manhattan distance (since turtle can't move diagonally)
        local dist = math.abs(corner[1] - fuelX) + 
                     math.abs(corner[2] - fuelY) + 
                     math.abs(corner[3] - fuelZ)
        if dist > maxDist then
            maxDist = dist
        end
    end
    
    -- Only need fuel to reach chest (one-way) + safety margin, since we refuel before returning
    local threshold = maxDist + 50
    
    log("Fuel threshold calculated: " .. threshold .. " (max distance to chest: " .. maxDist .. ")")
    return threshold
end

-- Main execution
initializeWorker()

if config.isCoordinated then
    -- Calculate fuel threshold based on zone dimensions
    fuelThreshold = calculateFuelThreshold()
    
    -- Override dig functions to use GPS validation and queuing
    local oldDropNotFuel = dig.dropNotFuel
    dig.dropNotFuel = function()
        queuedResourceAccess("output")
    end
    
    -- Set up dig API for zone-constrained mining
    dig.setFuelSlot(1)
    dig.setBlockSlot(2)
    dig.doBlacklist()
    dig.doAttack()
    
    -- Always wait for start signal from server (both fresh start and restart)
    if not config.miningStarted then
        log("Waiting for start signal from server...")
    else
        log("Resuming from saved state - waiting for start signal...")
        -- Reset flag so we wait for signal again
        config.miningStarted = false
        saveState()
    end
    
    modem.open(config.serverChannel)
    modem.open(config.broadcastChannel)
    
    while not config.miningStarted do
        local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
        if type(message) == "table" and message.type == "start_mining" then
            log("Start signal received!")
            config.miningStarted = true
            saveState()
            sendStatusUpdate("mining")
            break
        end
    end
    
    -- Run quarry with zone constraints
    log("\n=== Starting Zone Mining ===")
    local width = config.zone.xmax - config.zone.xmin + 1
    local length = config.zone.zmax - config.zone.zmin + 1
    local depth = math.abs(config.zone.ymin)
    local skip = config.zone.skip or 0
    
    log("Zone dimensions: " .. width .. "x" .. length .. "x" .. depth)
    
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
                log("\n=== ABORT RECEIVED ===")
                break
            end
        end
    end
    
    -- Quarry mining function
    local function mineQuarry()
        -- Workers start at dig.lua Y=0 (world Y=-1 where they were placed)
        -- Mine down layer by layer from Y=0 to Y=-depth
        -- Workers face south (rotation 180), mine east by going X=0 to X=-(width-1)
        for y = 0, -depth, -1 do
            if y <= -skip then -- Only mine at skip depth and below
                -- Mine current layer in a back-and-forth pattern
                for z = 0, length - 1 do
                    -- Mine eastward: X=0 down to X=-(width-1)
                    for x = 0, -(width - 1), -1 do
                        -- Check fuel and inventory periodically
                        checkFuel()
                        checkInv()
                        
                        -- Navigate to position
                        dig.goto(x, y, z, 0)
                        
                        -- Block any lava before digging
                        dig.blockLavaUp()
                        dig.blockLava() -- forward
                        dig.blockLavaDown()
                        
                        -- Dig at current position if needed
                        if turtle.detectDown() then
                            turtle.digDown()
                        end
                        
                        -- Check for lava again after digging
                        dig.blockLavaDown()
                    end
                end
            end
        end
        
        -- Return to start position after mining
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
        log("Abort received - dumping inventory and returning to start...")
        sendStatusUpdate("aborting")
        
        -- Use queuedResourceAccess to dump inventory, returning to starting position instead of current position
        queuedResourceAccess("output", config.startGPS)
        
        -- Send abort acknowledgment
        modem.transmit(config.serverChannel, config.serverChannel, {
            type = "abort_ack",
            turtle_id = config.turtleID,
            position = getGPS(3)
        })
        
        log("Abort complete - standing by")
        sendStatusUpdate("aborted")
        return
    elseif not miningSuccess then
        error(miningError)
    end
    
else
    -- Run as standalone (not coordinated)
    log("Running in standalone mode")
    log("To use coordinated mode, deploy via orchestrate_deploy.lua")
end

-- Completion sequence
if config.isCoordinated then
    log("\n=== Zone Mining Complete ===")
    
    -- Dump inventory and return to starting position in one operation
    queuedResourceAccess("output", config.startGPS)
    
    -- Send completion message
    sendStatusUpdate("complete")
    modem.transmit(config.serverChannel, config.serverChannel, {
        type = "zone_complete",
        turtle_id = config.turtleID,
        final_pos = getGPS(3)
    })
    
    -- Clean up state file since we're done
    if fs.exists(STATE_FILE) then
        fs.delete(STATE_FILE)
    end
    
    log("Completion reported to server")
    log("Worker standing by...")
end