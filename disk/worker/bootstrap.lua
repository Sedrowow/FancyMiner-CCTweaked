-- Bootstrap loader for worker turtles
-- This minimal program receives firmware from deployer and starts the worker
-- Modules must be pre-installed via setup script

local turtleID = os.getComputerID()

-- Load modules (must be pre-installed via setup script)
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

-- Open server channel for receiving firmware
modem.open(SERVER_CHANNEL)
logger.log("Listening on server channel: " .. SERVER_CHANNEL)

-- Receive firmware files (main files only - modules are pre-installed)
-- On first boot, worker gets modules via setup. On updates, server can push module updates too.
-- To keep bootstrap simple and fast, we only request main files here.
firmware.receiveFirmware(modem, SERVER_CHANNEL, turtleID, 
    {"quarry.lua", "dig.lua", "flex.lua",
     "modules/logger.lua", "modules/gps_utils.lua", "modules/gps_navigation.lua",
     "modules/state.lua", "modules/communication.lua", "modules/resource_manager.lua",
     "modules/firmware.lua"}, logger)

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
