-- Advanced Peripherals Ore Miner
-- Uses Geo Scanner to detect and mine specific ores
os.loadAPI("flex.lua")
os.loadAPI("dig.lua")

-- Configuration
local CONFIG_FILE = "oremine.cfg"
local MAX_SCAN_RADIUS = 8
local FUEL_SLOT = 1
local TORCH_SLOT = 2
local BLOCK_SLOT = 3
local DEFAULT_MAX_DISTANCE = 100
local DEFAULT_MIN_ORES = 32
-- Add protected block types
local PROTECTED_BLOCKS = {
    "minecraft:chest",
    "ironchest:",
    "sophisticatedstorage:",
    "minecraft:trapped_chest",
    "minecraft:barrel",
    "minecraft:shulker_box",
    "storagedrawers:",
    "minecraft:hopper",
    "turtle"
}

-- Config handling functions
local function createDefaultConfig()
    local file = fs.open(CONFIG_FILE, "w")
    file.writeLine("# Ore Miner Configuration")
    file.writeLine("# Format: key=value")
    file.writeLine("")
    file.writeLine("# Target ores (comma separated)")
    file.writeLine("target_ores=minecraft:diamond_ore,minecraft:iron_ore")
    file.writeLine("")
    file.writeLine("# Minimum ores to find before stopping")
    file.writeLine("min_ores=32")
    file.writeLine("")
    file.writeLine("# Maximum distance to travel")
    file.writeLine("max_distance=100")
    file.close()
    
    -- Print usage instructions
    flex.printColors("Configuration file created: " .. CONFIG_FILE, colors.yellow)
    flex.printColors("Please edit the configuration file and run the program again.", colors.lightBlue)
    flex.printColors("\nConfiguration options:", colors.white)
    flex.printColors("target_ores: Comma-separated list of ore names", colors.lightBlue)
    flex.printColors("min_ores: Minimum number of ores to find", colors.lightBlue)
    flex.printColors("max_distance: Maximum distance to travel", colors.lightBlue)
    flex.printColors("\nExample ore names:", colors.white)
    flex.printColors("minecraft:diamond_ore", colors.lightBlue)
    flex.printColors("minecraft:iron_ore", colors.lightBlue)
    flex.printColors("minecraft:gold_ore", colors.lightBlue)
    return false
end

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        return createDefaultConfig()
    end

    local file = fs.open(CONFIG_FILE, "r")
    local config = {
        target_ores = {},
        min_ores = DEFAULT_MIN_ORES,
        max_distance = DEFAULT_MAX_DISTANCE
    }
    
    for line in file.readLine do
        if line and line:sub(1,1) ~= "#" then
            local key, value = line:match("([^=]+)=(.+)")
            if key and value then
                key = key:gsub("%s+", "")
                value = value:gsub("%s+", "")
                
                if key == "target_ores" then
                    for ore in value:gmatch("([^,]+)") do
                        table.insert(config.target_ores, ore)
                    end
                elseif key == "min_ores" then
                    config.min_ores = tonumber(value) or DEFAULT_MIN_ORES
                elseif key == "max_distance" then
                    config.max_distance = tonumber(value) or DEFAULT_MAX_DISTANCE
                end
            end
        end
    end
    
    file.close()
    return config
end

-- Initialize peripherals
local geoScanner = peripheral.find("geoScanner")
if not geoScanner then
    flex.send("No Geo Scanner found!", colors.red)
    return
end

-- Load configuration or use command line arguments
local config
local args = {...}
if #args > 0 then
    -- Use command line arguments if provided
    config = {
        target_ores = {},
        min_ores = tonumber(args[2]) or DEFAULT_MIN_ORES,
        max_distance = tonumber(args[3]) or DEFAULT_MAX_DISTANCE
    }
    
    for ore in string.gmatch(args[1], "([^,]+)") do
        table.insert(config.target_ores, ore)
    end
else
    -- Load from config file
    config = loadConfig()
    if not config then
        return -- Config file was created, exit program
    end
