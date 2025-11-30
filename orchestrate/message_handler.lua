-- Message Handler Module for Orchestration Server
-- Handles all incoming modem messages from workers and deployer

local MessageHandler = {}

-- Dependencies (will be injected)
local Firmware, ZoneManager, ResourceManager, State

function MessageHandler.init(deps)
    Firmware = deps.Firmware
    ZoneManager = deps.ZoneManager
    ResourceManager = deps.ResourceManager
    State = deps.State
end

-- Handle deploy_request message
local function handleDeployRequest(modem, serverChannel, broadcastChannel, state, message)
    state.deployerID = message.deployer_id
    state.totalWorkers = message.num_workers
    state.quarryParams = message.quarry_params
    state.isDeployerWorker = message.is_deployer or false
    
    local zones = ZoneManager.calculateZones(
        message.quarry_params.width,
        message.quarry_params.length,
        message.quarry_params.depth,
        message.quarry_params.skip,
        message.num_workers
    )
    
    state.zones = zones
    
    modem.transmit(serverChannel, serverChannel, {
        type = "deploy_command",
        deployer_id = message.deployer_id,
        num_workers = message.num_workers,
        server_channel = serverChannel,
        zones = zones,
        quarry = message.quarry_params
    })
    
    state.deployerFacing = message.deployer_facing -- optional explicit facing
    print("Deployment initiated for " .. message.num_workers .. " workers")
    print("Calculated " .. #zones .. " zones")
    if state.deployerFacing then
        print("Deployer facing override received: " .. tostring(state.deployerFacing))
    end
    return true
end

-- Handle chest_positions message
local function handleChestPositions(modem, serverChannel, state, message)
    state.chestPositions.fuel = message.fuel_gps
    state.chestPositions.output = message.output_gps
    state.startGPS = message.start_gps
    local startGPS = message.start_gps
    
    print("Chest positions registered")
    print("Fuel: " .. textutils.serialize(message.fuel_gps))
    print("Output: " .. textutils.serialize(message.output_gps))
    print("Start: " .. textutils.serialize(startGPS))
    
    if not state.zones then
        print("Error: state.zones is nil!")
        return false
    end
    
    -- Calculate initial direction based on chest positions
    local initialDirection = ZoneManager.calculateInitialDirection(
        state.chestPositions.fuel,
        state.chestPositions.output
    )

    print("Calculated initial direction: " .. initialDirection)
    if state.deployerFacing then
        print("Deployer facing override present: will use for mining facing, zones still based on chests")
    end
    
    local gpsZones, err = ZoneManager.createGPSZones(state.zones, startGPS, initialDirection)
    if not gpsZones then
        print("Error creating GPS zones: " .. err)
        return false
    end
    
    state.gpsZones = gpsZones
    state.initialDirection = initialDirection
    print("GPS zones calculated with coordinate transformation")

    -- Debug: list all GPS zones for verification
    for i, gz in ipairs(state.gpsZones) do
        print(string.format("  Zone %d GPS: X[%d-%d] Z[%d-%d] Y[%d-%d]", i, gz.gps_xmin, gz.gps_xmax, gz.gps_zmin, gz.gps_zmax, gz.gps_ymin, gz.gps_ymax))
    end
    
    if not state.firmwareLoaded then
        state.firmwareLoaded = true
    end
    
    return true
end

-- Handle worker_online message
local function handleWorkerOnline(modem, serverChannel, broadcastChannel, state, message)
    local turtleID = message.turtle_id
    local currentTime = os.clock()
    local lastRequest = state.firmwareRequests[turtleID] or 0
    
    -- Only respond if haven't sent recently (allow re-send after 30 seconds)
    if (currentTime - lastRequest) > 30 then
        print("Worker " .. turtleID .. " online, sending server info...")
        
        modem.transmit(broadcastChannel, serverChannel, {
            type = "server_response",
            turtle_id = turtleID,
            server_channel = serverChannel
        })
        
        state.firmwareRequests[turtleID] = currentTime
    end
    
    return false -- No state save needed yet
end

-- Handle version_check message
local function handleVersionCheck(modem, serverChannel, state, message)
    local turtleID = message.turtle_id
    local workerVersion = message.current_version
    
    -- Get server version
    local serverVersion = nil
    if fs.exists(".local_version.txt") then
        local f = fs.open(".local_version.txt", "r")
        serverVersion = f.readAll()
        f.close()
    end
    
    local upToDate = (workerVersion == serverVersion and workerVersion ~= nil)
    
    print("Worker " .. turtleID .. " version check: worker=" .. (workerVersion or "none") .. ", server=" .. (serverVersion or "unknown") .. ", up-to-date=" .. tostring(upToDate))
    
    modem.transmit(serverChannel, serverChannel, {
        type = "version_response",
        turtle_id = turtleID,
        server_version = serverVersion,
        up_to_date = upToDate
    })
    
    -- If update needed, send firmware
    if not upToDate then
        print("Starting firmware transfer to turtle " .. turtleID .. "...")
        
        local currentTime = os.clock()
        
        -- Track firmware transfer state
        if not state.firmwareTransfers then
            state.firmwareTransfers = {}
        end
        
        state.firmwareTransfers[turtleID] = {
            startTime = currentTime,
            attempts = (state.firmwareTransfers[turtleID] and state.firmwareTransfers[turtleID].attempts or 0) + 1,
            complete = false
        }
        
        sleep(0.5)
        Firmware.sendToWorker(modem, serverChannel, turtleID)
        
        -- Start timer for firmware completion check
        state.firmwareTransfers[turtleID].checkTimer = os.startTimer(30)
    else
        print("Worker " .. turtleID .. " firmware is up-to-date, skipping transfer")
    end
    
    return false
end

-- Handle file_received message
local function handleFileReceived(message)
    print("Turtle " .. message.turtle_id .. " received " .. message.filename)
    return false
end

-- Handle firmware_complete message
local function handleFirmwareComplete(state, message)
    local turtleID = message.turtle_id
    print("Turtle " .. turtleID .. " confirmed firmware reception complete")
    
    if state.firmwareTransfers and state.firmwareTransfers[turtleID] then
        state.firmwareTransfers[turtleID].complete = true
        if state.firmwareTransfers[turtleID].checkTimer then
            os.cancelTimer(state.firmwareTransfers[turtleID].checkTimer)
        end
    end
    
    return false
end

-- Handle ready_for_assignment message
local function handleReadyForAssignment(modem, serverChannel, state, message)
    local turtleID = message.turtle_id
    local workerGPS = message.gps_position
    
    if not workerGPS then
        print("Error: Turtle " .. turtleID .. " did not provide GPS position")
        return false
    end
    
    if not state.workers[turtleID] then
        state.workers[turtleID] = {}
    end
    
    print("Turtle " .. turtleID .. " ready at GPS (" .. workerGPS.x .. ", " .. workerGPS.y .. ", " .. workerGPS.z .. "), assigning zone...")
    
    if not state.zones or not state.gpsZones then
        print("  Error: Zones not initialized yet!")
        return false
    end
    
    local matchedZone, gpsZone = ZoneManager.findZoneForPosition(state.gpsZones, workerGPS)
    
    if matchedZone then
        print("  Checking zone " .. matchedZone .. ": X[" .. gpsZone.gps_xmin .. "-" .. gpsZone.gps_xmax .. "] Z[" .. gpsZone.gps_zmin .. "-" .. gpsZone.gps_zmax .. "]")
        
        if gpsZone.assigned then
            -- Special handling: Workers placed on the start edge (same X as startGPS)
            -- often queue up along Z but share the same X, which all maps to zone 1.
            -- If the worker stands on the start X edge, assign the first unassigned
            -- zone whose Z range contains the worker, ignoring X.
            local startGPS = state.startGPS
            local assignedIndex = nil
            if startGPS and workerGPS.x == startGPS.x then
                for i = 1, #state.gpsZones do
                    local zc = state.gpsZones[i]
                    if not zc.assigned and workerGPS.z >= zc.gps_zmin and workerGPS.z <= zc.gps_zmax then
                        assignedIndex = i
                        gpsZone = zc
                        break
                    end
                end
            end

            if not assignedIndex then
                print("  ERROR: Zone " .. matchedZone .. " already assigned to turtle " .. gpsZone.turtle_id)
                print("  Cannot assign multiple workers to same zone!")
                print("  Turtle " .. turtleID .. " must be repositioned.")
                
                modem.transmit(serverChannel, serverChannel, {
                    type = "assignment_error",
                    turtle_id = turtleID,
                    error = "Zone already assigned. Reposition turtle and try again."
                })
                return false
            else
                print("  Start-edge placement detected; assigning next free zone " .. assignedIndex .. " by Z range")
                matchedZone = assignedIndex
            end
        end
        
        gpsZone.assigned = true
        gpsZone.turtle_id = turtleID
        
        -- Use stored initial direction from chest position calculation
        local initialDirection = state.initialDirection or ZoneManager.calculateInitialDirection(
            state.chestPositions.fuel,
            state.chestPositions.output
        )
        
        print("  Using initial direction: " .. initialDirection)

        -- Choose mining facing: if user provided deployerFacing, use it directly.
        -- Otherwise, derive as one-left of chest direction.
        local desiredFacing
        if state.deployerFacing then
            desiredFacing = state.deployerFacing
            print("  Using deployer override for desired facing: " .. desiredFacing)
        else
            local rotateLeft = { north = "west", west = "south", south = "east", east = "north" }
            desiredFacing = rotateLeft[initialDirection] or initialDirection
        end
        print("  Computed desired facing for mining: " .. desiredFacing)
        
        state.workers[turtleID].zone_index = matchedZone
        state.workers[turtleID].status = "assigned"
        
        modem.transmit(serverChannel, serverChannel, {
            type = "zone_assignment",
            turtle_id = turtleID,
            zone_index = matchedZone,
            zone = state.zones[matchedZone],
            gps_zone = gpsZone,
            chest_gps = {
                fuel = state.chestPositions.fuel,
                output = state.chestPositions.output
            },
            initial_direction = initialDirection,  -- Cardinal for dig +X axis mapping
            desired_facing = desiredFacing,        -- Workers should face this cardinal so forward = quarry length
            server_channel = serverChannel
        })
        
        print("  Assigned zone " .. matchedZone .. " (X: " .. state.zones[matchedZone].xmin .. "-" .. state.zones[matchedZone].xmax .. ")")
        return true
    else
        print("  Error: No zone found containing position (" .. workerGPS.x .. ", " .. workerGPS.z .. ")")
        print("  Worker is outside quarry boundaries!")
        if state.gpsZones then
            print("  Zone list:")
            for i = 1, #state.gpsZones do
                local z = state.gpsZones[i]
                print("    Zone " .. i .. ": X[" .. z.gps_xmin .. "-" .. z.gps_xmax .. "] Z[" .. z.gps_zmin .. "-" .. z.gps_zmax .. "]")
            end
        end
        return false
    end
end

-- Handle worker_ready message
local function handleWorkerReady(modem, serverChannel, broadcastChannel, state, message)
    local turtleID = message.turtle_id
    local wasReady = state.workers[turtleID] and state.workers[turtleID].status == "ready"
    
    print("DEBUG: Received worker_ready from turtle " .. turtleID .. " (wasReady=" .. tostring(wasReady) .. ")")
    
    if not state.workers[turtleID] then
        state.workers[turtleID] = {}
    end
    
    if not wasReady then
        state.readyCount = state.readyCount + 1
    end

    state.workers[turtleID].status = "ready"

    -- Recalculate readyCount from all workers with status == "ready"
    local actualReady = 0
    for id, w in pairs(state.workers) do
        if w.status == "ready" then actualReady = actualReady + 1 end
    end
    state.readyCount = actualReady

    print("Worker " .. turtleID .. " ready (" .. state.readyCount .. "/" .. state.totalWorkers .. ")")

    -- Start mining when all workers ready
    if state.readyCount >= state.totalWorkers and not state.miningStarted then
        state.miningStarted = true
        modem.transmit(broadcastChannel, serverChannel, {
            type = "start_mining"
        })
        print("All workers ready - mining started!")
    elseif state.miningStarted and state.workers[turtleID].status == "ready" then
        print("Sending start signal to restarted worker " .. turtleID)
        modem.transmit(serverChannel, serverChannel, {
            type = "start_mining"
        })
    end
    
    return true
end

-- Handle zone_complete message
local function handleZoneComplete(modem, serverChannel, state, message)
    state.completedCount = state.completedCount + 1
    local turtleID = message.turtle_id
    
    if state.workers[turtleID] then
        state.workers[turtleID].status = "complete"
        state.workers[turtleID].final_pos = message.final_pos
    end
    
    print("Turtle " .. turtleID .. " completed zone (" .. state.completedCount .. "/" .. state.totalWorkers .. ")")
    
    if turtleID == state.deployerID then
        print("  (Deployer)")
    end
    
    -- All zones complete, initiate cleanup
    if state.completedCount == state.totalWorkers then
        print("\n=== All zones complete! ===")
        
        if state.deployerID then
            print("Sending cleanup command to deployer...")
            modem.transmit(serverChannel, serverChannel, {
                type = "cleanup_command",
                turtle_id = state.deployerID
            })
        end
    end
    
    return true
end

-- Handle status_update message
local function handleStatusUpdate(state, message)
    if not state.workers[message.turtle_id] then
        state.workers[message.turtle_id] = {}
    end
    
    state.workers[message.turtle_id].lastUpdate = os.clock()
    state.workers[message.turtle_id].position = message.position
    state.workers[message.turtle_id].gps_position = message.gps_position
    state.workers[message.turtle_id].fuel = message.fuel
    state.workers[message.turtle_id].status = message.status
    
    return false -- Display will update, but don't need to save state for every update
end

-- Handle deployer_restart message
local function handleDeployerRestart(modem, serverChannel, state, message)
    print("Deployer " .. message.deployer_id .. " restarted, sending status...")
    
    local deploymentComplete = false
    local deploymentActive = false
    
    if state.deployerID == message.deployer_id then
        deploymentComplete = (state.chestPositions.fuel ~= nil and state.chestPositions.output ~= nil)
        deploymentActive = not deploymentComplete and not state.aborted and state.chestPositions.fuel ~= nil
    end
    
    modem.transmit(serverChannel, serverChannel, {
        type = "restart_response",
        deployer_id = message.deployer_id,
        deployment_complete = deploymentComplete,
        deployment_active = deploymentActive,
        zones = state.zones,
        chest_gps = state.chestPositions,
        start_gps = state.startGPS,
        server_channel = serverChannel
    })
    
    print("Sent restart response: complete=" .. tostring(deploymentComplete) .. ", active=" .. tostring(deploymentActive))
    return false
end

-- Handle deployment_complete message
local function handleDeploymentComplete(state, message)
    state.deploymentComplete = true
    print("Deployment complete - all workers placed")
    print("Waiting for workers to come online and download firmware...")
    return true
end

-- Handle worker_status_check message
local function handleWorkerStatusCheck(modem, serverChannel, state, message)
    local turtleID = message.turtle_id
    local jobActive = state.deploymentComplete and state.miningStarted and 
                      not state.aborted and state.completedCount < state.totalWorkers
    
    print("Worker " .. turtleID .. " status check - job active: " .. tostring(jobActive))
    print("DEBUG: Transmitting on channel " .. serverChannel .. " to turtle " .. turtleID)
    
    modem.transmit(serverChannel, serverChannel, {
        type = "job_status_response",
        turtle_id = turtleID,
        job_active = jobActive
    })
    
    print("DEBUG: Response sent")
    return false
end

-- Handle worker_status_check_detailed message
local function handleWorkerStatusCheckDetailed(modem, serverChannel, state, message)
    local turtleID = message.turtle_id
    local jobActive = state.deploymentComplete and state.miningStarted and 
                      not state.aborted and state.completedCount < state.totalWorkers
    
    print("Worker " .. turtleID .. " detailed status check - job active: " .. tostring(jobActive))
    
    local lastState = nil
    if jobActive and state.workers[turtleID] then
        -- Create clean copies of nested tables to avoid circular references
        local worker = state.workers[turtleID]
        
        -- Copy zone data
        local zoneCopy = nil
        if worker.zone then
            zoneCopy = {
                xmin = worker.zone.xmin,
                xmax = worker.zone.xmax,
                ymin = worker.zone.ymin,
                zmin = worker.zone.zmin,
                zmax = worker.zone.zmax,
                skip = worker.zone.skip
            }
        end
        
        -- Copy gps_zone data
        local gpsZoneCopy = nil
        if worker.gps_zone then
            gpsZoneCopy = {
                gps_xmin = worker.gps_zone.gps_xmin,
                gps_xmax = worker.gps_zone.gps_xmax,
                gps_ymin = worker.gps_zone.gps_ymin,
                gps_zmin = worker.gps_zone.gps_zmin,
                gps_zmax = worker.gps_zone.gps_zmax,
                initial_direction = worker.gps_zone.initial_direction
            }
        end
        
        -- Copy chest positions
        local chestCopy = nil
        if state.chestPositions then
            chestCopy = {
                fuel = state.chestPositions.fuel and {
                    x = state.chestPositions.fuel.x,
                    y = state.chestPositions.fuel.y,
                    z = state.chestPositions.fuel.z
                } or nil,
                output = state.chestPositions.output and {
                    x = state.chestPositions.output.x,
                    y = state.chestPositions.output.y,
                    z = state.chestPositions.output.z
                } or nil
            }
        end
        
        -- Copy GPS position
        local gpsCopy = nil
        if worker.gps_position then
            gpsCopy = {
                x = worker.gps_position.x,
                y = worker.gps_position.y,
                z = worker.gps_position.z
            }
        end
        
        -- Copy dig location array
        local digLocationCopy = nil
        if worker.position then
            digLocationCopy = {}
            for i = 1, #worker.position do
                digLocationCopy[i] = worker.position[i]
            end
        end
        
        lastState = {
            zone = zoneCopy,
            gps_zone = gpsZoneCopy,
            chestGPS = chestCopy,
            startGPS = gpsCopy,
            lastGPS = gpsCopy,
            digLocation = digLocationCopy
        }
    end
    
    modem.transmit(serverChannel, serverChannel, {
        type = "job_status_response_detailed",
        turtle_id = turtleID,
        job_active = jobActive,
        last_state = lastState
    })
    
    print("DEBUG: Detailed response sent")
    return false
end

-- Handle abort_ack message
local function handleAbortAck(state, message)
    state.abortAckCount = state.abortAckCount + 1
    if state.workers[message.turtle_id] then
        state.workers[message.turtle_id].status = "aborted"
    end
    print("Worker " .. message.turtle_id .. " acknowledged abort (" .. state.abortAckCount .. "/" .. state.totalWorkers .. ")")
    
    if state.abortAckCount >= state.totalWorkers then
        print("\n=== All workers have aborted ===")
        print("Workers returned to starting positions")
        print("System halted. Restart server to begin new operation.")
    end
    
    return true
end

-- Check for firmware transfer timeouts and retry if needed
function MessageHandler.checkFirmwareTimeouts(modem, serverChannel, broadcastChannel, state)
    if not state.firmwareTransfers then
        return
    end
    
    -- Fast exit if no transfers in progress
    local hasActiveTransfers = false
    for _, transfer in pairs(state.firmwareTransfers) do
        if not transfer.complete then
            hasActiveTransfers = true
            break
        end
    end
    
    if not hasActiveTransfers then
        return
    end
    
    local currentTime = os.clock()
    
    for turtleID, transfer in pairs(state.firmwareTransfers) do
        if not transfer.complete and transfer.attempts < 3 then
            -- Check if enough time has passed (30 seconds)
            if (currentTime - transfer.startTime) > 30 then
                print("Firmware transfer timeout for turtle " .. turtleID .. " (attempt " .. transfer.attempts .. "), retrying...")
                
                -- Reset timer and resend
                transfer.startTime = currentTime
                transfer.attempts = transfer.attempts + 1
                
                modem.transmit(broadcastChannel, serverChannel, {
                    type = "server_response",
                    turtle_id = turtleID,
                    server_channel = serverChannel
                })
                
                sleep(1.5)
                Firmware.sendToWorker(modem, serverChannel, turtleID)
            end
        elseif transfer.attempts >= 3 and not transfer.complete then
            print("Firmware transfer failed for turtle " .. turtleID .. " after 3 attempts")
            state.firmwareTransfers[turtleID] = nil
        end
    end
end

-- Main message handler dispatcher
function MessageHandler.handle(modem, serverChannel, broadcastChannel, state, message)
    if type(message) ~= "table" then 
        return false
    end
    
    local needsSave = false
    
    if message.type == "deploy_request" then
        needsSave = handleDeployRequest(modem, serverChannel, broadcastChannel, state, message)
        
    elseif message.type == "chest_positions" then
        needsSave = handleChestPositions(modem, serverChannel, state, message)
        
    elseif message.type == "worker_online" then
        needsSave = handleWorkerOnline(modem, serverChannel, broadcastChannel, state, message)
        
    elseif message.type == "version_check" then
        needsSave = handleVersionCheck(modem, serverChannel, state, message)
        
    elseif message.type == "get_version" then
        local turtleID = message.turtle_id
        local serverVersion = nil
        if fs.exists(".local_version.txt") then
            local f = fs.open(".local_version.txt", "r")
            serverVersion = f.readAll()
            f.close()
        end
        modem.transmit(serverChannel, serverChannel, {
            type = "version_info",
            turtle_id = turtleID,
            version = serverVersion
        })
        needsSave = false
        
    elseif message.type == "file_received" then
        needsSave = handleFileReceived(message)
        
    elseif message.type == "firmware_complete" then
        needsSave = handleFirmwareComplete(state, message)
        
    elseif message.type == "ready_for_assignment" then
        needsSave = handleReadyForAssignment(modem, serverChannel, state, message)
        
    elseif message.type == "worker_ready" then
        needsSave = handleWorkerReady(modem, serverChannel, broadcastChannel, state, message)
        
    elseif message.type == "resource_request" then
        needsSave = ResourceManager.handleRequest(modem, serverChannel, state, 
                                                   message.turtle_id, message.resource)
        
    elseif message.type == "resource_released" then
        needsSave = ResourceManager.handleRelease(modem, serverChannel, state, 
                                                   message.turtle_id, message.resource)
        
    elseif message.type == "zone_complete" then
        needsSave = handleZoneComplete(modem, serverChannel, state, message)
        
    elseif message.type == "status_update" then
        needsSave = handleStatusUpdate(state, message)
        
    elseif message.type == "deployer_restart" then
        needsSave = handleDeployerRestart(modem, serverChannel, state, message)
        
    elseif message.type == "deployment_complete" then
        needsSave = handleDeploymentComplete(state, message)
        
    elseif message.type == "worker_status_check" then
        needsSave = handleWorkerStatusCheck(modem, serverChannel, state, message)
        
    elseif message.type == "worker_status_check_detailed" then
        needsSave = handleWorkerStatusCheckDetailed(modem, serverChannel, state, message)
        
    elseif message.type == "abort_ack" then
        needsSave = handleAbortAck(state, message)
    end
    
    return needsSave
end

return MessageHandler
