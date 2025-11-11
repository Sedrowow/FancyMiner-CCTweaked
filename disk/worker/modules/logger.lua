-- Logger Module
-- Provides logging functionality with file and screen output
-- Prevents circular dependencies in other modules

local M = {}

local logFile = nil
local logToScreen = true
local logToFile = true

-- Initialize logger for a specific turtle
function M.init(turtleID, toScreen, toFile)
    logToScreen = (toScreen == nil) and true or toScreen
    logToFile = (toFile == nil) and true or toFile
    
    if logToFile then
        logFile = "worker_" .. turtleID .. ".log"
        
        -- Clear old log on initialization
        if fs.exists(logFile) then
            fs.delete(logFile)
        end
    end
end

-- Log a message
function M.log(message)
    message = tostring(message)
    
    -- Print to screen
    if logToScreen then
        print(message)
    end
    
    -- Append to log file
    if logToFile and logFile then
        local file = fs.open(logFile, "a")
        if file then
            file.writeLine("[" .. os.date("%H:%M:%S") .. "] " .. message)
            file.close()
        end
    end
end

-- Log with specific level prefix
function M.info(message)
    M.log("[INFO] " .. message)
end

function M.warn(message)
    M.log("[WARN] " .. message)
end

function M.error(message)
    M.log("[ERROR] " .. message)
end

function M.debug(message)
    M.log("[DEBUG] " .. message)
end

-- Log a section header
function M.section(message)
    M.log("\n=== " .. message .. " ===")
end

-- Enable/disable screen output
function M.setScreenOutput(enabled)
    logToScreen = enabled
end

-- Enable/disable file output
function M.setFileOutput(enabled)
    logToFile = enabled
end

-- Get log file path
function M.getLogFile()
    return logFile
end

return M
