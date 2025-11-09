-- Bootstrap loader for worker turtles
-- This minimal program receives firmware from deployer and starts the worker

local BROADCAST_CHANNEL = 65535
local turtleID = os.getComputerID()

print("Worker Bootstrap - ID: " .. turtleID)
print("Waiting for firmware...")

-- Find and open modem
local modem = peripheral.find("ender_modem")
if not modem then
    modem = peripheral.find("modem")
end

if not modem then
    error("No modem found!")
end

modem.open(BROADCAST_CHANNEL)

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
while not allFilesReceived do
    local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
    
    if type(message) == "table" then
        if message.type == "file_chunk_broadcast" then
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
                    
                    -- Check if all files received
                    allFilesReceived = checkAllFilesReceived()
                    
                    if allFilesReceived then
                        print("\nAll firmware received!")
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
