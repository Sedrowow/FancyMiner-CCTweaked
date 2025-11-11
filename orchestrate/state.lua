-- State Management Module for Orchestration Server
-- Handles saving/loading state and state initialization

local State = {}

State.STATE_FILE = "orchestrate_state.cfg"

-- Create initial state structure
function State.create()
    return {
        workers = {}, -- [turtle_id] = {zone, status, lastUpdate, etc}
        fuelQueue = {},
        outputQueue = {},
        fuelLock = false,
        outputLock = false,
        fuelLockTime = nil,
        outputLockTime = nil,
        readyCount = 0,
        totalWorkers = 0,
        deployerID = nil,
        quarryParams = nil,
        chestPositions = {
            fuel = nil,
            output = nil
        },
        startGPS = nil,
        miningStarted = false,
        completedCount = 0,
        aborted = false,
        abortAckCount = 0,
        firmwareRequests = {},
        zones = nil,
        gpsZones = nil,
        isDeployerWorker = false,
        deploymentComplete = false,
        firmwareLoaded = false
    }
end

-- Save state to disk
function State.save(state)
    local file = fs.open(State.STATE_FILE, "w")
    if file then
        file.write(textutils.serialize(state))
        file.close()
        return true
    end
    return false
end

-- Load state from disk
function State.load()
    if fs.exists(State.STATE_FILE) then
        local file = fs.open(State.STATE_FILE, "r")
        if file then
            local data = file.readAll()
            file.close()
            local loaded = textutils.unserialize(data)
            if loaded then
                return loaded, true
            end
        end
    end
    return State.create(), false
end

-- Clear state file and return fresh state
function State.reset()
    if fs.exists(State.STATE_FILE) then
        fs.delete(State.STATE_FILE)
    end
    return State.create()
end

return State
