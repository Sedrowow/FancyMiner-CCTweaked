-- Digs a staircase around a quarry
-- Run "stairs help"
-- Or dig a staircase to bedrock
-- Run "stairs"

-----------------------------------
--  /¯\  || ||  /\  |¯\ |¯\ \\// --
-- | O | ||_|| |  | | / | /  \/  --
--  \_\\  \__| |||| | \ | \  ||  --
-----------------------------------
-- /¯¯\ [¯¯]  /\  [¯¯] |¯\ /¯¯\  --
-- \_¯\  ||  |  |  ][  | / \_¯\  --
-- \__/  ||  |||| [__] | \ \__/  --
-----------------------------------

-- Names of tools
local name_torch = {
   "torch", "lantern", "lamp", "light" }
local name_bench = {
   "minecraft:crafting_table",
   "forge:workbench" }
local name_chest = { "chest" }
local name_box = {
   "shulker_box", "travelersbackpack" }


-- Stair blocks crafting material
local name_cobble = {
  "minecraft:cobblestone",
  "forge:cobblestone" }


-- Side that swaps with crafting bench
local tool_side = "none"
if not peripheral.find("workbench") then
 tool_side = "left"
 if peripheral.getType("left") == "modem" then
  tool_side = "right"
 end --if
end --if


-- Load APIs
os.loadAPI("flex.lua")
os.loadAPI("dig.lua")
dig.setFuelSlot(1)
dig.setBlockSlot(2)
dig.setBlockStacks(4)


function dump()
 local slot = turtle.getSelectedSlot()
 local keepers = { name_cobble, name_box,
    name_torch, name_bench, name_chest,
    "stairs" }
 local x,a = 0,false

 for x=1,16 do
  if flex.isItem(name_box,x) then
   turtle.select(x)
   a = turtle.placeUp()
   break
  end --if
 end --for

 if not a then
  keepers[#keepers+1] = "diamond"
  keepers[#keepers+1] = "ancient_debris"
 end --if

 local blocksPresent = dig.getBlockStacks()
 for x=4,16 do
  if not flex.isItem(keepers,x) then
   if dig.isDumpItem(x) then
    if blocksPresent <= 0 then
     turtle.drop()
    else
     blocksPresent = blocksPresent - 1
    end --if/else
   else
    turtle.select(x)
    if a then
     turtle.dropUp()
    else
     turtle.drop()
    end --if/else
   end --if/else
  end --if
 end --for

 turtle.select(slot)
 if a then turtle.digUp() end
 dig.checkBlocks()
 flex.condense()
end --function



-- Program parameter(s)
local args={...}

-- Tutorial, kind of
if #args > 0 and args[1] == "help" then
 flex.printColors("Place just to the "..
   "left of a turtle quarrying the same "..
   "dimensions.",colors.lightBlue)
 flex.printColors("Include a crafting "..
   "table and a chest in turtle's "..
   "inventory to auto-craft a staircase",
   colors.yellow)
 flex.printColors("Usage: stairs "..
   "[length] [width] [depth]",colors.pink)
 return
end --if

-- Modem Initialization and Status Function
local modem
local hasModem = false
local modem_channel = 6464 -- Default modem channel
local p = flex.getPeripheral("modem")
if #p > 0 then
    hasModem = true
    modem = peripheral.wrap(p[1])
    modem.open(modem_channel)
end

local last_status_sent_time = os.epoch("local") or 0
local status_send_interval = 4 * 1000 -- Send status every 10 seconds (in milliseconds)

local function sendStatus(is_mining, estimated_time_display)
    if not hasModem then return end

    local current_epoch_time_ms = os.epoch("local") or 0
    if current_epoch_time_ms - last_status_sent_time >= status_send_interval then
        local status_message = {
            type = "status_update",
            id = os.getComputerID(),
            label = os.getComputerLabel(),
            fuel = turtle.getFuelLevel(),
            position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
            is_mining = is_mining,
            estimated_time = estimated_time_display or "N/A",
            inventory_summary = {} -- Add inventory summary if needed
        }
        modem.transmit(modem_channel, modem_channel + 1, status_message)
        last_status_sent_time = current_epoch_time_ms
    end
end

-- What Goes Where
flex.printColors("Slot 1: Fuel\n"..
  "Slot 2: Blocks\nSlot 3: Torches\n"..
  "Anywhere: Crafting Bench, Chest\n"..
  "Optional: Shulker Box / Backpack",
  colors.lightBlue)
flex.printColors("Press Enter",
  colors.pink)
while flex.getKey() ~= keys.enter do
    sendStatus(false, "Waiting for user input...")
    sleep(0.1)
end


-- Convert Inputs
local dx,dy,dz,n,x,y,z
local height = 5
dz = tonumber(args[1]) or 256
dx = tonumber(args[2]) or dz
dy = tonumber(args[3]) or 256
-- -1 to match Quarry depth


--------------------------------------
-- |¯\ [¯¯] /¯¯] /¯¯][¯¯]|\ || /¯¯] --
-- |  | ][ | [¯|| [¯| ][ | \ || [¯| --
-- |_/ [__] \__| \__|[__]|| \| \__| --
--------------------------------------

flex.send("Digging staircase...",
  colors.yellow)

-- Staircase Digging Functions

local torchNum = 9

function placeTorch()
 turtle.select(3)
 if flex.isItem(name_torch) then

  if not turtle.place() then
   if not dig.fwd() then return false end
   turtle.select(2)
   dig.place()
   if not dig.back() then return false end

   turtle.select(3)
   if not dig.place() then
    if not dig.fwd() then return false end
    turtle.select(2)
    dig.placeUp()
    if not dig.back() then return false end
    turtle.select(3)
    dig.place()
   end --if/else
  end --if
 end --if

 turtle.select(2)
 sendStatus(true, "Placing torch...")
end --function


function stepDown()
 local x

 turtle.select(2)
 dig.right()
 for x=1,height-2 do
  dig.blockLava()
  if not dig.up() then return false end
  sendStatus(true, "Stepping down...")
 end --for
 dig.blockLava()
 dig.blockLavaUp()

 dig.left()
 dig.blockLava()
 dig.left()
 if not dig.fwd() then return false end
 dig.blockLavaUp()
 dig.blockLava()
 dig.right()
 dig.blockLava()
 dig.left()

 if torchNum >= 3 then
  if not dig.back() then return false end
  placeTorch()
  if not dig.down() then return false end
  if not dig.fwd() then return false end
  torchNum = 0
 else
  dig.blockLava()
  if not dig.down() then return false end
  torchNum = torchNum + 1
 end --if/else

 for x=1,height-2 do
  dig.blockLava()
  if not dig.down() then return false end
  sendStatus(true, "Stepping down...")
 end --for
 dig.blockLava()
 if not dig.placeDown() then return false end

 dig.right(2)
 if not dig.fwd() then return false end
 dig.blockLava()
 if not dig.placeDown() then return false end
 dig.left()

 if turtle.getItemCount(16) > 0 then
  dig.left()
  dump()
  dig.right()
 end --if/else

 if not dig.fwd() then return false end

 sendStatus(true, "Completed a step down.")
 return true
end --function


local function turnRight()
 turtle.select(2)
 dig.right()
 if not dig.up(height-2) then return false end
 dig.blockLavaUp()

 dig.left()
 if not dig.down() then return false end
 if not dig.fwd() then return false end
 dig.blockLavaUp()
 for x=1,height-3 do
  dig.blockLava()
  if not dig.down() then return false end
 end --for
 dig.blockLava()
 if not dig.placeDown() then return false end

 dig.left()
 if not dig.fwd() then return false end
 for x=1,height-3 do
  dig.blockLava()
  if not dig.up() then return false end
 end --for
 dig.blockLava()
 dig.blockLavaUp()

 dig.right()
 for x=1,height-3 do
  dig.blockLava()
  if not dig.down() then return false end
 end --for
 dig.blockLava()
 if not dig.placeDown() then return false end

 dig.left(2)
 if not dig.fwd() then return false end
 dig.right()
 if not dig.placeDown() then return false end
 for x=1,height-2 do
  dig.blockLava()
  if not dig.up() then return false end
 end --for
 dig.blockLava()
 dig.blockLavaUp()

 dig.right(2)
 if not dig.fwd() then return false end
 if not dig.down(height-1) then return false end
 if not dig.placeDown() then return false end
 dig.left()
 if not dig.fwd() then return false end
 dig.blockLava()
 if not dig.placeDown() then return false end
 if not dig.back() then return false end
 dig.right()
 if not dig.fwd() then return false end

 torchNum = torchNum + 1
 sendStatus(true, "Turning right.")
 return true
end --function


function endcap(h,stop)
 stop = ( stop ~= nil )
 h = h or 0 -- Height to dig layer
 local x

 dig.right()
 if not dig.placeDown() then return false end
 dig.checkBlocks()
 for x=1,height-2-h do
  dig.blockLava()
  if not dig.up() then return false end
 end --for
 dig.blockLava()
 dig.blockLavaUp()

 dig.left(2)
 if not dig.fwd() then return false end
 dig.blockLavaUp()
 for x=1,height-2-h do
  dig.blockLava()
  if not dig.down() then return false end
 end --for
 dig.blockLava()
 if not dig.placeDown() then return false end
 dig.checkBlocks()
 if not dig.back() then return false end

 dig.right()

 if stop then
  dig.blockLava()
  for x=1,height-2-h do
   if not dig.up() then return false end
   dig.blockLava()
  end --for
  dig.blockLavaUp()
  dig.left()

  if not dig.fwd() then return false end
  dig.blockLavaUp()
  dig.right()
  dig.blockLava()
  for x=1,height-2-h do
   if not dig.down() then return false end
   dig.blockLava()
  end --for

  dig.left()
  if not dig.back() then return false end
  dig.right()

 end --if
 sendStatus(true, "Creating endcap.")
 return true
end --function



local direction

function avoidBedrock()
 if dig.isStuck() then
  -- Hit Bedrock/Void
  if dig.getStuckDir() == "fwd" then
   dig.up()
   dig.placeDown()
   dig.checkBlocks()
   dig.setymin(dig.gety())
   dig.fwd()
  elseif dig.getStuckDir() == "down" then
   dig.setymin(dig.gety())
  end --if
 end --if

 -- Get X and Z on the inner stair block
 if dig.getx() >= dx+2 then
  dig.gotox(dx+1)

 elseif dig.getx() <= -1 then
  dig.gotox(0)

 end --if/else

 if dig.getz() >= dz+1 then
  dig.gotoz(dz)

 elseif dig.getz() <= -2 then
  dig.gotoz(-1)

 end --if/else

 dig.gotor(direction)
 dig.gotoy(dig.getymin())
 sendStatus(true, "Avoiding bedrock.")
end --function



-- Start Digging

turtle.select(2)

x = 0
direction = dig.getr()
while true do

 for n=0,dz-1 do
  if not stepDown() then break end
  x = x + 1
  if x >= dy then break end
  sendStatus(true, "Digging step " .. tostring(n+1) .. " of " .. tostring(dz))
 end
 if dig.isStuck() or x >= dy then break end
 if not turnRight() then break end
 x = x + 1
 sendStatus(true, "Turned right, starting next row.")

 direction = dig.getr()
 for n=0,dx-1 do
  if not stepDown() then break end
  x = x + 1
  if x >= dy then break end
  sendStatus(true, "Digging step " .. tostring(n+1) .. " of " .. tostring(dx))
 end
 if dig.isStuck() or x >= dy then break end
 if not turnRight() then break end
 x = x + 1
 sendStatus(true, "Turned right, starting next row.")

 direction = dig.getr()
end

avoidBedrock()
if not dig.fwd() then avoidBedrock() end
if not endcap(1) then avoidBedrock() end
if not dig.fwd() then avoidBedrock() end
if not endcap(1,true) then avoidBedrock() end

dig.left(2)
while not turtle.detect() do
 dig.fwd()
 sendStatus(true, "Returning to edge.")
end --while
dig.back()

-- This bit compensates for random Bedrock (mostly)
if #dig.getKnownBedrock() > 0 then
 for x=1,4 do
  dig.placeDown()
  dig.right()
  dig.fwd()
 end --for
 sendStatus(true, "Compensating for bedrock.")
end --for



----------------------------------------------
--  /¯] |¯\  /\  |¯¯] [¯¯] [¯¯] |\ ||  /¯¯] --
-- | [  | / |  | | ]   ||   ][  | \ | | [¯| --
--  \_] | \ |||| ||    ||  [__] || \|  \__| --
----------------------------------------------

-- Return locations of bench/chest
local function checkTools()
 local bench,chest = 0,0
 local x
 for x=1,16 do
  turtle.select(x)
  if flex.isItem(name_bench) then
   bench = x
  elseif flex.isItem(name_chest) then
   chest = x
  end --if/else
 end --for
 return bench,chest
end --function


local oldTool
local success = true

local function equip()
 if tool_side == "right" then
  return turtle.equipRight()
 elseif tool_side == "left" then
  return turtle.equipLeft()
 end --if/else
end --function


-- Equip Crafting Bench
local function setTool()
 if tool_side == "none" then return end

 flex.condense()
 local x,y = checkTools()

 if x == 0 then
  flex.send("Crafting Bench not found",
    colors.red)
  success = false
  sendStatus(false, "Crafting bench not found!")
  return false
 end --if

 turtle.select(x)
 y = turtle.getItemCount()
 if y > 1 then
  turtle.transferTo(math.min(
    x+1,16),y-1)
 end --if

 if not equip() then
  return false
 end --if

 -- Add a delay to allow peripheral system to recognize the newly equipped crafting table
 os.sleep(0.5)

 -- Check if the peripheral is actually available after equipping
 local craftingBench = peripheral.wrap(tool_side)
 if not craftingBench then
   flex.send("Failed to detect crafting bench peripheral",
     colors.red)
   success = false
   sendStatus(false, "Crafting bench peripheral not found!")
   return false
 end

 if turtle.getItemCount() > 0 then
  oldTool = turtle.getItemDetail()["name"]
 end --if

 flex.send("Crafting Bench equipped",
   colors.yellow)
 sendStatus(true, "Equipped crafting bench.")
 return true
end --function setTool()


-- Unequip Crafting Bench
local function restoreTool()
 if tool_side == "none" then return end

 flex.condense()
 local slot = turtle.getSelectedSlot()
 local x,y
 for x=1,16 do
  turtle.select(x)
  y = turtle.getItemCount()

  if oldTool == nil then
   -- If no tool, put Bench in empty slot
   if y == 0 then
    return equip()
   end --if

  else
   if y > 0 then
    if turtle.getItemDetail()["name"]
       == oldTool then
     if equip() then
	     flex.send("Tool restored",
	       colors.lightBlue)
	     turtle.select(slot)
	     sendStatus(true, "Tool restored.")
      return true
     end --if
    end --if
   end --if
  end --if
 end --for

 flex.send("Unable to restore tool",
   colors.red)
 success = false
 sendStatus(false, "Unable to restore tool.")
 return false
end --function restoreTool()


local depth = -dig.gety()
local bench, chest = checkTools()
local stairsNeeded = depth*2
local craftNum

-- Count existing stair blocks
local numStairs = 0
for x=1,16 do
 turtle.select(x)
 y = turtle.getItemCount()
 if y > 0 then
  if flex.isItem("stairs") then
   numStairs = numStairs + y
  end --if
 end --if
end --for

-- Count Cobblestone
local numCobble = 0
for x=1,16 do
 turtle.select(x)
 if flex.isItem(name_cobble) then
  numCobble = numCobble + turtle.getItemCount()
 end --if
end --for
turtle.select(1)

craftNum = math.ceil((stairsNeeded-numStairs)/4)


-- Check against cobble needed
if numCobble < craftNum*6
   or stairsNeeded > 64*4 then

 x = math.floor(numCobble/6)
 x = math.min(x,64)
 y = math.ceil(stairsNeeded/4)
 z = math.floor(100*x/y)

 flex.send("#1Only enough cobblestone "
   .."to craft #4"..tostring(z)
   .."#0%#1 of stairs")
 success = false
 sendStatus(false, "Insufficient cobblestone for stairs.")

 craftNum = x
end --if

if craftNum < 0 then
 craftNum = 0
end --if


-- If Crafting needs to (and can) happen
if craftNum > 0 and chest > 0 and
   ( bench > 0 or tool_side == "none" ) then

 local stairSlots = {1,5,6,9,10,11}
 local freeSlots = {2,3,4,7,8,12,13,14,15,16}

 -- Equip Crafing Banch and place Chest
 setTool()
 turtle.select(chest)
 turtle.place()

 -- Everything except Cobble into Chest
 for x=1,16 do
  turtle.select(x)
  if turtle.getItemCount() > 0 then
   if not flex.isItem(name_cobble)
      or flex.isItem("stairs") then
    turtle.drop()
   end --if
  end --if
 end --for
 flex.condense()

 -- Collect Cobble to Craft
 for x=1,11 do
  turtle.select(x)
  if x <= 5 then
   turtle.transferTo(x+11)
  elseif x == 6 then
   turtle.transferTo(4)
  elseif x == 7 then
   turtle.transferTo(8)
  else
   turtle.drop()
  end --if/else
  if turtle.getItemCount() > 0 then
   turtle.drop()
  end --if
 end --for

 -- Arrange Cobble into Recipe
 z = 16
 for x=1,#stairSlots do
  turtle.select(z)
  while turtle.getItemCount() < craftNum do
   if z > 12 then
    z = z-1
   else
    z = z-4
   end --if
   if z < 1 then break end
   turtle.select(z)
  end --while
  if z < 1 then break end
  turtle.select(z)
  turtle.transferTo(stairSlots[x],
    craftNum)
 end --for

 -- Drop excess cobble into chest
 for x=1,#freeSlots do
  turtle.select(freeSlots[x])
  turtle.drop()
 end --for

 -- Main Event! Craft Function! =D
 -- Add proper peripheral checks and error handling
 local cb = peripheral.wrap(tool_side)
 if not cb then
   flex.send("Crafting bench peripheral not found",colors.red)
   success = false
   sendStatus(false, "Crafting bench peripheral not found!")
 else
   local crafted = pcall(function()
     return cb.craft(craftNum)
   end)
   
   if crafted then
     flex.send("Stairs crafted",colors.lightBlue)
     sendStatus(true, "Stairs crafted.")
   else
     flex.send("Crafting error",colors.red)
     success = false
     sendStatus(false, "Crafting error.")
   end
 end

 -- Restore inventory in correct order
 for x=1,16 do
  turtle.select(x)
  turtle.drop()
 end --for
 turtle.select(1)
 while turtle.suck() do end
 restoreTool()
 turtle.dig()
 flex.condense()

end --if (crafting needed)



-----------------------------------------------
-- |¯\ || || [¯¯] ||   |¯\  [¯¯] |\ ||  /¯¯] --
-- | < ||_||  ][  ||_  |  |  ][  | \ | | [¯| --
-- |_/  \__| [__] |__] |_/  [__] || \|  \__| --
-----------------------------------------------


local function placeStairs()
 local x,y,z,slot
 slot = turtle.getSelectedSlot()
 y = turtle.getItemCount()
 z = true

 if y < 2 or not flex.isItem("stairs") then
  for x=1,16 do
   turtle.select(x)
   y = turtle.getItemCount()
   if y >= 2 and flex.isItem("stairs") then
    z = false
    break
   end --if
  end --for

  if z then
   turtle.select(slot)
   sendStatus(false, "Not enough stairs to place.")
   return false
  end --if
 end --if

 dig.placeDown()
 dig.right()
 dig.fwd()
 dig.left()
 dig.placeDown()
 dig.left()
 dig.fwd()
 dig.right()
 sendStatus(true, "Placing stairs.")
 return true
end --function


flex.send("Returning to surface",
  colors.yellow)
sendStatus(true, "Returning to surface.")

function isDone()
 -- Reached Surface
 return dig.gety() >= 0
end

-- Follow the Spiral [and place Stairs]
while not isDone() do
    sendStatus(true, "Ascending...")

 if dig.getr()%360 == 0 then
  while dig.getz() < dig.getzmax()-1 do
   dig.fwd()
   dig.up()
   placeStairs()
   if isDone() then break end
  end --while

 elseif dig.getr()%360 == 90 then
  while dig.getx() < dig.getxmax()-1 do
   dig.fwd()
   dig.up()
   placeStairs()
   if isDone() then break end
  end --while

 elseif dig.getr()%360 == 180 then
  while dig.getz() > dig.getzmin()+1 do
   dig.fwd()
   dig.up()
   placeStairs()
   if dig.gety() > -4 and dig.getz()
      == dig.getzmin()+1 then
    -- Up at the top
    dig.fwd()
    dig.up()
    placeStairs()
   end --if
   if isDone() then break end
  end --while

 elseif dig.getr()%360 == 270 then
  while dig.getx() > dig.getxmin()+1 do
   dig.fwd()
   dig.up()
   placeStairs()
   if isDone() then break end
  end --while

 end --if/else

 if not isDone() then dig.left() end

end --while


-- All Done!
turtle.select(1)
dig.goto(0,0,0,0)

if success then
 flex.send("Stairway finished!",
   colors.lightBlue)
   sendStatus(false, "Stairway finished!")
else
 flex.send("Reached Origin",
   colors.lightBlue)
   sendStatus(false, "Reached origin.")
end --if

flex.modemOff()
os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")
