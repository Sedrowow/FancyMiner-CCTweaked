-- Worker Deployment Module
-- Handles deploying, fueling, and initializing worker turtles

local M = {}

-- Ensure we have at least 8 fuel in slot 1
-- Returns: success (boolean), error message (string or nil)
function M.ensureFuel(digAPI)
    turtle.select(1)
    if turtle.getItemCount(1) >= 8 then
        return true
    end
    
    -- Save position and get fuel from chest
    local savedLoc = digAPI.location()
    digAPI.goto(1, 0, 0, 0)
    
    turtle.select(1)
    while turtle.getItemCount(1) < turtle.getItemSpace(1) do
        if not turtle.suckUp(1) then break end
    end
    
    digAPI.goto(savedLoc)
    
    if turtle.getItemCount(1) >= 8 then
        return true
    else
        return false, "Insufficient fuel in chest"
    end
end

-- Count turtles in inventory slots 4-16
-- Returns: table of slot numbers containing turtles
function M.findTurtleSlots()
    local turtleSlots = {}
    for slot = 4, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name:find("turtle") then
            table.insert(turtleSlots, slot)
        end
    end
    return turtleSlots
end

-- Deploy a single worker turtle
-- Parameters:
--   slot: inventory slot containing the turtle
--   zone: zone assignment table with xmin
--   zoneIndex: worker number for display
--   digAPI: reference to dig API for navigation
-- Returns: success (boolean), error message (string or nil)
function M.deployWorker(slot, zone, zoneIndex, digAPI)
    local detail = turtle.getItemDetail(slot)
    if not detail or not detail.name:find("turtle") then
        return false, "No turtle in slot " .. slot
    end
    
    -- Ensure we have fuel to give the worker
    local success, err = M.ensureFuel(digAPI)
    if not success then
        return false, err or "Failed to get fuel"
    end
    
    print("Deploying worker " .. zoneIndex)
    digAPI.goto(zone.xmin, 0, 0, 180)
    
    -- Clear space and place turtle
    if turtle.detectDown() then 
        turtle.digDown() 
    end
    
    turtle.select(slot)
    if not turtle.placeDown() then
        return false, "Failed to place turtle at position"
    end
    
    -- Give fuel and power on
    turtle.select(1)
    turtle.dropDown(8)
    
    local turtlePeripheral = peripheral.wrap("bottom")
    if turtlePeripheral and turtlePeripheral.turnOn then
        turtlePeripheral.turnOn()
    end
    
    return true
end

-- Deploy all workers from turtle slots to their assigned zones
-- Returns: number of successful deployments, number of failures
function M.deployAll(turtleSlots, zones, digAPI)
    local successCount = 0
    local failCount = 0
    
    for i, slot in ipairs(turtleSlots) do
        local success, err = M.deployWorker(slot, zones[i], i, digAPI)
        if success then
            successCount = successCount + 1
        else
            print("Warning: " .. (err or "Unknown error"))
            failCount = failCount + 1
        end
    end
    
    return successCount, failCount
end

-- Collect deployed worker turtles during cleanup
-- Returns: number of workers collected
function M.collectWorkers(zones, digAPI)
    local collectedCount = 0
    
    for i = 1, #zones - 1 do
        print("Collecting worker " .. i)
        digAPI.goto(zones[i].xmin, 0, 0, 0)
        
        local success, data = turtle.inspectDown()
        if success and data.name and data.name:find("turtle") then
            turtle.digDown()
            collectedCount = collectedCount + 1
        else
            print("Warning: No turtle at position")
        end
    end
    
    digAPI.goto(0, 0, 0, 0)
    return collectedCount
end

return M
