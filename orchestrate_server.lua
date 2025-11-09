-- Orchestration Server for Multi-Turtle Quarry System
-- Runs on a central computer to coordinate multiple mining turtles
-- Manages zone assignments, resource access queues, worker lifecycle, and firmware distribution

local SERVER_CHANNEL = os.getComputerID()
local BROADCAST_CHANNEL = 65535
local CHUNK_SIZE = 32768 -- 32KB chunks for file transfer

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
    completedCount = 0,
    aborted = false,
    abortAckCount = 0,
    firmwareCache = nil, -- Cached firmware files
    firmwareRequests = {}, -- Track which workers requested firmware
    zones = nil, -- Zone definitions (relative coordinates)
    gpsZones = nil, -- GPS zones with assignment tracking
    isDeployerWorker = false -- Whether deployer participates as worker
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
    if state.aborted then
        setColor(colors.red)
        write("Status: ABORTED - Workers Returning")
    elseif state.miningStarted then
        setColor(colors.lightGray)
        write("Status: Mining Active (Q=Abort)")
    else
        setColor(colors.lightGray)
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

-- Check for floppy disk and required firmware files
local function checkDisk()
    local drive = peripheral.find("drive")
    if not drive then
        error("No disk drive found! Server requires a floppy disk with firmware.")
    end
    
    if not drive.isDiskPresent() then
        error("No disk in drive! Insert disk with worker firmware.")
    end
    
    local diskPath = drive.getMountPath()
    local requiredFiles = {
        diskPath .. "/worker/quarry.lua",
        diskPath .. "/worker/dig.lua",
        diskPath .. "/worker/flex.lua"
    }
    
    for _, file in ipairs(requiredFiles) do
        if not fs.exists(file) then
            error("Missing required file: " .. file)
        end
    end
    
    print("Disk check passed - all firmware files found")
    return diskPath
end

-- Read file from disk
local function readDiskFile(diskPath, filename)
    local fullPath = diskPath .. "/worker/" .. filename
    local file = fs.open(fullPath, "r")
    if not file then
        error("Failed to open " .. fullPath)
    end
    local content = file.readAll()
    file.close()
    return content
end

-- Split content into chunks for transmission
local function createChunks(content)
    local chunks = {}
    local pos = 1
    while pos <= #content do
        table.insert(chunks, content:sub(pos, pos + CHUNK_SIZE - 1))
        pos = pos + CHUNK_SIZE
    end
    return chunks
end

-- Load firmware into cache
local function loadFirmware(diskPath)
    print("\nLoading firmware files into cache...")
    
    state.firmwareCache = {
        ["quarry.lua"] = readDiskFile(diskPath, "quarry.lua"),
        ["dig.lua"] = readDiskFile(diskPath, "dig.lua"),
        ["flex.lua"] = readDiskFile(diskPath, "flex.lua")
    }
    
    print("Firmware cached and ready for distribution")
end

