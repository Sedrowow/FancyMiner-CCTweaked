-- This is a replacement for the
-- 'excavate' program, as it can re-
-- cover from a reboot/unload event.
-- Also avoids destroying spawners!

-----------------------------------
-- [¯¯] || || |¯\ [¯¯] ||   |¯¯] --
--  ||  ||_|| | /  ||  ||_  | ]  --
--  ||   \__| | \  ||  |__] |__] --
-----------------------------------
--  /¯\  || ||  /\  |¯\ |¯\ \\// --
-- | O | ||_|| |  | | / | /  \/  --
--  \_\\  \__| |||| | \ | \  ||  --
-----------------------------------

local log_file = "log.txt"
local options_file = "flex_options.cfg"
os.loadAPI("flex.lua")
os.loadAPI("dig.lua")
local modem_channel = 6464
dig.doBlacklist() -- Avoid Protected Blocks
dig.doAttack() -- Attack entities that block the way
dig.setFuelSlot(1)
dig.setBlockSlot(2)
local world_height = 384

if fs.exists(options_file) then
 local file = fs.open("flex_options.cfg", "r")
 local line = file.readLine()
 while line ~= nil do
  if string.find(line, "modem_channel=") == 1 then
   modem_channel = tonumber( string.sub(
         line, 15, string.len(line) ) )
   break
  end --if
  line = file.readLine()
 end --while
 file.close()
end --if

-- Add debug prints around modem initialization
print("DEBUG: Attempting to initialize modem.")
local modem -- Make sure modem is declared here, outside of any function
local hasModem = false
local p = flex.getPeripheral("modem")
if #p > 0 then
    print("DEBUG: Modem peripheral found: " .. tostring(p[1]))
    hasModem = true
    modem = peripheral.wrap(p[1])
    -- No need to open modem if only using modem.transmit for broadcast on a specific channel
    print("DEBUG: Modem peripheral wrapped. Will attempt to transmit status on configured channel.")
else
    print("DEBUG: No modem peripheral found during initialization. Status updates disabled.")
    -- The script can still run without a modem, but status updates won't work.
end

local args = {...}
if #args == 0 then
 flex.printColors(
   "quarry <length> [width] [depth]\n"..
   "[skip <layers>] [dump] [nolava] [nether]",
   colors.lightBlue)
 return
end --if


local reloaded = false
if dig.saveExists() then
 reloaded = true
 dig.loadCoords() -- Load coordinates and blocks_processed_total
end --if
dig.makeStartup("quarry",args)


local zmax = tonumber(args[1])
local xmax = tonumber(args[2]) or zmax
local depth_arg = tonumber(args[3]) -- Store the third argument if it exists

local depth_in_layers -- This will be the number of layers to dig

if depth_arg ~= nil then
 -- If the third argument (depth) is provided, assume it's the number of layers
 depth_in_layers = depth_arg
 -- The minimum Y coordinate will be calculated later based on initial_ymax
else
 -- If depth argument is not provided, default to digging to bedrock
 -- Let's define "to bedrock" as WorldHeight layers, starting from y=0.
 depth_in_layers = world_height
end --if

-- ymin will be calculated later based on initial_ymax and depth_in_layers

if xmax == nil or zmax == nil then
 flex.send("Invalid dimensions,",colors.red)
 shell.run("rm startup.lua")
 return
end --if


local x
local skip = 0
local lava = true
local dodumps = false

for x=1,#args do

 if args[x] == "dump" then
  dodumps = true
 elseif args[x] == "nolava" then
  lava = false
 elseif args[x] == "nether" then
  dig.setBlockStacks(4)
 end --if

 if args[x] == "skip" then
  local skip_value = tonumber(args[x+1]) -- Use a temporary variable
  if skip_value == nil then
   flex.printColors("Please specify skip depth",
     colors.red)
   dig.saveClear()
   return -- Script exits
  end --if
  skip = skip_value -- Assign only if it's a number
  if dig.getymin() > -skip then
   dig.setymin(-skip)
  end --if
 end --if
