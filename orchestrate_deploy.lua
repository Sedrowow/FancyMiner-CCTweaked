-- Deployment Turtle for Multi-Turtle Quarry System
-- Deploys worker turtles, transfers firmware from floppy disk
-- Then becomes a worker itself after deployment

os.loadAPI("dig.lua")
os.loadAPI("flex.lua")

local SERVER_CHANNEL = nil
local BROADCAST_CHANNEL = 65535
local CHUNK_SIZE = 32768 -- 32KB chunks for file transfer

local state = {
    deployerID = os.getComputerID(),
    startGPS = nil,
    zones = {},
    numWorkers = 0,
    chestPositions = {
        fuel = nil,
        output = nil
    },
    deployedWorkers = {},
    myZone = nil,
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

-- Check for floppy disk and required files
local function checkDisk()
    local drive = peripheral.find("drive")
    if not drive then
        error("No disk drive found! Deployer requires a floppy disk with firmware.")
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

-- Split content into chunks
local function createChunks(content)
    local chunks = {}
    local pos = 1
    while pos <= #content do
        table.insert(chunks, content:sub(pos, pos + CHUNK_SIZE - 1))
        pos = pos + CHUNK_SIZE
    end
    return chunks
end

-- Send file to worker turtle via modem
local function transferFile(turtleID, filename, content)
    local chunks = createChunks(content)
    local totalChunks = #chunks
    
    print("Transferring " .. filename .. " to turtle " .. turtleID .. " (" .. totalChunks .. " chunks)")
    
    for i, chunk in ipairs(chunks) do
        modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
            type = "file_chunk",
            turtle_id = turtleID,
            filename = filename,
            chunk_num = i,
            total_chunks = totalChunks,
            data = chunk
        })
        
        -- Small delay between chunks
        sleep(0.1)
    end
    
    -- Wait for acknowledgment with timeout
    local timeout = os.startTimer(30)
    local ackReceived = false
    
    while not ackReceived do
        local event, p1, p2, p3, message = os.pullEvent()
        
        if event == "timer" and p1 == timeout then
            return false, "Timeout waiting for acknowledgment"
        elseif event == "modem_message" then
            if type(message) == "table" and 
               message.type == "file_received" and 
               message.turtle_id == turtleID and 
               message.filename == filename then
                ackReceived = true
                os.cancelTimer(timeout)
            end
        end
    end
    
    return true
end

-- Bootstrap code to inject into workers
local BOOTSTRAP_CODE = [[
-- Bootstrap loader for worker turtles
local BROADCAST_CHANNEL = 65535
local turtleID = os.getComputerID()
print("Worker Bootstrap - ID: " .. turtleID)
print("Waiting for firmware...")
local modem = peripheral.find("ender_modem")
if not modem then modem = peripheral.find("modem") end
if not modem then error("No modem found!") end
modem.open(BROADCAST_CHANNEL)
local fileChunks = {}
local filesReceived = {}
local requiredFiles = {"quarry.lua", "dig.lua", "flex.lua"}
local function checkAllFilesReceived()
    for _, filename in ipairs(requiredFiles) do
        if not filesReceived[filename] then return false end
    end
    return true
end
while true do
    local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
    if type(message) == "table" and message.type == "file_chunk_broadcast" then
        local filename = message.filename
        local isRequired = false
        for _, req in ipairs(requiredFiles) do
            if req == filename then isRequired = true; break end
        end
        if isRequired then
            if not fileChunks[filename] then
                fileChunks[filename] = {}
                print("Receiving " .. filename .. "...")
            end
            fileChunks[filename][message.chunk_num] = message.data
            local complete = true
            for i = 1, message.total_chunks do
                if not fileChunks[filename][i] then complete = false; break end
            end
            if complete and not filesReceived[filename] then
                local content = table.concat(fileChunks[filename])
                local file = fs.open(filename, "w")
                file.write(content)
                file.close()
                filesReceived[filename] = true
                print("Received: " .. filename)
                if checkAllFilesReceived() then
                    print("All firmware received!")
                    break
                end
            end
        end
    end
end
print("Loading APIs...")
os.loadAPI("dig.lua")
os.loadAPI("flex.lua")
print("Starting worker quarry program...")
shell.run("quarry.lua")
]]

