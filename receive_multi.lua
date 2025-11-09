-- Multi-Turtle Status Monitor for Orchestration System
-- Displays status updates from multiple coordinated mining turtles

os.loadAPI("flex.lua")

local modem_channel = 6464
local options_file = "flex_options.cfg"

-- Load channel from config
if fs.exists(options_file) then
    local file = fs.open(options_file, "r")
    local line = file.readLine()
    while line ~= nil do
        if string.find(line, "modem_channel=") == 1 then
            modem_channel = tonumber(string.sub(line, 15, string.len(line)))
            break
        end
        line = file.readLine()
    end
    file.close()
end

-- Find and configure modem
local modem
local p = flex.getPeripheral("modem")
if #p > 0 then
    modem = peripheral.wrap(p[1])
    modem.open(modem_channel)
else
    print("ERROR: No modem found!")
    print("Please attach a wireless or ender modem.")
    return
end

-- Track multiple turtles
local turtles = {} -- [turtle_id] = {status data, lastUpdate}
local displayMode = "summary" -- "summary" or "detail"
local selectedTurtle = nil
local sortBy = "id" -- "id", "fuel", "depth", "progress"

-- Get terminal dimensions
local termWidth, termHeight = term.getSize()
local isPocket = (termWidth <= 26) -- Detect pocket computer

local function formatTime(seconds)
    if not seconds or seconds < 0 then
        return "Calculating..."
    end
    
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    elseif mins > 0 then
        return string.format("%dm %ds", mins, secs)
    else
        return string.format("%ds", secs)
    end
end

local function formatNumber(num)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(num)
    end
end

local function calculateProgress(status)
    if not status.total_quarry_blocks or status.total_quarry_blocks == 0 then
        return 0
    end
    return (status.processed_blocks or 0) / status.total_quarry_blocks * 100
end

local function getSortedTurtles()
    local sorted = {}
    for id, data in pairs(turtles) do
        table.insert(sorted, {id = id, data = data})
    end
    
    table.sort(sorted, function(a, b)
        if sortBy == "id" then
            return a.id < b.id
        elseif sortBy == "fuel" then
            return (a.data.status.fuel or 0) > (b.data.status.fuel or 0)
        elseif sortBy == "depth" then
            return (a.data.status.position.y or 0) < (b.data.status.position.y or 0)
        elseif sortBy == "progress" then
            return calculateProgress(a.data.status) > calculateProgress(b.data.status)
        end
        return a.id < b.id
    end)
    
    return sorted
end

local function displaySummary()
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Header
    term.setTextColor(colors.yellow)
    if isPocket then
        print("=== Workers ===")
    else
        print("=== Multi-Turtle Status Monitor ===")
    end
    
    term.setTextColor(colors.white)
    local activeCount = 0
    for _ in pairs(turtles) do activeCount = activeCount + 1 end
    print("Active Turtles: " .. activeCount)
    
    if activeCount == 0 then
        term.setTextColor(colors.lightGray)
        print("\nWaiting for status updates...")
        print("Listening on channel " .. modem_channel)
        return
    end
    
    print()
    
    -- Column headers
    if not isPocket then
        term.setTextColor(colors.lightBlue)
        if termWidth >= 51 then
            print("ID   Fuel    Depth  Progress  ETA       Status")
            print("------------------------------------------------")
        else
            print("ID   Fuel  Depth  Prog%  Status")
            print("--------------------------------")
        end
    end
    
    -- Turtle list
    local sorted = getSortedTurtles()
    local maxDisplay = isPocket and 6 or (termHeight - 6)
    
    for i, entry in ipairs(sorted) do
        if i > maxDisplay then break end
        
        local id = entry.id
        local data = entry.data
        local status = data.status
        
        -- Color based on status
        local statusColor = colors.white
        if status.is_mining then
            statusColor = colors.lime
        elseif status.fuel and status.fuel < 1000 then
            statusColor = colors.red
        elseif not status.is_mining then
            statusColor = colors.orange
        end
        
        term.setTextColor(statusColor)
        
        if isPocket then
            -- Compact display for pocket computer
            local progress = calculateProgress(status)
            print(string.format("%d: %s%% F:%s",
                id,
                string.format("%3d", math.floor(progress)),
                formatNumber(status.fuel or 0)
            ))
        elseif termWidth >= 51 then
            -- Full display for regular monitor
            local progress = calculateProgress(status)
            local depth = math.abs(status.position.y or 0)
            local targetDepth = math.abs(status.ymin or 0)
            local eta = status.estimated_time_remaining or "Calc..."
            local statusText = status.is_mining and "Mining" or "Idle"
            
            print(string.format("%-4d %-7s %3d/%3d  %3d%%    %-9s %s",
                id,
                formatNumber(status.fuel or 0),
                depth,
                targetDepth,
                math.floor(progress),
                eta,
                statusText
            ))
        else
            -- Medium display
            local progress = calculateProgress(status)
            local depth = math.abs(status.position.y or 0)
            local statusText = status.is_mining and "Mine" or "Idle"
            
            print(string.format("%-4d %-5s %-5d %3d%%  %s",
                id,
                formatNumber(status.fuel or 0),
                depth,
                math.floor(progress),
                statusText
            ))
        end
    end
    
    -- Controls
    if not isPocket then
        print()
        term.setTextColor(colors.lightGray)
        print("Sort: [I]D [F]uel [D]epth [P]rogress")
        print("[Enter] Detail view  [Q] Quit")
    end
end

