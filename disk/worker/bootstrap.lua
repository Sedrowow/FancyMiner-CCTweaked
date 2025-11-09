-- Bootstrap loader for worker turtles
-- This minimal program receives firmware from deployer and starts the worker

local BROADCAST_CHANNEL = 65535
local SERVER_CHANNEL = nil
local turtleID = os.getComputerID()

print("Worker Bootstrap - ID: " .. turtleID)

-- Find and open modem
local modem = peripheral.find("ender_modem")
if not modem then
    modem = peripheral.find("modem")
end

if not modem then
    error("No modem found!")
end

modem.open(BROADCAST_CHANNEL)

-- Broadcast that we're online and wait for server response
print("Broadcasting online status...")
local serverDiscovered = false
local broadcastTimer = os.startTimer(2) -- Broadcast every 2 seconds

while not serverDiscovered do
    -- Broadcast we're online
    modem.transmit(BROADCAST_CHANNEL, BROADCAST_CHANNEL, {
        type = "worker_online",
        turtle_id = turtleID
    })
    
    local event, p1, p2, p3, p4 = os.pullEvent()
    
    if event == "timer" and p1 == broadcastTimer then
        -- Re-broadcast
        broadcastTimer = os.startTimer(2)
    elseif event == "modem_message" then
        local side, channel, replyChannel, message, distance = p1, p2, p3, p4, p5
        
        if type(message) == "table" and message.type == "server_response" then
            if message.turtle_id == turtleID then
                SERVER_CHANNEL = message.server_channel
                serverDiscovered = true
                os.cancelTimer(broadcastTimer)
                print("Server connected: Channel " .. SERVER_CHANNEL)
            end
        end
    end
end

-- Open server channel for firmware reception
modem.open(SERVER_CHANNEL)
print("Waiting for firmware...")

-- File reception state
local fileChunks = {}
local filesReceived = {}
local requiredFiles = {"quarry.lua", "dig.lua", "flex.lua"}
local allFilesReceived = false

-- Function to check if all files are received
local function checkAllFilesReceived()
    for _, filename in ipairs(requiredFiles) do
        if not filesReceived[filename] then
            return false
        end
    end
    return true
end

-- Main reception loop
print("Waiting for firmware...")
while not allFilesReceived do
    local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
    
    if type(message) == "table" then
        if message.type == "file_chunk" then
            local filename = message.filename
            
            -- Only process files we need
            local isRequired = false
            for _, req in ipairs(requiredFiles) do
                if req == filename then
                    isRequired = true
                    break
                end
            end
            
            if isRequired then
                if not fileChunks[filename] then
                    fileChunks[filename] = {}
                    print("Receiving " .. filename .. "...")
                end
                
                fileChunks[filename][message.chunk_num] = message.data
                
                -- Check if file is complete
                local complete = true
                for i = 1, message.total_chunks do
                    if not fileChunks[filename][i] then
                        complete = false
                        break
                    end
                end
                
                if complete and not filesReceived[filename] then
                    -- Reassemble and write file
                    local content = table.concat(fileChunks[filename])
                    local file = fs.open(filename, "w")
                    file.write(content)
                    file.close()
                    
                    filesReceived[filename] = true
                    print("Received: " .. filename .. " (" .. #content .. " bytes)")
                    
                    -- Acknowledge receipt to server
                    modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
                        type = "file_received",
                        turtle_id = turtleID,
                        filename = filename
                    })
                    
                    -- Check if all files received
                    allFilesReceived = checkAllFilesReceived()
                    
                    if allFilesReceived then
                        print("\nAll firmware received!")
                        
                        -- Get GPS position for zone matching
                        print("Getting GPS position...")
                        local gpsX, gpsY, gpsZ = gps.locate(5)
                        
                        if not gpsX then
                            error("Failed to get GPS coordinates")
                        end
                        
                        print("Position: " .. gpsX .. ", " .. gpsY .. ", " .. gpsZ)
                        
                        -- Notify server with GPS position
                        modem.transmit(SERVER_CHANNEL, SERVER_CHANNEL, {
                            type = "firmware_complete",
                            turtle_id = turtleID,
                            gps_position = {x = gpsX, y = gpsY, z = gpsZ}
                        })
                        
                        break
                    end
                end
            end
        end
    end
end

-- Load the APIs
print("\nLoading APIs...")
os.loadAPI("dig.lua")
os.loadAPI("flex.lua")

-- Execute the worker quarry program
print("Starting worker quarry program...")
sleep(1)

-- Run quarry.lua
shell.run("quarry.lua")