end --for


if not lava then -- Block lava around edges of quarry
 dig.setBlockSlot(0)
 -- Always keep a stack of blocks
end --if




----------------------------------------------
-- |¯¯]|| |||\ || /¯][¯¯][¯¯] /¯\ |\ ||/¯¯\ --
-- | ] ||_||| \ || [  ||  ][ | O || \ |\_¯\ --
-- ||   \__||| \| \_] || [__] \_/ || \|\__/ --
----------------------------------------------

local location
local function gotoBase()
 local x = dig.getxlast()
 location = dig.location()
 -- skip is used here
 if dig.gety() < -skip then
  dig.up() -- up calls addBlocksProcessed
 end
 dig.gotox(0) -- gotox calls movement, which calls addBlocksProcessed
 dig.gotoz(0) -- gotoz calls movement, which calls addBlocksProcessed
 dig.gotor(180) -- gotor calls update, doesn't add processed
 dig.gotoy(0) -- gotoy calls movement, which calls addBlocksProcessed
 dig.gotox(0) -- gotox calls movement, which calls addBlocksProcessed
 dig.setxlast(x)
 dig.gotoz(0) -- gotoz calls movement, which calls addBlocksProcessed
 dig.gotor(180) -- gotor calls update, doesn't add processed
 return location
end --function

local function returnFromBase(loc)
 local loc = loc or location
 local x = dig.getxlast()
 dig.gotor(0) -- gotor calls update, doesn't add processed
 checkFuel()
 -- skip is used here
 dig.gotoy(math.min(loc[2]+1,-skip)) -- gotoy calls movement, which calls addBlocksProcessed
 checkFuel()
 dig.gotoz(loc[3]) -- gotoz calls movement, which calls addBlocksProcessed
 checkFuel()
 dig.gotox(loc[1]) -- gotox calls movement, which calls addBlocksProcessed
 dig.setxlast(x) -- Important for restoring
 checkFuel()
 dig.gotor(loc[4]) -- gotor calls update, doesn't add processed
 checkFuel()
 dig.gotoy(loc[2]) -- gotoy calls movement, which calls addBlocksProcessed
end --function


local function checkHalt()
 -- Remote control halt via modem is removed (assuming for status only)
 -- Check for redstone signal from above
 if not rs.getInput("top") then
  return
 end --if
 -- skip is used here
 if dig.gety() == -skip then -- Check against skip depth
  return
 end --if
 if dig.gety() == 0 then -- Check against surface
  return
 end --if


 local loc,x
 -- Manual halt; redstone signal from above
 flex.send("Manual halt initiated (Redstone)", colors.orange)
 flex.printColors("Press ENTER to resume mining\n"
   .."or SPACE to return to base",
   colors.pink)

 while true do
  x = flex.getKey()
  if x == keys.enter then return end
  if x == keys.space then break end
 end --while

 flex.send("Returning to base", colors.yellow)
 loc = gotoBase() -- gotoBase calls movement, which calls addBlocksProcessed
 print(" ")
 flex.printColors("Press ENTER to resume mining",
   colors.pink)
 while flex.getKey() !== keys.enter do
  sleep(1)
 end --while

 if dodumps then dig.doDumpDown() end
 dig.dropNotFuel()
 flex.send("Resuming quarry",colors.yellow)
 returnFromBase(loc) -- returnFromBase calls movement, which calls addBlocksProcessed

end --function


local function checkInv()
 if turtle.getItemCount(16) > 0 then

  if dodumps then
   dig.right(2) -- right calls update
   dig.doDump()
   dig.left(2) -- left calls update
  end --if

  if turtle.getItemCount(14) > 0 then
   local loc = gotoBase() -- gotoBase calls movement, which calls addBlocksProcessed
   dig.dropNotFuel()
   returnFromBase(loc) -- returnFromBase calls movement, which calls addBlocksProcessed
  end --if

 end --if
end --function


