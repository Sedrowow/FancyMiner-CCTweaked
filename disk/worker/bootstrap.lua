-- Bootstrap loader for worker turtles
-- This minimal program receives firmware from deployer and starts the worker

-- Load modules
local logger = require("modules.logger")
local communication = require("modules.communication")
local gpsUtils = require("modules.gps_utils")
local firmware = require("modules.firmware")

local turtleID = os.getComputerID()

-- Initialize logger
logger.init(turtleID)
logger.section("Worker Bootstrap")
logger.log("Worker ID: " .. turtleID)

-- Initialize modem
local modem, err = communication.initModem()
if not modem then
    error(err)
end

-- Broadcast online status and wait for server response
logger.log("Broadcasting online status...")
local SERVER_CHANNEL, err = communication.waitForServerResponse(modem, turtleID, 60)
if not SERVER_CHANNEL then
    error(err or "Failed to discover server")
end

logger.log("Server connected: Channel " .. SERVER_CHANNEL)

-- Save server channel for quarry.lua
local success, err = communication.saveServerChannelFile(SERVER_CHANNEL)
if not success then
    logger.error(err or "Failed to save server channel")
end

-- Receive firmware files
firmware.receiveFirmware(modem, SERVER_CHANNEL, turtleID, 
    {"quarry.lua", "dig.lua", "flex.lua"}, logger)

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
