# GPS Integration System for FancyMiner

## Overview
The GPS system has been integrated into the FancyMiner quarry program to prevent coordinate system corruption when chunks are unloaded/reloaded during turtle movement.

## How It Works

### 1. **GPS Origin Tracking**
- When a quarry starts, it calls `dig.initGPSOrigin()` 
- This attempts to get the turtle's current world coordinates using `gps.locate()`
- If GPS is available, it calculates the world coordinates of the origin point (0,0,0 in relative coords)
- Formula: `world_origin = current_world_position - current_relative_position`
- **Origin Preservation**: Once GPS origin is established, it won't be overwritten on subsequent runs
- **Late GPS Setup**: If GPS becomes available after a quarry has started, the system will return to origin to establish coordinates

### 2. **Coordinate Translation**
The system can convert between two coordinate systems:
- **Relative coordinates**: The turtle's internal tracking (X, Y, Z from starting point)
- **World coordinates**: Minecraft's absolute world position

Functions available:
- `dig.relativeToWorld(rx, ry, rz)` - Convert relative to world coords
- `dig.worldToRelative(wx, wy, wz)` - Convert world to relative coords

### 3. **Position Verification**
The system verifies position in three scenarios:

#### a) On Resume/Load
- When loading a saved quarry (`dig.loadCoords()`), it automatically:
  - Loads the saved GPS origin
  - Gets current GPS position
  - Compares actual position vs expected position
  - Auto-corrects if there's a mismatch (chunk unload issue)

#### b) Periodic Checks (Every 200 blocks)
- During mining, `checkProgress()` calls `dig.verifyPositionGPS()` periodically
- Only corrects if position differs by more than 1 block (prevents false positives)
- GPS coordinates are rounded to nearest integer to avoid sub-block precision issues
- Auto-corrects any significant drift

#### c) Manual Recovery
- Call `dig.recoverPositionGPS()` to force a position check and correction

### 4. **Graceful Fallback**
- If GPS is not available (no GPS hosts nearby), the system works normally
- Uses traditional relative coordinate tracking
- Shows message: "GPS not available, using relative coordinates only"
- All GPS functions check `dig.isGPSEnabled()` before attempting GPS operations

## Setup Requirements

