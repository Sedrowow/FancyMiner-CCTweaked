-- This is a replacement for the
-- 'excavate' program, as it can re-
-- cover from a reboot/unload event.
-- Also avoids destroying spawners!

-----------------------------------
-- [¯¯] || || |¯\ [¯¯] ||   |¯¯] --
--  ||  ||_|| | /  ||  ||_  | ]  --
--  ||   \__| | \  ||  |__| |__] --
-----------------------------------
--  /¯\  || ||  /\  |¯\ |¯\ \\// --
-- | O | ||_|| |  | | / | /  \/  --
--  \_\\  \__| |||| | \ | \  ||  --
-----------------------------------

os.loadAPI("flex.lua")
os.loadAPI("dig.lua")
local log_file = "log.txt" -- Added log_file variable
local options_file = "flex_options.cfg" -- Added options_file variable
local modem_channel = 6464 -- Added modem_channel variable

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
    print("DEBUG: Modem peripheral wrapped. Will attempt to transmit status on channel 6465.")
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
 dig.loadCoords()
end --if
dig.makeStartup("quarry",args)


local zmax = tonumber(args[1])
local xmax = tonumber(args[2]) or zmax
local depth = world_height-1
local depth_arg = tonumber(args[3]) -- Store the depth argument separately

if depth_arg ~= nil then
 depth = depth_arg -- Use the provided depth argument
