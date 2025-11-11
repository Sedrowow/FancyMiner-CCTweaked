-- Server Communication Module
-- Handles all message passing with orchestration server

local M = {}

local BROADCAST_CHANNEL = 65535

-- Initialize modem and open channels
function M.initModem(serverChannel)
    local modem = peripheral.find("ender_modem")
    if not modem then
        modem = peripheral.find("modem")
    end
    
    if not modem then
        return nil, "No modem found! Worker requires a modem."
    end
    
    modem.open(BROADCAST_CHANNEL)
    if serverChannel then
        modem.open(serverChannel)
    end
    
    return modem
end

-- Send a message to the server
function M.sendMessage(modem, channel, message)
    if not modem then return false end
    modem.transmit(channel, channel, message)
    return true
end

-- Broadcast worker online status
function M.broadcastOnline(modem, turtleID)
    return M.sendMessage(modem, BROADCAST_CHANNEL, {
        type = "worker_online",
        turtle_id = turtleID
    })
end

-- Wait for server response with channel assignment
function M.waitForServerResponse(modem, turtleID, timeout)
    timeout = timeout or 60
    local timer = os.startTimer(timeout)
    local broadcastTimer = os.startTimer(2)
    
    while true do
        -- Broadcast periodically
        M.broadcastOnline(modem, turtleID)
        
        local event, p1, p2, p3, p4 = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            return nil, "Server discovery timeout"
        elseif event == "timer" and p1 == broadcastTimer then
            broadcastTimer = os.startTimer(2)
        elseif event == "modem_message" then
            local message = p4
            if type(message) == "table" and 
               message.type == "server_response" and
               message.turtle_id == turtleID then
                os.cancelTimer(timer)
                os.cancelTimer(broadcastTimer)
                return message.server_channel
            end
        end
    end
end

-- Send worker ready signal
function M.sendReady(modem, serverChannel, turtleID)
    return M.sendMessage(modem, serverChannel, {
        type = "worker_ready",
        turtle_id = turtleID
    })
end

-- Send firmware complete notification with GPS
function M.sendFirmwareComplete(modem, serverChannel, turtleID, gpsPosition)
    return M.sendMessage(modem, serverChannel, {
        type = "firmware_complete",
        turtle_id = turtleID,
        gps_position = gpsPosition
    })
end

-- Send ready for assignment notification
function M.sendReadyForAssignment(modem, serverChannel, turtleID, gpsPosition)
    return M.sendMessage(modem, serverChannel, {
        type = "ready_for_assignment",
        turtle_id = turtleID,
        gps_position = gpsPosition
    })
end

-- Send status update
function M.sendStatusUpdate(modem, serverChannel, turtleID, status, position, gpsPosition, fuel)
    if not modem or not serverChannel then return false end
    
    return M.sendMessage(modem, serverChannel, {
        type = "status_update",
        turtle_id = turtleID,
        status = status or "mining",
        position = position,
        gps_position = gpsPosition,
        fuel = fuel
    })
end

-- Send zone complete notification
function M.sendZoneComplete(modem, serverChannel, turtleID, finalPos)
    return M.sendMessage(modem, serverChannel, {
        type = "zone_complete",
        turtle_id = turtleID,
        final_pos = finalPos
    })
end

-- Send abort acknowledgment
function M.sendAbortAck(modem, serverChannel, turtleID, position)
    return M.sendMessage(modem, serverChannel, {
        type = "abort_ack",
        turtle_id = turtleID,
        position = position
    })
end

-- Send file received acknowledgment
function M.sendFileReceived(modem, serverChannel, turtleID, filename)
    return M.sendMessage(modem, serverChannel, {
        type = "file_received",
        turtle_id = turtleID,
        filename = filename
    })
end

-- Check job status with server
function M.checkJobStatus(modem, serverChannel, turtleID, timeout)
    timeout = timeout or 30
    
    print("DEBUG: Sending status check on channel " .. serverChannel .. " for turtle " .. turtleID)
    M.sendMessage(modem, serverChannel, {
        type = "worker_status_check",
        turtle_id = turtleID
    })
    
    local timer = os.startTimer(timeout)
    
    while true do
        local event, side, channel, replyChannel, message = os.pullEvent()
        
        if event == "timer" and side == timer then
            print("DEBUG: Job status check timed out")
            return false, "Server timeout"
        elseif event == "modem_message" then
            print("DEBUG: Received modem message: " .. textutils.serialize(message))
            if type(message) == "table" then
                if message.type == "job_status_response" and message.turtle_id == turtleID then
                    print("DEBUG: Job active = " .. tostring(message.job_active))
                    os.cancelTimer(timer)
                    return message.job_active
                end
            end
        end
    end
end

-- Wait for zone assignment
function M.waitForZoneAssignment(modem, turtleID, timeout)
    timeout = timeout or 120
    local timer = os.startTimer(timeout)
    
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            return nil, "Timeout waiting for zone assignment"
        elseif event == "modem_message" then
            local message = p4
            if type(message) == "table" and 
               message.type == "zone_assignment" and 
               message.turtle_id == turtleID then
                os.cancelTimer(timer)
                return message
            end
        end
    end
end

-- Wait for start mining signal
function M.waitForStartSignal(modem)
    while true do
        local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
        if type(message) == "table" and message.type == "start_mining" then
            return true
        end
    end
end

-- Listen for abort command (non-blocking check)
function M.checkAbort(modem)
    local event, side, channel, replyChannel, message = os.pullEventRaw("modem_message")
    if event == "modem_message" and 
       type(message) == "table" and 
       message.type == "abort_mining" then
        return true
    end
    return false
end

-- Read server channel from bootstrap file
function M.readServerChannelFile()
    if not fs.exists("server_channel.txt") then
        return nil, "Server channel file not found"
    end
    
    local file = fs.open("server_channel.txt", "r")
    if not file then
        return nil, "Failed to open server channel file"
    end
    
    local channel = tonumber(file.readLine())
    file.close()
    
    if not channel then
        return nil, "Invalid server channel in file"
    end
    
    return channel
end

-- Save server channel to file for quarry.lua
function M.saveServerChannelFile(serverChannel)
    local file = fs.open("server_channel.txt", "w")
    if not file then
        return false, "Failed to create server channel file"
    end
    
    file.writeLine(tostring(serverChannel))
    file.close()
    return true
end

return M
