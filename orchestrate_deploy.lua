-- Deployment Turtle for Multi-Turtle Quarry System
-- Deploys worker turtles, transfers firmware from floppy disk
-- Then becomes a worker itself after deployment

os.loadAPI("dig.lua")
os.loadAPI("flex.lua")

local SERVER_CHANNEL = nil
local BROADCAST_CHANNEL = 65535

local state = {
    deployerID = os.getComputerID(),
    startGPS = nil,
    zones = {},
    numWorkers = 0,
    chestPositions = {
        fuel = nil,
        output = nil
    },
    serverChannel = nil
}

-- Initialize modem
local modem = peripheral.find("ender_modem")
if not modem then
    modem = peripheral.find("modem")
end

if not modem then
    error("No modem found! Deployer requires an ender modem.")
end

print("Deployment Turtle Initialized")
print("Turtle ID: " .. state.deployerID)

-- Get GPS coordinates with retry
local function getGPS(retries)
    retries = retries or 5
    for i = 1, retries do
        local x, y, z = gps.locate(5)
        if x then
            return {x = x, y = y, z = z}
        end
        print("GPS attempt " .. i .. "/" .. retries .. " failed, retrying...")
        sleep(1)
    end
    error("Failed to get GPS coordinates after " .. retries .. " attempts")
end

-- Deploy a single worker turtle
-- Ensure we have at least 8 fuel in slot 1
local function ensureFuel()
    turtle.select(1)
    local count = turtle.getItemCount(1)
    
    if count >= 8 then
        return true
    end
    
    -- Need more fuel, go get it from fuel chest
    print("Getting more fuel from chest...")
    local currentX, currentY, currentZ = dig.getx(), dig.gety(), dig.getz()
    local currentR = dig.getr()
    
    -- Navigate to fuel chest (X+1, Y+1 from start)
    dig.goto(1, 1, 0, 0)
    dig.gotor(270) -- Face west toward chest
    
    -- Pull fuel from chest to fill slot 1
    turtle.select(1)
    local stackLimit = turtle.getItemSpace(1)
    
    while turtle.getItemCount(1) < stackLimit do
        if not turtle.suck(1) then
            -- No more fuel available in chest
            break
        end
    end
    
    if turtle.getItemCount(1) < 8 then
        print("Warning: Could not get enough fuel from chest")
    end
    
    -- Return to previous position
    dig.goto(currentX, currentY, currentZ, currentR)
    
    return turtle.getItemCount(1) >= 8
end

local function deployWorker(slot, zone, zoneIndex)
    -- Check if slot contains a turtle
    local detail = turtle.getItemDetail(slot)
    if not detail or not detail.name:find("turtle") then
        return false, "No turtle in slot " .. slot
    end
    
    -- Ensure we have fuel to give to worker
    if not ensureFuel() then
        return false, "Insufficient fuel to deploy worker " .. zoneIndex
    end
    
    -- Calculate deployment position
    local deployX = state.startGPS.x + zone.xmin
    local deployY = state.startGPS.y
    local deployZ = state.startGPS.z
    
    -- Navigate to deployment position
    print("Moving to deployment position for zone " .. zoneIndex)
    dig.goto(zone.xmin, 0, 0, 0)
    
    -- Place turtle
    turtle.select(slot)
    if not turtle.placeDown() then
        return false, "Failed to place turtle at zone " .. zoneIndex
    end
    
    -- Get placed turtle's ID by inspecting
    local success, data = turtle.inspectDown()
    if not success or not data.name:find("turtle") then
        return false, "Failed to verify turtle placement"
    end
    
    -- Drop 8 fuel into the placed worker
    turtle.select(1)
    if not turtle.dropDown(8) then
        print("Warning: Failed to fuel worker " .. zoneIndex)
    else
        print("Fueled worker " .. zoneIndex .. " with 8 fuel")
    end
    
    print("Turtle placed at zone " .. zoneIndex)
    return true, slot
end

-- Calculate GPS zone boundaries
local function calculateGPSZone(zone, startGPS)
    return {
        gps_xmin = startGPS.x + zone.xmin,
        gps_xmax = startGPS.x + zone.xmax,
        gps_zmin = startGPS.z + zone.zmin,
        gps_zmax = startGPS.z + zone.zmax,
        gps_ymin = startGPS.y + zone.ymin,
        gps_ymax = startGPS.y + zone.ymax
    }
end