function checkFuel()
 local a = turtle.getFuelLevel()
 -- This fuel estimate is very basic, you might need to adjust it
 -- local b = ( zmax + xmax + math.abs(dig.gety() - ymin) ) * 2 -- Original basic fuel estimate
 local c = true

 -- More detailed fuel estimate based on remaining blocks (using processed blocks)
 local current_processed_blocks = dig.getBlocksProcessed()
 local estimated_remaining_blocks = total_quarry_blocks - current_processed_blocks
 -- Rough estimate of fuel needed per *processed* block (adjust based on your setup)
 -- This assumes fuel is consumed for movement and digging
 local fuel_per_processed_block = 0.02 -- Example: needs calibration based on tests
 local estimated_fuel_needed = estimated_remaining_blocks * fuel_per_processed_block

 -- Use a more robust fuel check based on estimated needs
 -- Only check if estimated_fuel_needed is a valid number (it should be if math is correct)
 if type(estimated_fuel_needed) == 'number' and estimated_fuel_needed > 0 and a < estimated_fuel_needed * 1.2 then -- Check if current fuel is less than 120% of estimated needed
     flex.send("Fuel low (Estimated needed for remaining: "..tostring(math.ceil(estimated_fuel_needed)).."), returning to surface", colors.yellow)
     local loc = gotoBase() -- gotoBase calls movement, which calls addBlocksProcessed
     turtle.select(1)
     if dodumps then dig.doDumpDown() end
     while turtle.suckUp() do sleep(0) end
     dig.dropNotFuel()
     -- Ensure refuel amount is not nil or non-positive
     local refuel_amount = estimated_fuel_needed * 1.5
     if type(refuel_amount) == 'number' and refuel_amount > 0 then
        dig.refuel(refuel_amount) -- Refuel to 150% of estimated needed
     else
        dig.refuel(1000) -- Fallback refuel amount
     end
     flex.send("Fuel acquired! ("..tostring(turtle.getFuelLevel()).." fuel)", colors.lightBlue)
     returnFromBase(loc) -- returnFromBase calls movement, which calls addBlocksProcessed
 end
 -- ADDED MISSING `end` FOR checkFuel
end --function checkFuel()


-- Variables for status sending interval (DEFINED OUTSIDE any function)
-- Use os.epoch("utc") for a precise, real-world time-based timestamp in milliseconds for sending
local last_status_sent_time = os.epoch("utc") or 0 -- Initialize defensively with epoch time in milliseconds
-- Status send interval in milliseconds (4 seconds = 4000 milliseconds)
local status_send_interval = 4 * 1000 -- Send status every 4 seconds (in milliseconds)

-- Variables for ETA calculation and speed learning
local total_quarry_blocks = 0 -- Will be calculated after parsing args and initial descent
local blocks_processed_since_last_speed_check = 0 -- Renamed for clarity
-- Use os.epoch("local") for speed learning time
local time_of_last_speed_check = os.epoch("local") or 0 -- Use local time for speed learning
local avg_blocks_per_second = 0.8 -- Initial estimate (blocks processed per second)
local speed_check_threshold = 200 -- Recalculate speed after processing this many blocks

local dug = dig.getdug() -- Track dug blocks from previous checkProgress call
local processed_at_last_check = dig.getBlocksProcessed() -- Track processed blocks from previous checkProgress call
local ydeep = dig.getymin() -- Track min Y from previous checkProgress call

