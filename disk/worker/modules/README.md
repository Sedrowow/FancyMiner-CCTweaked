# Worker System Modules

This directory contains modular components for the worker turtle system that performs coordinated mining operations.

## Module Overview

### `logger.lua`
Centralized logging with file and screen output:
- Configurable screen and file logging
- Log levels (info, warn, error, debug)
- Section headers for better readability
- Automatic timestamping

**Key Functions:**
- `init(turtleID, toScreen, toFile)` - Initialize logger
- `log(message)` - Log a message
- `info/warn/error/debug(message)` - Log with level prefix
- `section(message)` - Log a section header

### `gps_utils.lua`
GPS utilities and helper functions:
- GPS coordinate retrieval with retry logic
- GPS formatting and validation
- Distance calculations (Manhattan and Euclidean)
- Position comparison

**Key Functions:**
- `getGPS(retries, timeout)` - Get GPS coordinates with retry
- `formatGPS(gps)` - Format GPS as string
- `equals(gps1, gps2, tolerance)` - Compare positions
- `manhattanDistance(gps1, gps2)` - Calculate Manhattan distance
- `distance(gps1, gps2)` - Calculate Euclidean distance
- `copy(gps)` - Copy GPS table
- `isValid(gps)` - Validate GPS structure

### `gps_navigation.lua`
GPS-based navigation using dig.lua for movement:
- Consolidated navigation system
- Cardinal direction management
- Pathfinding to GPS coordinates
- Direction calibration

**Key Functions:**
- `init(calibrate)` - Initialize GPS navigation system
- `updatePosition()` - Update current GPS position
- `getPosition()` - Get current GPS position
- `getStart()` - Get starting GPS position
- `getCurrentDirection()` - Get current cardinal direction
- `up/down()` - Vertical movement
- `goto(x, y, z)` - Navigate to GPS coordinates
- `faceDirection(direction)` - Face a cardinal direction
- `returnHome()` - Return to starting position

### `state.lua`
Worker state persistence and recovery:
- State serialization and deserialization
- Position and direction tracking
- Job status verification
- State restoration after restart

**Key Functions:**
- `save(turtleID, state, digAPI, gpsNavAPI)` - Save worker state
- `load(turtleID)` - Load worker state from disk
- `clear(turtleID)` - Delete state file
- `exists(turtleID)` - Check if state file exists
- `restore(savedState, digAPI, gpsNavAPI, logger)` - Restore position and state

### `communication.lua`
Complete server protocol implementation:
- Modem initialization and channel management
- All message types for worker-server communication
- Server discovery and connection
- Job status queries

**Key Functions:**
- `initModem(serverChannel)` - Initialize modem
- `sendMessage(modem, channel, message)` - Send message
- `broadcastOnline(modem, turtleID)` - Broadcast online status
- `waitForServerResponse(modem, turtleID, timeout)` - Wait for server
- `sendReady/sendFirmwareComplete/sendStatusUpdate()` - Status messages
- `sendZoneComplete/sendAbortAck()` - Completion messages
- `checkJobStatus(modem, serverChannel, turtleID, timeout)` - Check job
- `waitForZoneAssignment/waitForStartSignal()` - Wait for commands
- `readServerChannelFile/saveServerChannelFile()` - Channel persistence

### `resource_manager.lua`
Queued resource access management:
- Resource request and grant handling
- Queue position tracking
- Inventory dump and refuel operations
- Coordinated chest access with position restoration
- Fuel threshold calculation

**Key Functions:**
- `requestAccess(modem, serverChannel, turtleID, resourceType, logger)` - Request resource
- `releaseResource(modem, serverChannel, turtleID, resourceType, logger)` - Release resource
- `dumpInventory()` - Dump inventory to output chest
- `refuelFromChest()` - Refuel from fuel chest
- `accessResource(resourceType, returnPos, ...)` - Complete coordinated access
- `calculateFuelThreshold(config, logger)` - Calculate fuel threshold

### `firmware.lua`
Firmware file reception from server:
- Chunked file transfer handling
- File reassembly
- Receipt acknowledgment
- Progress tracking

**Key Functions:**
- `receiveFirmware(modem, serverChannel, turtleID, requiredFiles, logger)` - Receive all firmware

## File Structure

```
disk/worker/
├── modules/
│   ├── logger.lua           # Logging
│   ├── gps_utils.lua        # GPS utilities
│   ├── gps_navigation.lua   # GPS navigation
│   ├── state.lua            # State management
│   ├── communication.lua    # Server protocol
│   ├── resource_manager.lua # Resource queuing
│   └── firmware.lua         # Firmware reception
├── bootstrap.lua            # Worker initialization (~65 lines)
├── quarry.lua               # Main worker program (refactored)
├── dig.lua                  # Movement API
└── flex.lua                 # Utility functions
```

## Benefits

1. **Eliminated Duplication** - Single GPS and logging implementations
2. **Better Organization** - Clear separation of concerns
3. **Improved Maintainability** - Easy to locate and modify
4. **Enhanced Reliability** - Standardized error handling

## Design Principles

1. **Single Responsibility**: Each module has one focused purpose
2. **Loose Coupling**: Modules communicate through defined interfaces
3. **DRY**: No duplicate GPS or logging code
4. **Error Handling**: Consistent error return patterns
5. **Testability**: Modules can be tested independently
