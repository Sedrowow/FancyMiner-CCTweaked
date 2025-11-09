# Multi-Turtle Orchestrated Quarry System

A coordinated quarrying system for ComputerCraft that allows multiple turtles to work together on large excavation projects, managed by a central computer server.

## Architecture

The system consists of four main components:

1. **Orchestration Server** (`orchestrate_server.lua`) - Central computer that coordinates all workers
2. **Deployment Turtle** (`orchestrate_deploy.lua`) - Places worker turtles and becomes a worker itself
3. **Worker Bootstrap** (`disk/worker/bootstrap.lua`) - Minimal startup program that receives firmware
4. **Worker Firmware** (`disk/worker/quarry.lua` + APIs) - Full mining program transmitted after deployment

### How Worker Initialization Works

1. Worker turtles are pre-programmed with the lightweight bootstrap loader (saved as `startup.lua`)
2. When placed by the deployment turtle, they automatically run the bootstrap on startup
3. Bootstrap connects to broadcast channel and waits for firmware files
4. Deployment turtle transmits firmware files (quarry.lua, dig.lua, flex.lua) via modem in chunks
5. Workers reassemble and save the files locally
6. Bootstrap loads the APIs and executes the full quarry program
7. Workers receive zone assignments and begin coordinated mining

This approach solves the chicken-and-egg problem: workers only need a small bootstrap program initially, and receive the full firmware wirelessly after deployment.

## Features

- **Automatic Zone Division**: Server calculates optimal zone assignments based on quarry size and turtle count
- **Queue-Based Resource Access**: Sequential access to shared fuel and output chests prevents collisions
- **GPS-Enabled Navigation**: Workers use GPS to navigate outside their zones to shared resources
- **Crash Recovery**: State persistence allows resuming after unexpected shutdowns
- **Concurrent Operations**: Separate queues for fuel and output allow parallel access to different resources
- **Synchronized Startup**: All workers wait for ready signal before beginning mining

## Requirements

### Hardware
- 1 Computer (for orchestration server with ender modem)
- 1 Advanced Monitor (2x2 multi-block) - **Optional** for status display
- 1 Turtle (deployment turtle with ender modem)
- 2-13 additional Turtles (workers with ender modems)
- 2 Chests (fuel and output)
- 1 Floppy Disk with worker firmware
- GPS System (4+ computers positioned for triangulation)

### Software
- ComputerCraft (CC:Tweaked recommended)
- GPS host setup and operational

## Setup Instructions

### Quick Setup Helper

For easier setup, use the provided helper script:

```
wget https://raw.githubusercontent.com/Sedrowow/FancyMiner-CCTweaked/main/orchestrate_setup.lua setup.lua
setup
```

This will guide you through the setup process automatically.

### Manual Setup

### 1. Prepare the Floppy Disk

Create the following directory structure on a floppy disk:

```
disk/
  worker/
    bootstrap.lua
    quarry.lua
    dig.lua
    flex.lua
```

Copy the files from the `disk/worker/` directory to your floppy disk.

### 2. Set Up the Orchestration Server

1. Place a computer with a modem (ender modem recommended)
2. **Optional**: Attach a 2x2 advanced monitor for visual status display
   - Place 4 advanced monitors in a 2x2 configuration
   - Right-click with an empty hand to combine them
   - Attach to the computer (adjacent or via wired modem)
3. Copy `orchestrate_server.lua` to the computer
4. Run the server:
   ```
   orchestrate_server
   ```
5. Note the server's computer ID (displayed on startup)
6. If a monitor is detected, you'll see "Monitor detected: WxH" in the console

### 3. Prepare Worker Turtles

Before placing worker turtles in the deployment turtle's inventory, each worker must be pre-programmed:

1. On each worker turtle, copy the bootstrap loader:
   ```
   edit startup.lua
   ```
   
2. Paste the contents of `disk/worker/bootstrap.lua` or use pastebin:
   ```
   pastebin get <code> startup.lua
   ```
   
3. The worker is now ready for deployment

### 4. Prepare the Deployment Turtle

1. Place a turtle with:
   - Ender modem
   - Floppy disk drive attached (or adjacent)
   - Insert floppy disk with worker firmware
   
2. Load the turtle's inventory:
   - Slot 1: Output chest
   - Slot 2: Fuel chest
   - Slots 3-16: Pre-programmed worker turtles (up to 13)
   
3. Copy `orchestrate_deploy.lua`, `dig.lua`, and `flex.lua` to the turtle

4. Position the turtle at the quarry's starting location (origin point)

### 5. Start Deployment

1. On the deployment turtle, run:
   ```
   orchestrate_deploy
   ```

2. When prompted, enter:
   - Server channel ID (from step 2.4)
   - Quarry width (X-axis)
   - Quarry length (Z-axis)
   - Quarry depth
   - Skip depth (layers to skip from surface, 0 for none)

3. The turtle will:
   - Contact the server and receive zone assignments
   - Place output chest behind starting position
   - Place fuel chest adjacent to starting position
   - Deploy worker turtles at calculated positions
   - Transfer firmware via modem
   - Send zone assignments to workers

4. Workers will initialize and report ready

