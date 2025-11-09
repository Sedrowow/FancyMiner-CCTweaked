-- Orchestration Server for Multi-Turtle Quarry System
-- Runs on a central computer to coordinate multiple mining turtles
-- Manages zone assignments, resource access queues, and worker lifecycle

local SERVER_CHANNEL = os.getComputerID()
local BROADCAST_CHANNEL = 65535

local state = {
    workers = {}, -- [turtle_id] = {zone, status, lastUpdate}
    fuelQueue = {},
    outputQueue = {},
    fuelLock = false,
    outputLock = false,
    readyCount = 0,
    totalWorkers = 0,
    deployerID = nil,
    quarryParams = nil,
    chestPositions = {
        fuel = nil,
        output = nil
    },
    miningStarted = false,
    completedCount = 0
}

local STATE_FILE = "orchestrate_state.cfg"

-- Initialize modem
local modem = peripheral.find("ender_modem")
if not modem then
    modem = peripheral.find("modem")
end

if not modem then
    error("No modem found! Server requires a modem to communicate.")
end

modem.open(SERVER_CHANNEL)
modem.open(BROADCAST_CHANNEL)

-- Initialize monitor if available
local monitor = nil
local useMonitor = false
local displayWidth, displayHeight

-- Try to find and set up a monitor
local monitors = {peripheral.find("monitor")}
if #monitors > 0 then
    monitor = monitors[1]
    monitor.setTextScale(0.5) -- Good for 2x2 advanced monitors
    monitor.clear()
    useMonitor = true
    displayWidth, displayHeight = monitor.getSize()
    print("Monitor detected: " .. displayWidth .. "x" .. displayHeight)
else
    displayWidth, displayHeight = term.getSize()
end

print("Orchestration Server Started")
print("Server Channel: " .. SERVER_CHANNEL)
print("Computer ID: " .. os.getComputerID())

-- Display functions
local function setColor(color)
    if useMonitor then
        monitor.setTextColor(color)
    else
        term.setTextColor(color)
    end
end

local function setCursorPos(x, y)
    if useMonitor then
        monitor.setCursorPos(x, y)
    else
        term.setCursorPos(x, y)
    end
end

local function clearDisplay()
    if useMonitor then
        monitor.clear()
    else
        term.clear()
    end
end

local function write(text)
    if useMonitor then
        monitor.write(text)
    else
        term.write(text)
    end
end

