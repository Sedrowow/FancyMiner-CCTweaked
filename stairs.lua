-- Digs a staircase around a quarry
-- Run "stairs help"
-- Or dig a staircase to bedrock
-- Run "stairs"
-- <Flexico64@gmail.com>
-- Please email me if you have any
-- bugs or suggestions!

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


-- What Goes Where
flex.printColors("Slot 1: Fuel\n"..
  "Slot 2: Blocks\nSlot 3: Torches\n"..
  "Anywhere: Crafting Bench, Chest\n"..
  "Optional: Shulker Box / Backpack",
  colors.lightBlue)
flex.printColors("Press Enter",
  colors.pink)
while flex.getKey() ~= keys.enter do
 -- Handle remote commands during waiting
 local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
 if event == "modem_message" then
     local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
     if type(message) == "table" and message.type == "command" then
         if message.command == "status_request" then
             local status = {
                 type = "status",
                 fuel = turtle.getFuelLevel(),
                 inventory = dig.getInventory(),
                 position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                 is_mining = false, -- Not actively building stairs yet
                 estimated_time = "Waiting for user input..." -- Placeholder
             }
             modem.transmit(flex.modem_channel, replyChannel, status)
         elseif message.command == "unload_command" then
             flex.send("Received unload command while waiting, initiating unload...", colors.yellow)
             dig.dropNotFuel()
             flex.send("Unload complete.", colors.lightBlue)
             modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
         end
     end
 end
 if event ~= "key" then sleep(0.1) end -- Prevent tight loop if no event
end --while


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
end --function


function stepDown()
 local x

 turtle.select(2)
 dig.right()
 for x=1,height-2 do
  dig.blockLava()
  if not dig.up() then return false end
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
end --function



-- Start Digging

turtle.select(2)

