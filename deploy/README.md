# Deployment System Modules

This directory contains modular components for the deployment system that sets up worker turtles for mining operations.

## Module Overview

### `state.lua`
Manages deployment state persistence:
- State structure creation and initialization
- Save/load operations to disk
- State recovery after restart
- State file cleanup

**Key Functions:**
- `create()` - Create a new deployment state
- `save(state)` - Save state to disk
- `load()` - Load state from disk
- `clear()` - Delete state file
- `exists()` - Check if state file exists

### `positioning.lua`
Handles GPS coordinate retrieval and utilities:
- GPS coordinate retrieval with retry logic
- GPS formatting and display
- Position comparison and distance calculation

**Key Functions:**
- `getGPS(retries)` - Get GPS coordinates with retry
- `formatGPS(gps)` - Format GPS as a string
- `equals(gps1, gps2)` - Compare two GPS positions
- `distance(gps1, gps2)` - Calculate distance between positions

### `worker_deployment.lua`
Manages worker turtle deployment:
- Finding turtles in inventory
- Deploying individual workers to zones
- Fueling workers
- Collecting workers during cleanup

**Key Functions:**
- `findTurtleSlots()` - Find turtles in slots 4-16
- `ensureFuel(digAPI)` - Ensure fuel is available
- `deployWorker(slot, zone, zoneIndex, digAPI)` - Deploy a single worker
- `deployAll(turtleSlots, zones, digAPI)` - Deploy all workers
- `collectWorkers(zones, digAPI)` - Collect workers during cleanup

### `chest_manager.lua`
Handles fuel and output chest placement and management:
- Placing output and fuel chests
- Tracking chest GPS positions
- Waiting for fuel to be added
- Ensuring deployer has sufficient fuel

**Key Functions:**
- `placeOutputChest(startGPS)` - Place output chest at Y+1
- `placeFuelChest(startGPS, digAPI)` - Place fuel chest at X+1, Y+1
- `placeChests(startGPS, digAPI)` - Place both chests
- `waitForFuel(digAPI)` - Wait for fuel in chest
- `ensureDeployerFuel(digAPI, minimumFuel)` - Ensure deployer has fuel

### `communication.lua`
Manages all server communication:
- Modem initialization and channel management
- Server protocol messages (deploy request, chest positions, etc.)
- User input for configuration
- Deployment state coordination with server

**Key Functions:**
- `initModem(serverChannel)` - Initialize modem and open channels
- `sendMessage(modem, channel, message)` - Send a message
- `checkPreviousDeployment(...)` - Check server about previous state
- `getQuarryParams()` - Get quarry parameters from user
- `sendDeployRequest(...)` - Send deployment request to server
- `waitForDeployCommand(modem, timeout)` - Wait for zone assignments
- `sendChestPositions(...)` - Notify server of chest locations
- `sendDeploymentComplete(...)` - Notify deployment complete
- `waitForCleanupCommand(...)` - Wait for cleanup signal
- `getServerChannel()` - Get server channel from user

## Usage

The main `orchestrate_deploy.lua` file loads all modules and coordinates their interaction. Each module is designed to be independent and focused on a single responsibility.

## Deployment Flow

1. **Initialization**
   - Load modules
   - Initialize modem
   - Check for previous deployment state

2. **Configuration**
   - Get GPS coordinates
   - Get server channel from user
   - Get quarry parameters
   - Count available worker turtles

3. **Server Coordination**
   - Send deployment request to server
   - Receive zone assignments

4. **Setup**
   - Place fuel and output chests
   - Wait for fuel to be added
   - Deploy worker turtles to their zones

5. **Worker Mode**
   - Deployer transitions to worker mode
   - Runs bootstrap.lua to become a worker

6. **Cleanup**
   - Wait for cleanup command from server
   - Collect all deployed workers
   - Return to starting position

## Design Principles

1. **Separation of Concerns**: Each module has a single, well-defined responsibility
2. **Error Handling**: All functions return success/error information
3. **State Management**: Centralized state with clear save/load semantics
4. **Recoverable**: Can resume after restart using saved state
5. **Readable**: Clear function names and comprehensive comments

## Error Recovery

The deployment system can recover from interruptions:
- State is saved at key checkpoints
- On restart, checks with server about previous deployment
- Can resume or start fresh based on server response
- State file is cleared if deployment needs to restart

## Dependencies

- `dig.lua` - Navigation API (for turtle movement)
- `flex.lua` - Flexibility API
- ComputerCraft peripherals (modem, GPS)