local function updateDisplay()
    clearDisplay()
    setCursorPos(1, 1)
    
    -- Header
    setColor(colors.white)
    write("=== Orchestration Server ===")
    setCursorPos(1, 2)
    write("Workers: " .. state.totalWorkers .. " | Ready: " .. state.readyCount)
    setCursorPos(1, 3)
    write("Complete: " .. state.completedCount)
    setCursorPos(1, 4)
    write("----------------------------")
    
    -- Worker status
    local line = 5
    local workerList = {}
    for id, worker in pairs(state.workers) do
        table.insert(workerList, {id = id, worker = worker})
    end
    
    -- Sort by ID for consistent display
    table.sort(workerList, function(a, b) return a.id < b.id end)
    
    for _, entry in ipairs(workerList) do
        if line >= displayHeight - 1 then break end
        
        local id = entry.id
        local worker = entry.worker
        
        setCursorPos(1, line)
        
        -- Status color coding
        if worker.status == "complete" then
            setColor(colors.lime)
        elseif worker.status == "mining" then
            setColor(colors.lightBlue)
        elseif worker.status == "queued" or worker.status == "accessing_resource" then
            setColor(colors.yellow)
        elseif worker.status == "ready" then
            setColor(colors.orange)
        else
            setColor(colors.lightGray)
        end
        
        -- Turtle ID
        write("T" .. id .. ": ")
        
        -- Status
        setColor(colors.white)
        if worker.status == "complete" then
            write("DONE")
        elseif worker.status == "mining" then
            write("Mining")
        elseif worker.status == "queued" then
            write("Queued")
        elseif worker.status == "accessing_resource" then
            write("Resource")
        elseif worker.status == "ready" then
            write("Ready")
        else
            write(worker.status or "Init")
        end
        
        -- Position and fuel if available
        if worker.position then
            setColor(colors.lightGray)
            setCursorPos(20, line)
            write(string.format("Y:%d", worker.position.y or 0))
        end
        
        if worker.fuel then
            setColor(colors.orange)
            setCursorPos(30, line)
            write(string.format("F:%d", worker.fuel))
        end
        
        line = line + 1
    end
    
    -- Queue status at bottom
    if line < displayHeight - 2 then
        setCursorPos(1, displayHeight - 2)
        setColor(colors.white)
        write("Queues - Fuel: " .. #state.fuelQueue .. " | Output: " .. #state.outputQueue)
    end
    
    -- Status line at very bottom
    setCursorPos(1, displayHeight)
    setColor(colors.lightGray)
    if state.miningStarted then
        write("Status: Mining Active")
    else
        write("Status: Waiting...")
    end
end

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

-- Calculate zone assignments based on quarry dimensions
local function calculateZones(width, length, depth, skip, numWorkers)
    local zones = {}
    local baseWidth = math.floor(width / numWorkers)
    
    for i = 1, numWorkers do
        local xmin = (i - 1) * baseWidth
        local xmax = xmin + baseWidth - 1
        
        -- Last worker gets any remainder
        if i == numWorkers then
            xmax = width - 1
        end
        
        zones[i] = {
            xmin = xmin,
            xmax = xmax,
            zmin = 0,
            zmax = length - 1,
            ymin = -depth,
            ymax = 0,
            skip = skip or 0
        }
    end
    
    return zones
end

-- Grant resource access to next turtle in queue
local function grantNextResource(resourceType)
    local queue = (resourceType == "fuel") and state.fuelQueue or state.outputQueue
    local lockKey = (resourceType == "fuel") and "fuelLock" or "outputLock"
    
    if #queue > 0 and not state[lockKey] then
        local nextTurtle = table.remove(queue, 1)
        state[lockKey] = nextTurtle
        
        local chestPos = state.chestPositions[resourceType]
        local approachDir = (resourceType == "output") and "south" or "north"
        
        modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
            type = "resource_granted",
            turtle_id = nextTurtle,
            resource = resourceType,
            chest_gps = chestPos,
            approach_direction = approachDir
        })
        
        print("Granted " .. resourceType .. " access to turtle " .. nextTurtle)
        saveState()
    end
end