x = 0
direction = dig.getr()
while true do
 -- Handle remote commands during digging
 local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
 if event == "modem_message" then
     local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
     if type(message) == "table" and message.type == "command" then
         if message.command == "status_request" then
             -- Estimate remaining steps/levels (simple for stairs)
             local total_depth = dy -- Assuming dy is the target depth
             local current_y = dig.gety()
             local estimated_remaining_levels = math.max(0, current_y - dig.getymin()) -- Simplified estimate

             local estimated_time_display = "Calculating..."
             if estimated_remaining_levels > 0 then
                 -- Very rough time estimate based on remaining levels and average time per step
                 local avg_time_per_level = 30 -- Calibrate this value based on your turtle's performance
                 local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level
                 local hours = math.floor(estimated_time_seconds / 3600)
                 local minutes = math.floor((estimated_time_seconds % 3600) / 60)
                 local seconds = math.floor(estimated_time_seconds % 60)
                 estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
             end

             local status = {
                 type = "status",
                 fuel = turtle.getFuelLevel(),
                 inventory = dig.getInventory(),
                 position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                 is_mining = true, -- Actively building stairs
                 estimated_time = estimated_time_display
             }
             modem.transmit(flex.modem_channel, replyChannel, status)
         elseif message.command == "unload_command" then
             flex.send("Received unload command, initiating unload...", colors.yellow)
             dig.dropNotFuel()
             flex.send("Unload complete.", colors.lightBlue)
             modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
         end
     end
 end
 if event ~= nil then sleep(0.1) end -- Prevent tight loop if no event

 for n=0,dz-1 do
  if not stepDown() then break end
  x = x + 1
  if x >= dy then break end
  -- Handle remote commands during steps
  local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
  if event == "modem_message" then
      local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
      if type(message) == "table" and message.type == "command" then
          if message.command == "status_request" then
              local total_depth = dy
              local current_y = dig.gety()
              local estimated_remaining_levels = math.max(0, current_y - dig.getymin())

              local estimated_time_display = "Calculating..."
              if estimated_remaining_levels > 0 then
                  local avg_time_per_level = 30
                  local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level
                  local hours = math.floor(estimated_time_seconds / 3600)
                  local minutes = math.floor((estimated_time_seconds % 3600) / 60)
                  local seconds = math.floor(estimated_time_seconds % 60)
                  estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
              end

              local status = {
                  type = "status",
                  fuel = turtle.getFuelLevel(),
                  inventory = dig.getInventory(),
                  position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                  is_mining = true,
                  estimated_time = estimated_time_display
              }
              modem.transmit(flex.modem_channel, replyChannel, status)
          elseif message.command == "unload_command" then
              flex.send("Received unload command, initiating unload...", colors.yellow)
              dig.dropNotFuel()
              flex.send("Unload complete.", colors.lightBlue)
              modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
          end
      end
  end
 end
 if dig.isStuck() or x >= dy then break end
 if not turnRight() then break end
 x = x + 1
 -- Handle remote commands after turning
 local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
 if event == "modem_message" then
     local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
     if type(message) == "table" and message.type == "command" then
         if message.command == "status_request" then
             local total_depth = dy
             local current_y = dig.gety()
             local estimated_remaining_levels = math.max(0, current_y - dig.getymin())

             local estimated_time_display = "Calculating..."
             if estimated_remaining_levels > 0 then
                 local avg_time_per_level = 30
                 local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level
                 local hours = math.floor(estimated_time_seconds / 3600)
                 local minutes = math.floor((estimated_time_seconds % 3600) / 60)
                 local seconds = math.floor(estimated_time_seconds % 60)
                 estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
             end

             local status = {
                 type = "status",
                 fuel = turtle.getFuelLevel(),
                 inventory = dig.getInventory(),
                 position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                 is_mining = true,
                 estimated_time = estimated_time_display
             }
             modem.transmit(flex.modem_channel, replyChannel, status)
         elseif message.command == "unload_command" then
             flex.send("Received unload command, initiating unload...", colors.yellow)
             dig.dropNotFuel()
             flex.send("Unload complete.", colors.lightBlue)
             modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
         end
     end
 end


 direction = dig.getr()
 for n=0,dx-1 do
  if not stepDown() then break end
  x = x + 1
  if x >= dy then break end
  -- Handle remote commands during steps
   local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
   if event == "modem_message" then
       local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
       if type(message) == "table" and message.type == "command" then
           if message.command == "status_request" then
               local total_depth = dy
               local current_y = dig.gety()
               local estimated_remaining_levels = math.max(0, current_y - dig.getymin())

               local estimated_time_display = "Calculating..."
               if estimated_remaining_levels > 0 then
                   local avg_time_per_level = 30
                   local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level
                   local hours = math.floor(estimated_time_seconds / 3600)
                   local minutes = math.floor((estimated_time_seconds % 3600) / 60)
                   local seconds = math.floor(estimated_time_seconds % 60)
                   estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
               end

               local status = {
                   type = "status",
                   fuel = turtle.getFuelLevel(),
                   inventory = dig.getInventory(),
                   position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                   is_mining = true,
                   estimated_time = estimated_time_display
               }
               modem.transmit(flex.modem_channel, replyChannel, status)
           elseif message.command == "unload_command" then
               flex.send("Received unload command, initiating unload...", colors.yellow)
               dig.dropNotFuel()
               flex.send("Unload complete.", colors.lightBlue)
               modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
           end
       end
   end
 end
 if dig.isStuck() or x >= dy then break end
 if not turnRight() then break end
 x = x + 1
 -- Handle remote commands after turning
  local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
  if event == "modem_message" then
      local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
      if type(message) == "table" and message.type == "command" then
          if message.command == "status_request" then
              local total_depth = dy
              local current_y = dig.gety()
              local estimated_remaining_levels = math.max(0, current_y - dig.getymin())

              local estimated_time_display = "Calculating..."
              if estimated_remaining_levels > 0 then
                  local avg_time_per_level = 30
                  local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level
                  local hours = math.floor(estimated_time_seconds / 3600)
                  local minutes = math.floor((estimated_time_seconds % 3600) / 60)
                  local seconds = math.floor(estimated_time_seconds % 60)
                  estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
              end

              local status = {
                  type = "status",
                  fuel = turtle.getFuelLevel(),
                  inventory = dig.getInventory(),
                  position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                  is_mining = true,
                  estimated_time = estimated_time_display
              }
              modem.transmit(flex.modem_channel, replyChannel, status)
          elseif message.command == "unload_command" then
              flex.send("Received unload command, initiating unload...", colors.yellow)
              dig.dropNotFuel()
              flex.send("Unload complete.", colors.lightBlue)
              modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
          end
      end
  end

 direction = dig.getr()
end --while


avoidBedrock()
if not dig.fwd() then avoidBedrock() end
if not endcap(1) then avoidBedrock() end
if not dig.fwd() then avoidBedrock() end
if not endcap(1,true) then avoidBedrock() end