end

if #config.target_ores == 0 then
    flex.printColors("No target ores specified!", colors.red)
    flex.printColors("Please edit " .. CONFIG_FILE .. " or provide command line arguments:", colors.yellow)
    flex.printColors("Usage: oreminer <ore1,ore2,...> [min_ores] [max_distance]", colors.lightBlue)
    return
end

-- Statistics tracking
local oresFound = 0
local distanceTraveled = 0
local blocksDug = 0

-- Function to check and refuel from chest above start
local function refuelFromChest()
    local currentPos = {x = dig.getx(), y = dig.gety(), z = dig.getz()}
    
    -- Return to start
    dig.goto(0, 0, 0, 0)
    
    -- Get fuel from chest above
    turtle.select(FUEL_SLOT)
    while turtle.getItemCount(FUEL_SLOT) == 0 do
        if not turtle.suckUp() then
            flex.send("Waiting for fuel...", colors.red)
            sleep(5)
        end
    end
    
    -- Refuel
    turtle.refuel()
    
    -- Return to mining position
    dig.goto(currentPos.x, currentPos.y, currentPos.z, dig.getr())
end

-- Function to deposit items in chest behind start
local function depositItems()
    local currentPos = {x = dig.getx(), y = dig.gety(), z = dig.getz()}
    
    -- Return to start
    dig.goto(0, 0, 0, 180)  -- Face the chest
    
    -- Save the selected slot
    local selectedSlot = turtle.getSelectedSlot()
    
    -- Deposit everything except fuel, torches, and emergency blocks
    for slot = 1, 16 do
        turtle.select(slot)
        if slot ~= FUEL_SLOT and slot ~= TORCH_SLOT and slot ~= BLOCK_SLOT then
            turtle.drop()
        end
    end
    
    -- Restore selected slot
    turtle.select(selectedSlot)
    
    -- Return to mining position
    dig.goto(currentPos.x, currentPos.y, currentPos.z, dig.getr())
end

-- Function to check if a block should be protected
local function isProtectedBlock(blockName)
    if not blockName then return false end
    for _, protected in ipairs(PROTECTED_BLOCKS) do
        if blockName:find(protected) then
            return true
        end
    end
    return false
end

-- Add new configuration values
local TUNNEL_WIDTH = 3
local SCAN_RADIUS = 5
local TORCH_INTERVAL = 6
local VEIN_MAX_DISTANCE = 2 -- Maximum distance between ores to be considered same vein
local STATE_FILE = "oreminer_state.dat"

-- State tracking
local state = {
    position = {x = 0, y = 0, z = 0, r = 0},
    distanceTraveled = 0,
    oresFound = 0,
    currentVein = {},
    knownOres = {}, -- Format: {x=x, y=y, z=z, name=name, mined=bool}
    originPos = {x = 0, y = 0, z = 0}
}

-- Function to save state
local function saveState()
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialize(state))
    file.close()
end

-- Function to load state
local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        state = textutils.unserialize(file.readLine())
        file.close()
        return true
    end
    return false
end

-- Function to calculate distance between two points (including diagonal)
local function getDistance(pos1, pos2)
    return math.max(
        math.abs(pos1.x - pos2.x),
        math.abs(pos1.y - pos2.y),
        math.abs(pos1.z - pos2.z)
    )
end

-- Function to check if an ore belongs to current vein
local function isPartOfVein(ore)
    for _, knownOre in ipairs(state.currentVein) do
        if getDistance(ore, knownOre) <= VEIN_MAX_DISTANCE then
            return true
        end
    end
    return false
end