-- Handle incoming messages
local function handleMessage(message)
    if type(message) ~= "table" then return end
    
    if message.type == "deploy_request" then
        -- Client requesting deployment parameters
        state.deployerID = message.deployer_id
        state.totalWorkers = message.num_workers
        state.quarryParams = message.quarry_params
        
        local zones = calculateZones(
            message.quarry_params.width,
            message.quarry_params.length,
            message.quarry_params.depth,
            message.quarry_params.skip,
            message.num_workers
        )
        
        modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
            type = "deploy_command",
            deployer_id = message.deployer_id,
            num_workers = message.num_workers,
            server_channel = SERVER_CHANNEL,
            zones = zones,
            quarry = message.quarry_params
        })
        
        print("Deployment initiated for " .. message.num_workers .. " workers")
        saveState()
        updateDisplay()
        
    elseif message.type == "chest_positions" then
        -- Deployer reporting chest locations
        state.chestPositions.fuel = message.fuel_gps
        state.chestPositions.output = message.output_gps
        print("Chest positions registered")
        print("Fuel: " .. textutils.serialize(message.fuel_gps))
        print("Output: " .. textutils.serialize(message.output_gps))
        saveState()
        updateDisplay()
        
    elseif message.type == "worker_ready" then
        -- Worker finished initialization
        state.readyCount = state.readyCount + 1
        if state.workers[message.turtle_id] then
            state.workers[message.turtle_id].status = "ready"
        end
        
        print("Worker " .. message.turtle_id .. " ready (" .. state.readyCount .. "/" .. state.totalWorkers .. ")")
        
        -- Start mining when all workers ready
        if state.readyCount == state.totalWorkers and not state.miningStarted then
            state.miningStarted = true
            modem.transmit(BROADCAST_CHANNEL, SERVER_CHANNEL, {
                type = "start_mining"
            })
            print("All workers ready - mining started!")
        end
        saveState()
        updateDisplay()
        
    elseif message.type == "resource_request" then
        -- Turtle requesting access to fuel or output chest
        local resourceType = message.resource
        local queue = (resourceType == "fuel") and state.fuelQueue or state.outputQueue
        local lockKey = (resourceType == "fuel") and "fuelLock" or "outputLock"
        
        if not state[lockKey] then
            -- Resource available, grant immediately
            state[lockKey] = message.turtle_id
            
            local chestPos = state.chestPositions[resourceType]
            local approachDir = (resourceType == "output") and "south" or "north"
            
            modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
                type = "resource_granted",
                turtle_id = message.turtle_id,
                resource = resourceType,
                chest_gps = chestPos,
                approach_direction = approachDir
            })
            
            print("Granted " .. resourceType .. " access to turtle " .. message.turtle_id)
        else
            -- Resource in use, add to queue
            table.insert(queue, message.turtle_id)
            
            modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
                type = "queue_position",
                turtle_id = message.turtle_id,
                resource = resourceType,
                position = #queue
            })
            
            print("Queued turtle " .. message.turtle_id .. " for " .. resourceType .. " (position " .. #queue .. ")")
        end
        
        if state.workers[message.turtle_id] then
            state.workers[message.turtle_id].status = "queued"
        end
        saveState()
        updateDisplay()
        
    elseif message.type == "resource_released" then
        -- Turtle finished with resource
        local resourceType = message.resource
        local lockKey = (resourceType == "fuel") and "fuelLock" or "outputLock"
        
        state[lockKey] = false
        
        if state.workers[message.turtle_id] then
            state.workers[message.turtle_id].status = "mining"
        end
        
        print("Turtle " .. message.turtle_id .. " released " .. resourceType)
        
        -- Grant access to next in queue
        grantNextResource(resourceType)
        saveState()
        updateDisplay()
        
    elseif message.type == "zone_complete" then
        -- Worker finished mining assigned zone
        state.completedCount = state.completedCount + 1
        
        if state.workers[message.turtle_id] then
            state.workers[message.turtle_id].status = "complete"
            state.workers[message.turtle_id].final_pos = message.final_pos
        end
        
        print("Turtle " .. message.turtle_id .. " completed zone (" .. state.completedCount .. "/" .. state.totalWorkers .. ")")
        
        -- All zones complete, initiate cleanup
        if state.completedCount == state.totalWorkers then
            modem.transmit(BROADCAST_CHANNEL, SERVER_CHANNEL, {
                type = "all_complete"
            })
            
            if state.deployerID then
                modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
                    type = "cleanup_command",
                    turtle_id = state.deployerID,
                    workers = state.workers
                })
            end
            
            print("All zones complete! Cleanup initiated.")
        end
        saveState()
        updateDisplay()
        
    elseif message.type == "status_update" then
        -- Worker status update
        if not state.workers[message.turtle_id] then
            state.workers[message.turtle_id] = {}
        end
        
        state.workers[message.turtle_id].lastUpdate = os.clock()
        state.workers[message.turtle_id].position = message.position
        state.workers[message.turtle_id].fuel = message.fuel
        state.workers[message.turtle_id].status = message.status
        updateDisplay()
        
    elseif message.type == "worker_registered" then
        -- Deployer registered a new worker
        if not state.workers[message.turtle_id] then
            state.workers[message.turtle_id] = {
                zone = message.zone,
                gps_zone = message.gps_zone,
                status = "initializing",
                lastUpdate = os.clock(),
                position = nil,
                fuel = nil
            }
            print("Worker " .. message.turtle_id .. " registered")
            saveState()
            updateDisplay()
        end
        
    elseif message.type == "deployment_complete" then
        -- Deployer finished placing all workers
        print("Deployment complete - waiting for workers to initialize")
        saveState()
        updateDisplay()
    end
end

-- Main server loop
local function main()
    print("\n=== Orchestration Server Ready ===")
    print("Waiting for deployment requests...")
    print("Press Ctrl+T to stop\n")
    
    -- Try to load previous state
    if loadState() then
        print("Previous state loaded from disk")
    end
    
    -- Initial display
    updateDisplay()
    
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent()
        
        if event == "modem_message" then
            handleMessage(message)
        end
    end
end

-- Run server
local success, err = pcall(main)
if not success then
    print("Server error: " .. tostring(err))
    saveState()
end