dig.left(2)
while not turtle.detect() do
 dig.fwd()
 -- Handle remote commands while returning to edge
 local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
 if event == "modem_message" then
     local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
     if type(message) == "table" and message.type == "command" then
         if message.command == "status_request" then
              local status = {
                  type = "status",
                  fuel = turtle.getFuelLevel(),
                  inventory = dig.getInventory(),
                  position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                  is_mining = true, -- Still working
                  estimated_time = "Returning to edge..." -- Placeholder
              }
              modem.transmit(flex.modem_channel, replyChannel, status)
         elseif message.command == "unload_command" then
             flex.send("Received unload command, initiating unload...", colors.yellow)
             dig.dropNotFuel()
             flex.send("Unload complete.", colors.lightBlue)
             modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
         end
     end
 end
 if event ~= nil then sleep(0.1) end
end --while
dig.back()

-- This bit compensates for random Bedrock (mostly)
if #dig.getKnownBedrock() > 0 then
 for x=1,4 do
  dig.placeDown()
  dig.right()
  dig.fwd()
 end --for
end --for



----------------------------------------------
--  /¯] |¯\  /\  |¯¯] [¯¯] [¯¯] |\ ||  /¯¯] --
-- | [  | / |  | | ]   ||   ][  | \ | | [¯| --
--  \_] | \ |||| ||    ||  [__] || \|  \__| --
----------------------------------------------


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
end --function


flex.send("Returning to surface",
  colors.yellow)

function isDone()
 -- Reached Surface
 return dig.gety() >= 0
end

-- Follow the Spiral [and place Stairs]
while not isDone() do
 -- Handle remote commands during ascent
 local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
 if event == "modem_message" then
     local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
     if type(message) == "table" and message.type == "command" then
         if message.command == "status_request" then
              local total_depth = dy
              local current_y = dig.gety()
              local estimated_remaining_levels = math.max(0, current_y - dig.getymin())

              local estimated_time_display = "Calculating..."
              if estimated_remaining_levels > 0 then
                  local avg_time_per_level = 30
                  local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level
                  local hours = math.floor(estimated_time_seconds / 3600)
                  local minutes = math.floor((estimated_time_seconds % 3600) / 60)
                  local seconds = math.floor(estimated_time_seconds % 60)
                  estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
              end

              local status = {
                  type = "status",
                  fuel = turtle.getFuelLevel(),
                  inventory = dig.getInventory(),
                  position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                  is_mining = true, -- Still working
                  estimated_time = estimated_time_display
              }
              modem.transmit(flex.modem_channel, replyChannel, status)
         elseif message.command == "unload_command" then
             flex.send("Received unload command, initiating unload...", colors.yellow)
             dig.dropNotFuel()
             flex.send("Unload complete.", colors.lightBlue)
             modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
         end
     end
 end
 if event ~= nil then sleep(0.1) end


 if dig.getr()%360 == 0 then
  while dig.getz() < dig.getzmax()-1 do
   dig.fwd()
   dig.up()
   placeStairs()
   if isDone() then break end
   -- Handle remote commands during steps
    local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
    if event == "modem_message" then
        local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
        if type(message) == "table" and message.type == "command" then
            if message.command == "status_request" then
                 local total_depth = dy
                 local current_y = dig.gety()
                 local estimated_remaining_levels = math.max(0, current_y - dig.getymin())

                 local estimated_time_display = "Calculating..."
                 if estimated_remaining_levels > 0 then
                     local avg_time_per_level = 30
                     local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level
                     local hours = math.floor(estimated_time_seconds / 3600)
                     local minutes = math.floor((estimated_time_seconds % 3600) / 60)
                     local seconds = math.floor(estimated_time_seconds % 60)
                     estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
                 end

                 local status = {
                     type = "status",
                     fuel = turtle.getFuelLevel(),
                     inventory = dig.getInventory(),
                     position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                     is_mining = true,
                     estimated_time = estimated_time_display
                 }
                 modem.transmit(flex.modem_channel, replyChannel, status)
            elseif message.command == "unload_command" then
                flex.send("Received unload command, initiating unload...", colors.yellow)
                dig.dropNotFuel()
                flex.send("Unload complete.", colors.lightBlue)
                modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
            end
        end
    end
  end

 elseif dig.getr()%360 == 90 then
  while dig.getx() < dig.getxmax()-1 do
   dig.fwd()
   dig.up()
   placeStairs()
   if isDone() then break end
   -- Handle remote commands during steps
    local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
    if event == "modem_message" then
        local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
        if type(message) == "table" and message.type == "command" then
            if message.command == "status_request" then
                 local total_depth = dy
                 local current_y = dig.gety()
                 local estimated_remaining_levels = math.max(0, current_y - dig.getymin())

                 local estimated_time_display = "Calculating..."
                 if estimated_remaining_levels > 0 then
                     local avg_time_per_level = 30
                     local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level
                     local hours = math.floor(estimated_time_seconds / 3600)
                     local minutes = math.floor((estimated_time_seconds % 3600) / 60)
                     local seconds = math.floor(estimated_time_seconds % 60)
                     estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
                 end

                 local status = {
                     type = "status",
                     fuel = turtle.getFuelLevel(),
                     inventory = dig.getInventory(),
                     position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                     is_mining = true,
                     estimated_time = estimated_time_display
                 }
                 modem.transmit(flex.modem_channel, replyChannel, status)
            elseif message.command == "unload_command" then
                flex.send("Received unload command, initiating unload...", colors.yellow)
                dig.dropNotFuel()
                flex.send("Unload complete.", colors.lightBlue)
                modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
            end
        end
    end
  end

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
   -- Handle remote commands during steps
    local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
    if event == "modem_message" then
        local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
        if type(message) == "table" and message.type == "command" then
            if message.command == "status_request" then
                 local total_depth = dy
                 local current_y = dig.gety()
                 local estimated_remaining_levels = math.max(0, current_y - dig.getymin())

                 local estimated_time_display = "Calculating..."
                 if estimated_remaining_levels > 0 then
                     local avg_time_per_level = 30
                     local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level
                     local hours = math.floor(estimated_time_seconds / 3600)
                     local minutes = math.floor((estimated_time_seconds % 3600) / 60)
                     local seconds = math.floor(estimated_time_seconds % 60)
                     estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
                 end

                 local status = {
                     type = "status",
                     fuel = turtle.getFuelLevel(),
                     inventory = dig.getInventory(),
                     position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                     is_mining = true,
                     estimated_time = estimated_time_display
                 }
                 modem.transmit(flex.modem_channel, replyChannel, status)
            elseif message.command == "unload_command" then
                flex.send("Received unload command, initiating unload...", colors.yellow)
                dig.dropNotFuel()
                flex.send("Unload complete.", colors.lightBlue)
                modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
            end
        end
    end
  end

 elseif dig.getr()%360 == 270 then
  while dig.getx() > dig.getxmin()+1 do
   dig.fwd()
   dig.up()
   placeStairs()
   if isDone() then break end
   -- Handle remote commands during steps
    local event, p1, p2, p3, p4, p5, p6 = os.pullEvent("modem_message", 0.1)
    if event == "modem_message" then
        local modemSide, senderChannel, replyChannel, message, senderDistance = p1, p2, p3, p4, p5
        if type(message) == "table" and message.type == "command" then
            if message.command == "status_request" then
                 local total_depth = dy
                 local current_y = dig.gety()
                 local estimated_remaining_levels = math.max(0, current_y - dig.getymin())

                 local estimated_time_display = "Calculating..."
                 if estimated_remaining_levels > 0 then
                     local avg_time_per_level = 30
                     local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level
                     local hours = math.floor(estimated_time_seconds / 3600)
                     local minutes = math.floor((estimated_time_seconds % 3600) / 60)
                     local seconds = math.floor(estimated_time_seconds % 60)
                     estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
                 end

                 local status = {
                     type = "status",
                     fuel = turtle.getFuelLevel(),
                     inventory = dig.getInventory(),
                     position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
                     is_mining = true,
                     estimated_time = estimated_time_display
                 }
                 modem.transmit(flex.modem_channel, replyChannel, status)
            elseif message.command == "unload_command" then
                flex.send("Received unload command, initiating unload...", colors.yellow)
                dig.dropNotFuel()
                flex.send("Unload complete.", colors.lightBlue)
                modem.transmit(flex.modem_channel, replyChannel, { type = "ack", command = "unload_command" })
            end
        end
    end
  end

 end --if/else

 if not isDone() then dig.left() end

end --while


-- All Done!
turtle.select(1)
dig.goto(0,0,0,0)

if success then
 flex.send("Stairway finished!",
   colors.lightBlue)
else
 flex.send("Reached Origin",
   colors.lightBlue)
end --if

flex.modemOff()
os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")