-- Add this function to gather and send status (DEFINED OUTSIDE any function)
local function sendStatus()
    -- Gather status data
    -- total_quarry_blocks is calculated once after initial descent

    local current_processed_blocks = dig.getBlocksProcessed()
    local estimated_remaining_blocks = total_quarry_blocks - current_processed_blocks

    local estimated_completion_time_str = "Calculating..."

    -- Calculate Estimated Completion Time if we have enough info and a valid speed
    if type(estimated_remaining_blocks) == 'number' and estimated_remaining_blocks > 0 and type(avg_blocks_per_second) == 'number' and avg_blocks_per_second > 0 then
        local estimated_time_remaining_seconds = estimated_remaining_blocks / avg_blocks_per_second
        local current_local_epoch_time_sec = (os.epoch("local") or 0) / 1000 -- Get current local time in seconds
        local estimated_completion_time_sec = current_local_epoch_time_sec + estimated_time_remaining_seconds

        -- Format the completion time using the local timezone
        -- os.date() with a format string and timestamp gives a formatted string
        estimated_completion_time_str = os.date("%Y-%m-%d %H:%M:%S", estimated_completion_time_sec)
    elseif total_quarry_blocks > 0 and estimated_remaining_blocks <= 0 then
         estimated_completion_time_str = "Completed" -- Indicate if digging is theoretically done
    end


    -- Get inventory summary (basic example)
    local inventory_summary = {}
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            table.insert(inventory_summary, { name = item.name, count = item.count })
        end
    end
    -- Ensure 'done' is accessible or determine mining state differently if 'done' is local to main loop
    local is_mining_status = false
    -- Assuming 'done' is a boolean defined in the main loop's scope
    if type(done) == "boolean" then
       is_mining_status = not done and not dig.isStuck()
    else
       -- If 'done' is not globally available, assume mining is true unless stuck
       is_mining_status = not dig.isStuck()
    end

    local status_message = {
        type = "status_update", -- Indicate this is a status update
        id = os.getComputerID(), -- Include turtle ID
        label = os.getComputerLabel(), -- Include turtle label
        fuel = turtle.getFuelLevel(),
        position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
        is_mining = is_mining_status, -- Reflect actual mining state
        -- Estimated time remaining duration is replaced by completion time string
        estimated_completion_time = estimated_completion_time_str,
        total_quarry_blocks = total_quarry_blocks, -- Send total blocks for context
        dug_blocks = dig.getdug(), -- Still send dug blocks
        processed_blocks = current_processed_blocks, -- Send processed blocks for context
        ymin = ymin, -- Add ymin (minimum Y planned) to the status message
        inventory_summary = inventory_summary -- Include basic inventory summary
    }

    -- Send the status message on a specific channel (e.g., 6465)
    local status_channel = modem_channel -- Channel for status updates
    if modem then -- Check if modem peripheral is available
        -- print("DEBUG: Attempting to transmit status on channel " .. status_channel) -- NEW DEBUG PRINT before transmit
        -- Transmit from status_channel to status_channel for a broadcast on 6465
        modem.transmit(status_channel, status_channel, status_message)
        -- print("DEBUG: Status update sent on channel " .. status_channel) -- Optional debug
    else
        -- print("DEBUG: sendStatus called but modem is nil. Cannot transmit.") -- NEW DEBUG PRINT if modem is nil
    end
end

