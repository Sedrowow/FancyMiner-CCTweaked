-- Bootstrap loader for worker turtles
-- This minimal program receives firmware from deployer and starts the worker

local turtleID = os.getComputerID()

-- Check if modules exist, if not we need to receive firmware first
local needsFirmware = not fs.exists("modules/logger.lua") or 
                       not fs.exists("modules/communication.lua") or
                       not fs.exists("modules/gps_utils.lua") or
                       not fs.exists("modules/firmware.lua")

if needsFirmware then
    -- Bootstrap minimal communication to get modules
    print("Worker " .. turtleID .. " - First boot, receiving firmware...")
    
    local modem = peripheral.find("ender_modem") or peripheral.find("modem")
    if not modem then
        error("No modem found")
    end
    modem.open(turtleID)
    modem.open(65535)
    
    -- Broadcast online and wait for server
    local SERVER_CHANNEL = nil
    local timeout = os.startTimer(60)
    
    modem.transmit(65535, turtleID, {
        type = "worker_online",
        turtle_id = turtleID
    })
    
    while not SERVER_CHANNEL do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == timeout then
            error("Timeout waiting for server")
        elseif event == "modem_message" then
            local message = p4
            if type(message) == "table" and message.type == "server_response" and message.turtle_id == turtleID then
                SERVER_CHANNEL = message.server_channel
                os.cancelTimer(timeout)
            end
        end
    end
    
    print("Server found on channel " .. SERVER_CHANNEL)
    print("Receiving firmware files...")
    
    -- Create modules directory
    if not fs.exists("modules") then
        fs.makeDir("modules")
    end
    
    -- Receive all firmware files
    local expectedFiles = {
        "quarry.lua", "dig.lua", "flex.lua",
        "modules/logger.lua", "modules/gps_utils.lua", "modules/gps_navigation.lua",
        "modules/state.lua", "modules/communication.lua", "modules/resource_manager.lua",
        "modules/firmware.lua"
    }
    
    local fileBuffers = {}
    local fileChunkCounts = {}
    local receivedFiles = {}
    
    for _, filename in ipairs(expectedFiles) do
        fileBuffers[filename] = {}
        fileChunkCounts[filename] = 0
    end
    
    while #receivedFiles < #expectedFiles do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        
        if type(message) == "table" and message.type == "file_chunk" and message.turtle_id == turtleID then
            local filename = message.filename
            local chunkNum = message.chunk_num
            local totalChunks = message.total_chunks
            local data = message.data
            
            if fileBuffers[filename] then
                fileBuffers[filename][chunkNum] = data
                fileChunkCounts[filename] = fileChunkCounts[filename] + 1
                
                if fileChunkCounts[filename] == totalChunks then
                    -- Ensure directory exists for files with paths
                    local dir = fs.getDir(filename)
                    if dir and dir ~= "" and not fs.exists(dir) then
                        fs.makeDir(dir)
                    end
                    
                    local content = table.concat(fileBuffers[filename])
                    local file = fs.open(filename, "w")
                    file.write(content)
                    file.close()
                    table.insert(receivedFiles, filename)
                    print("Received " .. filename .. " (" .. #receivedFiles .. "/" .. #expectedFiles .. ")")
                    
                    modem.transmit(SERVER_CHANNEL, turtleID, {
                        type = "file_received",
                        turtle_id = turtleID,
                        filename = filename
                    })
                end
            end
        end
    end
    
    print("All firmware received!")
    sleep(0.5)
end

-- Now load modules
local logger = require("modules.logger")
local communication = require("modules.communication")
local gpsUtils = require("modules.gps_utils")
local firmware = require("modules.firmware")

-- Initialize logger
logger.init(turtleID)
logger.section("Worker Bootstrap")
logger.log("Worker ID: " .. turtleID)

-- Initialize modem
local modem, err = communication.initModem()
if not modem then
    error(err)
end

-- Check if we already have server channel
local SERVER_CHANNEL = nil
if fs.exists(".server_channel") then
    local f = fs.open(".server_channel", "r")
    SERVER_CHANNEL = tonumber(f.readAll())
    f.close()
    logger.log("Using saved server channel: " .. SERVER_CHANNEL)
else
    -- Broadcast online status and wait for server response
    logger.log("Broadcasting online status...")
    SERVER_CHANNEL, err = communication.waitForServerResponse(modem, turtleID, 60)
    if not SERVER_CHANNEL then
        error(err or "Failed to discover server")
    end
    
    logger.log("Server connected: Channel " .. SERVER_CHANNEL)
    
    -- Save server channel for quarry.lua
    local success, err = communication.saveServerChannelFile(SERVER_CHANNEL)
    if not success then
        logger.error(err or "Failed to save server channel")
    end
end

-- Get GPS position for zone matching
logger.log("Getting GPS position...")
local gpsPosition, err = gpsUtils.getGPS(5)
if not gpsPosition then
    error(err or "Failed to get GPS coordinates")
end

logger.log("Position: " .. gpsUtils.formatGPS(gpsPosition))

-- Notify server with GPS position
communication.sendFirmwareComplete(modem, SERVER_CHANNEL, turtleID, gpsPosition)

-- Load the APIs
logger.section("Loading APIs")
os.loadAPI("dig.lua")
os.loadAPI("flex.lua")

-- Execute the worker quarry program
logger.log("Starting worker quarry program...")
sleep(1)

shell.run("quarry.lua")