end --if
local ymin = -depth -- Calculate ymin based on the depth argument


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
-- |¯¯]|| |||\ || /¯][¯¯][¯¯] /¯\ |\ ||/¯¯\\ --
-- | ] ||_||| \\ || [  ||  ][ | O || \ |\¯\\ --
-- ||   \__||| \| \_| || [__] \_/ || \|\\__/ --
----------------------------------------------

local location
local function gotoBase()
 local x = dig.getxlast()
 location = dig.location()
 -- skip is used here
 if dig.gety() < -skip then dig.up() end
 dig.gotox(0)
 dig.gotoz(0)
 dig.gotor(180)
 dig.gotoy(0)
 dig.gotox(0)
 dig.setxlast(x)
 dig.gotoz(0)
 dig.gotor(180)
 return location
end --function

local function returnFromBase(loc)
 local loc = loc or location
 local x = dig.getxlast()
 dig.gotor(0)
 checkFuel()
 -- skip is used here
 dig.gotoy(math.min(loc[2]+1,-skip))
 checkFuel()
 dig.gotoz(loc[3])
 checkFuel()
 dig.gotox(loc[1])
 dig.setxlast(x) -- Important for restoring
 checkFuel()
 dig.gotor(loc[4])
 checkFuel()
 dig.gotoy(loc[2])
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
 loc = gotoBase()
 print(" ")
 flex.printColors("Press ENTER to resume mining",
   colors.pink)
 while flex.getKey() ~= keys.enter do
  sleep(1)
 end --while

 if dodumps then dig.doDumpDown() end
 dig.dropNotFuel()
 flex.send("Resuming quarry",colors.yellow)
 returnFromBase(loc)

end --function


local function checkInv()
 if turtle.getItemCount(16) > 0 then

  if dodumps then
   dig.right(2)
   dig.doDump()
   dig.left(2)
  end --if

  if turtle.getItemCount(14) > 0 then
   local loc = gotoBase()
   dig.dropNotFuel()
   returnFromBase(loc)
  end --if

 end --if
end --function

local total_quarry_blocks = 0 -- Will be calculated after initial descent
function checkFuel()
 local a = turtle.getFuelLevel()
 -- This fuel estimate is very basic, you might need to adjust it
 -- local b = ( zmax + xmax + math.abs(dig.gety() - ymin) ) * 2 -- Original basic fuel estimate
 local c = true

 -- More detailed fuel estimate based on remaining blocks (using processed blocks)
 local current_processed_blocks = dig.getBlocksProcessed() or 0
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
end --function checkFuel()

-- Variables for status sending interval (DEFINED OUTSIDE any function)
-- Use os.epoch("local") for a precise, real-world time-based timestamp in milliseconds for sending
local last_status_sent_time = os.epoch("local") or 0 -- Initialize defensively with epoch time in milliseconds
-- Status send interval in milliseconds (4 seconds = 4000 milliseconds)
local status_send_interval = 4 * 1000 -- Send status every 4 seconds (in milliseconds)

-- Variables for ETA calculation and speed learning
-- total_quarry_blocks is calculated once after initial descent
local blocks_since_last_speed_check = 0 -- Renamed for clarity
-- Use os.epoch("local") for speed learning time
local time_of_last_speed_check = os.epoch("local") or 0 -- Use local time for speed learning
local avg_blocks_per_second = 0.8 -- Initial estimate (blocks processed per second)
local speed_check_threshold = 50 -- Recalculate speed after processing this many blocks

local dug = dig.getdug() or 0 -- Track dug blocks from previous checkProgress call, handle nil
local processed_at_last_check = dig.getBlocksProcessed() or 0 -- Track processed blocks from previous checkProgress call, handle nil
local ydeep = dig.getymin() or 0 -- Track min Y from previous checkProgress call, handle nil
local last_gps_check_block = 0 -- Track when we last did GPS verification

-- Add this function to gather and send status (DEFINED OUTSIDE any function)
local function sendStatus()
    -- Gather status data
    -- total_quarry_blocks is calculated once after initial descent

    local current_processed_blocks = dig.getBlocksProcessed() or 0
    local estimated_remaining_blocks = total_quarry_blocks - current_processed_blocks

    local estimated_time_remaining_seconds = -1 -- Default to -1 if cannot calculate
    local estimated_completion_time_str = "Calculating..."
    local estimated_time_remaining_duration_str = "Calculating..." -- Added: for remaining duration

    -- Calculate Estimated Time Remaining and Completion Time if we have enough info and a valid speed
    if type(estimated_remaining_blocks) == 'number' and estimated_remaining_blocks > 0 and type(avg_blocks_per_second) == 'number' and avg_blocks_per_second > 0 then
        estimated_time_remaining_seconds = estimated_remaining_blocks / avg_blocks_per_second

        -- Format the completion time using the local timezone
        local current_local_epoch_time_sec = (os.epoch("local") or 0) / 1000 -- Get current local time in seconds
        local estimated_completion_time_sec = current_local_epoch_time_sec + estimated_time_remaining_seconds
        estimated_completion_time_str = os.date("%Y-%m-%d %H:%M:%S", estimated_completion_time_sec)

        -- Format the remaining duration as MM:SS
        local minutes = math.floor(estimated_time_remaining_seconds / 60)
        local seconds = math.floor(estimated_time_remaining_seconds % 60)
        estimated_time_remaining_duration_str = string.format("%02d:%02d", minutes, seconds)

    elseif total_quarry_blocks > 0 and estimated_remaining_blocks <= 0 then
        estimated_completion_time_str = "Completed" -- Indicate if digging is theoretically done
        estimated_time_remaining_duration_str = "00:00" -- Duration is zero when completed
    end


    -- Get inventory summary (basic example)
    local inventory_summary = {}
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            table.insert(inventory_summary, { name = item.name, count = item.count })
        end
    end
    -- Infer mining state; assumes mining when not stuck
    local is_mining_status = not dig.isStuck()


    local status_message = {
        type = "status_update", -- Indicate this is a status update
        id = os.getComputerID(), -- Include turtle ID
        label = os.getComputerLabel(), -- Include turtle label
        fuel = turtle.getFuelLevel(),
        position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
        is_mining = is_mining_status, -- Reflect actual mining state
        estimated_completion_time = estimated_completion_time_str, -- Estimated completion date and time
        estimated_time_remaining = estimated_time_remaining_duration_str, -- Added: Estimated time remaining duration (MM:SS)
        total_quarry_blocks = total_quarry_blocks, -- Send total blocks for context
        dug_blocks = dig.getdug() or 0, -- Still send dug blocks, handle nil
        processed_blocks = current_processed_blocks, -- Send processed blocks for context
        ymin = ymin, -- Add ymin (minimum Y planned) to the status message
        inventory_summary = inventory_summary -- Include basic inventory summary
    }

    -- Send the status message on a specific channel
    local status_channel = modem_channel -- Channel for status updates
    if modem then -- Check if modem peripheral is available
        -- print("DEBUG: Attempting to transmit status on channel " .. status_channel) -- NEW DEBUG PRINT before transmit
        -- Transmit from modem_channel to status_channel for a broadcast
        modem.transmit(modem_channel, status_channel, status_message)
        -- print("DEBUG: Status update sent on channel " .. status_channel) -- Optional debug
    else
        -- print("DEBUG: sendStatus called but modem is nil. Cannot transmit.") -- NEW DEBUG PRINT if modem is nil
    end
end

-- checkProgress function (MODIFIED to call sendStatus and implement speed learning)
local function checkProgress()
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
    flex.printColors("Dug: "..tostring(dig.getdug() or 0).." blocks", colors.lightBlue) -- Handle nil

    term.setCursorPos(1,4)
    term.clearLine()
    flex.printColors("Depth: "..tostring(-dig.gety()).."m / "..tostring(-ymin).."m", colors.green)

    -- Speed Learning Logic
    -- Use processed blocks for speed calculation base
    local current_processed_blocks = dig.getBlocksProcessed() or 0
    -- Only update if blocks were actually processed since the last check
    if current_processed_blocks > processed_at_last_check then
        local blocks_processed_this_check = current_processed_blocks - processed_at_last_check
        blocks_since_last_speed_check = blocks_since_last_speed_check + blocks_processed_this_check

        -- Check if threshold is met for speed recalculation
        if blocks_since_last_speed_check >= speed_check_threshold then
            local current_epoch_time_ms = os.epoch("local") or 0
            local time_elapsed_ms = current_epoch_time_ms - time_of_last_speed_check

            -- Avoid division by zero or very small times
            if type(time_elapsed_ms) == 'number' and time_elapsed_ms > 0 then
                local current_period_bps = blocks_since_last_speed_check / (time_elapsed_ms / 1000) -- Calculate speed for this period in blocks per second
                -- Check against math.huge and -math.huge as values, AND check for NaN using self-comparison
                 if type(current_period_bps) == 'number' and current_period_bps ~= math.huge and current_period_bps ~= -math.huge and current_period_bps == current_period_bps then -- **CORRECTED: Replaced not math.nan() with self-comparison**
                     -- Simple averaging: average the new rate with the existing average
                     avg_blocks_per_second = (avg_blocks_per_second + current_period_bps) / 2
                 else
                      print("DEBUG: current_period_bps is not a valid number for averaging (NaN, +Inf, or -Inf). Value: " .. tostring(current_period_bps)) -- Added debug print
                 end
            else
                -- If no time has elapsed or time is invalid, do not calculate or update speed for this period.
                 print("DEBUG: Skipping speed calculation due to zero or invalid time_elapsed_ms (" .. tostring(time_elapsed_ms) .. ").") -- Added debug print
            end


            -- Reset for the next speed check period
            blocks_since_last_speed_check = 0
            time_of_last_speed_check = current_epoch_time_ms -- Start next period timer from now

        end
    end
    -- Update processed_at_last_check for the next checkProgress call
    processed_at_last_check = current_processed_blocks


    -- Calculate Estimated Time Remaining in Seconds
    local estimated_time_remaining_seconds = -1 -- Default to -1 if cannot calculate
    -- Use processed blocks for ETA base
    local remaining_blocks_for_eta = total_quarry_blocks - current_processed_blocks

    if type(remaining_blocks_for_eta) == 'number' and remaining_blocks_for_eta > 0 and type(avg_blocks_per_second) == 'number' and avg_blocks_per_second > 0 then
        estimated_time_remaining_seconds = remaining_blocks_for_eta / avg_blocks_per_second
    end

    -- Format Estimated Time Remaining as MM:SS for local display
    local eta_display_str = "Calculating..."
    if type(estimated_time_remaining_seconds) == 'number' and estimated_time_remaining_seconds >= 0 then
        local minutes = math.floor(estimated_time_remaining_seconds / 60)
        local seconds = math.floor(estimated_time_remaining_seconds % 60)
        eta_display_str = string.format("%02d:%02d", minutes, seconds)
        if estimated_time_remaining_seconds == 0 then
            eta_display_str = "Done"
        end
    end

    -- Display ETA on local console
    term.setCursorPos(1,5) -- Example line, adjust as needed
    term.clearLine()
    flex.printColors("ETA: "..eta_display_str, colors.yellow) -- Use yellow for ETA


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

    -- Update dug and ydeep for the next checkProgress call
    dug = dig.getdug() or 0 -- Corrected to get current dug value, handle nil
    ydeep = dig.gety() or 0 -- Update ydeep, handle nil

    -- Periodic GPS verification (every 200 blocks processed)
    -- Only verify if we've crossed a boundary (not on every call)
    local last_gps_check_block = last_gps_check_block or 0
    if dig.isGPSEnabled() and (current_processed_blocks - last_gps_check_block) >= 200 then
        dig.verifyPositionGPS(1) -- Tolerance of 1 block
        last_gps_check_block = current_processed_blocks
    end

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
--       |\/|  /\  [¯¯] |\ ||         --
--       |  | |  |  ][  | \ |         --
--      |||| |||| [__] || \|         --
---------------------------------------
-- |¯\ |¯\  /¯\   /¯¯] |¯\  /\  |\/| --
-- | / | / | O | | [¯| | / |  | |  | --
-- ||  | \  \_/   \__| | \ |||| |||| --
---------------------------------------

local a,b,c,x,y,z,r,loc
local xdir, zdir = 1, 1

turtle.select(1)
if reloaded then
 flex.send("Resuming "..tostring(zmax).."x"
   ..tostring(xmax).." quarry",colors.yellow)

 -- GPS position verification happens in dig.loadCoords()
 -- If GPS wasn't previously available but is now, offer to establish it
 if not dig.isGPSEnabled() then
  local wx, wy, wz = dig.getGPSPosition(2)
  if wx then
   flex.send("GPS is now available!", colors.green)
   flex.send("Returning to origin to establish GPS...", colors.cyan)
   
   -- Save current position
   local resume_x = dig.getx()
   local resume_y = dig.gety()
   local resume_z = dig.getz()
   local resume_r = dig.getr()
   
   -- Return to origin
   gotoBase()
   
   -- Establish GPS at origin
   if dig.establishGPSAtOrigin() then
    flex.send("GPS established successfully!", colors.green)
   end
   
   -- Return to mining position
   flex.send("Returning to mining position...", colors.yellow)
   dig.gotor(0)
   checkFuel()
   dig.gotoy(math.min(resume_y,-skip))
   checkFuel()
   dig.gotoz(resume_z)
   checkFuel()
   dig.gotox(resume_x)
   checkFuel()
   dig.gotor(resume_r)
   checkFuel()
  end
 end
 
 local resume_x = dig.getx()
 local resume_y = dig.gety()
 local resume_z = dig.getz()
 local resume_r = dig.getr()

 if dig.gety()==dig.getymin() and dig.gety()~=0 then
  -- We're at the mining level
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
  -- We need to return to our last position
  flex.send("Returning to last position...", colors.yellow)
  gotoBase()
  if dodumps then dig.doDumpDown() end
  dig.dropNotFuel()
  
  -- Return to saved mining position
  dig.gotor(0)
  checkFuel()
  -- First go to the correct Y level
  dig.gotoy(math.min(resume_y,-skip))
  checkFuel()
  -- Then move to correct X/Z position
  dig.gotoz(resume_z)
  checkFuel()
  dig.gotox(resume_x)
  checkFuel()
  -- Finally restore the correct rotation
  dig.gotor(resume_r)
  checkFuel()
  
  -- Update state tracking variables
  xdir = dig.getxlast()
  if xdir == 0 then xdir = 1 end
  zdir = dig.getzlast()
  if zdir == 0 then zdir = 1 end
  
  flex.send("Resumed at position: X=" .. resume_x .. 
            ", Y=" .. resume_y .. 
            ", Z=" .. resume_z, colors.yellow)
 end --if

else

 flex.send("Starting "..tostring(zmax).."x"
   ..tostring(xmax).." quarry",colors.yellow)

 if skip > 0 then
  flex.send("Skipping "..tostring(skip)
    .."m", colors.lightGray)
 end --if

 if depth_arg ~= nil then -- Check if depth_arg was provided
  flex.send("Going "..tostring(depth_arg)
    .."m deep", colors.lightGray)
 else
  flex.send("To bedrock!",colors.lightGray)
 end --if/else

 -- Initialize GPS at starting position (new quarry, at origin)
 flex.send("Initializing GPS system...", colors.cyan)
 dig.initGPSOrigin(false) -- Don't force new origin

end --if/else


-- Immediately before the descent loop
print("DEBUG: Before descent loop. dig.gety(): " .. tostring(dig.gety()) .. ", -skip: " .. tostring(-skip)) -- Debug print kept
-- Reset speed learning timer and counter at the start of a new quarry or resume
blocks_since_last_speed_check = 0
time_of_last_speed_check = os.epoch("local") or 0

while dig.gety() > -skip do
 checkFuel()
 dig.down()

 if dig.isStuck() then
  flex.send("Co-ordinates lost! Shutting down",
    colors.red)
  --rs.delete("startup.lua")
  return
 end --if
 -- checkReceivedCommand() -- Remove if not doing remote control
end --while
print("DEBUG: After descent loop.") -- Debug print kept

-- **CORRECTED: Calculate total_quarry_blocks based on the full volume from Y=0 down to ymin**
-- This represents the total number of locations in the quarry.
local total_quarry_depth_layers = 0 - ymin
total_quarry_blocks = xmax * zmax * total_quarry_depth_layers -- Corrected total blocks calculation

-- Ensure total_quarry_blocks is not negative or zero if dimensions are invalid or mining depth is 0 or less
if total_quarry_blocks <= 0 then
    flex.send("Error: Calculated total quarry blocks is <= 0. Check dimensions and skip value.", colors.red)
    shell.run("rm startup.lua")
    return
end

print("DEBUG: Total quarry blocks calculated (full volume from Y=0 to ymin): "..tostring(total_quarry_blocks))

-- **REMOVED: Code that was adding skipped blocks to dug and processed counts here.**
-- This is no longer necessary as dig.lua now counts all successful movements.


--------------------------
-- |\/|  /\  [¯¯] |\ || --
-- |  | |  |  ][  | \ | --
-- |||| |||| [__] || \| --
--------------------------
-- ||    /¯\   /¯\  |¯\ --
-- ||_  | O | | O | | / --
-- |__]  \_/   \_/  ||  --
--------------------------