-- checkProgress function (MODIFIED to call sendStatus and implement speed learning)
local function checkProgress()
    -- print("DEBUG: checkProgress called.")

    -- Print detailed progress information (keep this for console)
    term.setCursorPos(1,1)
    term.clearLine()
    flex.printColors("Pos: X="..tostring(dig.getx())..
                       ", Y="..tostring(dig.gety())..
                       ", Z="..tostring(dig.getz())..
                       ", Rot="..tostring(dig.getr()%360), colors.white)

    term.setCursorPos(1,2)
    term.clearLine()
    flex.printColors("Fuel: "..tostring(turtle.getFuelLevel()), colors.orange)

    term.setCursorPos(1,3)
    term.clearLine()
    flex.printColors("Dug: "..tostring(dig.getdug()).." blocks", colors.lightBlue)

    term.setCursorPos(1,4)
    term.clearLine()
    flex.printColors("Depth: "..tostring(-dig.gety()).."m / "..tostring(-ymin).."m", colors.green)

    -- Speed Learning Logic based on processed blocks
    local current_processed = dig.getBlocksProcessed()
    local blocks_processed_this_check = current_processed - processed_at_last_check -- Compare to the 'processed_at_last_check' variable

    -- Update blocks since last speed check only if blocks were actually processed
    if blocks_processed_this_check > 0 then
        blocks_processed_since_last_speed_check = blocks_processed_since_last_speed_check + blocks_processed_this_check

        -- Check if threshold is met for speed recalculation
        if blocks_processed_since_last_speed_check >= speed_check_threshold then
            local current_epoch_time_ms = os.epoch("local") or 0
            local time_elapsed_ms = current_epoch_time_ms - time_of_last_speed_check

            -- Avoid division by zero or very small times
            if time_elapsed_ms > 50 then -- Require at least 50ms to avoid noisy data
                local current_period_bps = blocks_processed_since_last_speed_check / (time_elapsed_ms / 1000) -- Calculate speed for this period
                -- Simple averaging: average the new rate with the existing average
                avg_blocks_per_second = (avg_blocks_per_second + current_period_bps) / 2
                -- print("DEBUG: Speed updated. Blocks processed this period: "..tostring(blocks_processed_since_last_speed_check)..", Time elapsed (ms): "..tostring(time_elapsed_ms)..", Current BPS: "..tostring(current_period_bps)..", New Avg BPS: "..tostring(avg_blocks_per_second)) -- Optional debug
            end

            -- Reset for the next speed check period
            blocks_processed_since_last_speed_check = 0
            time_of_last_speed_check = current_epoch_time_ms -- Start next period timer from now
        end
    end


    -- Use os.epoch("utc") for timing comparison in milliseconds for status *sending*
    local current_epoch_time_ms_utc = os.epoch("utc") or 0 -- Get current epoch time in milliseconds (UTC for sending interval)
    local time_difference_ms = current_epoch_time_ms_utc - (last_status_sent_time or 0) -- Calculate difference in milliseconds

    -- print("DEBUG: Status check timing (Epoch UTC) - os.epoch(): "..tostring(current_epoch_time_ms_utc)..", last_status_sent_time: "..tostring(last_status_sent_time)..", difference: "..tostring(time_difference_ms)..", interval (ms): "..tostring(status_send_interval))

    -- Send status update periodically using os.epoch() for the check
    if type(current_epoch_time_ms_utc) == 'number' and time_difference_ms >= status_send_interval then
        -- print("DEBUG: Status send interval met (Epoch UTC). Calling sendStatus.")
        sendStatus()
        last_status_sent_time = current_epoch_time_ms_utc -- Update last sent time using epoch time in milliseconds
    -- else
        -- print("DEBUG: Status send interval not met (Epoch UTC).")
    end

    -- Update dug and processed_at_last_check for the next checkProgress call
    dug = dig.getdug()
    processed_at_last_check = current_processed -- Update the processed counter tracker
    ydeep = dig.gety() -- Update ydeep

    -- checkReceivedCommand() -- Remove this if not doing remote control
end --function checkProgress()



local newlayer = false
function checkNewLayer()
 if newlayer then
  -- This encodes whether or not the turtle has
  --  started a new layer if at the edge
  dig.setr(dig.getr() % 360 + 360)
 else
  dig.setr(dig.getr() % 360)
 end --if
end --function



function lavax()
  if dig.getx() == 0 then
   dig.gotor(270)
   checkNewLayer()
   dig.blockLava()
  elseif dig.getx() == xmax-1 then
   dig.gotor(90)
   checkNewLayer()
   dig.blockLava()
  end --if/else
end --function

function lavaz()
  if dig.getz() == 0 then
   dig.gotor(180)
   checkNewLayer()
   dig.blockLava()
  elseif dig.getz() == zmax-1 then
   dig.gotor(0)
   checkNewLayer()
   dig.blockLava()
  end --if/else
end --function

function checkLava(n)
 if lava then
  local x
  local r = dig.getr() % 360

  if r == 0 or r == 180 then
   lavaz()
   lavax()
  else
   lavax()
   lavaz()
  end --if/else

  -- skip is used here
  if dig.gety() == -skip then
   dig.blockLavaUp()
  end --if

  -- skip is used here
  if dig.getx() == 0 and dig.getz() == 0
     and dig.gety() > -skip then
   for x=1,4 do
    dig.blockLava()
    dig.left()
    checkNewLayer()
   end --for
  end --if

  if n ~= 0 then
   dig.gotor(r)
   checkNewLayer()
  end --if

 end --if
