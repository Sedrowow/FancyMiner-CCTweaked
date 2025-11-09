-- Worker Turtle for Multi-Turtle Coordinated Quarry System
-- GPS-aware mining with resource queue management
-- Receives zone assignments from orchestration server

os.loadAPI("dig.lua")
os.loadAPI("flex.lua")

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
    aborted = false
}

local modem = peripheral.find("ender_modem")
if not modem then
    modem = peripheral.find("modem")
end

if not modem then
    error("No modem found! Worker requires an ender modem.")
end

print("Worker Turtle ID: " .. config.turtleID)

-- File reception state
local fileChunks = {}
local filesReceived = {}

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

local function validateInZone()
    if not config.isCoordinated or not config.gps_zone then
        return true -- Not in coordinated mode
    end
    
    local currentGPS = getGPS(3)
    if not currentGPS then
        print("Warning: GPS unavailable for zone validation")
        return true -- Assume okay if GPS fails
    end
    
    local inZone = currentGPS.x >= config.gps_zone.gps_xmin and
                   currentGPS.x <= config.gps_zone.gps_xmax and
                   currentGPS.z >= config.gps_zone.gps_zmin and
                   currentGPS.z <= config.gps_zone.gps_zmax
    
    if not inZone then
        flex.send("Warning: Outside assigned zone! GPS: " .. 
                  textutils.serialize(currentGPS), colors.red)
    end
    
    return inZone
end

local function gpsNavigateTo(targetGPS, approachDir)
    if not targetGPS then
        return false, "No target GPS provided"
    end
    
    -- Get current position
    local currentGPS = getGPS(5)
    if not currentGPS then
        return false, "Failed to get current GPS position"
    end
    
    print("Navigating from " .. textutils.serialize(currentGPS) .. 
          " to " .. textutils.serialize(targetGPS))
    
    -- Calculate approach position based on direction
    local approachGPS = {x = targetGPS.x, y = targetGPS.y, z = targetGPS.z}
    if approachDir == "north" then
        approachGPS.z = targetGPS.z + 1
    elseif approachDir == "south" then
        approachGPS.z = targetGPS.z - 1
    elseif approachDir == "east" then
        approachGPS.x = targetGPS.x + 1
    elseif approachDir == "west" then
        approachGPS.x = targetGPS.x - 1
    elseif approachDir == "down" then
        approachGPS.y = targetGPS.y - 1
    elseif approachDir == "up" then
        approachGPS.y = targetGPS.y + 1
    end
    
    -- Navigate to Y level first
    local currentY = dig.gety()
    local targetY = approachGPS.y
    if currentY < targetY then
        for i = 1, targetY - currentY do
            dig.up()
        end
    elseif currentY > targetY then
        for i = 1, currentY - targetY do
            dig.down()
        end
    end
    
    -- Use GPS to verify and navigate X/Z
    local attempts = 0
    while attempts < 10 do
        currentGPS = getGPS(5)
        if not currentGPS then
            attempts = attempts + 1
            sleep(1)
            break
        end
        
        local deltaX = approachGPS.x - currentGPS.x
        local deltaZ = approachGPS.z - currentGPS.z
        
        -- Check if we've arrived
        if math.abs(deltaX) < 0.5 and math.abs(deltaZ) < 0.5 then
            break
        end
        
        -- Move toward target
        if math.abs(deltaX) > 0.5 then
            if deltaX > 0 then
                dig.gotor(90)
                dig.fwd()
            else
                dig.gotor(270)
                dig.fwd()
            end
        elseif math.abs(deltaZ) > 0.5 then
            if deltaZ > 0 then
                dig.gotor(0)
                dig.fwd()
            else
                dig.gotor(180)
                dig.fwd()
            end
        end
        
        attempts = attempts + 1
    end
    
    -- Face the chest (or position for vertical access)
    if approachDir == "north" then
        dig.gotor(180) -- Face south toward chest
    elseif approachDir == "south" then
        dig.gotor(0) -- Face north toward chest
    elseif approachDir == "east" then
        dig.gotor(270) -- Face west toward chest
    elseif approachDir == "west" then
        dig.gotor(90) -- Face east toward chest
    elseif approachDir == "down" or approachDir == "up" then
        -- No specific facing needed for vertical chest access
        dig.gotor(0) -- Face north by default
    end
    
    return true