-- Modified scan function to track veins
local function scanForOres()
    if not geoScanner then return {} end
    
    local ores = {}
    local scan = geoScanner.scan(SCAN_RADIUS)
    
    if not scan then return {} end
    
    -- Convert scanner coordinates to absolute coordinates
    for _, block in ipairs(scan) do
        if block and block.name and not isProtectedBlock(block.name) then
            if block.name:find("ore") and not block.name:find("chest") and not block.name:find("barrel") then
                for _, targetOre in ipairs(config.target_ores) do
                    if block.name == targetOre then
                        local absolutePos = {
                            x = state.position.x + block.x,
                            y = state.position.y + block.y,
                            z = state.position.z + block.z,
                            name = block.name
                        }
                        
                        -- Check if ore is already known
                        local isKnown = false
                        for _, known in ipairs(state.knownOres) do
                            if known.x == absolutePos.x and 
                               known.y == absolutePos.y and 
                               known.z == absolutePos.z then
                                isKnown = true
                                break
                            end
                        end
                        
                        if not isKnown then
                            table.insert(state.knownOres, absolutePos)
                            if isPartOfVein(absolutePos) then
                                table.insert(state.currentVein, absolutePos)
                                table.insert(ores, {
                                    x = block.x,
                                    y = block.y,
                                    z = block.z,
                                    name = block.name
                                })
                            end
                        end
                        break
                    end
                end
            end
        end
    end
    
    return ores
end

-- Function to check and fill holes in a wall or floor
local function fillHole(direction)
    turtle.select(BLOCK_SLOT)
    if direction == "down" then
        if not turtle.detectDown() then
            turtle.placeDown()
            return true
        end
    elseif direction == "up" then
        if not turtle.detectUp() then
            turtle.placeUp()
            return true
        end
    elseif direction == "forward" then
        if not turtle.detect() then
            turtle.place()
            return true
        end
    end
    return false
end

-- Function to check wall and place block if needed, separate from floor/ceiling checks
local function fillWall()
    turtle.select(BLOCK_SLOT)
    if not turtle.detect() then
        dig.place()
        return true
    end
    return false
end

-- Function to dig 3x3 tunnel section
local function digTunnelSection()
    -- Store initial orientation
    local startR = dig.getr()
    
    -- Ensure we're facing forward (north = 0 degrees)
    dig.gotor(0)
    
    -- Bottom layer
    -- Dig and fill center floor
    dig.dig()
    if not turtle.detectDown() then
        turtle.select(BLOCK_SLOT)
        dig.placeDown()
    end
    
    -- Left side bottom
    dig.left()
    dig.dig()
    dig.fwd()
    -- Check and fill both floor and wall independently
    if not turtle.detectDown() then
        turtle.select(BLOCK_SLOT)
        dig.placeDown()
    end
    fillWall() -- Always check and fill wall regardless of floor
    dig.back()
    
    -- Right side bottom
    dig.right(2)
    dig.dig()
    dig.fwd()
    -- Check and fill both floor and wall independently
    if not turtle.detectDown() then
        turtle.select(BLOCK_SLOT)
        dig.placeDown()
    end
    fillWall() -- Always check and fill wall regardless of floor
    dig.back()
    dig.left()
    
    -- Middle layer
    dig.up()
    dig.dig()
    
    -- Left wall
    dig.left()
    dig.dig()
    dig.fwd()
    fillWall() -- Always check and fill wall
    dig.back()
    
    -- Right wall
    dig.right(2)
    dig.dig()
    dig.fwd()
    fillWall() -- Always check and fill wall
    dig.back()
    dig.left()
    
    -- Top layer
    dig.up()
    
    -- Center ceiling
    dig.dig()
    if not turtle.detectUp() then
        turtle.select(BLOCK_SLOT)
        dig.placeUp()
    end
    
    -- Left side top
    dig.left()
    dig.dig()
    dig.fwd()
    -- Check and fill both ceiling and wall independently
    if not turtle.detectUp() then
        turtle.select(BLOCK_SLOT)
        dig.placeUp()
    end
    fillWall() -- Always check and fill wall regardless of ceiling
    dig.back()
    
    -- Right side top
    dig.right(2)
    dig.dig()
    dig.fwd()
    -- Check and fill both ceiling and wall independently
    if not turtle.detectUp() then
        turtle.select(BLOCK_SLOT)
        dig.placeUp()
    end
    fillWall() -- Always check and fill wall regardless of ceiling
    dig.back()
    dig.left()
    
    -- Place torch if needed
    if state.distanceTraveled % TORCH_INTERVAL == 0 then
        turtle.select(TORCH_SLOT)
        dig.down(2)
        turtle.placeDown()
        dig.up(2)
    end
    
    -- Return to starting position
    dig.down(2)
    dig.gotor(startR)
    
    -- Ensure block slot is selected
    turtle.select(BLOCK_SLOT)
