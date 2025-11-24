# Coordinate System Fix

## Problem
Turtles deployed within zones were incorrectly reported as "outside quarry boundaries" even though they were physically placed in the correct locations.

### Root Cause
The issue stemmed from a **coordinate system mismatch** between:
1. **dig.lua coordinate system**: Uses relative coordinates where X = right, Z = forward (from turtle's perspective)
2. **GPS coordinate system**: Uses absolute world coordinates (X and Z are cardinal directions)

When the deployer turtle placed workers along what it thought was the X-axis (using `dig.goto(zone.xmin, 0, 0, 180)`), this was correctly following the dig.lua coordinate system. However, the **GPS zone boundaries** were incorrectly assuming that dig.lua's X-axis always aligned with GPS X-axis, which is only true if the deployer is facing east.

### Example from Screenshot
- Input: width=40, length=40 (dig.lua coordinates)
- Deployer placed turtles along dig.lua X-axis
- In the world, the deployer was facing **north** (GPS -Z direction)
- So dig.lua X-axis actually corresponded to GPS **Z-axis**
- But GPS zones were created assuming X=X, causing the mismatch

## Solution

### Changes Made

#### 1. `orchestrate/zone_manager.lua`

**Updated `createGPSZones()` function:**
- Now accepts `initialDirection` parameter (north/south/east/west)
- Transforms dig.lua coordinates to GPS coordinates based on the actual direction:
  - **North**: dig.lua +X → GPS -Z, dig.lua +Z → GPS +X
  - **South**: dig.lua +X → GPS +Z, dig.lua +Z → GPS -X
  - **East**: dig.lua +X → GPS +X, dig.lua +Z → GPS +Z (original assumption)
  - **West**: dig.lua +X → GPS -X, dig.lua +Z → GPS -Z

**Fixed `calculateInitialDirection()` function:**
- Corrected the logic to properly map chest positions to cardinal directions
- The function determines which cardinal direction corresponds to dig.lua's +X axis
- Based on fuel chest being at (+1, 0, 0) relative to output chest at (0, 0, 0)

#### 2. `orchestrate/message_handler.lua`

**Updated `handleChestPositions()` function:**
- Now calculates `initialDirection` when chest positions are registered
- Passes `initialDirection` to `createGPSZones()`
- Stores `initialDirection` in state for later use

**Updated `handleReadyForAssignment()` function:**
- Uses stored `initialDirection` when assigning zones to workers
- Ensures consistent direction calculation throughout the system

## How It Works

1. **Deployer places chests**: Output at (0,0,0), Fuel at (+1,0,0) in dig.lua coordinates
2. **Server calculates direction**: By comparing GPS positions of the two chests, determines which cardinal direction is dig.lua's +X
3. **Zones are transformed**: When creating GPS zones, coordinates are transformed based on this direction
4. **Workers are matched**: When workers report their GPS position, they're now correctly matched to their zones

## Testing

To verify the fix:
1. Deploy turtles with any orientation (north, south, east, or west facing)
2. Workers should now correctly match their GPS positions to assigned zones
3. No more "outside quarry boundaries" errors for correctly placed workers
4. Console should show "Calculated initial direction: [north/south/east/west]"

## Technical Details

### Coordinate Transformation Matrix

| Direction | dig.lua X → GPS | dig.lua Z → GPS |
|-----------|----------------|----------------|
| North     | -Z             | +X             |
| South     | +Z             | -X             |
| East      | +X             | +Z             |
| West      | -X             | -Z             |

### Worker Placement
- Workers face rotation 180° (opposite of dig.lua +X direction)
- This ensures they face toward the quarry area when mining starts
- GPS zones account for this by using the transformed coordinates

## Files Modified
- `orchestrate/zone_manager.lua`
- `orchestrate/message_handler.lua`