end

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
    
    print("Requesting " .. resourceType .. " access...")
    
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
            print("Timeout waiting for " .. resourceType .. " access")
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
                    print("Queue position: " .. message.position)
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
    
    print("Released " .. resourceType .. " access")
end

-- Coordinated resource operations
local function queuedResourceAccess(resourceType)
    if not config.isCoordinated then
        -- Fall back to normal operation
        if resourceType == "output" then
            dig.dropNotFuel()
        elseif resourceType == "fuel" then
            dig.refuel(1000)
        end
        return
    end
    
    -- Save current position
    local savedPos = {
        x = dig.getx(),
        y = dig.gety(),
        z = dig.getz(),
        r = dig.getr()
    }
    local savedGPS = getGPS(5)
    
    -- Validate we're in zone before leaving
    validateInZone()
    
    -- Request access
    local success, chestPos, approachDir = requestResourceAccess(resourceType)
    if not success then
        print("Failed to get " .. resourceType .. " access")
        return
    end
    
    print("Access granted, navigating to chest...")
    
    -- Navigate to chest
    local navSuccess, err = gpsNavigateTo(chestPos, approachDir)
    if not navSuccess then
        print("Navigation failed: " .. tostring(err))
        releaseResource(resourceType)
        return
    end
    
    -- Perform operation based on approach direction and resource type
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
        
        print("Refueled to " .. turtle.getFuelLevel() .. "/" .. fuelLimit .. 
              ", holding " .. turtle.getItemCount(1) .. " fuel items")
    end
    
    print("Operation complete, returning to mining position...")
    
    -- Return to saved position using GPS
    if savedGPS then
        gpsNavigateTo(savedGPS, "north")
    end
    
    -- Fine-tune using dead reckoning
    dig.goto(savedPos.x, savedPos.y, savedPos.z, savedPos.r)
    
    -- Validate we're back in zone
    validateInZone()
    
    -- Release resource
    releaseResource(resourceType)
    
    -- Send status update after returning to mining
    sendStatusUpdate("mining")
end

-- Initialize worker - receive firmware and zone assignment
local function initializeWorker()
    print("\n=== Worker Initialization ===")
    print("Waiting for firmware and zone assignment...")
    
    modem.open(config.broadcastChannel)
    
    local initTimeout = os.startTimer(120) -- 2 minute timeout
    local gotAssignment = false
    
    while not gotAssignment do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == initTimeout then
            error("Timeout waiting for initialization")
        elseif event == "modem_message" then
            local side, channel, replyChannel, message, distance = p1, p2, p3, p4, p5
            if type(message) == "table" then
                if message.type == "file_chunk_broadcast" then
                    -- Receive firmware file chunk
                    local filename = message.filename
                    if not fileChunks[filename] then
                        fileChunks[filename] = {}
                    end
                    
                    fileChunks[filename][message.chunk_num] = message.data
                    
                    -- Check if file is complete
                    local complete = true
                    for i = 1, message.total_chunks do
                        if not fileChunks[filename][i] then
                            complete = false
                            break
                        end
                    end
                    
                    if complete and not filesReceived[filename] then
                        -- Reassemble and write file
                        local content = table.concat(fileChunks[filename])
                        local file = fs.open(filename, "w")
                        file.write(content)
                        file.close()
                        
                        filesReceived[filename] = true
                        print("Received: " .. filename)
                        
                        -- Acknowledge receipt
                        modem.transmit(config.serverChannel or config.broadcastChannel, 
                                     config.broadcastChannel, {
                            type = "file_received",
                            turtle_id = config.turtleID,
                            filename = filename
                        })
                    end
                    
                elseif message.type == "zone_assignment" then
                    -- Check if this might be our zone based on GPS
                    local currentGPS = getGPS(5)
                    if currentGPS then
                        local inZone = currentGPS.x >= message.gps_zone.gps_xmin and
                                     currentGPS.x <= message.gps_zone.gps_xmax and
                                     currentGPS.z >= message.gps_zone.gps_zmin and
                                     currentGPS.z <= message.gps_zone.gps_zmax
                        
                        if inZone then
                            config.zone = message.zone
                            config.gps_zone = message.gps_zone
                            config.chestGPS = message.chest_gps
                            config.serverChannel = message.server_channel
                            config.isCoordinated = true
                            config.startGPS = currentGPS
                            
                            modem.open(config.serverChannel)
                            
                            print("Zone assignment received!")
                            print("Zone: X=" .. config.zone.xmin .. "-" .. config.zone.xmax)
                            
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
        end
    end
    
    -- Wait for start signal
    print("Waiting for start signal...")
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if type(message) == "table" and message.type == "start_mining" then
            print("Start signal received!")
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
            print("Using reserve fuel from slot 1...")
            while turtle.getFuelLevel() < fuelThreshold and turtle.getItemCount(1) > 1 do
                turtle.refuel(1)
            end
            print("Refueled from reserve to " .. turtle.getFuelLevel() .. ", " .. turtle.getItemCount(1) .. " items remain")
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
    
    print("Fuel threshold calculated: " .. threshold .. " (max distance to chest: " .. maxDist .. ")")
    return threshold
