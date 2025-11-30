-- Orchestration Server for Multi-Turtle Quarry System
-- Runs on a central computer to coordinate multiple mining turtles
-- Manages zone assignments, resource access queues, worker lifecycle, and firmware distribution

-- Load modules
local Log = dofile('orchestrate/log.lua')
local Display = require("orchestrate.display")
local State = require("orchestrate.state")
local Firmware = require("orchestrate.firmware")
local ResourceManager = require("orchestrate.resource_manager")
local ZoneManager = require("orchestrate.zone_manager")
local MessageHandler = require("orchestrate.message_handler")

-- Initialize message handler with dependencies
MessageHandler.init({
    Firmware = Firmware,
    ZoneManager = ZoneManager,
    ResourceManager = ResourceManager,
    State = State
})

local SERVER_CHANNEL = os.getComputerID()
local BROADCAST_CHANNEL = 65535

local state = State.create()

-- Initialize modem
local modem = peripheral.find("ender_modem")
if not modem then
    modem = peripheral.find("modem")
end

if not modem then
    error("No modem found! Server requires a modem to communicate.")
end

modem.open(SERVER_CHANNEL)
modem.open(BROADCAST_CHANNEL)

-- Initialize display
Log.init()
Log.wrapPrint()
Display.init()
print("Logging to server_log.txt (rotation enabled)")

print("Orchestration Server Started")
print("Server Channel: " .. SERVER_CHANNEL)
print("Computer ID: " .. os.getComputerID())

-- Handle incoming messages
local function handleMessage(message)
    local needsSave = MessageHandler.handle(modem, SERVER_CHANNEL, BROADCAST_CHANNEL, state, message)
    if needsSave then
        State.save(state)
    end
end

