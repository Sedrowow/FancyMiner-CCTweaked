local log_file = "log.txt"
local options_file = "flex_options.cfg"
os.loadAPI("flex.lua")
os.loadAPI("dig.lua")
local modem_channel = 6464
-- local received_command = nil -- Remove if not needed for status only

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
    print("DEBUG: Modem peripheral wrapped. Will attempt to transmit status on channel "..tostring(modem_channel)..".") -- Corrected channel number in print
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
  -- The getymin in dig.lua is not set based on the initial depth arg, it's the lowest y reached.
  -- So the check below doesn't make sense here. The skip is only for initial descent.
  -- if dig.getymin() > -skip then
  --  dig.setymin(-skip)
  -- end --if
 end --if
end --for


if not lava then -- Block lava around edges of quarry
 dig.setBlockSlot(0)
 -- Always keep a stack of blocks
end --if




----------------------------------------------
-- |¯¯]|| |||\ || /¯][¯¯][¯¯] /¯\ |\ ||/¯¯\\ --
-- | ] ||_||| \ || || [  ||  ][ | O || \ |\¯\\ --
-- ||   \__||| \| \_| || [__] \_/ || \|\__/ --
----------------------------------------------

local saved_location -- Variable to store the location before going to base
local function gotoBase()
 -- Save the current location *before* moving
 saved_location = dig.location()

 -- Move to base coordinates (0, 0, 0) and face South (180)
 -- dig.goto handles movement in the correct order (Y then X then Z)
 dig.goto(0, 0, 0, 180)

 -- At base (0,0,0, facing South)
 -- You can add base operations here like refueling or dumping before returning

 return saved_location -- Return the saved location
end --function

local function returnFromBase(loc)
 local loc = loc or saved_location -- Use the saved_location if loc is nil

 if type(loc) ~= "table" or #loc < 4 then
     flex.send("Error: Invalid saved location data to return from base.", colors.red)
     return false -- Indicate failure to return
 end

 -- Return to the saved coordinates and rotation
 -- dig.goto handles movement in the correct order
 dig.goto(loc[1], loc[2], loc[3], loc[4])

 -- After returning, perform checks
 checkFuel() -- Check fuel after moving back
 checkInv() -- Check inventory after moving back
 checkHalt() -- Check halt after moving back
 dig.checkBlocks() -- Check building blocks

 return true -- Indicate successful return
end --function


local function checkHalt()
 -- Check for redstone signal from above (Y+1)
 -- Check redstone input specifically on the top side
 if peripheral.isPresent("top") then
    local top_peripheral = peripheral.wrap("top")
    if top_peripheral.isBundled? then -- Check if it's a bundled cable
        -- Assuming redstone input from the top peripheral acts as a halt signal
        local bundled_input = top_peripheral.getBundledInput("top")
        if bundled_input > 0 then -- Check if any bundled color is active
             -- Redstone signal from above
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
             loc = gotoBase() -- Go to base
             print(" ")
             flex.printColors("Press ENTER to resume mining",
               colors.pink)
             while flex.getKey() ~= keys.enter do
              sleep(1)
             end --while

             -- Operations at base before returning
             if dodumps then dig.doDumpDown() end
             dig.dropNotFuel()
             flex.send("Resuming quarry",colors.yellow)
             returnFromBase(loc) -- Return from base
             return true -- Indicate halt was handled
        end
    elseif top_peripheral.getInput? then -- Check if it's a standard redstone port
         if top_peripheral.getInput("top") then -- Check if standard redstone is active
             -- Redstone signal from above
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
             loc = gotoBase() -- Go to base
             print(" ")
             flex.printColors("Press ENTER to resume mining",
               colors.pink)
             while flex.getKey() ~= keys.enter do
              sleep(1)
             end --while

             -- Operations at base before returning
             if dodumps then dig.doDumpDown() end
             dig.dropNotFuel()
             flex.send("Resuming quarry",colors.yellow)
             returnFromBase(loc) -- Return from base
             return true -- Indicate halt was handled
         end
    end
 end
 -- Check redstone input on all sides as a fallback/alternative
 local sides = {"bottom", "left", "right", "front", "back"}
 for _, side in ipairs(sides) do
     if rs.getInput(side) then
         local loc,x
         -- Manual halt; redstone signal from the side
         flex.send("Manual halt initiated (Redstone on "..side..")", colors.orange)
          flex.printColors("Press ENTER to resume mining\n"
           .."or SPACE to return to base",
           colors.pink)

         while true do
          x = flex.getKey()
          if x == keys.enter then return end
          if x == keys.space then break end
         end --while

         flex.send("Returning to base", colors.yellow)
         loc = gotoBase() -- Go to base
         print(" ")
         flex.printColors("Press ENTER to resume mining",
           colors.pink)
         while flex.getKey() ~= keys.enter do
          sleep(1)
         end --while

         -- Operations at base before returning
         if dodumps then dig.doDumpDown() end
         dig.dropNotFuel()
         flex.send("Resuming quarry",colors.yellow)
         returnFromBase(loc) -- Return from base
         return true -- Indicate halt was handled
     end
 end

 return false -- Indicate no halt occurred
end --function


local function checkInv()
 -- Check if inventory is full (slot 16 has items)
 if turtle.getItemCount(16) > 0 then
     flex.send("Inventory full, returning to base", colors.yellow)
     local loc = gotoBase() -- Go to base
     -- At base (0,0,0, facing South)
     dig.gotor(0) -- Face North at base for potential dumping/refueling area
     if dodumps then
         dig.doDump() -- Dump forward (North)
     end
     dig.dropNotFuel() -- Drop other items into chest at base (should be North)
     flex.send("Inventory emptied", colors.lightBlue)
     returnFromBase(loc) -- Return to where it was
     return true -- Indicate inventory was handled
 end
 return false -- Indicate inventory is not full
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
 -- Also ensure current fuel is actually less than estimated needed before returning to base
 if type(estimated_fuel_needed) == 'number' and estimated_fuel_needed > 0 and a < estimated_fuel_needed then -- Check if current fuel is less than estimated needed (removed 1.2 safety margin for going to base)
     flex.send("Fuel low (Estimated needed for remaining: "..tostring(math.ceil(estimated_fuel_needed)).."), returning to surface", colors.yellow)
     local loc = gotoBase() -- Go to base (gotoBase calls movement, which calls addBlocksProcessed)
     turtle.select(1)
     if dodumps then dig.doDumpDown() end
     while turtle.suckUp() do sleep(0) end -- Suck up fuel items from chest below
     dig.dropNotFuel() -- Drop items that aren't fuel into a chest (should be North)
     -- Ensure refuel amount is not nil or non-positive
     local refuel_amount = estimated_fuel_needed * 1.5 -- Refuel to 150% of estimated needed
     if type(refuel_amount) == 'number' and refuel_amount > 0 then
       dig.refuel(refuel_amount)
     else
       dig.refuel(1000) -- Fallback refuel amount
     end
     flex.send("Fuel acquired! ("..tostring(turtle.getFuelLevel()).." fuel)", colors.lightBlue)
     returnFromBase(loc) -- Return from base (returnFromBase calls movement, which calls addBlocksProcessed)
     return true -- Indicate fuel was handled
 end
 return false -- Indicate fuel is sufficient
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
-- **ADDED: In-game time for pause detection**
local time_of_last_in_game_check = os.time() or 0 -- Use in-game time for pause detection
local avg_blocks_per_second = 0.8 -- Initial estimate (blocks processed per second)
local speed_check_threshold = 50 -- Recalculate speed after processing this many blocks

local dug = dig.getdug() or 0 -- Track dug blocks from previous checkProgress call, handle nil
local processed_at_last_check = dig.getBlocksProcessed() or 0 -- Track processed blocks from previous checkProgress call, handle nil
local ydeep = dig.getymin() or 0 -- Track min Y from previous checkProgress call, handle nil

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

    elseif type(total_quarry_blocks) == 'number' and total_quarry_blocks > 0 and type(current_processed_blocks) == 'number' and estimated_remaining_blocks <= 0 then
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
    -- Infer mining state; assumes mining when not stuck and not completed
    local is_mining_status = not dig.isStuck() and (type(estimated_remaining_blocks) ~= 'number' or estimated_remaining_blocks > 0)


    local status_message = {
        type = "status_update", -- Indicate this is a status update
        script = "quarry", -- Added script identifier
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
    flex.printColors("Dug: "..tostring(dig.getdug() or 0).." blocks", colors.lightBlue) -- Handle nil

    term.setCursorPos(1,4)
    term.clearLine()
    flex.printColors("Depth: "..tostring(-dig.gety()).."m / "..tostring(-ymin).."m", colors.green)

    -- Speed Learning Logic with Pause Detection
    local current_processed_blocks = dig.getBlocksProcessed() or 0
    local current_epoch_time_ms = os.epoch("local") or 0 -- Real-world time in milliseconds
    local current_in_game_time_sec = os.time() or 0 -- In-game time in seconds

    local real_world_time_elapsed_ms = current_epoch_time_ms - (time_of_last_speed_check or 0)
    local in_game_time_elapsed_sec = current_in_game_time_sec - (time_of_last_in_game_check or 0)

    -- Convert real-world elapsed time to seconds for comparison
    local real_world_time_elapsed_sec = real_world_time_elapsed_ms / 1000

    -- Define a threshold for pause detection (e.g., if real-world time is 5 seconds or more ahead of in-game time)
    local pause_threshold_sec = 5

    -- Check if blocks were actually processed since the last check AND check for significant pause
    if current_processed_blocks > processed_at_last_check then
        -- Check for significant pause (if real-world time is much larger than in-game time elapsed)
        if real_world_time_elapsed_sec > in_game_time_elapsed_sec + pause_threshold_sec then
             -- Pause detected
             flex.send("Pause detected. Skipping speed calculation for this period.", colors.orange)
             -- Perform self-correction by moving to current perceived coordinates
             flex.send("Performing self-correction to re-sync position.", colors.yellow)
             local current_pos = dig.location() -- Get current perceived location
             if current_pos and #current_pos >= 4 then
                 -- Use dig.goto to move to the current perceived location.
                 -- This will use dig.lua's movement functions, triggering checks.
                 dig.goto(current_pos[1], current_pos[2], current_pos[3], current_pos[4])
                 flex.send("Self-correction complete.", colors.lightBlue)
             else
                  flex.send("Self-correction failed: Could not get current position.", colors.red)
             end

             -- Reset speed learning timers and counters after a pause and correction
             blocks_since_last_speed_check = 0
             time_of_last_speed_check = current_epoch_time_ms
             time_of_last_in_game_check = current_in_game_time_sec
             processed_at_last_check = current_processed_blocks -- Update processed blocks after potential movement
        else
            -- No significant pause, proceed with speed calculation
            local blocks_processed_this_check = current_processed_blocks - processed_at_last_check
            blocks_since_last_speed_check = blocks_since_last_speed_check + blocks_processed_this_check

            -- Check if threshold is met for speed recalculation
            if blocks_since_last_speed_check >= speed_check_threshold then
                -- Avoid division by zero or very small times
                if type(real_world_time_elapsed_sec) == 'number' and real_world_time_elapsed_sec > 0 then
                    local current_period_bps = blocks_since_last_speed_check / real_world_time_elapsed_sec -- Calculate speed for this period in blocks per second
                     -- Check against math.huge and -math.huge as values, AND check for NaN using self-comparison
                     if type(current_period_bps) == 'number' and current_period_bps ~= math.huge and current_period_bps ~= -math.huge and current_period_bps == current_period_bps then -- **CORRECTED: Replaced not math.nan() with self-comparison**
                         -- Simple averaging: average the new rate with the existing average
                         avg_blocks_per_second = (avg_blocks_per_second + current_period_bps) / 2
                     else
                          print("DEBUG: current_period_bps is not a valid number for averaging (NaN, +Inf, or -Inf). Value: " .. tostring(current_period_bps)) -- Added debug print
                     end
                else
                    -- If no real-world time has elapsed or time is invalid, do not calculate or update speed for this period.
                     print("DEBUG: Skipping speed calculation due to zero or invalid real_world_time_elapsed_sec (" .. tostring(real_world_time_elapsed_sec) .. ").") -- Added debug print
                end

                -- Reset for the next speed check period
                blocks_since_last_speed_check = 0
                time_of_last_speed_check = current_epoch_time_ms -- Start next period real-world timer from now
                time_of_last_in_game_check = current_in_game_time_sec -- Start next period in-game timer from now

            end
        end
    end
    -- Update processed_at_last_check for the next checkProgress call, regardless of pause
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
 checkProgress() -- checkProgress calls status send logic and speed learning (with pause detection)
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
-- ||    /¯\   /¯\  |¯\ --
-- ||_  | O | | O | | / --
-- |__]  \_/   \_/  ||  --
--------------------------

local a,b,c,x,y,z,r,loc
local xdir = 1 -- Start moving along +X for the first row traversal pattern

turtle.select(1)
if reloaded then

 flex.send("Resuming "..tostring(zmax).."x"
   ..tostring(xmax).." quarry",colors.yellow)

 -- When reloading, determine the current xdir and zdir based on saved position/rotation
 local saved_r = dig.getr() % 360
 -- Simple attempt to determine xdir/zdir based on facing direction after reload
 if saved_r == 0 or saved_r == 180 then -- Facing North (+Z) or South (-Z)
     -- Likely in a Z traversal row
     -- Determine zdir based on where it is relative to zmax/zmin (should be moving towards the other boundary)
     if dig.getz() >= zmax -1 and saved_r == 0 then zdir = -1 -- Hit Z max, should turn back South
     elseif dig.getz() <= 0 and saved_r == 180 then zdir = 1 -- Hit Z min, should turn back North
     else zdir = (saved_r == 0) and 1 or -1 -- Otherwise, continue in current Z direction
     end
     -- Determine xdir based on the X coordinate (which "column" it's in)
     -- Assuming the pattern alternates X direction every xmax Z-traversals (every full row)
     -- This is complex to perfectly restore. Default to 1 for now or require reloading at base.
      xdir = 1 -- Simplification: may need more complex logic if reloading mid-row transition or mid-X step
 elseif saved_r == 90 then -- Facing East (+X)
     -- This orientation is typically only used for stepping between rows along X
      zdir = 1 -- Should be about to start a +Z row or just finished one
      xdir = 1 -- Should be moving along +X
 elseif saved_r == 270 then -- Facing West (-X)
      zdir = 1 -- Should be about to start a +Z row or just finished one
      xdir = -1 -- Should be moving along -X
 end
 -- Need to ensure zdir is correctly set for the start of the next row traversal loop

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

  -- Initial descent to skip depth
  print("DEBUG: Before initial descent loop. dig.gety(): " .. tostring(dig.gety()) .. ", -skip: " .. tostring(-skip)) -- Debug print kept
  -- Reset speed learning timer and counter before descent
  blocks_since_last_speed_check = 0
  time_of_last_speed_check = os.epoch("local") or 0
  time_of_last_in_game_check = os.time() or 0 -- Initialize in-game time check

  while dig.gety() > -skip do
   checkFuel()
   dig.down()
   if dig.isStuck() then
    flex.send("Stuck during initial descent! Shutting down",
      colors.red)
    shell.run("rm startup.lua")
    return
   end --if
   checkProgress() -- Check progress (and potential pause) during descent
  end --while
  print("DEBUG: After initial descent loop. Current Y: "..tostring(dig.gety())) -- Debug print kept

    -- After descent, move to the starting corner (0, -skip, 0) and face North (0)
    dig.gotoy(-skip) -- Ensure at the correct starting Y after descent
    dig.gotox(0)
    dig.gotoz(0)
    dig.gotor(0) -- Face North (+Z) to start the first row traversal
    local zdir = 1 -- First row will traverse in the +Z direction

 end --if/else (reloaded)

-- **CORRECTED: Set initial dig.getymax() to the starting Y level**
-- This is needed for the total_quarry_blocks calculation
if not reloaded then -- Only set initial ymax if not reloading
    dig.setymax(dig.gety()) -- Set the starting Y as the max Y
end


-- **CORRECTED: Calculate total_quarry_blocks based on the full volume from Y=ymax down to ymin**
-- This represents the total number of locations in the quarry.
-- The starting Y is dig.getymax(), going down to ymin.
local total_quarry_depth_layers = dig.getymax() - ymin + 1 -- Corrected to be inclusive of both start and end layers
total_quarry_blocks = xmax * zmax * total_quarry_depth_layers -- Corrected total blocks calculation

-- Ensure total_quarry_blocks is not negative or zero if dimensions are invalid or mining depth is 0 or less
if type(total_quarry_blocks) ~= 'number' or total_quarry_blocks <= 0 then
    flex.send("Error: Calculated total quarry blocks is invalid or <= 0 ("..tostring(total_quarry_blocks).."). Check dimensions and depth.", colors.red)
    shell.run("rm startup.lua")
    return
end

print("DEBUG: Total quarry blocks calculated (full volume from Y="..tostring(dig.getymax()).." to ymin="..tostring(ymin).."): "..tostring(total_quarry_blocks))

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
time_of_last_in_game_check = os.time() or 0 -- Initialize in-game time check for main loop

-- Outer loop: Iterate through layers (from current Y down to ymin)
while dig.gety() >= ymin and not done and not dig.isStuck() do

    -- Middle loop: Iterate through rows (xmax times per layer)
    for row_step = 1, xmax do

        -- Determine direction along Z for this row based on xdir and row_step (snake pattern)
        local current_zdir
        if xdir == 1 then -- Moving +X, rows alternate +Z and -Z starting with +Z
            current_zdir = (row_step % 2 == 1) and 1 or -1 -- 1st row +Z, 2nd -Z, etc.
        elseif xdir == -1 then -- Moving -X, rows alternate +Z and -Z starting with -Z
             current_zdir = (row_step % 2 == 1) and -1 or 1 -- 1st row -Z, 2nd +Z, etc.
        end

        -- Ensure turtle is oriented correctly at the start of the row traversal
        if current_zdir == 1 then dig.gotor(0) -- Face North (+Z)
        elseif current_zdir == -1 then dig.gotor(180) -- Face South (-Z)
        end


        -- Inner loop: Traverse the row (zmax times)
        for z_step = 1, zmax do
            checkAll(0) -- Perform checks/status updates (includes checkFuel, checkInv, checkHalt, checkProgress)

            -- Move forward one step (digging/moving)
            dig.fwd()

            if dig.isStuck() then done = true; break end -- Exit inner loop if stuck
        end -- for z_step

        if done then break end -- Exit middle loop if stuck

        -- After traversing a row, move one step along X (unless it's the last row)
        if row_step < xmax then
            checkAll(0) -- Checks before moving along X (includes checkFuel, checkInv, checkHalt, checkProgress)
            -- Determine rotation to move along X based on xdir
            if xdir == 1 then dig.gotor(90) -- Face East (+X)
            elseif xdir == -1 then dig.gotor(270) -- Face West (-X)
            end
            dig.fwd() -- Move one step along X
             if dig.isStuck() then done = true; break end -- Exit middle loop if stuck
        end

    end -- for row_step

    if done then break end -- Exit outer loop if stuck

    -- After completing all rows in a layer, move down to the next layer
    xdir = -xdir -- Reverse X direction for the next layer's stepping pattern
    if dig.gety() > ymin then -- Only move down if not at the minimum Y
         checkAll(0) -- Checks before moving down (includes checkFuel, checkInv, checkHalt, checkProgress)
         dig.down()
          if dig.isStuck() then done = true; break end -- Exit outer loop if stuck
         flex.printColors("Starting new layer at Y="..tostring(dig.gety()), colors.purple)
         -- Reset speed learning timer and counter at the start of a new layer
         blocks_since_last_speed_check = 0
         time_of_last_speed_check = os.epoch("local") or 0
         time_of_last_in_game_check = os.time() or 0 -- Initialize in-game time check for new layer
    end

end -- while layer


if dig.isStuck() then
    flex.send("Quarry stopped due to being stuck.", colors.red)
else
    flex.send("Digging completed, returning to surface", colors.yellow)
end

sendStatus() -- Send final status update

-- Return to base after completing quarry or getting stuck
gotoBase()

-- Operations at base after going there
turtle.select(dig.getBlockSlot() or 2) -- Select block slot (default to 2 if not set)
if turtle.getItemCount(turtle.getSelectedSlot()) > 0 and dig.isBuildingBlock(turtle.getSelectedSlot()) then
    -- We are at (0,0,0) facing South (180) after gotoBase
    -- No need to move again, just place down if at Y=0
    if dig.gety() == 0 then
         dig.placeDown() -- Place block at origin
         flex.send("Placed origin marker at 0,0,0", colors.lightGray)
    end
end
turtle.select(1) -- Select fuel slot


if dodumps then
 dig.gotor(0) -- Face North at base (0,0,0) for dumping area
 dig.doDump() -- Dump forward (North)
 -- No need to turn 180 back if the base is handled correctly by gotoBase/returnFromBase
 -- dig.gotor(180)
end
dig.dropNotFuel() -- Drop other items into chest at base (should be North)
dig.gotor(180) -- Face South again at base


dig.clearSave()
flex.modemOff() -- Keep this to close the modem even if not used for remote control
os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")