os.loadAPI("flex.lua")
os.loadAPI("dig.lua")

-- Initialize peripherals
local geoScanner = peripheral.find("geoScanner")
if not geoScanner then
    print("No Geo Scanner found!")
    return
end

-- Function to scan and display ore locations
local function scanAndDisplay()
    print("Performing scan...")
    local scan = geoScanner.scan(8) -- Use max radius of 8
    
    -- Current turtle position
    print("\nTurtle position:")
    print(string.format("X: %d, Y: %d, Z: %d", dig.getx(), dig.gety(), dig.getz()))
    print("Rotation: " .. dig.getr())
    
    -- Display all blocks found
    print("\nBlocks found:")
    for _, block in ipairs(scan) do
        if block.name:find("ore") then -- Only show ores for clarity
            print(string.format("\nOre: %s", block.name))
            print(string.format("Relative: x=%d, y=%d, z=%d", block.x, block.y, block.z))
            print(string.format("Absolute: x=%d, y=%d, z=%d", 
                dig.getx() + block.x,
                dig.gety() + block.y,
                dig.getz() + block.z))
        end
    end
    
    return scan
end

-- Function to test mining a specific ore
local function testMineOre(ore)
    print(string.format("\nAttempting to mine %s", ore.name))
    print(string.format("Moving to coordinates: x=%d, y=%d, z=%d", ore.x, ore.y, ore.z))
    
    -- Store starting position
    local startX = dig.getx()
    local startY = dig.gety()
    local startZ = dig.getz()
    local startR = dig.getr()
    
    -- Try to mine the ore
    print("\nStarting movement sequence...")
    dig.gotoy(startY + ore.y)
    dig.gotox(startX + ore.x)
    dig.gotoz(startZ + ore.z)
    
    -- Check what block we're facing
    print("\nChecking block at destination...")
    local success, data = turtle.inspect()
    if success then
        print("Found block: " .. data.name)
        
        -- Try to mine it
        print("Attempting to mine...")
        if turtle.dig() then
            print("Successfully mined block!")
        else
            print("Failed to mine block!")
        end
    else
        print("No block detected at destination!")
    end
    
    -- Return to start
    print("\nReturning to start position...")
    dig.goto(startX, startY, startZ, startR)
end

-- Main test sequence
print("=== Geo Scanner Coordinate Test ===")
print("Press Enter to start scan")
read()

local scan = scanAndDisplay()

-- If ores were found, offer to test mine one
local ores = {}
for _, block in ipairs(scan) do
    if block.name:find("ore") then
        table.insert(ores, block)
    end
end

if #ores > 0 then
    print("\nFound " .. #ores .. " ores. Test mine one? (y/n)")
    local input = read():lower()
    if input == "y" then
        print("\nSelect ore to mine (1-" .. #ores .. "):")
        for i, ore in ipairs(ores) do
            print(i .. ": " .. ore.name)
        end
        local selection = tonumber(read())
        if selection and selection >= 1 and selection <= #ores then
            testMineOre(ores[selection])
        end
    end
end

print("\nTest complete!")
