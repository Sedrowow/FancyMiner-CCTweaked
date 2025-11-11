-- Chest Management for Deployment
-- Handles placement and tracking of fuel and output chests

local M = {}

-- Place output chest at current location Y+1
-- Returns: GPS position of chest, or nil and error message
function M.placeOutputChest(startGPS)
    turtle.select(3)
    if not turtle.placeUp() then
        return nil, "No output chest in slot 3 or placement failed"
    end
    
    return {
        x = startGPS.x,
        y = startGPS.y + 1,
        z = startGPS.z
    }
end

-- Place fuel chest at X+1, Y+1 from start position
-- Assumes turtle is at 0,0,0 relative position
-- Returns: GPS position of chest, or nil and error message
function M.placeFuelChest(startGPS, digAPI)
    digAPI.goto(1, 0, 0, 90)
    turtle.select(2)
    if not turtle.placeUp() then
        return nil, "No fuel chest in slot 2 or placement failed"
    end
    
    return {
        x = startGPS.x + 1,
        y = startGPS.y + 1,
        z = startGPS.z
    }
end

-- Place both fuel and output chests
-- Returns: chestPositions table with fuel and output GPS, or nil and error
function M.placeChests(startGPS, digAPI)
    print("Placing chests...")
    
    -- Place output chest at starting position
    local outputGPS, err = M.placeOutputChest(startGPS)
    if not outputGPS then
        return nil, err
    end
    
    -- Place fuel chest at X+1
    local fuelGPS, err = M.placeFuelChest(startGPS, digAPI)
    if not fuelGPS then
        return nil, err
    end
    
    -- Return to starting position
    digAPI.goto(0, 0, 0, 0)
    
    return {
        fuel = fuelGPS,
        output = outputGPS
    }
end

-- Wait for fuel to appear in the fuel chest
-- Returns: true when fuel is detected
function M.waitForFuel(digAPI)
    print("Waiting for fuel in chest...")
    digAPI.goto(1, 0, 0, 0)
    turtle.select(1)
    
    while not turtle.suckUp(1) do 
        sleep(1) 
    end
    
    print("Fuel detected")
    digAPI.goto(0, 0, 0, 0)
    return true
end

-- Ensure deployer turtle has sufficient fuel (at least 8, preferably 64)
-- Returns: success (boolean)
function M.ensureDeployerFuel(digAPI, minimumFuel)
    minimumFuel = minimumFuel or 8
    
    turtle.select(1)
    if turtle.getItemCount(1) >= minimumFuel then
        return true
    end
    
    digAPI.goto(1, 0, 0, 0)
    turtle.select(1)
    
    -- Try to get 64 fuel, but accept if we have at least minimumFuel
    while turtle.getItemCount(1) < 64 do
        if not turtle.suckUp(1) then
            if turtle.getItemCount(1) >= minimumFuel then 
                break 
            end
            sleep(1)
        end
    end
    
    digAPI.goto(0, 0, 0, 0)
    return turtle.getItemCount(1) >= minimumFuel
end

return M
