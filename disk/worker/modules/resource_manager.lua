-- Resource Manager Module
-- Handles queued access to shared resources (fuel and output chests)

local M = {}

-- Request access to a resource (fuel or output)
function M.requestAccess(modem, serverChannel, turtleID, resourceType, logger)
    if not modem or not serverChannel then
        return true -- Not in coordinated mode
    end
    
    logger.log("Requesting " .. resourceType .. " access...")
    
    -- Send request
    modem.transmit(serverChannel, serverChannel, {
        type = "resource_request",
        turtle_id = turtleID,
        resource = resourceType
    })
    
    -- Wait for grant
    local timeout = os.startTimer(300) -- 5 minute timeout
    local granted = false
    local chestPos = nil
    local approachDir = nil
    
    while not granted do
        local event, p1, p2, p3, p4 = os.pullEvent()
        
        if event == "timer" and p1 == timeout then
            logger.warn("Timeout waiting for " .. resourceType .. " access")
            return false
        elseif event == "modem_message" then
            local message = p4
            if type(message) == "table" then
                if message.type == "resource_granted" and 
                   message.turtle_id == turtleID and
                   message.resource == resourceType then
                    granted = true
                    chestPos = message.chest_gps
                    approachDir = message.approach_direction
                    os.cancelTimer(timeout)
                elseif message.type == "queue_position" and
                       message.turtle_id == turtleID then
                    logger.log("Queue position: " .. message.position)
                end
            end
        end
    end
    
    return true, chestPos, approachDir
end

-- Release a resource
function M.releaseResource(modem, serverChannel, turtleID, resourceType, logger)
    if not modem or not serverChannel then
        return
    end
    
    modem.transmit(serverChannel, serverChannel, {
        type = "resource_released",
        turtle_id = turtleID,
        resource = resourceType
    })
    
    logger.log("Released " .. resourceType .. " access")
end

-- Dump inventory to output chest
function M.dumpInventory()
    turtle.select(1)
    for slot = 1, 16 do
        if slot ~= 1 and turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            turtle.dropUp()
        end
    end
    turtle.select(1)
end

-- Refuel from fuel chest
function M.refuelFromChest()
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
    
    return turtle.getFuelLevel(), fuelLimit, turtle.getItemCount(1)
end

-- Coordinated resource access with queuing
-- Returns to specified position (or current position if nil)
function M.accessResource(resourceType, returnPos, modem, serverChannel, turtleID, 
                          config, digAPI, gpsNavAPI, logger)
    
    if not config.isCoordinated then
        -- Fall back to normal operation without coordination
        if resourceType == "output" then
            digAPI.dropNotFuel()
        elseif resourceType == "fuel" then
            digAPI.refuel(1000)
        end
        return
    end
    
    -- Save current position and direction
    local savedPos = gpsNavAPI.getPosition()
    local savedRotation = digAPI.getr()
    local savedDirection = digAPI.getCardinalDir()
    
    -- Use custom return position if provided
    local targetReturnPos = returnPos or savedPos
    
    logger.log("Saving position: " .. textutils.serialize(savedPos) .. 
          " rotation=" .. savedRotation .. 
          " direction=" .. tostring(savedDirection))
    
    if returnPos then
        logger.log("Will return to custom position: " .. textutils.serialize(returnPos))
    end
    
    -- Request access
    local success, chestPos, approachDir = M.requestAccess(
        modem, serverChannel, turtleID, resourceType, logger
    )
    
    if not success then
        logger.error("Failed to get " .. resourceType .. " access")
        return
    end
    
    logger.log("Access granted, navigating to chest...")
    
    -- Navigate to position below the chest
    local chestGPS = config.chestGPS[resourceType]
    if not chestGPS then
        logger.error("Unknown resource type: " .. resourceType)
        M.releaseResource(modem, serverChannel, turtleID, resourceType, logger)
        return
    end
    
    gpsNavAPI.goto(chestGPS.x, chestGPS.y - 1, chestGPS.z)
    
    -- Perform operation
    if resourceType == "output" then
        M.dumpInventory()
        logger.log("Inventory dumped")
    elseif resourceType == "fuel" then
        local fuelLevel, fuelLimit, fuelItems = M.refuelFromChest()
        logger.log(string.format("Refueled to %d/%d, holding %d fuel items", 
            fuelLevel, fuelLimit, fuelItems))
    end
    
    logger.log("Operation complete, returning to position...")
    
    -- Return to target position
    local returnSuccess = gpsNavAPI.goto(
        targetReturnPos.x, 
        targetReturnPos.y, 
        targetReturnPos.z
    )
    
    if not returnSuccess then
        logger.error("Failed to return to target position!")
    else
        logger.log("Successfully arrived at saved GPS position")
    end
    
    -- Restore facing direction
    if savedDirection then
        logger.log("Restoring direction to: " .. savedDirection)
        if gpsNavAPI.faceDirection(savedDirection) then
            digAPI.setr(savedRotation)
            logger.log("Direction restored")
        else
            logger.warn("Failed to restore direction")
            digAPI.setr(savedRotation)
        end
    else
        digAPI.setr(savedRotation)
    end
    
    -- Release resource
    M.releaseResource(modem, serverChannel, turtleID, resourceType, logger)
end

-- Calculate fuel threshold based on maximum distance to fuel chest
function M.calculateFuelThreshold(config, logger)
    if not config.isCoordinated or not config.chestGPS.fuel or not config.gps_zone then
        return 1000 -- Default fallback
    end
    
    local fuelX = config.chestGPS.fuel.x
    local fuelY = config.chestGPS.fuel.y
    local fuelZ = config.chestGPS.fuel.z
    
    -- Check all corners of the zone
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
        local dist = math.abs(corner[1] - fuelX) + 
                     math.abs(corner[2] - fuelY) + 
                     math.abs(corner[3] - fuelZ)
        if dist > maxDist then
            maxDist = dist
        end
    end
    
    local threshold = maxDist + 50
    
    logger.log("Fuel threshold calculated: " .. threshold .. 
        " (max distance: " .. maxDist .. ")")
    
    return threshold
end

return M
