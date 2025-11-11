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
    
    -- Send deployment request to server
    local numWorkers = #turtleSlots + 1  -- +1 for deployer itself
    communication.sendDeployRequest(modem, SERVER_CHANNEL, state.deployerID, numWorkers, quarryParams)
    
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
    
    -- Deploy all worker turtles
    print("\n=== Deploying Workers ===")
    local successCount, failCount = workerDeploy.deployAll(turtleSlots, state.zones, dig)
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

-- Wait for cleanup command from server
communication.waitForCleanupCommand(modem, SERVER_CHANNEL, state.deployerID)

-- Collect all deployed workers
print("\n=== Collecting Workers ===")
local collectedCount = workerDeploy.collectWorkers(state.zones, dig)
print(string.format("Collected %d workers", collectedCount))
print("\n=== Cleanup Complete ===")
