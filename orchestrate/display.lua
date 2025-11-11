-- Display Module for Orchestration Server
-- Handles all monitor/screen output and formatting

local Display = {}

-- Display configuration
Display.monitor = nil
Display.useMonitor = false
Display.displayWidth = 0
Display.displayHeight = 0

-- Current view state
Display.viewState = {
    mode = "main", -- "main", "worker", "fuel_queue", or "output_queue"
    selectedWorker = nil
}

-- Initialize display (monitor or terminal)
function Display.init()
    -- Try to find and set up a monitor
    local monitors = {peripheral.find("monitor")}
    if #monitors > 0 then
        Display.monitor = monitors[1]
        Display.monitor.setTextScale(0.5) -- Good for 2x2 advanced monitors
        Display.monitor.clear()
        Display.useMonitor = true
        Display.displayWidth, Display.displayHeight = Display.monitor.getSize()
        print("Monitor detected: " .. Display.displayWidth .. "x" .. Display.displayHeight)
    else
        Display.displayWidth, Display.displayHeight = term.getSize()
    end
end

-- Helper functions
function Display.setColor(color)
    if Display.useMonitor then
        Display.monitor.setTextColor(color)
    else
        term.setTextColor(color)
    end
end

function Display.setCursorPos(x, y)
    if Display.useMonitor then
        Display.monitor.setCursorPos(x, y)
    else
        term.setCursorPos(x, y)
    end
end

function Display.clearDisplay()
    if Display.useMonitor then
        Display.monitor.clear()
    else
        term.clear()
    end
end

function Display.write(text)
    if Display.useMonitor then
        Display.monitor.write(text)
    else
        term.write(text)
    end
end

