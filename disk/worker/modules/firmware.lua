-- Firmware Reception Module
-- Handles receiving firmware files from the orchestration server

local M = {}

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
    return true
end

return M
