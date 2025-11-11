-- State Management for Deployment System
-- Handles saving and loading deployment state for recovery

local STATE_FILE = "deploy_state.cfg"

local M = {}

-- Create a new deployment state
function M.create()
    return {
        deployerID = os.getComputerID(),
        startGPS = nil,
        zones = {},
        numWorkers = 0,
        chestPositions = {
            fuel = nil,
            output = nil
        },
        serverChannel = nil,
        deploymentComplete = false,
        workerPhaseComplete = false
    }
end

-- Save state to disk
function M.save(state)
    local file = fs.open(STATE_FILE, "w")
    if not file then
        error("Failed to open state file for writing")
    end
    file.write(textutils.serialize(state))
    file.close()
end

-- Load state from disk
function M.load()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        if not file then
            return nil
        end
        local data = file.readAll()
        file.close()
        
        local state = textutils.unserialize(data)
        if state then
            return state
        end
    end
    return nil
end

-- Delete state file
function M.clear()
    if fs.exists(STATE_FILE) then
        fs.delete(STATE_FILE)
    end
end

-- Check if state file exists
function M.exists()
    return fs.exists(STATE_FILE)
end

return M