local done = false -- 'done' is local to this main loop
-- Reset speed learning timer and counter at the start of the main loop
blocks_since_last_speed_check = 0
time_of_last_speed_check = os.epoch("local") or 0

-- Assuming the inner loop always traverses along the Z axis (length)
local inner_loop_dimension = zmax
-- Assuming the outer loop moves along the X axis (width) and handles layer changes
local outer_loop_dimension = xmax

-- Add state validation function near the top of the file
local function validateState()
    -- Validate position bounds
    if dig.getx() >= xmax or dig.getx() < 0 then
        flex.send("Position out of X bounds, attempting recovery...", colors.red)
        dig.gotox(math.min(math.max(dig.getx(), 0), xmax-1))
    end
    if dig.getz() >= zmax or dig.getz() < 0 then
        flex.send("Position out of Z bounds, attempting recovery...", colors.red)
        dig.gotoz(math.min(math.max(dig.getz(), 0), zmax-1))
    end
    
    -- Validate rotation
    local r = dig.getr() % 360
    if r ~= 0 and r ~= 90 and r ~= 180 and r ~= 270 then
        flex.send("Invalid rotation detected, correcting...", colors.red)
        dig.gotor(math.floor(r/90) * 90)
    end
    
    return true
end

-- Add state save function
local function saveCurrentState()
    -- Save current position and state
    dig.saveCoords()
    -- Verify save was successful
    if not dig.saveExists() then
        flex.send("Warning: Failed to save state!", colors.red)
    end