end

-- Modified main mining loop
local function mineOreVein()
    while #state.currentVein > 0 do
        -- Get next closest ore
        local closest = state.currentVein[1]
        local minDist = math.huge
        
        for i, ore in ipairs(state.currentVein) do
            local dist = getDistance(state.position, ore)
            if dist < minDist then
                minDist = dist
                closest = ore
            end
        end
        
        -- Mine the ore
        if mineToCoordinates(
            closest.x - state.position.x,
            closest.y - state.position.y,
            closest.z - state.position.z
        ) then
            -- Remove from vein and mark as mined
            for i, ore in ipairs(state.currentVein) do
                if ore.x == closest.x and 
                   ore.y == closest.y and 
                   ore.z == closest.z then
                    table.remove(state.currentVein, i)
                    break
                end
            end
            for i, ore in ipairs(state.knownOres) do
                if ore.x == closest.x and 
                   ore.y == closest.y and 
                   ore.z == closest.z then
                    ore.mined = true
                    break
                end
            end
        end
        
        -- Scan for new connected ores
        scanForOres()
        saveState()
    end
end

-- Main mining loop
flex.send("Starting ore mining operation...", colors.yellow)
flex.send("Target ores: " .. table.concat(config.target_ores, ", "), colors.lightBlue)
flex.send("Minimum ores: " .. config.min_ores, colors.lightBlue)
flex.send("Maximum distance: " .. config.max_distance, colors.lightBlue)

-- Always start facing forward (0 degrees)
dig.gotor(0)

-- Create initial entry tunnel (4 blocks)
flex.send("Creating entry tunnel...", colors.yellow)
for i = 1, 4 do
    digTunnelSection()
    -- Move forward while maintaining orientation
    dig.gotor(0)  -- Ensure we're facing forward
    if dig.fwd() then
        state.distanceTraveled = state.distanceTraveled + 1
        state.position = {
            x = dig.getx(),
            y = dig.gety(),
            z = dig.getz(),
            r = dig.getr()
        }
        saveState()
    end
end

-- Now continue with main mining loop
while state.distanceTraveled < config.max_distance and state.oresFound < config.min_ores do
    -- Check fuel
    if turtle.getFuelLevel() < 100 then
        refuelFromChest()
    end
    
    if turtle.getItemCount(14) > 0 then
        depositItems()
    end
    
    -- Dig tunnel section and move forward
    digTunnelSection()
    
    -- Move forward at ground level
    dig.gotor(0)  -- Ensure we're facing forward
    if dig.fwd() then
        state.distanceTraveled = state.distanceTraveled + 1
        state.position = {
            x = dig.getx(),
            y = dig.gety(),
            z = dig.getz(),
            r = dig.getr()
        }
        saveState()
    end
    
    -- Scan for ores after moving
    local ores = scanForOres()
    if #ores > 0 then
        flex.send("Found " .. #ores .. " matching ores nearby!", colors.green)
        mineOreVein()
    end
end

-- Return to start
flex.send("Mining operation complete!", colors.green)
flex.send("Total distance: " .. distanceTraveled .. "m", colors.lightBlue)
flex.send("Total ores: " .. oresFound, colors.lightBlue)
flex.send("Total blocks dug: " .. blocksDug, colors.lightBlue)

-- Ensure we're facing the right way before returning
dig.gotor(0)  -- Face the starting direction (north)
dig.goto(0, 0, 0, 0)  -- Return to start while maintaining orientation
depositItems()

os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")
