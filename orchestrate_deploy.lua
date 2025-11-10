-- Deployment Turtle for Multi-Turtle Quarry System
-- Deploys worker turtles, transfers firmware from floppy disk
-- Then becomes a worker itself after deployment

os.loadAPI("dig.lua")
os.loadAPI("flex.lua")

local SERVER_CHANNEL = nil
local BROADCAST_CHANNEL = 65535

local STATE_FILE = "deploy_state.cfg"

local state = {
    deployerID = os.getComputerID(),
    startGPS = nil,
    zones = {},
    numWorkers = 0,
    chestPositions = {
        fuel = nil,
        output = nil
    },
    serverChannel = nil,
    deploymentComplete = false,
    workerPhaseComplete = false
}

-- Save state to disk
local function saveState()
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialize(state))
    file.close()
end

-- Load state from disk
local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        local data = file.readAll()
        file.close()
        state = textutils.unserialize(data)
        return true
    end
    return false
end

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
        sleep(1)
    end
    error("Failed to get GPS after " .. retries .. " attempts")
end

-- Ensure we have at least 8 fuel in slot 1
local function ensureFuel()
    turtle.select(1)
    if turtle.getItemCount(1) >= 8 then
        return true
    end
    
    -- Save position and get fuel from chest
    local savedLoc = dig.location()
    dig.goto(1, 0, 0, 0)
    
    turtle.select(1)
    while turtle.getItemCount(1) < turtle.getItemSpace(1) do
        if not turtle.suckUp(1) then break end
    end
    
    dig.goto(savedLoc)
    return turtle.getItemCount(1) >= 8
end

local function deployWorker(slot, zone, zoneIndex)
    local detail = turtle.getItemDetail(slot)
    if not detail or not detail.name:find("turtle") then
        return false, "No turtle in slot " .. slot
    end
    
    if not ensureFuel() then
        return false, "Insufficient fuel"
    end
    
    print("Deploying worker " .. zoneIndex)
    dig.goto(zone.xmin, 0, 0, 180)
    
    -- Clear space and place turtle
    if turtle.detectDown() then turtle.digDown() end
    turtle.select(slot)
    if not turtle.placeDown() then
        return false, "Failed to place turtle"
    end
    
    -- Fuel and power on
    turtle.select(1)
    turtle.dropDown(8)
    
    local turtlePeripheral = peripheral.wrap("bottom")
    if turtlePeripheral and turtlePeripheral.turnOn then
        turtlePeripheral.turnOn()
    end
    
    return true
end