end

-- Add near the state validation function
local function validatePosition()
    -- Get current position
    local current_x = dig.getx()
    local current_z = dig.getz()
    
    -- Check if we're out of bounds and log the issue
    if current_x >= xmax or current_x < 0 or current_z >= zmax or current_z < 0 then
        flex.send(string.format("Position out of bounds! X=%d, Z=%d (max: X=%d, Z=%d)", 
            current_x, current_z, xmax-1, zmax-1), colors.red)
        return false
    end
    return true
end

-- Modify the validatePosition function to use proper bounds
local function validatePosition()
    -- Get current position
    local current_x = dig.getx()
    local current_z = dig.getz()
    
    -- Check if we're out of bounds and log the issue
    -- Changed bounds checking to be inclusive of the max values
    if current_x > xmax or current_x < 0 or current_z > zmax or current_z < 0 then
        flex.send(string.format("Position out of bounds! X=%d, Z=%d (max: X=%d, Z=%d)", 
            current_x, current_z, xmax, zmax), colors.red)
        return false
    end
    return true
end

-- Replace the validatePosition function with this Y-aware version
local function validatePosition()
    -- Get current position
    local current_x = dig.getx()
    local current_y = dig.gety()
    local current_z = dig.getz()
    
    -- Add position debugging
    print(string.format("DEBUG: Current position - X=%d, Y=%d, Z=%d (bounds: 0 to X=%d, Y to %d, Z=%d)", 
        current_x, current_y, current_z, xmax-1, ymin, zmax-1))
    
    -- Check if we're out of bounds
    -- Note: Y coordinate can go negative for digging down, but shouldn't go below ymin
    if current_x >= xmax or current_x < 0 or 
       current_z >= zmax or current_z < 0 or 
       current_y < ymin then -- Only check lower Y bound
        flex.send(string.format("Position out of bounds! X=%d, Y=%d, Z=%d", current_x, current_y, current_z), colors.red)
        
        -- Store original position for logging
        local orig_x = current_x
        local orig_y = current_y
        local orig_z = current_z
        
        -- Calculate closest valid position
        local target_x = math.min(math.max(current_x, 0), xmax-1)
        local target_y = math.max(current_y, ymin) -- Only enforce minimum Y
        local target_z = math.min(math.max(current_z, 0), zmax-1)
        
        flex.send(string.format("Attempting to recover to X=%d, Y=%d, Z=%d", target_x, target_y, target_z), colors.yellow)
        
        -- First try to correct X position
        if current_x ~= target_x then
            dig.gotox(target_x)
            if dig.getx() ~= target_x then
                flex.send("Failed to correct X position!", colors.red)
                return false
            end
        end
        
        -- Then try to correct Z position
        if current_z ~= target_z then
            dig.gotoz(target_z)
            if dig.getz() ~= target_z then
                flex.send("Failed to correct Z position!", colors.red)
                return false
            end
        end
        
        -- Finally correct Y if we're too deep
        if current_y < target_y then
            dig.gotoy(target_y)
            if dig.gety() ~= target_y then
                flex.send("Failed to correct Y position!", colors.red)
                return false
            end
        end
        
        -- Verify the recovery was successful
        if dig.getx() == target_x and dig.getz() == target_z and dig.gety() >= target_y then
            flex.send(string.format("Successfully recovered from (%d,%d,%d) to (%d,%d,%d)", 
                orig_x, orig_y, orig_z, target_x, target_y, target_z), colors.green)
            return true
        else
            flex.send("Position recovery failed!", colors.red)
            return false
        end
    end
    return true