-- Main deployment sequence
local function deploy()
    print("\n=== Starting Deployment Sequence ===\n")
    
    -- Get starting GPS coordinates
    print("Acquiring GPS coordinates...")
    state.startGPS = getGPS()
    print("Starting position: " .. textutils.serialize(state.startGPS))
    
    -- Request deployment parameters from server
    print("\nRequesting deployment parameters from server...")
    print("Enter server channel ID:")
    SERVER_CHANNEL = tonumber(read())
    
    modem.open(SERVER_CHANNEL)
    modem.open(BROADCAST_CHANNEL)
    
    -- Count available turtles (slots 4-16, slots 1-3 are for fuel/chests)
    local turtleSlots = {}
    for slot = 4, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name:find("turtle") then
            table.insert(turtleSlots, slot)
        end
    end
    
    if #turtleSlots == 0 then
        error("No turtles found in inventory (slots 3-16)")
    end
    
    print("Found " .. #turtleSlots .. " turtles available for deployment")
    
    -- Request quarry parameters
    print("\nEnter quarry width:")
    local width = tonumber(read())
    print("Enter quarry length:")
    local length = tonumber(read())
    print("Enter quarry depth:")
    local depth = tonumber(read())
    print("Enter skip depth (0 for none):")
    local skip = tonumber(read())
    
    -- Send deployment request to server (include deployer as a worker)
    print("\nSending deploy_request to channel " .. SERVER_CHANNEL)
    print("Deployer ID: " .. state.deployerID)
    print("Num workers: " .. (#turtleSlots + 1))
    
    modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
        type = "deploy_request",
        deployer_id = state.deployerID,
        num_workers = #turtleSlots + 1,  -- +1 for deployer itself
        is_deployer = true,
        quarry_params = {
            width = width,
            length = length,
            depth = depth,
            skip = skip
        }
    })
    
    -- Wait for deployment command from server
    print("\nWaiting for server response...")
    local gotCommand = false
    
    while not gotCommand do
        local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
        
        if type(message) == "table" and message.type == "deploy_command" then
            state.zones = message.zones
            state.numWorkers = message.num_workers
            state.serverChannel = message.server_channel
            SERVER_CHANNEL = message.server_channel
            gotCommand = true
            print("Received zone assignments from server")
        end
    end
    
    -- Place output chest directly above starting position
    print("\nPlacing output chest...")
    dig.up() -- Move up
    turtle.select(3) -- Output chest in slot 3
    if not turtle.placeDown() then
        error("Failed to place output chest - ensure chest is in slot 3")
    end
    
    local outputGPS = {
        x = state.startGPS.x,
        y = state.startGPS.y + 1,
        z = state.startGPS.z
    }
    state.chestPositions.output = outputGPS
    
    -- Place fuel chest one space east and at same level
    print("Placing fuel chest...")
    dig.gotor(90) -- Face east
    turtle.select(2) -- Chest in slot 2
    if not turtle.place() then
        error("Failed to place fuel chest - ensure chest is in slot 2")
    end
    
    local fuelGPS = {
        x = state.startGPS.x + 1,
        y = state.startGPS.y + 1,
        z = state.startGPS.z
    }
    state.chestPositions.fuel = fuelGPS
    
    -- Return to ground level at starting position
    dig.gotor(270) -- Face west
    dig.fwd() -- Move back over start
    dig.down() -- Go down to ground level
    dig.gotor(0) -- Face north
    
    -- Report chest positions and starting GPS to server
    dig.gotor(0) -- Face forward
    modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
        type = "chest_positions",
        fuel_gps = fuelGPS,
        output_gps = outputGPS,
        start_gps = state.startGPS
    })
    
    print("Chests placed and registered with server")
    print("Server will load firmware from its disk drive")
    
    -- Wait for fuel to be placed in fuel chest
    print("\n=== Waiting for fuel ===")
    print("Please place fuel in the fuel chest")
    
    dig.goto(1, 1, 0, 0) -- Move to fuel chest position (X+1, Y+1)
    dig.gotor(270) -- Face west toward chest
    
    -- Wait until fuel is detected in chest
    turtle.select(1)
    while true do
        if turtle.suck(1) then
            print("Fuel detected! Proceeding with deployment...")
            break
        end
        sleep(1)
    end
    
    -- Return to start position
    dig.goto(0, 0, 0, 0)
    
    print("\nReady to deploy workers...")
    
    -- Deploy each worker turtle
    print("\n=== Deploying Workers ===\n")
    
    for i, slot in ipairs(turtleSlots) do
        local zone = state.zones[i]
        print("\nDeploying worker " .. i .. "/" .. #turtleSlots)
        print("Zone: X=" .. zone.xmin .. "-" .. zone.xmax .. ", Z=" .. zone.zmin .. "-" .. zone.zmax)
        
        local success, err = deployWorker(slot, zone, i)
        if not success then
            print("Warning: " .. err)
        end
    end
    
    -- Wait for workers to boot and connect to server
    print("\nWaiting for workers to initialize...")
    print("Workers will broadcast online status to server...")
    print("Server will respond with firmware and zone assignments...")
    sleep(2)
    
    -- Notify server that deployment is complete
    print("Notifying server of deployment completion...")
    modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
        type = "deployment_complete",
        deployer_id = state.deployerID
    })
    
    print("\n=== Deployment Complete ===")
    print("Workers deployed: " .. #state.deployedWorkers)
    
    -- Verify we have fuel before becoming a worker
    print("\n=== Preparing to Transition to Worker Mode ===")
    turtle.select(1)
    local fuelCount = turtle.getItemCount(1)
    
    if fuelCount < 8 then
        print("Getting fuel for self...")
        dig.goto(1, 1, 0, 0)
        dig.gotor(270)
        turtle.select(1)
        
        local stackLimit = turtle.getItemSpace(1)
        while turtle.getItemCount(1) < stackLimit do
            if not turtle.suck(1) then
                if turtle.getItemCount(1) >= 8 then
                    break -- Have enough even if not full
                end
                print("Waiting for more fuel...")
                sleep(1)
            end
        end
        
        dig.goto(0, 0, 0, 0)
        print("Fueled successfully with " .. turtle.getItemCount(1) .. " fuel")
    end
    
    print("\n=== Transitioning to Worker Mode ===\n")
    
    -- Deployer gets the last zone
    local deployerZone = state.zones[#state.zones]
    print("Deployer will mine zone " .. #state.zones)
    print("Zone: X=" .. deployerZone.xmin .. "-" .. deployerZone.xmax .. ", Z=" .. deployerZone.zmin .. "-" .. deployerZone.zmax)
    
    -- Navigate to deployer's zone starting position
    print("\nMoving to zone starting position...")
    dig.goto(deployerZone.xmin, 0, 0, 0)
    print("Arrived at zone " .. #state.zones .. " starting position")
    
    print("\nStarting worker bootstrap process...")
    print("Deployer will now operate as a worker turtle")
    sleep(1)
end

-- Run deployment
local success, err = pcall(deploy)

if not success then
    print("\nDeployment failed: " .. tostring(err))
    error(err)
end

print("\nDeployment successful! Becoming worker...")

-- Load and run bootstrap to join as worker
if fs.exists("bootstrap.lua") then
    shell.run("bootstrap.lua")
    
    -- Bootstrap/quarry completed - deployer is now waiting for cleanup command
    print("\n=== Worker Phase Complete ===")
    print("Deployer finished mining zone")
    print("Waiting for cleanup command from server...")
    
    -- Wait for cleanup command
    modem.open(SERVER_CHANNEL)
    
    while true do
        local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
        
        if type(message) == "table" then
            if message.type == "cleanup_command" and message.turtle_id == state.deployerID then
                print("\n=== Cleanup Command Received ===")
                print("Starting worker collection...")
                
                -- Navigate to each worker's starting position and collect them
                -- Workers are at their zone starting positions (zone.xmin, 0, 0)
                for i = 1, #state.zones - 1 do  -- Exclude last zone (deployer's zone)
                    local zone = state.zones[i]
                    local workerX = zone.xmin
                    
                    print("\nCollecting worker " .. i .. "...")
                    print("  Navigating to position X=" .. workerX)
                    
                    -- Navigate to worker position
                    dig.goto(workerX, 0, 0, 0)
                    
                    -- Worker should be below us at ground level
                    local success, data = turtle.inspectDown()
                    if success and data.name and data.name:find("turtle") then
                        print("  Found turtle, breaking...")
                        turtle.digDown()
                        print("  Worker " .. i .. " collected")
                    else
                        print("  Warning: No turtle found at position")
                    end
                end
                
                -- Return to initial starting position
                print("\nReturning to starting position...")
                dig.goto(0, 0, 0, 0)
                
                print("\n=== Cleanup Complete ===")
                print("All workers collected")
                print("Deployer at starting position")
                print("Chests remain in place for future use")
                break
            end
        end
    end
else
    print("Error: bootstrap.lua not found!")
    print("Deployer cannot transition to worker mode.")
end