-- Send firmware to a specific worker
local function sendFirmwareToWorker(turtleID)
    if not state.firmwareCache then
        print("Error: Firmware not loaded!")
        return
    end
    
    print("Sending firmware to turtle " .. turtleID .. "...")
    
    for filename, content in pairs(state.firmwareCache) do
        print("  Sending " .. filename .. "...")
        local chunks = createChunks(content)
        
        for i, chunk in ipairs(chunks) do
            modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
                type = "file_chunk",
                turtle_id = turtleID,
                filename = filename,
                chunk_num = i,
                total_chunks = #chunks,
                data = chunk
            })
            sleep(0.05) -- Small delay between chunks
        end
    end
    
    print("Firmware sent to turtle " .. turtleID)
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
        -- Both chests are at Y=1, workers access from below at Y=0
        local approachDir = "down"
        
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
    if type(message) ~= "table" then 
        print("DEBUG: Received non-table message, type: " .. type(message))
        print("DEBUG: Content: " .. tostring(message))
        return 
    end
    
    print("DEBUG: Received message type: " .. tostring(message.type))
    
    if message.type == "deploy_request" then
        print("DEBUG: Processing deploy_request from deployer " .. message.deployer_id)
        -- Client requesting deployment parameters
        state.deployerID = message.deployer_id
        state.totalWorkers = message.num_workers
        state.quarryParams = message.quarry_params
        state.isDeployerWorker = message.is_deployer or false
        
        local zones = calculateZones(
            message.quarry_params.width,
            message.quarry_params.length,
            message.quarry_params.depth,
            message.quarry_params.skip,
            message.num_workers
        )
        
        -- Store zones with GPS boundaries (will be calculated after chest placement)
        state.zones = zones
        
        modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
            type = "deploy_command",
            deployer_id = message.deployer_id,
            num_workers = message.num_workers,
            server_channel = SERVER_CHANNEL,
            zones = zones,
            quarry = message.quarry_params
        })
        
        print("Deployment initiated for " .. message.num_workers .. " workers")
        print("Calculated " .. #zones .. " zones")
        saveState()
        updateDisplay()
        
    elseif message.type == "chest_positions" then
        -- Deployer reporting chest locations and starting GPS
        state.chestPositions.fuel = message.fuel_gps
        state.chestPositions.output = message.output_gps
        local startGPS = message.start_gps
        
        print("Chest positions registered")
        print("Fuel: " .. textutils.serialize(message.fuel_gps))
        print("Output: " .. textutils.serialize(message.output_gps))
        print("Start: " .. textutils.serialize(startGPS))
        
        -- Calculate GPS zones from relative zones
        state.gpsZones = {}
        for i, zone in ipairs(state.zones) do
            state.gpsZones[i] = {
                gps_xmin = startGPS.x + zone.xmin,
                gps_xmax = startGPS.x + zone.xmax,
                gps_zmin = startGPS.z + zone.zmin,
                gps_zmax = startGPS.z + zone.zmax,
                gps_ymin = startGPS.y + zone.ymin,
                gps_ymax = startGPS.y + zone.ymax,
                assigned = false
            }
        end
        print("GPS zones calculated")
        
        saveState()
        updateDisplay()
        
        -- Load firmware into cache (ready for worker requests)
        local diskPath = checkDisk()
        loadFirmware(diskPath)
        
    elseif message.type == "worker_online" then
        -- Worker broadcasting that it's online and ready
        local turtleID = message.turtle_id
        local currentTime = os.clock()
        local lastRequest = state.firmwareRequests[turtleID] or 0
        
        -- Only respond if we have firmware loaded and haven't sent recently (allow re-send after 30 seconds)
        if state.firmwareCache and (currentTime - lastRequest) > 30 then
            print("Worker " .. turtleID .. " online, sending server info...")
            
            -- Send server channel response
            modem.transmit(BROADCAST_CHANNEL, SERVER_CHANNEL, {
                type = "server_response",
                turtle_id = turtleID,
                server_channel = SERVER_CHANNEL
            })
            
            -- Mark when we sent firmware to this worker
            state.firmwareRequests[turtleID] = currentTime
            
            -- Send firmware after a brief delay
            sleep(0.5)
            sendFirmwareToWorker(turtleID)
        end
        
    elseif message.type == "file_received" then
        -- Worker acknowledged receiving a file
        print("Turtle " .. message.turtle_id .. " received " .. message.filename)
        
    elseif message.type == "firmware_complete" then
        -- Worker has all firmware files, match to zone by GPS position
        local turtleID = message.turtle_id
        local workerGPS = message.gps_position
        
        if not workerGPS then
            print("Error: Turtle " .. turtleID .. " did not provide GPS position")
            return
        end
        
        print("Turtle " .. turtleID .. " at GPS (" .. workerGPS.x .. ", " .. workerGPS.y .. ", " .. workerGPS.z .. "), finding matching zone...")
        
        -- Find zone that contains this worker's GPS position
        if state.zones and state.gpsZones then
            local matchedZone = nil
            
            for i = 1, #state.gpsZones do
                local gpsZone = state.gpsZones[i]
                
                -- Check if worker's position is within this zone's boundaries
                if workerGPS.x >= gpsZone.gps_xmin and workerGPS.x <= gpsZone.gps_xmax and
                   workerGPS.z >= gpsZone.gps_zmin and workerGPS.z <= gpsZone.gps_zmax then
                    
                    if gpsZone.assigned then
                        print("  Warning: Zone " .. i .. " already assigned to turtle " .. gpsZone.turtle_id)
                        print("  Multiple workers in same zone!")
                    end
                    
                    -- Assign this zone to this turtle
                    gpsZone.assigned = true
                    gpsZone.turtle_id = turtleID
                    matchedZone = i
                    
                    -- Send zone assignment
                    modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
                        type = "zone_assignment",
                        turtle_id = turtleID,
                        zone_index = i,
                        zone = state.zones[i],
                        gps_zone = gpsZone,
                        server_channel = SERVER_CHANNEL
                    })
                    
                    print("  Matched to zone " .. i .. " (X: " .. state.zones[i].xmin .. "-" .. state.zones[i].xmax .. ")")
                    saveState()
                    break
                end
            end
            
            if not matchedZone then
                print("  Error: No zone found containing position (" .. workerGPS.x .. ", " .. workerGPS.z .. ")")
                print("  Worker is outside quarry boundaries!")
            end
        end
        
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
            local approachDir = (resourceType == "output") and "down" or "west"
            
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
        local turtleID = message.turtle_id
        
        if state.workers[turtleID] then
            state.workers[turtleID].status = "complete"
            state.workers[turtleID].final_pos = message.final_pos
        end
        
        print("Turtle " .. turtleID .. " completed zone (" .. state.completedCount .. "/" .. state.totalWorkers .. ")")
        
        if turtleID == state.deployerID then
            print("  (Deployer)")
        end
        
        -- All zones complete, initiate cleanup
        if state.completedCount == state.totalWorkers then
            print("\n=== All zones complete! ===")
            
            -- Send cleanup command to deployer
            if state.deployerID then
                print("Sending cleanup command to deployer...")
                modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
                    type = "cleanup_command",
                    turtle_id = state.deployerID
                })
            end
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
        
    elseif message.type == "deployment_complete" then
        -- Deployer finished placing all workers
        print("Deployment complete - all workers placed")
        print("Waiting for workers to come online and download firmware...")
        saveState()
        updateDisplay()
        
    elseif message.type == "abort_ack" then
        -- Worker acknowledged abort command
        state.abortAckCount = state.abortAckCount + 1
        if state.workers[message.turtle_id] then
            state.workers[message.turtle_id].status = "aborted"
        end
        print("Worker " .. message.turtle_id .. " acknowledged abort (" .. state.abortAckCount .. "/" .. state.totalWorkers .. ")")
        saveState()
        updateDisplay()
        
        -- All workers acknowledged
        if state.abortAckCount >= state.totalWorkers then
            print("\n=== All workers have aborted ===")
            print("Workers returned to starting positions")
            print("System halted. Restart server to begin new operation.")
        end
    end