end --function


local function checkAll(n)
 checkNewLayer()
 checkProgress() -- checkProgress calls status send logic and speed learning
 checkFuel()
 checkInv()
 checkHalt() -- checkHalt also uses skip
 checkLava(n)
 dig.checkBlocks()
 checkNewLayer()
end --function


---------------------------------------
--      |\/|  /\  [¯¯] |\ ||         --
--      |  | |  |  ][  | \ |         --
--      |||| |||| [__] || \|         --
---------------------------------------
-- |¯\ |¯\  /¯\   /¯¯] |¯\  /\  |\/| --
-- | / | / | O | | [¯| | / |  | |  | --
-- ||  | \  \_/   \__| | \ |||| |||| --
---------------------------------------

local a,b,c,x,y,z,r,loc
local xdir, zdir = 1, 1

turtle.select(1)
-- Initialize blocks processed tracker at the very start
processed_at_last_check = dig.getBlocksProcessed()

if reloaded then

 flex.send("Resuming "..tostring(zmax).."x"
   ..tostring(xmax).." quarry",colors.yellow)

 if dig.gety()==dig.getymin() and dig.gety()~=0 then
  zdir = dig.getzlast()
  if zdir == 0 then zdir = 1 end
  xdir = dig.getxlast()
  if xdir == 0 then xdir = 1 end

  if dig.getr() >= 360 then
   -- This encodes whether or not the turtle has
   --  started a new layer if at the edge
   xdir = -xdir
   newlayer = true
  end --if

 else
  gotoBase() -- gotoBase calls movement, which calls addBlocksProcessed
  if dodumps then dig.doDumpDown() end
  dig.dropNotFuel()
  dig.gotor(0) -- gotor calls update
  checkFuel()
  -- skip is used here
  dig.gotoy(math.min(dig.getymin(),-skip)) -- gotoy calls movement, which calls addBlocksProcessed
 end --if

else

 flex.send("Starting "..tostring(zmax).."x"
   ..tostring(xmax).." quarry",colors.yellow)

 if skip > 0 then
  flex.send("Skipping "..tostring(skip)
    .."m", colors.lightGray)
 end --if

 -- Clarify depth based on depth_arg interpretation
 if depth_arg !== nil then
  flex.send("Going "..tostring(depth_in_layers).." layers deep", colors.lightGray)
 else
  flex.send("Going to bedrock!",colors.lightGray)
 end --if/else

end --if/else


-- Immediately before the descent loop
print("DEBUG: Before descent loop. dig.gety(): " .. tostring(dig.gety()) .. ", -skip: " .. tostring(-skip)) -- Debug print kept
-- Reset speed learning period counters and timer at the start of a new quarry or resume
blocks_processed_since_last_speed_check = 0
time_of_last_speed_check = os.epoch("local") or 0
processed_at_last_check = dig.getBlocksProcessed() -- Initialize processed tracker


while dig.gety() > -skip do
 checkFuel()
 dig.down() -- down calls addBlocksProcessed

 if dig.isStuck() then
  flex.send("Co-ordinates lost! Shutting down",
    colors.red)
  --rs.delete("startup.lua")
  return
 end --if
 -- checkReceivedCommand() -- Remove if not doing remote control
end --while
print("DEBUG: After descent loop.") -- Debug print kept

-- Now that the initial descent is done, set the starting Y for total block calculation
local initial_ymax = dig.gety() -- This should be 0 or -skip

-- Calculate total blocks based on dimensions and number of layers
total_quarry_blocks = xmax * zmax * depth_in_layers

-- Ensure total_quarry_blocks is not negative
if total_quarry_blocks < 0 then total_quarry_blocks = 0 end
print("DEBUG: Total quarry blocks calculated: "..tostring(total_quarry_blocks).." (X="..tostring(xmax)..", Z="..tostring(zmax)..", Layers="..tostring(depth_in_layers)..")")
print("DEBUG: Initial Ymax: "..tostring(initial_ymax)..", Calculated Ymin: "..tostring(ymin))


--------------------------
-- |\/|  /\  [¯¯] |\ || --
-- |  | |  |  ][  | \ | --
-- |||| |||| [__] || \| --
--------------------------
-- ||    /¯\   /¯\  |¯\ --
-- ||_  | O | | O | | / --
-- |__]  \_/   \_/  ||  --
--------------------------

