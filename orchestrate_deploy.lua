-- Deployment Turtle for Multi-Turtle Quarry System
-- Deploys worker turtles, transfers firmware from floppy disk
-- Then becomes a worker itself after deployment

os.loadAPI("dig.lua")
os.loadAPI("flex.lua")

-- Load deployment modules
local stateModule = require("deploy.state")
local positioning = require("deploy.positioning")
local workerDeploy = require("deploy.worker_deployment")
local chestManager = require("deploy.chest_manager")
local communication = require("deploy.communication")

local SERVER_CHANNEL = nil

-- Initialize state
local state = stateModule.create()

print("Deployment Turtle Initialized")
print("Turtle ID: " .. state.deployerID)

-- Initialize modem
local modem, err = communication.initModem()
if not modem then
    error(err)
end

-- Main deployment sequence
local function deploy()
    print("=== Deployment Starting ===")
    
    -- Check if we're restarting from a previous deployment
    local savedState = stateModule.load()
    if savedState then
        print("Found previous deployment state")
        state = savedState
        SERVER_CHANNEL = state.serverChannel
        
        -- Reinitialize modem with saved server channel
        modem = communication.initModem(SERVER_CHANNEL)
        
        local shouldContinue, deploymentComplete, err = 
            communication.checkPreviousDeployment(modem, SERVER_CHANNEL, state.deployerID, 10)
        
        if shouldContinue and deploymentComplete then
            print("Deployment complete, transitioning to worker mode")
            state.deploymentComplete = true
            return
        else
            print(err or "Previous deployment incomplete, starting fresh")
            state = stateModule.create()
            stateModule.clear()
        end
    end
    
    -- Get GPS coordinates
    local gps, err = positioning.getGPS()
    if not gps then
        error(err)
    end
    state.startGPS = gps
    print("GPS: " .. positioning.formatGPS(state.startGPS))
    
    -- Get server channel and initialize communication
    SERVER_CHANNEL = communication.getServerChannel()
    state.serverChannel = SERVER_CHANNEL
    modem = communication.initModem(SERVER_CHANNEL)
    
    -- Count available turtles
    local turtleSlots = workerDeploy.findTurtleSlots()
    if #turtleSlots == 0 then
        error("No turtles in slots 4-16")
    end
    print("Found " .. #turtleSlots .. " turtles")
    
    -- Get quarry parameters from user
    local quarryParams = communication.getQuarryParams()
    
    -- Optional: get deployer facing from user to override chest-derived direction
    print("Enter deployer facing (N/E/S/W) or press Enter for auto (by chests):")
    local facingInput = read()
    local deployerFacing = nil
    if facingInput and #facingInput > 0 then
        local inp = string.lower((facingInput or ""):gsub("%s+",""))
        local map = { n = "north", e = "east", s = "south", w = "west",
                      north = "north", east = "east", south = "south", west = "west" }
        deployerFacing = map[inp]
        if deployerFacing then
            print("Using deployer facing override: " .. deployerFacing)
        else
            print("Invalid facing input; continuing with auto-detected by chests")
        end
    end
    
    -- Send deployment request to server
    local numWorkers = #turtleSlots + 1  -- +1 for deployer itself
    communication.sendDeployRequest(modem, SERVER_CHANNEL, state.deployerID, numWorkers, quarryParams, deployerFacing)
    
    -- Wait for zone assignments from server
    local zones, numWorkers, serverChannel = communication.waitForDeployCommand(modem)
    if not zones then
        error(numWorkers)  -- numWorkers contains error message in this case
    end
    
    state.zones = zones
    state.numWorkers = numWorkers
    state.serverChannel = serverChannel
    SERVER_CHANNEL = serverChannel
    stateModule.save(state)
    
    -- Place fuel and output chests
    local chestPositions, err = chestManager.placeChests(state.startGPS, dig)
    if not chestPositions then
        error(err)
    end
    
    state.chestPositions = chestPositions
    stateModule.save(state)
    print("Chests placed")
    
    -- Notify server of chest positions
    communication.sendChestPositions(modem, SERVER_CHANNEL, 
        chestPositions.fuel, chestPositions.output, state.startGPS)
    
    -- Wait for fuel to be added to the fuel chest
    chestManager.waitForFuel(dig)
    
    -- Compute desired facing (same rule as server):
    -- If user provided facing override earlier, use it; otherwise one-left of chest-derived direction
    local function calculateInitialDirection(fuelGPS, outputGPS)
        local dx = fuelGPS.x - outputGPS.x
        local dz = fuelGPS.z - outputGPS.z
        if math.abs(dx) > math.abs(dz) then
            return (dx > 0) and "east" or "west"
        else
            return (dz > 0) and "south" or "north"
        end
    end
    local initialDir = calculateInitialDirection(chestPositions.fuel, chestPositions.output)
    local desiredFacing = nil
    if state.deployerFacing then
        desiredFacing = state.deployerFacing
    else
        local rotateLeft = { north = "west", west = "south", south = "east", east = "north" }
        desiredFacing = rotateLeft[initialDir] or initialDir
    end

    -- Deploy all worker turtles
    print("\n=== Deploying Workers ===")
    local successCount, failCount = workerDeploy.deployAll(turtleSlots, state.zones, dig, desiredFacing)
    print(string.format("Deployed %d workers (%d failed)", successCount, failCount))
    
    -- Prepare deployer turtle with fuel
    print("\n=== Preparing Deployer ===")
    if not chestManager.ensureDeployerFuel(dig, 8) then
        error("Failed to get sufficient fuel for deployer")
    end
    
    -- Move deployer to its assigned zone
    local deployerZone = state.zones[#state.zones]
    print("Moving to zone " .. #state.zones)
    dig.goto(deployerZone.xmin, -1, 0, 180)
    
    -- Notify server that deployment is complete
    communication.sendDeploymentComplete(modem, SERVER_CHANNEL, state.deployerID)
    
    state.deploymentComplete = true
    stateModule.save(state)
    
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
    SERVER_CHANNEL = state.serverChannel
    modem = communication.initModem(SERVER_CHANNEL)
end

-- Transition to worker mode
if not fs.exists("bootstrap.lua") then
    error("bootstrap.lua not found")
end

shell.run("bootstrap.lua")

state.workerPhaseComplete = true
stateModule.save(state)

-- Wait for cleanup command or abort from server
local waitResult = communication.waitForCleanupCommand(modem, SERVER_CHANNEL, state.deployerID)

if waitResult == "abort" then
    print("\n=== Abort Received - Collecting Workers Early ===")
end

-- Collect all deployed workers
print("\n=== Collecting Workers ===")
local collectedCount = workerDeploy.collectWorkers(state.zones, dig)
print(string.format("Collected %d workers", collectedCount))
print("\n=== Cleanup Complete ===")