5. When all workers are ready, mining begins automatically

6. The deployment turtle will join as a worker

## Operation

### Resource Management

**Fuel Access**:
- Workers monitor fuel levels during mining
- When low, request fuel access from server
- Navigate to shared fuel chest using GPS
- Pull fuel, refuel, and return to zone
- Release access for next worker

**Output Chest Access**:
- Workers monitor inventory (slots 14-16)
- When full, request output access
- Navigate to shared output chest
- Deposit items (keeping fuel and blocks)
- Return to zone and release access

### Queue System

- Only one turtle can access each resource at a time
- Requests are processed in FIFO order
- Workers continue mining while queued
- Server broadcasts queue position updates

### GPS Navigation

- Workers validate position before/after resource trips
- Use GPS for long-distance navigation to chests
- Fall back to dead reckoning if GPS unavailable
- Fixed approach directions prevent collisions:
  - Output chest: Approach from south
  - Fuel chest: Approach from north

### Mining Pattern

Each worker:
- Mines assigned X-range (vertical slice)
- Full Z-length of quarry
- Layer-by-layer from top to specified depth
- Serpentine pattern within zone

## Monitoring

### Monitor Display (Optional)

If a monitor is attached to the server, it will display a real-time status dashboard:

**Header Section**:
- Total workers, ready count, and completed count
- Current operation status (Waiting/Mining Active)

**Worker Status** (per turtle):
- Turtle ID and current status:
  - DONE (green) - Zone complete
  - Mining (light blue) - Actively mining
  - Queued (yellow) - Waiting for resource access
  - Resource (yellow) - Accessing fuel/output chest
  - Ready (orange) - Initialized, waiting for start
  - Init (gray) - Initializing
- Current Y position (depth)
- Current fuel level

**Queue Information**:
- Number of workers waiting for fuel access
- Number of workers waiting for output access

The display updates automatically as workers report status changes.

**Monitor Setup**:
- Use a 2x2 advanced monitor configuration
- Server automatically scales text to 0.5 for optimal density
- No additional configuration required
- Display updates on all status changes and every 10 seconds from workers

### Server Console

The orchestration server displays:
- Worker registration and ready status
- Resource requests and queue positions
- Access grants and releases
- Zone completion notifications

### Worker Status

Workers send status updates including:
- Position (X, Y, Z, rotation)
- Fuel level
- Mining state
- Inventory summary

## Completion and Cleanup

When all workers finish their zones:

1. Server broadcasts "all complete" message
2. Deployment turtle receives cleanup command
3. Deployment turtle navigates to each worker
4. Workers return to surface near output chest
5. Deployment turtle collects workers
6. System shuts down gracefully

## Troubleshooting

### GPS Issues
- **Problem**: Workers report "GPS unavailable"
- **Solution**: Verify GPS system is operational, check range
- **Fallback**: Workers use dead reckoning until GPS restored

### Queue Timeout
- **Problem**: Worker stuck waiting for resource access
- **Solution**: Check if another worker crashed while holding lock
- **Workaround**: Restart server (releases all locks)

### Zone Boundary Violations
- **Problem**: Worker reports "Outside assigned zone"
- **Solution**: GPS drift correction built-in, worker attempts recovery
- **Check**: Verify GPS coverage over entire quarry area

### File Transfer Failure
- **Problem**: "Timeout waiting for acknowledgment"
- **Solution**: Check modem range, verify floppy disk files
- **Retry**: Deployment has 3 retry attempts per file

## Configuration

### Modifying Queue Timeout

In `orchestrate_server.lua`, change:
```lua
local timeout = os.startTimer(300) -- 300 seconds = 5 minutes
```

### Adjusting Fuel Threshold

In `disk/worker/quarry.lua`, modify:
```lua
local needed = 1000 -- Request fuel when below this level
```

### Changing Approach Directions

In `orchestrate_server.lua`, update:
```lua
local approachDir = (resourceType == "output") and "south" or "north"
```

## Advanced Usage

### Custom Zone Assignments

Modify the `calculateZones` function in `orchestrate_server.lua` to implement custom zone division strategies:
- Horizontal bands (Z-axis division)
- Depth layers (Y-axis division)
- Custom patterns for specific terrain

### Adding More Resource Types

1. Add new queue in `orchestrate_server.lua`:
   ```lua
   state.customQueue = {}
   state.customLock = false
   ```

2. Handle in `handleMessage` function
3. Add chest position tracking
4. Implement worker request/release logic

## Performance Tips

- Use ender modems for unlimited range
- Position GPS computers above quarry for best coverage
- Pre-fuel deployment turtle (reduces queue pressure)
- Use chest upgrades (diamond/crystal) for larger capacity
- Optimize zone count: 4-8 workers ideal for most quarries

## Limitations

- Maximum 13 worker turtles (inventory slots 3-16)
- Requires GPS coverage over entire operation area
- Modem message size limits large file transfers (32KB chunks)
- Sequential resource access may create bottlenecks on very large quarries

## Credits

Based on the original FancyMiner-CCTweaked quarry system by Sedrowow.
Extended with multi-turtle orchestration and GPS-aware resource management.

## License

Same license as parent project.