local done = false -- 'done' is local to this main loop
-- Reset speed learning timer and counter at the start of the main loop if not reloaded
if not reloaded then
 blocks_processed_since_last_speed_check = 0
 time_of_last_speed_check = os.epoch("local") or 0
 processed_at_last_check = dig.getBlocksProcessed() -- Initialize processed tracker
end


while not done and not dig.isStuck() do
 -- checkReceivedCommand() -- Remove if not doing remote control
 turtle.select(1)

 while not done do
  -- checkReceivedCommand() -- Remove if not doing remote control

  checkAll(0) -- checkAll calls checkProgress, which calls status send and speed learning

  if dig.getz()<=0 and zdir==-1 then break end
  if dig.getz()>=zmax-1 and zdir==1 then break end

  if zdir == 1 then dig.gotor(0) -- gotor calls update
  elseif zdir == -1 then dig.gotor(180) -- gotor calls update
  end --if/else
  checkNewLayer()

  dig.fwd() -- fwd calls addBlocksProcessed

  if dig.isStuck() then
   done = true
  end --if

 end --while (z loop)

 if done then break end

 zdir = -zdir
 newlayer = false

 -- Add print at the start of a new row
 flex.printColors("Starting new row at X="..tostring(dig.getx()).." Z="..tostring(dig.getz()).." Layer="..tostring(-dig.gety()), colors.gray)

 if dig.getx()<=0 and xdir==-1 then
  newlayer = true
 elseif dig.getx()>=xmax-1 and xdir==1 then
  newlayer = true
 else
  checkAll(0) -- checkAll calls checkProgress, which calls status send and speed learning
  dig.gotox(dig.getx()+xdir) -- gotox calls movement, which calls addBlocksProcessed
 end --if/else

 if newlayer and not dig.isStuck() then
  xdir = -xdir
  if dig.getymin() <= ymin then break end
  checkAll(0) -- checkAll calls checkProgress, which calls status send and speed learning
  dig.down() -- down calls addBlocksProcessed
  -- Add print at the start of a new layer
  flex.printColors("Starting new layer at Y="..tostring(dig.gety()), colors.purple)
  -- Reset speed learning timer and counter at the start of a new layer
  blocks_processed_since_last_speed_check = 0
  time_of_last_speed_check = os.epoch("local") or 0
  processed_at_last_check = dig.getBlocksProcessed() -- Initialize processed tracker for the layer
 end --if

end --while (cuboid dig loop)


flex.send("Digging completed, returning to surface",
  colors.yellow)
gotoBase() -- gotoBase calls movement, which calls addBlocksProcessed

flex.send("Descended "..tostring(-dig.getymin())..
    "m total",colors.green)
flex.send("Dug "..tostring(dig.getdug())..
    " blocks total",colors.lightBlue)

-- Final status send upon completion
sendStatus()


for x=1,16 do
 if dig.isBuildingBlock(x) then
  turtle.select(x)
  dig.placeDown()
  break
 end --if
end --for
turtle.select(1)

if dodumps then
 dig.gotor(0) -- gotor calls update
 dig.doDump()
 dig.gotor(180) -- gotor calls update
end
dig.dropNotFuel()
dig.gotor(0) -- gotor calls update

dig.clearSave()
flex.modemOff() -- Keep this to close the modem even if not used for remote control
os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")