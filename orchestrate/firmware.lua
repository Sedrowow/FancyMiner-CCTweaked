-- Firmware Management Module for Orchestration Server
-- Handles firmware distribution to workers

local Firmware = {}

Firmware.CHUNK_SIZE = 32768 -- 32KB chunks for file transfer

-- Check for floppy disk and required firmware files
function Firmware.checkDisk()
    local drive = peripheral.find("drive")
    if not drive then
        return nil, "No disk drive found"
    end
    
    if not drive.isDiskPresent() then
        return nil, "No disk in drive"
    end
    
    local diskPath = drive.getMountPath()
    local requiredFiles = {
        diskPath .. "/worker/quarry.lua",
        diskPath .. "/worker/dig.lua",
        diskPath .. "/worker/flex.lua",
        diskPath .. "/worker/modules/logger.lua",
        diskPath .. "/worker/modules/gps_utils.lua",
        diskPath .. "/worker/modules/gps_navigation.lua",
        diskPath .. "/worker/modules/state.lua",
        diskPath .. "/worker/modules/communication.lua",
        diskPath .. "/worker/modules/resource_manager.lua",
        diskPath .. "/worker/modules/firmware.lua"
    }
    
    for _, file in ipairs(requiredFiles) do
        if not fs.exists(file) then
            return nil, "Missing required file: " .. file
        end
    end
    
    return diskPath, nil
end

-- Read file from disk
function Firmware.readDiskFile(diskPath, filename)
    local fullPath = diskPath .. "/worker/" .. filename
    local file = fs.open(fullPath, "r")
    if not file then
        return nil, "Failed to open " .. fullPath
    end
    local content = file.readAll()
    file.close()
    return content, nil
end

-- Get all firmware files to send
-- Note: Modules are pre-installed via setup script, but can be updated via firmware distribution
function Firmware.getFirmwareFiles()
    return {
        "quarry.lua",
        "dig.lua",
        "flex.lua",
        "modules/logger.lua",
        "modules/gps_utils.lua",
        "modules/gps_navigation.lua",
        "modules/state.lua",
        "modules/communication.lua",
        "modules/resource_manager.lua",
        "modules/firmware.lua"
    }
end

-- Split content into chunks for transmission
function Firmware.createChunks(content)
    local chunks = {}
    local pos = 1
    while pos <= #content do
        table.insert(chunks, content:sub(pos, pos + Firmware.CHUNK_SIZE - 1))
        pos = pos + Firmware.CHUNK_SIZE
    end
    return chunks
end

-- Send firmware to a specific worker
function Firmware.sendToWorker(modem, serverChannel, turtleID)
    local diskPath, err = Firmware.checkDisk()
    if not diskPath then
        print("Error: Firmware disk not available - " .. err)
        return false
    end
    
    print("Sending firmware to turtle " .. turtleID .. "...")
    
    local files = Firmware.getFirmwareFiles()
    for _, filename in ipairs(files) do
        print("  Sending " .. filename .. "...")
        local content, readErr = Firmware.readDiskFile(diskPath, filename)
        if not content then
            print("  Error reading " .. filename .. ": " .. readErr)
            return false
        end
        
        local chunks = Firmware.createChunks(content)
        
        for i, chunk in ipairs(chunks) do
            modem.transmit(serverChannel, serverChannel, {
                type = "file_chunk",
                turtle_id = turtleID,
                filename = filename,
                chunk_num = i,
                total_chunks = #chunks,
                data = chunk
            })
            sleep(0.1) -- Small delay between chunks to prevent overwhelming receiver
        end
    end
    
    print("Firmware sent to turtle " .. turtleID)
    return true
end

-- Validate firmware disk is available
function Firmware.validate()
    local diskPath, err = Firmware.checkDisk()
    if diskPath then
        print("Disk check passed - all firmware files found")
        return true
    else
        error(err)
    end
end

return Firmware