end

-- Add this new function to handle complete position recovery
local function recoverPosition()
    -- Get current layer information
    local current_y = dig.gety()
    local current_x = dig.getx()
    local current_z = dig.getz()
    
    flex.send("Attempting full position recovery...", colors.yellow)
    
    -- First, try to return to a known good X position
    local target_x = math.min(math.max(0, current_x), xmax-1)
    if not dig.gotox(target_x) then
        flex.send("Failed to recover X position", colors.red)
        return false
    end
    
    -- Then correct Z position
    local target_z = math.min(math.max(0, current_z), zmax-1)
    if not dig.gotoz(target_z) then
        flex.send("Failed to recover Z position", colors.red)
        return false
    end
    
    -- Adjust rotation based on current position
    if zdir == 1 then
        dig.gotor(0)
    else
        dig.gotor(180)
    end
    
    flex.send(string.format("Recovered to position X=%d, Z=%d", dig.getx(), dig.getz()), colors.green)
    return true
end

-- Replace the main mining loop with this corrected version
while not done and not dig.isStuck() do
    validateState()
    turtle.select(1)
    
    -- Changed loop condition to ensure we process all blocks from 0 to zmax-1 (inclusive)
    for step = 0, zmax-1 do  -- Changed to start at 0 and go to zmax-1
        checkAll(0)
        
        -- Set rotation based on current Z direction
        if zdir == 1 then 
            dig.gotor(0)
        elseif zdir == -1 then 
            dig.gotor(180)
        end
        
        saveCurrentState()
        
        -- Only move forward if we haven't processed the last block in this row
        -- Note: We're already at the block we want to process, so check if we should move to the next one
        if step < zmax-1 then  -- Only move forward if we're not at the last block
            -- Validate position before moving
            if not validatePosition() then
                flex.send("Position validation failed, attempting recovery...", colors.yellow)
                if not recoverPosition() then
                    flex.send("Recovery failed, stopping quarry", colors.red)
                    done = true
                    break
                end
            end
            
            -- Move forward with validation
            if not dig.fwd() then
                if not recoverPosition() then
                    done = true
                    break
                end
            end
            
            -- Validate position after movement
            if not validatePosition() then
                if not recoverPosition() then
                    done = true
                    break
                end
            end
        end
    end

    if done then break end
    
    -- After traversing a row, change Z direction and move to next row along X
    zdir = -zdir
    newlayer = false
    
    validateState()
    
    -- Handle row transition
    local current_x = dig.getx()
    
    -- Check if we need to start a new layer
    if (current_x <= 0 and xdir == -1) or (current_x >= xmax-1 and xdir == 1) then
        newlayer = true
        flex.send("Starting new layer...", colors.yellow)
    else
        checkAll(0)
        saveCurrentState()
        local target_x = current_x + xdir
        -- Validate target position before moving
        if target_x >= 0 and target_x < xmax then  -- Changed condition to use < xmax
            dig.gotox(target_x)
        else
            flex.send("X position would be out of bounds, starting new layer", colors.yellow)
            newlayer = true
        end
    end
    
    -- Handle layer transition
    if newlayer and not dig.isStuck() then
        xdir = -xdir
        -- Save state before layer change
        saveCurrentState()
        
        if dig.gety() <= ymin then
            done = true
            break
        end
        
        checkAll(0)
        if not dig.down() then
            flex.send("Layer transition failed, attempting recovery...", colors.red)
            validateState()
            if not dig.down() then
                done = true
                break
            end
        end
        
        -- Validate state after layer change
        validateState()
        
        flex.printColors("Starting new layer at Y="..tostring(dig.gety()), colors.purple)
    end
end


flex.send("Digging completed, returning to surface",
  colors.yellow)
sendStatus() -- Send final status update
gotoBase()

flex.send("Descended "..tostring(-(dig.getymin() or 0)).. -- Handle nil for dig.getymin
    "m total",colors.green)
flex.send("Dug "..tostring(dig.getdug() or 0).. -- Handle nil for dig.getdug
    " blocks total",colors.lightBlue)

-- Final status send upon completion (redundant if called before gotoBase, but harmless)
-- sendStatus()


for x=1,16 do
 if dig.isBuildingBlock(x) then
  turtle.select(x)
  dig.placeDown()
  break
 end --if
end --for
turtle.select(1)

if dodumps then
 dig.gotor(0)
 dig.doDump()
 dig.gotor(180)
end
dig.dropNotFuel()
dig.gotor(0)

dig.clearSave()
flex.modemOff() -- Keep this to close the modem even if not used for remote control
os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")