end

-- Main execution
-- Always try to initialize as coordinated worker
-- If we're deployed, we'll get zone assignments
-- If standalone, this will fail/timeout and we skip to standalone mode

local coordinatedMode = false
local initSuccess = pcall(function()
    initializeWorker()
    coordinatedMode = true
end)

if coordinatedMode then
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
    
    -- Run quarry with zone constraints
    print("\n=== Starting Zone Mining ===")
    local width = config.zone.xmax - config.zone.xmin + 1
    local length = config.zone.zmax - config.zone.zmin + 1
    local depth = math.abs(config.zone.ymin)
    local skip = config.zone.skip or 0
    
    print("Zone dimensions: " .. width .. "x" .. length .. "x" .. depth)
    
    -- Set up periodic status updates and abort checking
    local lastStatusUpdate = os.clock()
    local statusUpdateInterval = 10 -- Send status every 10 seconds
    
    -- Wrap dig functions to include periodic status updates, fuel checks, and abort checks
    local originalFwd = dig.fwd
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
        
        return result
    end
    
    -- Set up parallel task to listen for abort
    local function abortListener()
        while not config.aborted do
            local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
            if type(message) == "table" and message.type == "abort_mining" then
                config.aborted = true
                print("\n=== ABORT RECEIVED ===")
                break
            end
        end
    end
    
    -- Run the actual quarry operation with abort handling
    local miningSuccess, miningError = pcall(function()
        parallel.waitForAny(
            function() dig.quarry(width, length, depth, skip) end,
            abortListener
        )
    end)
    
    -- Handle abort
    if not miningSuccess and config.aborted then
        print("Returning to starting position...")
        sendStatusUpdate("aborting")
        
        -- Return to start GPS position if available
        if config.startGPS then
            local returnSuccess = gpsNavigateTo(config.startGPS, "north")
            if not returnSuccess then
                print("Warning: Could not return to exact start position")
            end
        end
        
        -- Send abort acknowledgment
        modem.transmit(config.serverChannel, config.serverChannel, {
            type = "abort_ack",
            turtle_id = config.turtleID,
            position = getGPS(3)
        })
        
        print("Abort complete - standing by")
        sendStatusUpdate("aborted")
        return
    elseif not miningSuccess then
        error(miningError)
    end
    
else
    -- Run as standalone (not coordinated)
    print("Running in standalone mode")
    print("To use coordinated mode, deploy via orchestrate_deploy.lua")
end

-- Completion sequence
if config.isCoordinated then
    print("\n=== Zone Mining Complete ===")
    print("Dumping remaining inventory...")
    
    -- Request output chest access to dump remaining items
    -- queuedResourceAccess handles navigation and dumping automatically
    queuedResourceAccess("output")
    
    -- Return to starting position
    print("Returning to starting position...")
    if config.startGPS then
        gpsNavigateTo(config.startGPS, "north")
    end
    dig.goto(0, 0, 0, 0)
    print("Arrived at starting position")
    
    -- Send completion message
    sendStatusUpdate("complete")
    modem.transmit(config.serverChannel, config.serverChannel, {
        type = "zone_complete",
        turtle_id = config.turtleID,
        final_pos = {
            x = dig.getx(),
            y = dig.gety(),
            z = dig.getz()
        }
    })
    
    print("Completion reported to server")
    print("Worker standing by...")
    -- Exit and return control (to deployer script if deployer, or just finish if regular worker)
end
