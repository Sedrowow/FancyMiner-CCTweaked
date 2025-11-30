-- Server Communication Module
-- Handles all modem communication with the orchestration server

local M = {}

local BROADCAST_CHANNEL = 65535

-- Initialize modem and open channels
-- Returns: modem peripheral, or nil and error message
function M.initModem(serverChannel)
    local modem = peripheral.find("ender_modem")
    if not modem then
        modem = peripheral.find("modem")
    end
    
    if not modem then
        return nil, "No modem found! Deployer requires an ender modem."
    end
    
    if serverChannel then
        modem.open(serverChannel)
    end
    modem.open(BROADCAST_CHANNEL)
    
    return modem
end

-- Send a message to the server
function M.sendMessage(modem, channel, message)
    modem.transmit(channel, channel, message)
end

-- Check with server about previous deployment state
-- Returns: shouldContinue (boolean), deploymentComplete (boolean), error message
function M.checkPreviousDeployment(modem, serverChannel, deployerID, timeout)
    timeout = timeout or 10
    
    print("Checking with server...")
    
    M.sendMessage(modem, serverChannel, {
        type = "deployer_restart",
        deployer_id = deployerID
    })
    
    local timer = os.startTimer(timeout)
    
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            return false, false, "Server not responding"
        elseif event == "modem_message" then
            local message = p4
            if message.type == "restart_response" and message.deployer_id == deployerID then
                os.cancelTimer(timer)
                
                if message.deployment_complete then
                    return true, true, nil
                else
                    return false, false, "Previous deployment incomplete"
                end
            end
        end
    end
end

-- Get quarry parameters from user
-- Returns: params table with width, length, depth, skip
function M.getQuarryParams()
    print("\nEnter quarry width:")
    local width = tonumber(read())
    print("Enter quarry length:")
    local length = tonumber(read())
    print("Enter quarry depth:")
    local depth = tonumber(read())
    print("Enter skip depth (0 for none):")
    local skip = tonumber(read())
    
    return {
        width = width,
        length = length,
        depth = depth,
        skip = skip
    }
end

-- Send deployment request to server
-- Returns: true on success
-- Optional parameter deployerFacing: cardinal direction the deployer computer is physically facing
function M.sendDeployRequest(modem, serverChannel, deployerID, numWorkers, quarryParams, deployerFacing)
    print("\nContacting server...")
    
    M.sendMessage(modem, serverChannel, {
        type = "deploy_request",
        deployer_id = deployerID,
        num_workers = numWorkers,
        is_deployer = true,
        quarry_params = quarryParams,
        deployer_facing = deployerFacing -- may be nil
    })
    
    return true
end

-- Wait for deployment command from server with zone assignments
-- Returns: zones table, numWorkers, serverChannel, or nil and error
function M.waitForDeployCommand(modem, timeout)
    timeout = timeout or 300  -- 5 minute default timeout
    
    print("\nWaiting for server response...")
    
    local timer = os.startTimer(timeout)
    
    while true do
        local event, side, channel, replyChannel, message = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            return nil, "Server deploy command timeout"
        elseif event == "modem_message" then
            if type(message) == "table" and message.type == "deploy_command" then
                os.cancelTimer(timer)
                print("Received zone assignments from server")
                return message.zones, message.num_workers, message.server_channel
            end
        end
    end
end

-- Send chest position information to server
function M.sendChestPositions(modem, serverChannel, fuelGPS, outputGPS, startGPS)
    M.sendMessage(modem, serverChannel, {
        type = "chest_positions",
        fuel_gps = fuelGPS,
        output_gps = outputGPS,
        start_gps = startGPS
    })
end

-- Notify server that deployment is complete
function M.sendDeploymentComplete(modem, serverChannel, deployerID)
    print("Notifying server...")
    M.sendMessage(modem, serverChannel, {
        type = "deployment_complete",
        deployer_id = deployerID
    })
end

-- Wait for cleanup command from server
-- Returns: true when cleanup command received
function M.waitForCleanupCommand(modem, serverChannel, deployerID)
    print("\n=== Waiting for Cleanup Command ===")
    modem.open(serverChannel)
    
    while true do
        local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
        
        if type(message) == "table" and 
           message.type == "cleanup_command" and 
           message.turtle_id == deployerID then
            return true
        end
    end
end

-- Get server channel from user
-- Returns: channel number
function M.getServerChannel()
    print("\nEnter server channel ID:")
    return tonumber(read())
end

return M