-- Deploy a single worker turtle
local function deployWorker(slot, zone, zoneIndex)
    -- Check if slot contains a turtle
    local detail = turtle.getItemDetail(slot)
    if not detail or not detail.name:find("turtle") then
        return false, "No turtle in slot " .. slot
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
    
    -- Inject bootstrap code via disk drive (if available) or direct transfer
    -- Since we can't directly write to the turtle's filesystem, we'll use a different approach:
    -- The worker will receive the bootstrap via modem first
    
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
    
    -- Check for firmware disk
    local diskPath = checkDisk()
    
    -- Request deployment parameters from server
    print("\nRequesting deployment parameters from server...")
    print("Enter server channel ID:")
    SERVER_CHANNEL = tonumber(read())
    
    modem.open(SERVER_CHANNEL)
    modem.open(BROADCAST_CHANNEL)
    
    -- Count available turtles
    local turtleSlots = {}
    for slot = 3, 16 do
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
    
    -- Send deployment request to server
    modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
        type = "deploy_request",
        deployer_id = state.deployerID,
        num_workers = #turtleSlots,
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
    
    -- Place output chest behind starting position
    print("\nPlacing output chest...")
    dig.gotor(180) -- Face backward
    turtle.select(1) -- Chest should be in slot 1
    if not turtle.place() then
        error("Failed to place output chest - ensure chest is in slot 1")
    end
    
    local outputGPS = {
        x = state.startGPS.x,
        y = state.startGPS.y,
        z = state.startGPS.z - 1
    }
    state.chestPositions.output = outputGPS
    
    -- Place fuel chest to the side
    print("Placing fuel chest...")
    dig.gotor(90) -- Face right
    turtle.select(2) -- Chest should be in slot 2
    if not turtle.place() then
        error("Failed to place fuel chest - ensure chest is in slot 2")
    end
    
    local fuelGPS = {
        x = state.startGPS.x + 1,
        y = state.startGPS.y,
        z = state.startGPS.z
    }
    state.chestPositions.fuel = fuelGPS
    
    -- Report chest positions to server
    dig.gotor(0) -- Face forward
    modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
        type = "chest_positions",
        fuel_gps = fuelGPS,
        output_gps = outputGPS
    })
    
    print("Chests placed and registered with server")
    
    -- Load firmware from disk
    print("\nLoading firmware from disk...")
    local firmware = {
        ["quarry.lua"] = readDiskFile(diskPath, "quarry.lua"),
        ["dig.lua"] = readDiskFile(diskPath, "dig.lua"),
        ["flex.lua"] = readDiskFile(diskPath, "flex.lua")
    }
    print("Firmware loaded successfully")
    
    -- Deploy each worker turtle
    print("\n=== Deploying Workers ===\n")
    
    for i, slot in ipairs(turtleSlots) do
        local zone = state.zones[i]
        print("\nDeploying worker " .. i .. "/" .. #turtleSlots)
        print("Zone: X=" .. zone.xmin .. "-" .. zone.xmax .. ", Z=" .. zone.zmin .. "-" .. zone.zmax)
        
        local success, err = deployWorker(slot, zone, i)
        if not success then
            print("Warning: " .. err)
        else
            -- Note: We'll handle file transfer after getting worker ID via handshake
            table.insert(state.deployedWorkers, {
                slot = slot,
                zone = zone,
                gps_zone = calculateGPSZone(zone, state.startGPS),
                index = i
            })
        end
    end
    
    -- Wait a moment for workers to boot
    print("\nWaiting for workers to initialize...")
    sleep(2)
    
    -- Broadcast firmware to all deployed workers
    -- Workers will identify themselves and request their specific zone assignment
    print("\nBroadcasting firmware files...")
    
    for i, worker in ipairs(state.deployedWorkers) do
        -- Broadcast zone info so worker can identify if it's theirs
        local zoneMsg = {
            type = "zone_assignment",
            zone_index = i,
            zone = worker.zone,
            gps_zone = worker.gps_zone,
            chest_gps = {
                fuel = {
                    x = fuelGPS.x,
                    y = fuelGPS.y,
                    z = fuelGPS.z,
                    approach = "north"
                },
                output = {
                    x = outputGPS.x,
                    y = outputGPS.y,
                    z = outputGPS.z,
                    approach = "south"
                }
            },
            server_channel = SERVER_CHANNEL
        }
        
        modem.transmit(BROADCAST_CHANNEL, SERVER_CHANNEL, zoneMsg)
        sleep(0.5)
    end
    
    -- Broadcast firmware files
    for filename, content in pairs(firmware) do
        print("Broadcasting " .. filename .. "...")
        local chunks = createChunks(content)
        
        for i, chunk in ipairs(chunks) do
            modem.transmit(BROADCAST_CHANNEL, SERVER_CHANNEL, {
                type = "file_chunk_broadcast",
                filename = filename,
                chunk_num = i,
                total_chunks = #chunks,
                data = chunk
            })
            sleep(0.1)
        end
    end
    
    -- Notify server that deployment is complete
    modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
        type = "deployment_complete",
        deployer_id = state.deployerID
    })
    
    print("\n=== Deployment Complete ===")
    print("Workers deployed: " .. #state.deployedWorkers)
    print("\nWaiting for all workers to report ready...")
    print("Then this turtle will join as a worker.\n")
    
    -- Save my zone (last one if odd number, or create one)
    if #state.zones > #turtleSlots then
        state.myZone = state.zones[#state.zones]
        state.myZone.gps_zone = calculateGPSZone(state.myZone, state.startGPS)
    end
    
    return state.myZone
end

-- Run deployment
local success, myZone = pcall(deploy)

if not success then
    print("\nDeployment failed: " .. tostring(myZone))
    error(myZone)
end

print("\nDeployment successful!")
if myZone then
    print("This turtle will mine zone: X=" .. myZone.xmin .. "-" .. myZone.xmax)
    print("\nPress any key to continue as worker...")
    os.pullEvent("key")
    
    -- Continue to worker mode
    shell.run("quarry", myZone.xmax - myZone.xmin + 1, myZone.zmax - myZone.zmin + 1, myZone.ymin)
end
