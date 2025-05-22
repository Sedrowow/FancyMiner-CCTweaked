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
    
    -- Deposit everything except fuel, torches, and blocks
    for slot = 4, 16 do
        turtle.select(slot)
        turtle.drop()
    end
    
    -- Return to mining position
    dig.goto(currentPos.x, currentPos.y, currentPos.z, dig.getr())
end

-- Function to scan for ores in the area
local function scanForOres()
    local ores = {}
    local scan = geoScanner.scan(MAX_SCAN_RADIUS)
    
    for _, block in ipairs(scan) do
        for _, targetOre in ipairs(config.target_ores) do
            if block.name == targetOre then
                table.insert(ores, {
                    x = block.x,
                    y = block.y,
                    z = block.z,
                    name = block.name
                })
            end
        end
    end
    
    return ores
end

-- Function to mine to specific coordinates relative to current position
local function mineToCoordinates(x, y, z)
    local startX = dig.getx()
    local startY = dig.gety()
    local startZ = dig.getz()
    
    -- Mine to the ore
    dig.gotoy(y)
    dig.gotox(x)
    dig.gotoz(z)
    
    -- Mine the ore
    dig.dig()
    blocksDug = blocksDug + 1
    oresFound = oresFound + 1
    
    -- Return to tunnel
    dig.goto(startX, startY, startZ, dig.getr())
end

-- Main mining loop
flex.send("Starting ore mining operation...", colors.yellow)
flex.send("Target ores: " .. table.concat(config.target_ores, ", "), colors.lightBlue)
flex.send("Minimum ores: " .. config.min_ores, colors.lightBlue)
flex.send("Maximum distance: " .. config.max_distance, colors.lightBlue)

-- Start at height y=12 (good for most valuable ores)
dig.goto(0, -12, 0, 0)

while distanceTraveled < config.max_distance and oresFound < config.min_ores do
    -- Check fuel
    if turtle.getFuelLevel() < 100 then
        refuelFromChest()
    end
    
    -- Check inventory
    if turtle.getItemCount(16) > 0 then
        depositItems()
    end
    
    -- Scan for ores
    local ores = scanForOres()
    if #ores > 0 then
        flex.send("Found " .. #ores .. " matching ores nearby!", colors.green)
        
        -- Mine each ore found
        for _, ore in ipairs(ores) do
            mineToCoordinates(ore.x, ore.y, ore.z)
            flex.send("Mined " .. ore.name .. " (" .. oresFound .. "/" .. config.min_ores .. ")", colors.lightBlue)
        end
    end
    
    -- Move forward in main tunnel
    if dig.fwd() then
        distanceTraveled = distanceTraveled + 1
        
        -- Place torch every 8 blocks
        if distanceTraveled % 8 == 0 then
            turtle.select(TORCH_SLOT)
            turtle.placeUp()
        end
    end
    
    -- Progress update
    if distanceTraveled % 10 == 0 then
        flex.send("Distance: " .. distanceTraveled .. "m, Ores found: " .. oresFound, colors.yellow)
    end
end

-- Return to start
flex.send("Mining operation complete!", colors.green)
flex.send("Total distance: " .. distanceTraveled .. "m", colors.lightBlue)
flex.send("Total ores: " .. oresFound, colors.lightBlue)
flex.send("Total blocks dug: " .. blocksDug, colors.lightBlue)

dig.goto(0, 0, 0, 0)
depositItems()

os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")