end

-- Main server loop
local function main()
    print("\n=== Orchestration Server Ready ===")
    print("Waiting for deployment requests...")
    print("Press 'Q' to abort operation")
    print("Press Ctrl+T to stop\n")
    
    -- Try to load previous state
    if loadState() then
        print("Previous state loaded from disk")
    end
    
    -- Initial display
    updateDisplay()
    
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "modem_message" then
            -- p1=side, p2=channel, p3=replyChannel, p4=message, p5=distance
            local side, channel, replyChannel, message, distance = p1, p2, p3, p4, p5
            print("DEBUG: Modem message on channel " .. channel .. " from " .. replyChannel)
            print("DEBUG: Message type: " .. type(message))
            if type(message) == "table" then
                print("DEBUG: Message.type: " .. tostring(message.type))
            end
            handleMessage(message)
            
        elseif event == "key" then
            local key = p1
            -- Q key = 16
            if key == keys.q and state.miningStarted and not state.aborted then
                print("\n=== ABORT INITIATED ===")
                print("Sending abort command to all workers...")
                
                state.aborted = true
                state.abortAckCount = 0
                
                -- Broadcast abort command
                modem.transmit(BROADCAST_CHANNEL, SERVER_CHANNEL, {
                    type = "abort_mining"
                })
                
                print("Abort command sent. Waiting for workers to return...")
                saveState()
                updateDisplay()
            end
        end
    end
end

-- Run server
local success, err = pcall(main)
if not success then
    print("Server error: " .. tostring(err))
    saveState()
end