### GPS Hosts
To use GPS, you need at least 4 computers set up as GPS hosts. They must be:
1. Located at known coordinates
2. Running as GPS hosts (use ComputerCraft's `gps host` command)
3. Distributed in different positions (ideally forming a tetrahedron)

Example GPS host setup on each computer:
```lua
gps.host(x, y, z)
```

Or use the built-in program:
```
gps host <x> <y> <z>
```

### No Setup Required
If GPS hosts are not available, the system automatically falls back to relative coordinates.

## API Functions

### Initialization
- `dig.initGPSOrigin(force_new)` - Initialize GPS at current position (called automatically by quarry)
  - If origin already exists and `force_new` is false, verifies position instead of creating new origin
  - Returns false if not at origin and no GPS data exists yet
- `dig.establishGPSAtOrigin()` - Establish GPS when at origin (0,0,0)
  - Used when GPS becomes available after quarry has started
  - Must be called when turtle is at origin position

### Position Information
- `dig.isGPSEnabled()` - Returns true if GPS is available
- `dig.getGPSOrigin()` - Returns world coordinates of origin (ox, oy, oz)
- `dig.getGPSPosition(timeout)` - Get current GPS world position

### Coordinate Conversion
- `dig.relativeToWorld(rx, ry, rz)` - Convert relative to world coords
- `dig.worldToRelative(wx, wy, wz)` - Convert world to relative coords

### Recovery Functions
- `dig.verifyPositionGPS(tolerance)` - Check and correct position if needed
  - `tolerance` (optional): Number of blocks difference to tolerate before correcting (default: 1)
  - Returns true if correction was made, false otherwise
- `dig.recoverPositionGPS()` - Force position recovery from GPS
  - Always rounds to nearest integer block position

### Setting GPS Origin Manually
```lua
dig.setGPSOrigin(world_x, world_y, world_z)
```

## Save File Format
The save file now includes GPS data:
```
xdist
ydist
zdist
rdist
xmin
xmax
ymin
ymax
zmin
zmax
xlast
ylast
zlast
rlast
lastmove
dugtotal
blocks_processed_total
gps_origin_x  -- NEW
gps_origin_y  -- NEW
gps_origin_z  -- NEW
gps_enabled   -- NEW
```

## Benefits

1. **Chunk Unload Protection**: If the turtle moves while chunk unloads, position is corrected on reload
2. **Drift Detection**: Periodic checks catch any coordinate drift
3. **No Breaking Changes**: Works with or without GPS
4. **Automatic Recovery**: Position correction happens automatically
5. **World Coordinate Tracking**: Know exact world position at all times
6. **Origin Preservation**: GPS origin is saved and never overwritten, ensuring consistency
7. **Late GPS Setup**: Can add GPS hosts later and system will auto-configure on next resume

## Example Output

### New Quarry with GPS:
```
Initializing GPS system...
GPS enabled: Origin at (1234, 64, 5678)
Current world position: (1234, 64, 5678)
```

### Resume with Existing GPS:
```
Resuming 16x16 quarry
GPS origin loaded: (1234, 64, 5678)
GPS position verified
```

### Resume - GPS Becomes Available:
```
Resuming 16x16 quarry
GPS now available but origin not set
Will establish GPS after returning to origin
GPS is now available!
Returning to origin to establish GPS...
GPS established at origin: (1234, 64, 5678)
Returning to mining position...
```

### Position Correction After Chunk Unload:
```
GPS correction: (5,10,3) -> (5,11,3)
Position mismatch detected! Correcting...
GPS recovery: Position corrected from (5,10,3) to (5,11,3)
```

### Without GPS:
```
Initializing GPS system...
GPS not available, using relative coordinates only
```

## Important Behaviors

### GPS Precision and Tolerance
- GPS coordinates have sub-block precision (decimals)
- All GPS positions are automatically rounded to nearest integer
- Position corrections only occur if difference exceeds 1 block
- This prevents false corrections from minor GPS fluctuations or rounding errors
- Ensures turtle stays within quarry bounds

### GPS Origin Preservation
- Once a GPS origin is established and saved to `dig_save.cfg`, it is **never overwritten**
- This ensures coordinate consistency across server restarts, chunk unloads, and program reruns
- If you need to reset the GPS origin, delete `dig_save.cfg` or manually edit the file

### Adding GPS After Starting
If you start a quarry without GPS, then add GPS hosts later:
1. The system detects GPS is now available on next resume
2. Turtle automatically returns to origin (0,0,0)
3. GPS origin is established at the origin point
4. Turtle returns to mining position
5. All coordinates are now GPS-verified

### Running Same Quarry Multiple Times
If you rerun the same quarry program:
- GPS origin from `dig_save.cfg` is preserved
- Position is verified against GPS
- No coordinates are overwritten
- Mining continues with same reference frame

## Testing
To test the GPS system:
1. Set up GPS hosts in your world
2. Start a quarry normally
3. Verify GPS initialization message
4. Let it mine a bit, then force a chunk unload (teleport far away)
5. Return and watch it auto-correct position

### Testing Late GPS Addition:
1. Start a quarry without GPS hosts
2. Let it mine a bit
3. Add GPS hosts to your world
4. Restart the quarry program
5. Watch it return to origin and establish GPS

## Troubleshooting

**GPS not working?**
- Check if GPS hosts are running: `gps locate 2`
- Ensure at least 4 GPS hosts are active
- Verify wireless modems are on GPS hosts
- Check hosts are in range (wireless modem range)

**Position still wrong?**
- Call `dig.recoverPositionGPS()` manually
- Check GPS host coordinates are correct
- Ensure turtle has a wireless modem
