-- Resource Management Module for Orchestration Server
-- Handles fuel and output chest access queuing and locking

local ResourceManager = {}

-- Resource timeout in seconds (5 minutes)
ResourceManager.RESOURCE_TIMEOUT = 300

-- Check for resource timeout and force release if needed
function ResourceManager.checkTimeout(state, resourceType)
    local lockKey = (resourceType == "fuel") and "fuelLock" or "outputLock"
    local timeKey = (resourceType == "fuel") and "fuelLockTime" or "outputLockTime"
    
    print("DEBUG checkTimeout: " .. resourceType .. " lock=" .. tostring(state[lockKey]) .. " time=" .. tostring(state[timeKey]))
    
    if state[lockKey] and state[timeKey] then
        local elapsed = os.clock() - state[timeKey]
        print("DEBUG: " .. resourceType .. " elapsed=" .. math.floor(elapsed) .. "s, timeout=" .. ResourceManager.RESOURCE_TIMEOUT .. "s")
        if elapsed > ResourceManager.RESOURCE_TIMEOUT then
            print("WARNING: Turtle " .. state[lockKey] .. " timed out on " .. resourceType .. " (" .. math.floor(elapsed) .. "s)")
            print("Force-releasing " .. resourceType .. " lock...")
            
            local timedOutTurtle = state[lockKey]
            state[lockKey] = false
            state[timeKey] = nil
            
            if state.workers[timedOutTurtle] then
                state.workers[timedOutTurtle].status = "timeout"
            end
            
            return true, timedOutTurtle
        end
    end
    return false, nil
end

-- Grant resource access to next turtle in queue
function ResourceManager.grantNext(modem, serverChannel, state, resourceType)
    local queue = (resourceType == "fuel") and state.fuelQueue or state.outputQueue
    local lockKey = (resourceType == "fuel") and "fuelLock" or "outputLock"
    local timeKey = (resourceType == "fuel") and "fuelLockTime" or "outputLockTime"
    
    if #queue > 0 and not state[lockKey] then
        local nextTurtle = table.remove(queue, 1)
        state[lockKey] = nextTurtle
        state[timeKey] = os.clock()
        
        local chestPos = state.chestPositions[resourceType]
        -- Both chests are at Y=1, workers access from below at Y=0
        local approachDir = "down"
        
        modem.transmit(serverChannel, serverChannel, {
            type = "resource_granted",
            turtle_id = nextTurtle,
            resource = resourceType,
            chest_gps = chestPos,
            approach_direction = approachDir
        })
        
        print("Granted " .. resourceType .. " access to turtle " .. nextTurtle)
        return true
    end
    return false
end

-- Handle resource request from worker
function ResourceManager.handleRequest(modem, serverChannel, state, turtleID, resourceType)
    local queue = (resourceType == "fuel") and state.fuelQueue or state.outputQueue
    local lockKey = (resourceType == "fuel") and "fuelLock" or "outputLock"
    local timeKey = (resourceType == "fuel") and "fuelLockTime" or "outputLockTime"
    
    -- Check if turtle already has the lock
    if state[lockKey] == turtleID then
        print("Turtle " .. turtleID .. " already has " .. resourceType .. " access")
        -- Send confirmation so worker doesn't hang waiting
        local chestPos = state.chestPositions[resourceType]
        local approachDir = "down"
        
        modem.transmit(serverChannel, serverChannel, {
            type = "resource_granted",
            turtle_id = turtleID,
            resource = resourceType,
            chest_gps = chestPos,
            approach_direction = approachDir
        })
        return false
    end
    
    -- Check if turtle is already in queue
    local alreadyQueued = false
    local queuePos = 0
    for i, id in ipairs(queue) do
        if id == turtleID then
            alreadyQueued = true
            queuePos = i
            break
        end
    end
    
    if alreadyQueued then
        -- Turtle already in queue, just send current position
        modem.transmit(serverChannel, serverChannel, {
            type = "queue_position",
            turtle_id = turtleID,
            resource = resourceType,
            position = queuePos
        })
        print("Turtle " .. turtleID .. " already queued for " .. resourceType .. " (position " .. queuePos .. ")")
        return false
    end
    
    if not state[lockKey] then
        -- Resource available, grant immediately
        state[lockKey] = turtleID
        state[timeKey] = os.clock()
        
        local chestPos = state.chestPositions[resourceType]
        local approachDir = "down"
        
        modem.transmit(serverChannel, serverChannel, {
            type = "resource_granted",
            turtle_id = turtleID,
            resource = resourceType,
            chest_gps = chestPos,
            approach_direction = approachDir
        })
        
        print("Granted " .. resourceType .. " access to turtle " .. turtleID)
    else
        -- Resource in use, add to queue
        table.insert(queue, turtleID)
        
        modem.transmit(serverChannel, serverChannel, {
            type = "queue_position",
            turtle_id = turtleID,
            resource = resourceType,
            position = #queue
        })
        
        print("Queued turtle " .. turtleID .. " for " .. resourceType .. " (position " .. #queue .. ")")
    end
    
    if state.workers[turtleID] then
        state.workers[turtleID].status = "queued"
    end
    
    return true
end

-- Handle resource release from worker
function ResourceManager.handleRelease(modem, serverChannel, state, turtleID, resourceType)
    local lockKey = (resourceType == "fuel") and "fuelLock" or "outputLock"
    local timeKey = (resourceType == "fuel") and "fuelLockTime" or "outputLockTime"
    
    state[lockKey] = false
    state[timeKey] = nil
    
    if state.workers[turtleID] then
        state.workers[turtleID].status = "mining"
    end
    
    print("Turtle " .. turtleID .. " released " .. resourceType)
    
    -- Grant access to next in queue
    ResourceManager.grantNext(modem, serverChannel, state, resourceType)
    
    return true
end

return ResourceManager