-- Main server loop
local function main()
    print("\n=== Orchestration Server Ready ===")
    
    -- Try to load previous state
    local loadedState, isRestart = State.load()
    if isRestart then
        state = loadedState
        print("Previous state loaded from disk")
        print("Deployment complete: " .. tostring(state.deploymentComplete))
        print("Mining started: " .. tostring(state.miningStarted))
        print("Total workers: " .. state.totalWorkers)
        print("Ready count: " .. state.readyCount)
        print("Completed: " .. state.completedCount)
        
        -- Check if firmware disk is available
        if state.deploymentComplete and not state.firmwareLoaded then
            print("\nChecking for firmware disk...")
            local success, err = pcall(function()
                Firmware.validate()
                state.firmwareLoaded = true
            end)
            if not success then
                print("Warning: Firmware disk not available - " .. tostring(err))
                print("Workers may need firmware disk to be reinserted")
            end
        end
        
        -- If mining was started, remind workers to continue
        if state.miningStarted and state.completedCount < state.totalWorkers then
            print("\nSending resume signal to all workers...")
            modem.transmit(BROADCAST_CHANNEL, SERVER_CHANNEL, {
                type = "start_mining"
            })
        end
    else
        print("Waiting for deployment requests...")
    end
    
    print("Press 'Q' to abort operation")
    print("Press 'R' to reset server state")
    print("Press Ctrl+T to stop\n")
    
    -- Initial display
    local workerLines, queueLine, removeButtons, clearAllLine, queueType = Display.update(state)
    
    -- Start timeout check timer
    local timeoutCheckTimer = os.startTimer(10) -- Check every 10 seconds
    
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        -- Check for resource timeouts and firmware transfer timeouts periodically
        if event == "timer" and p1 == timeoutCheckTimer then
            print("DEBUG: Timeout check timer fired")
            local timedOut, turtleID = ResourceManager.checkTimeout(state, "fuel")
            if timedOut then
                print("DEBUG: Fuel timeout triggered for turtle " .. turtleID)
                ResourceManager.grantNext(modem, SERVER_CHANNEL, state, "fuel")
                State.save(state)
                workerLines, queueLine, removeButtons, clearAllLine, queueType = Display.update(state)
            end
            
            timedOut, turtleID = ResourceManager.checkTimeout(state, "output")
            if timedOut then
                print("DEBUG: Output timeout triggered for turtle " .. turtleID)
                ResourceManager.grantNext(modem, SERVER_CHANNEL, state, "output")
                State.save(state)
                workerLines, queueLine, removeButtons, clearAllLine, queueType = Display.update(state)
            end
            
            -- Check for firmware transfer timeouts
            MessageHandler.checkFirmwareTimeouts(modem, SERVER_CHANNEL, BROADCAST_CHANNEL, state)
            
            timeoutCheckTimer = os.startTimer(10)
            print("DEBUG: Next timeout check in 10 seconds")
        end
        
        if event == "modem_message" then
            local side, channel, replyChannel, message, distance = p1, p2, p3, p4, p5
            handleMessage(message)
            workerLines, queueLine, removeButtons, clearAllLine, queueType = Display.update(state)
            
        elseif event == "monitor_touch" or event == "mouse_click" then
            local side, x, y = p1, p2, p3
            
            local viewChanged, actionType, actionData = Display.handleTouch(x, y, workerLines, queueLine, removeButtons, clearAllLine, queueType)
            
            if actionType == "remove_from_queue" then
                -- Remove specific entry from queue
                local queue = (actionData.queueType == "fuel") and state.fuelQueue or state.outputQueue
                local removedID = table.remove(queue, actionData.position)
                print("Removed turtle " .. removedID .. " from " .. actionData.queueType .. " queue (position " .. actionData.position .. ")")
                State.save(state)
                workerLines, queueLine, removeButtons, clearAllLine, queueType = Display.update(state)
            elseif actionType == "clear_queue" then
                -- Clear entire queue
                local queue = (actionData.queueType == "fuel") and state.fuelQueue or state.outputQueue
                local count = #queue
                if actionData.queueType == "fuel" then
                    state.fuelQueue = {}
                else
                    state.outputQueue = {}
                end
                print("Cleared " .. actionData.queueType .. " queue (" .. count .. " entries removed)")
                State.save(state)
                workerLines, queueLine, removeButtons, clearAllLine, queueType = Display.update(state)
            elseif viewChanged then
                workerLines, queueLine, removeButtons, clearAllLine, queueType = Display.update(state)
            end
            
        elseif event == "key" then
            local key = p1
            -- Q key = 16
            if key == keys.q and state.miningStarted and not state.aborted then
                print("\n=== ABORT INITIATED ===")
                print("Sending abort command to all workers...")
                
                state.aborted = true
                state.abortAckCount = 0
                
                -- Broadcast abort command
                modem.transmit(BROADCAST_CHANNEL, SERVER_CHANNEL, {
                    type = "abort_mining"
                })
                
                print("Abort command sent. Waiting for workers to return...")
                State.save(state)
                workerLines, queueLine, removeButtons, clearAllLine, queueType = Display.update(state)
            -- R key = 19
            elseif key == keys.r then
                print("\n=== RESET INITIATED ===")
                print("Are you sure you want to reset the server state? (Y/N)")
                
                local confirmEvent, confirmKey = os.pullEvent("key")
                -- Y key = 21
                if confirmKey == keys.y then
                    print("Resetting server state...")
                    state = State.reset()
                    
                    -- Broadcast reset to workers (optional - they can reconnect)
                    modem.transmit(BROADCAST_CHANNEL, SERVER_CHANNEL, {
                        type = "server_reset"
                    })
                    
                    print("Server state reset complete.")
                    print("Waiting for new deployment requests...")
                    workerLines, queueLine, removeButtons, clearAllLine, queueType = Display.update(state)
                else
                    print("Reset cancelled.")
                end
            end
        end
    end
end

-- Run server
local success, err = pcall(main)
if not success then
    print("Server error: " .. tostring(err))
    State.save(state)
end