-- Main deployment sequence
local function deploy()
    print("=== Deployment Starting ===")
    
    -- Check if we're restarting from a previous deployment
    if loadState() then
        print("Found previous deployment state")
        print("Checking with server...")
        
        SERVER_CHANNEL = state.serverChannel
        modem.open(SERVER_CHANNEL)
        modem.open(BROADCAST_CHANNEL)
        
        -- Ping server to check status
        modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
            type = "deployer_restart",
            deployer_id = state.deployerID
        })
        
        -- Wait for server response
        local timeout = os.startTimer(10)
        while true do
            local event, p1, p2, p3, p4 = os.pullEvent()
            
            if event == "timer" and p1 == timeout then
                print("Server not responding, starting fresh deployment")
                state = {deployerID = os.getComputerID()}
                fs.delete(STATE_FILE)
                break
            elseif event == "modem_message" then
                local message = p4
                if message.type == "restart_response" and message.deployer_id == state.deployerID then
                    os.cancelTimer(timeout)
                    
                    if message.deployment_complete then
                        print("Deployment complete, transitioning to worker mode")
                        state.deploymentComplete = true
                        return
                    else
                        -- Deployment wasn't complete - either aborted or in progress
                        -- Since deployer state is not granular enough to resume mid-deployment,
                        -- we start fresh
                        print("Previous deployment incomplete, starting fresh")
                        state = {deployerID = os.getComputerID()}
                        fs.delete(STATE_FILE)
                        break
                    end
                end
            end
        end
    end
    
    state.startGPS = getGPS()
    print("GPS: " .. textutils.serialize(state.startGPS))
    
    print("\nEnter server channel ID:")
    SERVER_CHANNEL = tonumber(read())
    state.serverChannel = SERVER_CHANNEL
    modem.open(SERVER_CHANNEL)
    modem.open(BROADCAST_CHANNEL)
    
    -- Count turtles in slots 4-16
    local turtleSlots = {}
    for slot = 4, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name:find("turtle") then
            table.insert(turtleSlots, slot)
        end
    end
    
    if #turtleSlots == 0 then
        error("No turtles in slots 4-16")
    end
    
    print("Found " .. #turtleSlots .. " turtles")
    
    -- Get quarry parameters
    print("\nEnter quarry width:")
    local width = tonumber(read())
    print("Enter quarry length:")
    local length = tonumber(read())
    print("Enter quarry depth:")
    local depth = tonumber(read())
    print("Enter skip depth (0 for none):")
    local skip = tonumber(read())
    
    print("\nContacting server...")
    
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
            saveState()
            gotCommand = true
            print("Received zone assignments from server")
        end
    end
    
    -- Place chests at Y+1
    print("\nPlacing chests...")
    turtle.select(3)
    if not turtle.placeUp() then error("No output chest in slot 3") end
    
    state.chestPositions.output = {
        x = state.startGPS.x,
        y = state.startGPS.y + 1,
        z = state.startGPS.z
    }
    
    dig.goto(1, 0, 0, 90)
    turtle.select(2)
    if not turtle.placeUp() then error("No fuel chest in slot 2") end
    
    state.chestPositions.fuel = {
        x = state.startGPS.x + 1,
        y = state.startGPS.y + 1,
        z = state.startGPS.z
    }
    
    dig.goto(0, 0, 0, 0)
    modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
        type = "chest_positions",
        fuel_gps = state.chestPositions.fuel,
        output_gps = state.chestPositions.output,
        start_gps = state.startGPS
    })
    
    saveState()
    print("Chests placed")
    
    -- Wait for fuel
    print("\nWaiting for fuel in chest...")
    dig.goto(1, 0, 0, 0)
    turtle.select(1)
    while not turtle.suckUp(1) do sleep(1) end
    print("Fuel detected")
    
    dig.goto(0, 0, 0, 0)
    
    -- Deploy workers
    print("\n=== Deploying Workers ===")
    for i, slot in ipairs(turtleSlots) do
        local success, err = deployWorker(slot, state.zones[i], i)
        if not success then print("Warning: " .. err) end
    end
    
    -- Prepare deployer
    print("\n=== Preparing Deployer ===")
    if not ensureFuel() then
        dig.goto(1, 0, 0, 0)
        turtle.select(1)
        while turtle.getItemCount(1) < 64 do
            if not turtle.suckUp(1) then
                if turtle.getItemCount(1) >= 8 then break end
                sleep(1)
            end
        end
        dig.goto(0, 0, 0, 0)
    end
    
    -- Move to deployer's zone
    local deployerZone = state.zones[#state.zones]
    print("Moving to zone " .. #state.zones)
    dig.goto(deployerZone.xmin, -1, 0, 180)
    
    print("Notifying server...")
    modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
        type = "deployment_complete",
        deployer_id = state.deployerID
    })
    
    state.deploymentComplete = true
    saveState()
    
    print("\n=== Deployment Complete ===")
    print("Transitioning to worker mode...")
    sleep(1)
end

-- Run deployment
local success, err = pcall(deploy)

if not success then
    print("\nDeployment failed: " .. tostring(err))
    error(err)
end

-- Skip to worker mode if deployment was already complete
if state.deploymentComplete then
    print("Resuming from saved state...")
    
    -- Restore modem channels
    SERVER_CHANNEL = state.serverChannel
    modem.open(SERVER_CHANNEL)
    modem.open(BROADCAST_CHANNEL)
end

-- Become worker
if not fs.exists("bootstrap.lua") then
    error("bootstrap.lua not found")
end

shell.run("bootstrap.lua")

state.workerPhaseComplete = true
saveState()

-- Wait for cleanup command
print("\n=== Waiting for Cleanup Command ===")
modem.open(SERVER_CHANNEL)

while true do
    local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
    
    if type(message) == "table" and message.type == "cleanup_command" and message.turtle_id == state.deployerID then
        print("\n=== Collecting Workers ===")
        
        for i = 1, #state.zones - 1 do
            print("Collecting worker " .. i)
            dig.goto(state.zones[i].xmin, 0, 0, 0)
            
            local success, data = turtle.inspectDown()
            if success and data.name and data.name:find("turtle") then
                turtle.digDown()
            else
                print("Warning: No turtle at position")
            end
        end
        
        dig.goto(0, 0, 0, 0)
        print("\n=== Cleanup Complete ===")
        break
    end
end