-- Queue detail view
function Display.showQueueDetail(state, queueType)
    Display.clearDisplay()
    Display.setCursorPos(1, 1)
    
    local queue = (queueType == "fuel") and state.fuelQueue or state.outputQueue
    local lockKey = (queueType == "fuel") and "fuelLock" or "outputLock"
    local title = (queueType == "fuel") and "Fuel Queue" or "Output Queue"
    
    Display.setColor(colors.white)
    Display.write("=== " .. title .. " ===")
    Display.setCursorPos(1, 2)
    Display.setColor(colors.yellow)
    Display.write("[Touch anywhere to return]")
    Display.setCursorPos(1, 3)
    Display.write("----------------------------")
    
    local line = 4
    
    -- Show current lock holder
    if state[lockKey] then
        Display.setColor(colors.white)
        Display.setCursorPos(1, line)
        Display.write("Current Access: ")
        Display.setColor(colors.lime)
        Display.write("Turtle " .. state[lockKey])
        line = line + 1
        
        -- Show how long they've had access
        local timeKey = (queueType == "fuel") and "fuelLockTime" or "outputLockTime"
        if state[timeKey] then
            Display.setColor(colors.lightGray)
            Display.setCursorPos(3, line)
            local elapsed = math.floor(os.clock() - state[timeKey])
            Display.write("Time: " .. elapsed .. "s")
            line = line + 1
        end
        line = line + 1
    else
        Display.setColor(colors.white)
        Display.setCursorPos(1, line)
        Display.write("Current Access: ")
        Display.setColor(colors.lightGray)
        Display.write("None (Available)")
        line = line + 2
    end
    
    -- Show queue with clear button
    Display.setColor(colors.white)
    Display.setCursorPos(1, line)
    Display.write("Queue (" .. #queue .. " waiting): ")
    
    -- Add clear all button if queue not empty
    local clearAllLine = nil
    if #queue > 0 then
        Display.setColor(colors.red)
        Display.write("[Clear All]")
        clearAllLine = line
    end
    line = line + 1
    
    -- Store line mapping for remove buttons
    local removeButtons = {}
    
    if #queue == 0 then
        Display.setColor(colors.lightGray)
        Display.setCursorPos(3, line)
        Display.write("(empty)")
    else
        for i, turtleID in ipairs(queue) do
            if line >= Display.displayHeight then break end
            
            Display.setCursorPos(1, line)
            Display.setColor(colors.red)
            Display.write("[X]")
            removeButtons[line] = i  -- Map line to queue position
            
            Display.setColor(colors.yellow)
            Display.write(" " .. i .. ". ")
            Display.setColor(colors.white)
            Display.write("Turtle " .. turtleID)
            
            -- Show worker info if available
            local worker = state.workers[turtleID]
            if worker then
                Display.setColor(colors.lightGray)
                if worker.gps_position then
                    Display.setCursorPos(20, line)
                    Display.write(string.format("GPS:%d,%d,%d",
                        math.floor(worker.gps_position.x or 0),
                        math.floor(worker.gps_position.y or 0),
                        math.floor(worker.gps_position.z or 0)))
                end
                if worker.fuel then
                    Display.setCursorPos(40, line)
                    Display.write("F:" .. worker.fuel)
                end
            end
            
            line = line + 1
        end
    end
    
    return removeButtons, clearAllLine
end

-- Worker detail view
function Display.showWorkerDetail(state, workerID)
    local worker = state.workers[workerID]
    if not worker then
        Display.viewState.mode = "main"
        return Display.update(state)
    end
    
    Display.clearDisplay()
    Display.setCursorPos(1, 1)
    
    Display.setColor(colors.white)
    Display.write("=== Worker " .. workerID .. " Details ===")
    Display.setCursorPos(1, 2)
    Display.setColor(colors.yellow)
    Display.write("[Touch anywhere to return]")
    Display.setCursorPos(1, 3)
    Display.write("----------------------------")
    
    local line = 4
    Display.setColor(colors.white)
    
    -- Status
    Display.setCursorPos(1, line)
    Display.write("Status: ")
    if worker.status == "complete" then
        Display.setColor(colors.lime)
    elseif worker.status == "timeout" then
        Display.setColor(colors.red)
    elseif worker.status == "mining" then
        Display.setColor(colors.lightBlue)
    elseif worker.status == "queued" then
        Display.setColor(colors.yellow)
    else
        Display.setColor(colors.lightGray)
    end
    Display.write(worker.status or "Unknown")
    line = line + 1
    
    -- GPS Position
    if worker.gps_position then
        Display.setColor(colors.white)
        Display.setCursorPos(1, line)
        Display.write("GPS Position:")
        line = line + 1
        Display.setColor(colors.lightGray)
        Display.setCursorPos(3, line)
        Display.write(string.format("X: %.1f", worker.gps_position.x or 0))
        line = line + 1
        Display.setCursorPos(3, line)
        Display.write(string.format("Y: %.1f", worker.gps_position.y or 0))
        line = line + 1
        Display.setCursorPos(3, line)
        Display.write(string.format("Z: %.1f", worker.gps_position.z or 0))
        line = line + 1
    end
    
    -- Dig Position
    if worker.position then
        line = line + 1
        Display.setColor(colors.white)
        Display.setCursorPos(1, line)
        Display.write("Dig Coordinates:")
        line = line + 1
        Display.setColor(colors.lightGray)
        Display.setCursorPos(3, line)
        Display.write(string.format("X: %d", worker.position.x or 0))
        line = line + 1
        Display.setCursorPos(3, line)
        Display.write(string.format("Y: %d", worker.position.y or 0))
        line = line + 1
        Display.setCursorPos(3, line)
        Display.write(string.format("Z: %d", worker.position.z or 0))
        line = line + 1
    end
    
    -- Fuel
    if worker.fuel then
        line = line + 1
        Display.setColor(colors.white)
        Display.setCursorPos(1, line)
        Display.write("Fuel Level: ")
        Display.setColor(colors.orange)
        Display.write(tostring(worker.fuel))
        line = line + 1
    end
    
    -- Zone assignment
    if worker.zone then
        line = line + 1
        Display.setColor(colors.white)
        Display.setCursorPos(1, line)
        Display.write("Zone Assignment:")
        line = line + 1
        Display.setColor(colors.lightGray)
        Display.setCursorPos(3, line)
        Display.write(string.format("X: %d to %d", worker.zone.xmin or 0, worker.zone.xmax or 0))
        line = line + 1
        Display.setCursorPos(3, line)
        Display.write(string.format("Z: %d to %d", worker.zone.zmin or 0, worker.zone.zmax or 0))
        line = line + 1
        Display.setCursorPos(3, line)
        Display.write(string.format("Y: %d to %d", worker.zone.ymax or 0, worker.zone.ymin or 0))
        line = line + 1
    end
    
    -- Last update time
    if worker.lastUpdate then
        line = line + 1
        Display.setColor(colors.white)
        Display.setCursorPos(1, line)
        Display.write("Last Update: ")
        Display.setColor(colors.lightGray)
        local elapsed = math.floor(os.clock() - worker.lastUpdate)
        Display.write(elapsed .. "s ago")
    end
end

-- Main overview display
function Display.showMainView(state)
    Display.clearDisplay()
    Display.setCursorPos(1, 1)
    
    -- Header
    Display.setColor(colors.white)
    Display.write("=== Orchestration Server ===")
    Display.setCursorPos(1, 2)
    Display.write("Workers: " .. state.totalWorkers .. " | Ready: " .. state.readyCount)
    Display.setCursorPos(1, 3)
    Display.write("Complete: " .. state.completedCount)
    Display.setCursorPos(1, 4)
    Display.write("----------------------------")
    
    -- Worker status
    local line = 5
    local workerList = {}
    local workerLines = {}
    
    for id, worker in pairs(state.workers) do
        table.insert(workerList, {id = id, worker = worker})
    end
    
    -- Sort by ID for consistent display
    table.sort(workerList, function(a, b) return a.id < b.id end)
    
    for _, entry in ipairs(workerList) do
        if line >= Display.displayHeight - 1 then break end
        
        local id = entry.id
        local worker = entry.worker
        
        -- Store line number for this worker (for touch detection)
        workerLines[line] = id
        
        Display.setCursorPos(1, line)
        
        -- Status color coding
        if worker.status == "complete" then
            Display.setColor(colors.lime)
        elseif worker.status == "timeout" then
            Display.setColor(colors.red)
        elseif worker.status == "mining" then
            Display.setColor(colors.lightBlue)
        elseif worker.status == "queued" or worker.status == "accessing_resource" then
            Display.setColor(colors.yellow)
        elseif worker.status == "ready" then
            Display.setColor(colors.orange)
        else
            Display.setColor(colors.lightGray)
        end
        
        -- Turtle ID
        Display.write("T" .. id .. ": ")
        
        -- Status
        Display.setColor(colors.white)
        if worker.status == "complete" then
            Display.write("DONE")
        elseif worker.status == "timeout" then
            Display.setColor(colors.red)
            Display.write("TIMEOUT")
        elseif worker.status == "mining" then
            Display.write("Mining")
        elseif worker.status == "queued" then
            Display.write("Queued")
        elseif worker.status == "accessing_resource" then
            Display.write("Resource")
        elseif worker.status == "ready" then
            Display.write("Ready")
        else
            Display.write(worker.status or "Init")
        end
        
        -- GPS position if available, otherwise dig position
        if worker.gps_position then
            Display.setColor(colors.lightGray)
            Display.setCursorPos(20, line)
            Display.write(string.format("GPS:%d,%d,%d", 
                math.floor(worker.gps_position.x or 0),
                math.floor(worker.gps_position.y or 0),
                math.floor(worker.gps_position.z or 0)))
        elseif worker.position then
            Display.setColor(colors.lightGray)
            Display.setCursorPos(20, line)
            Display.write(string.format("Pos:%d,%d,%d", 
                worker.position.x or 0,
                worker.position.y or 0,
                worker.position.z or 0))
        end
        
        if worker.fuel then
            Display.setColor(colors.orange)
            Display.setCursorPos(45, line)
            Display.write(string.format("F:%d", worker.fuel))
        end
        
        line = line + 1
    end
    
    -- Queue status at bottom (clickable)
    local queueLine = Display.displayHeight - 2
    if line < queueLine then
        Display.setCursorPos(1, queueLine)
        Display.setColor(colors.white)
        Display.write("Queues - ")
        Display.setColor(colors.cyan)
        Display.write("[Fuel: " .. #state.fuelQueue .. "]")
        Display.setColor(colors.white)
        Display.write(" | ")
        Display.setColor(colors.cyan)
        Display.write("[Output: " .. #state.outputQueue .. "]")
    end
    
    -- Status line at very bottom
    Display.setCursorPos(1, Display.displayHeight)
    if state.aborted then
        Display.setColor(colors.red)
        Display.write("Status: ABORTED - Workers Returning")
    elseif state.miningStarted then
        Display.setColor(colors.lightGray)
        Display.write("Status: Mining Active (Q=Abort)")
    else
        Display.setColor(colors.lightGray)
        Display.write("Status: Waiting...")
    end
    
    -- Return worker line mapping and queue line for touch detection
    return workerLines, queueLine
end

-- Main update function
function Display.update(state)
    if Display.viewState.mode == "worker" and Display.viewState.selectedWorker then
        Display.showWorkerDetail(state, Display.viewState.selectedWorker)
        return nil, nil, nil, nil, nil
    elseif Display.viewState.mode == "fuel_queue" then
        local removeButtons, clearAllLine = Display.showQueueDetail(state, "fuel")
        return nil, nil, removeButtons, clearAllLine, "fuel"
    elseif Display.viewState.mode == "output_queue" then
        local removeButtons, clearAllLine = Display.showQueueDetail(state, "output")
        return nil, nil, removeButtons, clearAllLine, "output"
    else
        return Display.showMainView(state)
    end
end

-- Handle touch events
-- Returns: viewChanged, actionType, actionData
function Display.handleTouch(x, y, workerLines, queueLine, removeButtons, clearAllLine, queueType)
    if Display.viewState.mode == "fuel_queue" or Display.viewState.mode == "output_queue" then
        -- Check if clicking on remove button [X]
        if removeButtons and removeButtons[y] and x >= 1 and x <= 3 then
            -- Clicked on [X] button for a queue entry
            return true, "remove_from_queue", {queueType = queueType, position = removeButtons[y]}
        elseif clearAllLine and y == clearAllLine and x >= 19 then
            -- Clicked on [Clear All] button (starts around x=19-22 depending on queue size)
            return true, "clear_queue", {queueType = queueType}
        else
            -- Any other touch returns to main
            Display.viewState.mode = "main"
            Display.viewState.selectedWorker = nil
            return true, nil, nil
        end
    elseif Display.viewState.mode == "worker" then
        -- Any touch in worker view returns to main
        Display.viewState.mode = "main"
        Display.viewState.selectedWorker = nil
        return true, nil, nil
    elseif Display.viewState.mode == "main" then
        if workerLines and workerLines[y] then
            -- Touch on a worker line - show worker details
            Display.viewState.mode = "worker"
            Display.viewState.selectedWorker = workerLines[y]
            return true, nil, nil
        elseif queueLine and y == queueLine then
            -- Touch on queue line - determine which queue based on x position
            -- "Queues - [Fuel: X] | [Output: Y]"
            -- Fuel is roughly at x 10-20, Output at x 25+
            if x < 24 then
                Display.viewState.mode = "fuel_queue"
            else
                Display.viewState.mode = "output_queue"
            end
            return true, nil, nil
        end
    end
    return false, nil, nil
end

return Display
