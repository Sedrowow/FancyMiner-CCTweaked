-- Firmware Reception Module
-- Handles receiving firmware files from the orchestration server

local M = {}

-- Check firmware version with server
function M.checkVersion(modem, serverChannel, turtleID, logger)
    -- Check local firmware version
    local localVersion = nil
    if fs.exists(".firmware_version") then
        local f = fs.open(".firmware_version", "r")
        localVersion = f.readAll()
        f.close()
        logger.log("Local firmware version: " .. localVersion)
    else
        logger.log("No local firmware version found")
    end
    
    -- Request firmware version from server
    logger.log("Checking firmware version with server...")
    modem.transmit(serverChannel, serverChannel, {
        type = "version_check",
        turtle_id = turtleID,
        current_version = localVersion
    })
    
    -- Wait for version response
    local needsUpdate = true
    local versionTimeout = os.startTimer(10)
    
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()
        
        if event == "timer" and p1 == versionTimeout then
            logger.log("Version check timeout, proceeding with firmware download")
            break
        elseif event == "modem_message" then
            local message = p4
            if type(message) == "table" and message.type == "version_response" and message.turtle_id == turtleID then
                if message.up_to_date then
                    logger.log("Firmware is up to date (" .. (localVersion or "unknown") .. ")")
                    needsUpdate = false
                else
                    logger.log("Firmware update available: " .. (message.server_version or "unknown"))
                end
                os.cancelTimer(versionTimeout)
                break
            end
        end
    end
    
    return needsUpdate
end

-- Check if all required files have been received
local function checkAllFilesReceived(filesReceived, requiredFiles)
    for _, filename in ipairs(requiredFiles) do
        if not filesReceived[filename] then
            return false
        end
    end
    return true
end

-- Receive firmware files over modem
function M.receiveFirmware(modem, serverChannel, turtleID, requiredFiles, logger)
    requiredFiles = requiredFiles or {"quarry.lua", "dig.lua", "flex.lua"}
    
    -- Create modules directory if needed (for updates)
    if not fs.exists("modules") then
        fs.makeDir("modules")
    end
    
    local fileChunks = {}
    local filesReceived = {}
    
    logger.log("Waiting for firmware...")
    
    while not checkAllFilesReceived(filesReceived, requiredFiles) do
        local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
        
        if type(message) == "table" and message.type == "file_chunk" and message.turtle_id == turtleID then
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
                    logger.log("Receiving " .. filename .. "...")
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
                    
                    -- Ensure directory exists for files with paths
                    local dir = fs.getDir(filename)
                    if dir and dir ~= "" and not fs.exists(dir) then
                        fs.makeDir(dir)
                    end
                    
                    local file = fs.open(filename, "w")
                    file.write(content)
                    file.close()
                    
                    filesReceived[filename] = true
                    logger.log("Received: " .. filename .. " (" .. #content .. " bytes)")
                    
                    -- Acknowledge receipt to server
                    modem.transmit(serverChannel, serverChannel, {
                        type = "file_received",
                        turtle_id = turtleID,
                        filename = filename
                    })
                end
            end
        end
    end
    
    logger.log("All firmware received!")
    
    -- Request version info from server to save locally
    modem.transmit(serverChannel, serverChannel, {
        type = "get_version",
        turtle_id = turtleID
    })
    
    -- Wait briefly for version response
    local versionTimer = os.startTimer(2)
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()
        if event == "timer" and p1 == versionTimer then
            break
        elseif event == "modem_message" then
            local msg = p4
            if type(msg) == "table" and msg.type == "version_info" and msg.turtle_id == turtleID then
                if msg.version then
                    local f = fs.open(".firmware_version_new", "w")
                    f.write(msg.version)
                    f.close()
                    logger.log("Version saved: " .. msg.version)
                end
                os.cancelTimer(versionTimer)
                break
            end
        end
    end
    
    return true
end

return M