local function displayDetail(turtleID)
    term.clear()
    term.setCursorPos(1, 1)
    
    local data = turtles[turtleID]
    if not data then
        term.setTextColor(colors.red)
        print("Turtle " .. turtleID .. " not found!")
        sleep(2)
        return
    end
    
    local status = data.status
    
    -- Header
    term.setTextColor(colors.yellow)
    print("=== Turtle " .. turtleID .. " ===")
    
    if status.label and status.label ~= "" then
        term.setTextColor(colors.white)
        print("Label: " .. status.label)
    end
    
    print()
    
    -- Status
    term.setTextColor(colors.orange)
    print("Fuel: " .. (status.fuel or 0))
    
    term.setTextColor(colors.lightGray)
    print(string.format("Pos: X=%d, Y=%d, Z=%d",
        status.position.x or 0,
        status.position.y or 0,
        status.position.z or 0))
    
    term.setTextColor(colors.white)
    print("Mining: " .. tostring(status.is_mining))
    
    -- Progress
    term.setTextColor(colors.lightBlue)
    if status.total_quarry_blocks then
        local progress = calculateProgress(status)
        print(string.format("Progress: %d / %d (%.1f%%)",
            status.processed_blocks or 0,
            status.total_quarry_blocks,
            progress))
    end
    
    term.setTextColor(colors.lightBlue)
    print("Dug: " .. (status.dug_blocks or 0) .. " blocks")
    
    -- Depth
    term.setTextColor(colors.green)
    local depth = math.abs(status.position.y or 0)
    local targetDepth = math.abs(status.ymin or 0)
    print(string.format("Depth: %dm / %dm", depth, targetDepth))
    
    -- ETA
    term.setTextColor(colors.yellow)
    print("ETA: " .. (status.estimated_time_remaining or "Calculating..."))
    print("Done: " .. (status.estimated_completion_time or "Calculating..."))
    
    -- Inventory (if space permits)
    if termHeight > 20 and status.inventory_summary then
        print()
        term.setTextColor(colors.white)
        print("Inventory:")
        local maxItems = math.min(#status.inventory_summary, termHeight - 18)
        for i = 1, maxItems do
            local item = status.inventory_summary[i]
            print("  " .. item.name .. " (" .. item.count .. ")")
        end
        if #status.inventory_summary > maxItems then
            print("  ... and " .. (#status.inventory_summary - maxItems) .. " more")
        end
    end
    
    -- Last update
    print()
    term.setTextColor(colors.lightGray)
    local timeSince = os.clock() - data.lastUpdate
    print(string.format("Updated: %.1fs ago", timeSince))
    
    print()
    print("[Backspace] Return  [Q] Quit")
end

local function handleInput()
    -- Non-blocking key check
    local event, key = os.pullEvent()
    
    if event == "key" then
        if key == keys.q then
            return "quit"
        elseif key == keys.i then
            sortBy = "id"
        elseif key == keys.f then
            sortBy = "fuel"
        elseif key == keys.d then
            sortBy = "depth"
        elseif key == keys.p then
            sortBy = "progress"
        elseif key == keys.enter then
            if displayMode == "summary" then
                local sorted = getSortedTurtles()
                if #sorted > 0 then
                    selectedTurtle = sorted[1].id
                    displayMode = "detail"
                end
            end
        elseif key == keys.backspace then
            if displayMode == "detail" then
                displayMode = "summary"
                selectedTurtle = nil
            end
        end
    elseif event == "modem_message" then
        local modemSide, senderChannel, replyChannel, message, senderDistance = key, keys.f, keys.d, keys.p, keys.enter
        
        if senderChannel == modem_channel and type(message) == "table" then
            if message.type == "status_update" and message.id then
                turtles[message.id] = {
                    status = message,
                    lastUpdate = os.clock()
                }
            end
        end
    end
    
    return nil
end

-- Main loop
print("Multi-Turtle Status Monitor")
print("Listening on channel " .. modem_channel)
print("Waiting for turtle status updates...")
sleep(2)

local updateTimer = os.startTimer(1)

while true do
    -- Display current view
    if displayMode == "summary" then
        displaySummary()
    elseif displayMode == "detail" and selectedTurtle then
        displayDetail(selectedTurtle)
    end
    
    -- Handle events (non-blocking with parallel)
    local event, param1, param2, param3, param4, param5 = os.pullEvent()
    
    if event == "key" then
        if param1 == keys.q then
            break
        elseif param1 == keys.i then
            sortBy = "id"
        elseif param1 == keys.f then
            sortBy = "fuel"
        elseif param1 == keys.d then
            sortBy = "depth"
        elseif param1 == keys.p then
            sortBy = "progress"
        elseif param1 == keys.enter then
            if displayMode == "summary" then
                local sorted = getSortedTurtles()
                if #sorted > 0 then
                    selectedTurtle = sorted[1].id
                    displayMode = "detail"
                end
            end
        elseif param1 == keys.backspace then
            if displayMode == "detail" then
                displayMode = "summary"
                selectedTurtle = nil
            end
        end
    elseif event == "modem_message" then
        if param2 == modem_channel and type(param4) == "table" then
            if param4.type == "status_update" and param4.id then
                turtles[param4.id] = {
                    status = param4,
                    lastUpdate = os.clock()
                }
            end
        end
    elseif event == "timer" and param1 == updateTimer then
        updateTimer = os.startTimer(1)
    end
end

-- Cleanup
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.white)
print("Monitor stopped.")
