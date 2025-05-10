-- Digs a staircase around a quarry
-- Run "stairs help"
-- Or dig a staircase to bedrock
-- Run "stairs"

-----------------------------------
--  /¯\  || ||  /\  |¯\ |¯\ \\// --
-- | O | ||_|| |  | | / | /  \/  --
--  \_\\  \__| |||| | \ | \  ||  --
-----------------------------------
-- /¯¯\ [¯¯]  /\  [¯¯] |¯\ /¯¯\  --
-- \_¯\  ||  |  |  ][  | / \_¯\  --
-- \__/  ||  |||| [__] | \ \__/  --
-----------------------------------

-- Load APIs
local log_file = "log.txt" -- Added log_file variable
local options_file = "flex_options.cfg" -- Added options_file variable
os.loadAPI("flex.lua")
os.loadAPI("dig.lua")
dig.setFuelSlot(1)
dig.setBlockSlot(2)
dig.setBlockStacks(4)

local modem_channel = 6464 -- Default modem channel

-- Get modem channel from options file if it exists
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


-- Modem initialization (needed for sending)
local modem
local hasModem = false
local p = flex.getPeripheral("modem")
if #p > 0 then
    hasModem = true
    modem = peripheral.wrap(p[1])
    modem.open(modem_channel) -- Open the modem on the configured channel
end


-- **ADDED: Log history for status updates**
local log_history = {}
local max_log_history = 15 -- Keep the last 15 log messages


-- Names of tools
local name_torch = {
   "torch", "lantern", "lamp", "light" }
-- Removed crafting table peripheral name: local name_bench = { "minecraft:crafting_table", "forge:workbench" }
local name_chest = { "chest" }
local name_box = {
   "shulker_box", "travelersbackpack" }


-- Stair blocks
local name_cobble = {
  "minecraft:cobblestone",
  "forge:cobblestone" }
-- Added explicit name for stairs block
local name_stairs = {"minecraft:cobblestone_stairs"}


-- Removed crafting materials as crafting is removed
-- local name_wood_log = { ... }
-- local name_planks = { ... }
local name_coal = { "minecraft:coal", "forge:coal" }
local name_stick = { "minecraft:stick", "forge:sticks" }


-- Side that swaps with crafting bench
local tool_side = "none"
-- Removed crafting bench peripheral logic: if not peripheral.find("workbench") then ... end


-- **MODIFIED: Home Base Location and Navigation Logic**
local home_base_coords = { x = 0, y = 0, z = 0, r = 180 } -- At origin, facing South
local home_chest_side = "back" -- The side the chest is on relative to the turtle's position
local saved_location -- Variable to store the location before going to base

-- **ADDED: Crafting helper functions**
local function clearCraftingGrid()
    -- Clear slots 1-9 (3x3 crafting grid)
    for slot = 1, 9 do
        if turtle.getItemCount(slot) > 0 then
            -- Try to move items to inventory slots 10-16
            local moved = false
            for target = 10, 16 do
                if turtle.getItemCount(target) == 0 then
                    turtle.select(slot)
                    moved = turtle.transferTo(target)
                    if moved then break
                    end
                end
            end
            -- If couldn't move, try to merge with similar items
            if not moved then
                turtle.select(slot)
                for target = 10, 16 do
                    local details = turtle.getItemDetail(target)
                    if details and turtle.getItemDetail(slot).name == details.name then
                        turtle.transferTo(target)
                        break
                    end
                end
            end
        end
    end
    turtle.select(1) -- Return to first slot
end

local function setupCraftingGrid(pattern, count)
    clearCraftingGrid() -- Ensure crafting grid is clear
    -- Pattern should be a table of 9 entries describing the 3x3 grid
    -- Each entry should be an item name or nil
    for i = 1, 9 do
        if pattern[i] then
            -- Find the item in inventory slots 10-16
            for slot = 10, 16 do
                local details = turtle.getItemDetail(slot)
                if details and details.name == pattern[i] then
                    local needed = count or 1
                    turtle.select(slot)
                    turtle.transferTo(i, needed)
                    break
                end
            end
        end
    end
    turtle.select(1) -- Return to first slot
end

local function craftStairs(count)
    count = count or 1
    -- Cobblestone stairs pattern (6 cobblestone in L shape)
    local pattern = {
        "minecraft:cobblestone", "nil",                "nil",
        "minecraft:cobblestone", "minecraft:cobblestone", "nil",
        "minecraft:cobblestone", "minecraft:cobblestone", "minecraft:cobblestone"
    }
    
    setupCraftingGrid(pattern, 1)
    if turtle.craft(count) then
        send_log_message("Crafted "..tostring(count).." stairs", colors.lightBlue)
        return true
    else
        send_log_message("Failed to craft stairs", colors.red)
        return false
    end
end

-- **MODIFIED: gotoBase with better coordinate handling**
local function gotoBase()
    -- Save current location before moving
    saved_location = dig.location()
    if not saved_location then
        send_log_message("Failed to save current location", colors.red)
        return nil
    end
    
    send_log_message("Returning to home base...", colors.yellow)
    
    -- First try to get to the right Y level (surface)
    if dig.gety() < home_base_coords.y then
        while dig.gety() < home_base_coords.y and not dig.isStuck() do
            if not dig.up() then break end
        end
    elseif dig.gety() > home_base_coords.y then
        while dig.gety() > home_base_coords.y and not dig.isStuck() do
            if not dig.down() then break end
        end
    end
    
    -- Then move to X,Z coordinates
    if not dig.gotox(home_base_coords.x) then
        send_log_message("Failed to reach home base X coordinate", colors.red)
        return nil
    end
    if not dig.gotoz(home_base_coords.z) then
        send_log_message("Failed to reach home base Z coordinate", colors.red)
        return nil
    end
    
    -- Finally, face the right direction
    if not dig.gotor(home_base_coords.r) then
        send_log_message("Failed to reach home base rotation", colors.red)
        return nil
    end

    -- Verify position
    if dig.getx() == home_base_coords.x and
       dig.gety() == home_base_coords.y and
       dig.getz() == home_base_coords.z and
       dig.getr() % 360 == home_base_coords.r then
        send_log_message("Successfully reached home base", colors.lightBlue)
        return saved_location
    else
        send_log_message("Failed to reach exact home base coordinates", colors.red)
        return nil
    end
end

-- Variables for status sending interval
local last_status_sent_time = os.epoch("local") or 0 -- Initialize defensively with epoch time in milliseconds
local status_send_interval = 4 * 1000 -- Send status every 4 seconds (in milliseconds)

-- **ADDED: sendStatus function (Defined before send_log_message)**
local function sendStatus()
    -- Gather status data
    local current_y = dig.gety()
    local estimated_remaining_levels = math.max(0, current_y - dig.getymin()) -- Simplified estimate
    -- Need dig.getymin() to be set correctly for this to be meaningful

    local estimated_time_display = "Calculating..."
    -- Rough time estimate based on remaining levels and average time per step (assuming 30 seconds/level)
    local avg_time_per_level = 30
    local estimated_time_seconds = estimated_remaining_levels * avg_time_per_level

    if estimated_remaining_levels > 0 and estimated_time_seconds > 0 then
        local hours = math.floor(estimated_time_seconds / 3600)
        local minutes = math.floor((estimated_time_seconds % 3600) / 60)
        local seconds = math.floor(estimated_time_seconds % 60)
        estimated_time_display = string.format("%02d:%02d:%02d", hours, minutes, seconds)
    elseif estimated_remaining_levels <= 0 and current_y <= dig.getymin() then
         estimated_time_display = "Completed" -- Indicate if digging is theoretically done
    end


    -- Get inventory summary (basic example)
    local inventory_summary = {}
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            table.insert(inventory_summary, { name = item.name, count = item.count })
        end
    end

    -- Determine mining status (simplified for stairs)
    local is_mining_status = true -- Assume mining is true while in the main digging/ascending loops
    -- We might need a way to track if the main loops are finished to set this to false


    local status_message = {
        type = "status_update", -- Indicate this is a status update
        script = "stairs", -- **ADDED: Script identifier**
        id = os.getComputerID(), -- Include turtle ID
        label = os.getComputerLabel(), -- Include turtle label
        fuel = turtle.getFuelLevel(),
        position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
        is_mining = is_mining_status, -- Reflect actual mining state
        estimated_time_remaining = estimated_time_display, -- Use the calculated ETA
        log_history = log_history, -- **ADDED: Include log history**
        -- Stairs doesn't track total/processed blocks like quarry, so omit those
        -- dug_blocks = dig.getdug() or 0, -- dugtotal in dig.lua might be relevant
        inventory_summary = inventory_summary -- Include basic inventory summary
    }

    -- Send the status message on the flex modem channel
    if modem then -- Check if modem peripheral is available
        modem.transmit(modem_channel, modem_channel, status_message)
    end
end


-- **ADDED: Wrapper function for flex.send to capture messages (Defined after sendStatus)**
local function send_log_message(message, color)
    -- Add message to history
    table.insert(log_history, message)
    -- Trim history if too long
    while #log_history > max_log_history do
        table.remove(log_history, 1)
    end
    -- Call original flex.send
    flex.send(message, color)
    -- We also need to send a status update whenever a log message is sent
    -- This ensures receive.lua gets the latest log quickly
    sendStatus()
end
-- Helper function to check and send status periodically
local function checkAndSendStatus()
     local current_epoch_time_ms = os.epoch("local") or 0
     -- **FIXED: Ensure last_status_sent_time is a number before calculation**
     local time_difference_ms = 0
     if type(last_status_sent_time) == 'number' then
         time_difference_ms = current_epoch_time_ms - last_status_sent_time
     else
         -- Initialize last_status_sent_time if it's not a number
         last_status_sent_time = current_epoch_time_ms
     end


     if type(current_epoch_time_ms) == 'number' and time_difference_ms >= status_send_interval then
         sendStatus()
         last_status_sent_time = current_epoch_time_ms -- Update last sent time
     end
end

-- **MODIFIED: Functions to go to and return from Home Base (with workaround for dig.goto at origin)**
local function gotoHomeBase()
    -- Save the current location *before* moving
    saved_location = dig.location()
    send_log_message("Returning to home base...", colors.yellow)

    -- Attempt to move to home base coordinates (0, 0, 0) and face South (180)
    local success = dig.goto(home_base_coords.x, home_base_coords.y, home_base_coords.z, home_base_coords.r)
    checkAndSendStatus() -- Send status after attempting to arrive at base

    -- **WORKAROUND:** Check if the turtle is actually AT the home base coords/rotation
    -- If it is, consider the goto successful even if dig.goto returned false.
    if dig.getx() == home_base_coords.x and
       dig.gety() == home_base_coords.y and
       dig.getz() == home_base_coords.z and
       dig.getr() % 360 == home_base_coords.r then -- Use modulo for rotation comparison
       send_log_message("Confirmed arrival at home base.", colors.lightBlue)
       return saved_location -- Return the saved location (indicating success)
    end

    -- If dig.goto failed AND the turtle is not at the home base coords, then report failure
    if not success then
        send_log_message("Failed to reach home base.", colors.red)
        -- Consider a fallback or just stop if cannot reach base
        return nil -- Indicate failure
    end

    -- If dig.goto succeeded but the turtle is somehow not at the exact coords (unlikely, but as a failsafe)
    -- This case should ideally not happen if dig.goto is working correctly.
    send_log_message("Reached near home base, but coordinates not exact.", colors.orange)
    return saved_location -- Return the saved location (treating as success for now)
end

local function returnFromHomeBase(loc)
    local loc = loc or saved_location -- Use the saved_location if loc is nil

    if type(loc) ~= "table" or #loc < 4 then
        send_log_message("Error: Invalid saved location data to return from home base.", colors.red)
        return false -- Indicate failure to return
    end

    send_log_message("Returning to mining location...", colors.yellow)

    -- Return to the saved coordinates and rotation
    -- dig.goto handles movement in the correct order
    local success = dig.goto(loc[1], loc[2], loc[3], loc[4])

    -- After returning, perform checks
    checkAndSendStatus() -- Send status after returning
    -- checkFuel() -- Check fuel after moving back (already handled in manageSupplies)
    -- manageTorchesAtBase() -- Check torches after moving back (already handled in manageSupplies)
    -- checkInv() -- Check inventory after moving back (already handled in manageSupplies)
    dig.checkBlocks() -- Check building blocks

    if not success then
         send_log_message("Failed to return to mining location.", colors.red)
    end
    return success -- Indicate successful return
end
-- Helper function to interact with home chest
local function interactWithHomeChest(callback)
    -- Save current rotation
    local current_r = dig.getr()
    -- Turn around to face chest (180 degrees from North)
    dig.gotor(180)
    -- Do the chest interaction
    local result = callback()
    -- Return to original rotation only if we haven't found what we needed
    if not result then
        dig.gotor(current_r)
    end
    return result
end

-- **ADDED: Pause function to wait for items in chest/inventory**
local function pauseUntilItemAvailable(item_names, chest_side, min_count)
    if not item_names then
        send_log_message("Error: No item names provided to wait for", colors.red)
        return false
    end
    
    local min_count = min_count or 1
    local item_found_in_inventory_or_chest = false
    local chest = chest_side and peripheral.wrap(chest_side)
    
    -- Convert single string to table for consistent handling
    local items_to_check = type(item_names) == 'string' and {item_names} or item_names
    
    -- Create readable item list for message
    local item_list = table.concat(items_to_check, " or ")
    send_log_message("Waiting for " .. item_list .. " in inventory or chest...", colors.orange)
    checkAndSendStatus()

    -- First check inventory before any chest interaction
    for slot = 1, 16 do
        if flex.isItem(items_to_check, slot) and turtle.getItemCount(slot) >= min_count then
            item_found_in_inventory_or_chest = true
            return true
        end
    end

    -- Only interact with chest if we need to
    if not item_found_in_inventory_or_chest and chest then
        return interactWithHomeChest(function()
            local attempts = 0
            while not item_found_in_inventory_or_chest and attempts < 3 do
                local chest_items = chest.list()
                if chest_items then
                    for chest_slot, item_detail in pairs(chest_items) do
                        for _, name in ipairs(items_to_check) do
                            if item_detail.name == name and item_detail.count >= min_count then
                                -- Found matching item, try to pull it
                                local target_slot = -1
                                for try_slot = 10, 16 do
                                    if turtle.getItemCount(try_slot) == 0 then
                                        target_slot = try_slot
                                        break
                                    end
                                end
                                
                                if target_slot ~= -1 then
                                    local original_slot = turtle.getSelectedSlot()
                                    turtle.select(target_slot)
                                    local pulled_count = chest.pullItems(chest_side, chest_slot, min_count, target_slot)
                                    if pulled_count > 0 then
                                        item_found_in_inventory_or_chest = true
                                        send_log_message("Retrieved " .. pulled_count .. " " .. item_detail.name .. " from chest", colors.lightBlue)
                                        turtle.select(original_slot)
                                        return true
                                    end
                                    turtle.select(original_slot)
                                end
                            end
                        end
                    end
                end
                attempts = attempts + 1
                if not item_found_in_inventory_or_chest then
                    sleep(2) -- Wait before checking chest again
                    checkAndSendStatus()
                end
            end
            return false
        end)
    end

    if not item_found_in_inventory_or_chest then
        sleep(2)
        checkAndSendStatus()
    end

    return item_found_in_inventory_or_chest
end


-- **MODIFIED: dump function - Use home base for dumping (removed coal crafting)**
function dump()
 local slot = turtle.getSelectedSlot()
 -- Define items that should NOT be dumped
 -- Fuel (slot 1), Blocks (slot 2), Torches (slot 3), Backpack/Shulker Box, and the chest itself if in inventory
 local non_dump_slots = {1, 2, 3} -- Fuel, Blocks, Torches (these are essential for the task itself)
 local keepers = {name_box, name_chest} -- Items that should be kept if in other slots

 local items_to_dump = {}
 -- Identify items to dump (not in non_dump_slots and not in keepers list)
 for x=1,16 do
    local item_detail = turtle.getItemDetail(x)
    if item_detail and not flex.isItem(keepers, x) then -- Check if item is not a keeper type
        local is_nondump_slot = false
        for _, non_dump_slot in ipairs(non_dump_slots) do
            if x == non_dump_slot then
                is_nondump_slot = true
                break
            end
        end
        if not is_nondump_slot then
             table.insert(items_to_dump, { slot = x, name = item_detail.name, count = turtle.getItemCount(x) })
        end
    end
 end

 if #items_to_dump > 0 then
     local loc = gotoHomeBase() -- Go to home base
     if not loc then return false end -- Stop if cannot reach home base

     -- Interact with the home chest to dump items
     local success = interactWithHomeChest(function()
         local chest = peripheral.wrap(home_chest_side)
         if chest and chest.pushItems then -- Check if it's a valid inventory peripheral
             send_log_message("Dumping items into chest...", colors.yellow)
             for _, item in ipairs(items_to_dump) do
                 turtle.select(item.slot)
                 local success, dumped_count = chest.pushItems(home_chest_side, item.slot, item.count) -- Dump item into chest
                 if success then
                      send_log_message("Dumped "..tostring(dumped_count).." "..item.name, colors.lightBlue)
                 else
                      send_log_message("Failed to dump "..item.name, colors.orange)
                 end
                 checkAndSendStatus() -- Send status after each dump attempt
             end
             send_log_message("Dumping complete.", colors.lightBlue)
             return true
         else
             return false
         end
     end)

     if not success then
         send_log_message("No chest found on side '"..home_chest_side.."' at home base. Cannot dump items.", colors.red)
         -- Fallback: just drop items if chest is not found
         send_log_message("Dropping items instead.", colors.orange)
         turtle.select(slot) -- Restore selected slot temporarily
         for _, item in ipairs(items_to_dump) do
             turtle.select(item.slot)
             turtle.drop() -- Drop the item
              send_log_message("Dropped "..tostring(item.count).." "..item.name, colors.lightBlue)
              checkAndSendStatus() -- Send status after each drop
         end
     end

     turtle.select(slot) -- Restore original selected slot
     dig.checkBlocks() -- Ensure building blocks are in selected slot
     flex.condense() -- Condense inventory
     returnFromHomeBase(loc) -- Return from home base
 end

 -- Removed coal block crafting logic from here
 return true -- Indicate dump process attempted
end --function


-- Program parameter(s)
local args={...}

-- Tutorial, kind of
if #args > 0 and args[1] == "help" then
 send_log_message("Place just to the ".. -- Use wrapper
   "left of a turtle quarrying the same "..
   "dimensions.",colors.lightBlue)
 send_log_message("Include a chest at the origin (0,0,0) BEHIND the turtle\n".. -- Mention home chest is behind
   "to auto-dump items and get Fuel, Stair Blocks, and Torches.", colors.yellow) -- Updated message
 -- Removed crafting materials as crafting is removed
 -- send_log_message("Provide Wood Logs, Coal, and Sticks in the chest to craft torches.", colors.yellow)
 send_log_message("Usage: stairs ".. -- Use wrapper
   "[length] [width] [depth]",colors.pink)
 return
end --if


-- What Goes Where
send_log_message("Slot 1: Fuel\n".. -- Use wrapper
  "Slot 2: Blocks\nSlot 3: Torches\n"..
  "Home Chest (at 0,0,0 BEHIND the turtle): Dumping, Fuel, Stair Blocks, Torches", -- Updated message
  colors.lightBlue)
flex.printColors("Press Enter", -- Keep this as flex.printColors for local display only
  colors.pink)

-- **MODIFIED: Removed the while flex.getKey() loop that was listening for modem messages**
-- Now just wait for the user to press Enter without listening for remote commands.
while flex.getKey() ~= keys.enter do
    -- Periodically send status while waiting for user input
    sendStatus()
    sleep(0.5) -- Add a short sleep to prevent tight loop and allow status sending
end


-- Convert Inputs
local dx,dy,dz,n,x,y,z
local height = 5
dz = tonumber(args[1]) or 256
dx = tonumber(args[2]) or dz
dy = tonumber(args[3]) or 256
-- -1 to match Quarry depth




-- **MODIFIED: checkFuel function - Get fuel from chest and pause if needed**
local function checkFuel()
    local current_fuel = turtle.getFuelLevel()
    local estimated_fuel_needed = 500 -- Simple estimate: always try to keep at least 500 fuel

    -- First check if we already have usable fuel in slot 1
    local current_slot = turtle.getSelectedSlot()
    turtle.select(1)
    if turtle.getItemCount(1) > 0 and turtle.refuel(0) then
        -- We have fuel in slot 1, try to use it
        local success = turtle.refuel(64) -- Try to use up to 64 items
        if success and turtle.getFuelLevel() >= estimated_fuel_needed then
            turtle.select(current_slot)
            return false -- We got enough fuel, no need to go to base
        end
    end
    turtle.select(current_slot)

    if current_fuel < estimated_fuel_needed then
        send_log_message("Fuel low, returning to home base for fuel...", colors.yellow)
        local loc = gotoHomeBase() -- Go to home base
        if not loc then return false end -- Stop if cannot reach home base

        -- Interact with the home chest to get fuel
        local chest = peripheral.wrap(home_chest_side)
        if chest and chest.pullItems then -- Check if it's a valid inventory peripheral
            send_log_message("Attempting to get fuel from chest...", colors.yellow)
            local fuel_pulled_count = 0
            -- Try to pull fuel items (coal, coal blocks, lava buckets) from the chest
            local fuel_item_names = { "minecraft:coal", "minecraft:coal_block", "minecraft:lava_bucket", "forge:coal", "forge:coal_blocks" }
            local original_slot = turtle.getSelectedSlot()
            turtle.select(1) -- Select fuel slot

            -- First check what's in the chest
            local chest_items = chest.list()
            if chest_items then
                for slot, item in pairs(chest_items) do
                    for _, fuel_name in ipairs(fuel_item_names) do
                        if item.name == fuel_name then
                            -- Found fuel, try to pull it
                            local pulled = chest.pullItems(home_chest_side, slot, 64, 1) -- Pull to slot 1
                            if pulled > 0 and turtle.refuel(0) then -- Check if item is valid fuel
                                turtle.refuel(pulled) -- Use the fuel
                                fuel_pulled_count = fuel_pulled_count + pulled
                                send_log_message("Pulled and used "..tostring(pulled).." "..item.name.." for fuel.", colors.lightBlue)
                                checkAndSendStatus()
                                if turtle.getFuelLevel() >= estimated_fuel_needed then
                                    turtle.select(original_slot)
                                    send_log_message("Refueling complete.", colors.lightBlue)
                                    returnFromHomeBase(loc)
                                    return true
                                end
                            end
                        end
                    end
                end
            end

            -- If we got here, we didn't find enough fuel
            turtle.select(original_slot)
            send_log_message("Could not acquire enough fuel from chest.", colors.orange)
            if turtle.getFuelLevel() < 200 then -- Critical fuel level
                send_log_message("Critical fuel level! Cannot continue.", colors.red)
                return false
            end
        else
            send_log_message("No chest found on side '"..home_chest_side.."' at home base. Cannot get fuel.", colors.red)
        end

        returnFromHomeBase(loc) -- Return from home base
        return true -- Indicate fuel check was handled
    end
    return false -- Indicate fuel is sufficient
end

-- Removed crafting helper functions as crafting is removed
-- local function findCraftingMaterial(item_names, exclude_slots) ... end
-- local function moveItemToCraftingSlot(from_slot, to_crafting_slot, amount) ... end
-- local function clearCraftingSlot(crafting_slot) ... end


-- **MODIFIED: manageTorchesAtBase function - Check inventory first**
local function manageTorchesAtBase()
    local current_torches = turtle.getItemCount(3) -- Check torch slot (slot 3)
    local min_torches = 1 -- Keep at least 1 torch
    local needed_torches = min_torches - current_torches

    -- First check if we already have enough torches before doing anything
    if current_torches >= min_torches then
        return true -- We have enough torches, no need to go to base
    end

    if needed_torches > 0 then
        send_log_message("Torch count low ("..tostring(current_torches).."), managing torches at base...", colors.yellow)
        local loc = gotoHomeBase() -- Go to home base
        if not loc then return false end -- Stop if cannot reach home base

        local chest = peripheral.wrap(home_chest_side)
        if chest and chest.pullItems and chest.pushItems and chest.list then -- Check if it's a valid inventory peripheral with required methods
            send_log_message("Attempting to get torches from chest...", colors.yellow)

            -- Pause and wait if no torches are found in inventory or chest
             pauseUntilItemAvailable(name_torch, home_chest_side, needed_torches)

            local original_selected_slot = turtle.getSelectedSlot()
            turtle.select(3) -- Select torch slot

             -- Now that item is available (either was there or pulled), try to pull again if needed
            local current_torches_after_wait = turtle.getItemCount(3)
             if current_torches_after_wait < min_torches then
                local success, pulled = chest.pullItems(home_chest_side, -1, min_torches - current_torches_after_wait, name_torch) -- Pull needed torches from any slot (-1)
                if success and pulled > 0 then
                    send_log_message("Pulled "..tostring(pulled).." torches from chest.", colors.lightBlue)
                    checkAndSendStatus()
                else
                     send_log_message("Could not acquire enough torches from chest after waiting.", colors.orange)
                end
             end


            turtle.select(original_selected_slot) -- Restore selected slot

            if turtle.getItemCount(3) >= min_torches then
                send_log_message("Torch management complete. Have "..tostring(turtle.getItemCount(3)).." torches.", colors.lightBlue)
            else
                send_log_message("Could not acquire enough torches. Have "..tostring(turtle.getItemCount(3)).." torches.", colors.orange)
                 -- Still pause if torch management failed even after initial wait
                 -- pauseUntilItemAvailable(name_torch, home_chest_side, needed_torches)
            end

        else
            send_log_message("No chest found on side '"..home_chest_side.."' at home base or missing required peripheral methods. Cannot get torches.", colors.red)
             -- Pause if no chest is found
             pauseUntilItemAvailable(name_torch, nil, needed_torches) -- Pass nil for chest_side to only check inventory
        end

        returnFromHomeBase(loc) -- Return from home base
        return true -- Indicate torch management was handled
    end
    return false -- Indicate enough torches are available
end

-- **MODIFIED: Fix block pulling in manageSupplies**
local function manageSupplies()
    -- Check inventory first (dumps), then fuel, then torches.
    -- Dumping might free up space for fuel/torches/blocks.
    local inventory_handled = dump() -- dump now handles going to base, dumping, and returning
    if not inventory_handled then return false end -- Stop if dump failed

    local fuel_handled = checkFuel() -- checkFuel now handles going to base, refueling, and returning
    if not fuel_handled then return false end -- Stop if fuel check/get failed

    local torches_handled = manageTorchesAtBase() -- manageTorchesAtBase handles going to base, getting torches, and returning
    if not torches_handled then return false end -- Stop if torch check/get failed

    -- Now check and get blocks (stairs)
    local blocks_needed = dig.getBlockStacks() * 64 - turtle.getItemCount(2) -- Need a full stack in block slot (slot 2)
    local min_blocks = 64 -- At least one stack

    if turtle.getItemCount(2) < min_blocks then
        send_log_message("Building block count low ("..tostring(turtle.getItemCount(2)).."), managing blocks at base...", colors.yellow)
        local loc = gotoHomeBase() -- Go to home base
         if not loc then return false end -- Stop if cannot reach home base

        local chest = peripheral.wrap(home_chest_side)
        if chest and chest.pullItems and chest.pushItems and chest.list then
             send_log_message("Attempting to get building blocks from chest...", colors.yellow)

             -- Pause and wait if no blocks are found in inventory or chest
             pauseUntilItemAvailable({name_cobble, name_stairs}, home_chest_side, min_blocks)

             local original_selected_slot = turtle.getSelectedSlot()
             turtle.select(2) -- Select block slot

              -- Now that item is available (either was there or pulled), try to pull again if needed
             local current_blocks_after_wait = turtle.getItemCount(2)
             if current_blocks_after_wait < min_blocks then
                 local pulled_count = 0
                 local chest_items = chest.list()
                 if chest_items then
                     -- Try cobblestone first
                     for slot, item in pairs(chest_items) do
                         if item.name == "minecraft:cobblestone" then
                             local pull_count = math.min(64, min_blocks - current_blocks_after_wait)
                             local pulled = chest.pullItems(home_chest_side, slot, pull_count)
                             if pulled > 0 then
                                 pulled_count = pulled_count + pulled
                                 send_log_message("Pulled "..tostring(pulled).." cobblestone.", colors.lightBlue)
                                 checkAndSendStatus()
                             end
                             if pulled_count >= min_blocks then break end
                         end
                     end

                     -- If still need more, try stairs
                     if pulled_count < min_blocks then
                         for slot, item in pairs(chest_items) do
                             if item.name == "minecraft:cobblestone_stairs" then
                                 local pull_count = math.min(64, min_blocks - pulled_count)
                                 local pulled = chest.pullItems(home_chest_side, slot, pull_count)
                                 if pulled > 0 then
                                     pulled_count = pulled_count + pulled
                                     send_log_message("Pulled "..tostring(pulled).." stairs.", colors.lightBlue)
                                     checkAndSendStatus()
                                 end
                                 if pulled_count >= min_blocks then break end
                             end
                         end
                     end

                     if pulled_count > 0 then
                         send_log_message("Building block management complete. Have "..tostring(turtle.getItemCount(2)).." blocks.", colors.lightBlue)
                     else
                         send_log_message("Could not acquire enough building blocks from chest after waiting.", colors.orange)
                     end
                 end
             end
            turtle.select(original_selected_slot) -- Restore selected slot
             dig.checkBlocks() -- Ensure block slot is correct after pulling
        else
             send_log_message("No chest found on side '"..home_chest_side.."' at home base or missing required peripheral methods. Cannot get building blocks.", colors.red)
              -- Pause if no chest is found
             pauseUntilItemAvailable({name_cobble, name_stairs}, nil, min_blocks) -- Pass nil for chest_side to only check inventory
        end

        returnFromHomeBase(loc) -- Return from home base
        return true -- Indicate block management was handled
    end

    return true -- Indicate supplies are sufficient or handled
end


--------------------------------------
-- |¯\ [¯¯] /¯¯] /¯¯][¯¯]|\ || /¯¯] --
-- |  |  ][ | [¯|| [¯|  ][ | \ || [¯| --
-- |_/ [__] \__| \__|[__]|| \| \__| --
--------------------------------------

send_log_message("Digging staircase...", colors.yellow) -- Use wrapper
sendStatus() -- Send status after logging start

-- Staircase Digging Functions

local torchNum = 9

function placeTorch()
 checkAndSendStatus() -- Check and send status periodically
 turtle.select(3)
 if flex.isItem(name_torch) and turtle.getItemCount(3) > 0 then

  if not turtle.place() then
   if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
   turtle.select(2)
   dig.place()
   if not dig.back() then checkAndSendStatus(); return false end -- Added status check

   turtle.select(3)
   if not turtle.place() then
    if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
    turtle.select(2)
    dig.placeUp()
    if not dig.back() then checkAndSendStatus(); return false end -- Added status check
    turtle.select(3)
    if not turtle.place() then checkAndSendStatus(); return false end -- Added status check
   end --if/else
  end --if
 else
     -- Torches are low or missing, manage supplies (which will handle getting them and pause if needed)
     send_log_message("Torch count low or missing for placement, managing supplies...", colors.yellow)
     if not manageSupplies() then return false end -- Manage supplies (includes getting torches)
      -- After managing supplies, re-check torch count and attempt to select/place
     if flex.isItem(name_torch, 3) and turtle.getItemCount(3) > 0 then -- Check slot 3 specifically
         turtle.select(3)
          if not turtle.place() then
              -- Attempted to place after getting torches, still failed
              send_log_message("Failed to place torch even after managing supplies.", colors.orange)
              return false -- Indicate failure
          end
     else
         send_log_message("Could not obtain torches to place after managing supplies.", colors.red)
         return false -- Indicate failure
     end
 end --if

 turtle.select(2)
 checkAndSendStatus() -- Check and send status periodically
 return true -- Ensure placeTorch returns a boolean
end --function


function stepDown()
 local x

 checkAndSendStatus() -- Check and send status periodically
 if not manageSupplies() then return false end -- Check and manage supplies before a step
 turtle.select(2)
 dig.right()
 for x=1,height-2 do
  dig.blockLava()
  if not dig.up() then checkAndSendStatus(); return false end -- Added status check
  checkAndSendStatus() -- Check and send status periodically during upward movement
 end --for
 dig.blockLava()
 dig.blockLavaUp()

 dig.left()
 dig.blockLava()
 dig.left()
 if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
 dig.blockLavaUp()
 dig.blockLava()
 dig.right()
 dig.blockLava()
 dig.left()

 if torchNum >= 3 then
  if not dig.back() then checkAndSendStatus(); return false end -- Added status check
  if not placeTorch() then checkAndSendStatus(); return false end -- Added status check and return check
  if not dig.down() then checkAndSendStatus(); return false end -- Added status check
  if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
  torchNum = 0
 else
  dig.blockLava()
  if not dig.down() then checkAndSendStatus(); return false end -- Added status check
  torchNum = torchNum + 1
 end --if/else

 for x=1,height-2 do
  dig.blockLava()
  if not dig.down() then checkAndSendStatus(); return false end -- Added status check
  checkAndSendStatus() -- Check and send status periodically during downward movement
 end --for
 dig.blockLava()
 if not dig.placeDown() then checkAndSendStatus(); return false end -- Added status check

 dig.right(2)
 if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
 dig.blockLava()
 if not dig.placeDown() then checkAndSendStatus(); return false end -- Added status check
 dig.left()

 -- Removed dump call here, dump is now part of manageSupplies
 -- if turtle.getItemCount(16) > 0 then
 --  dig.left()
 --  dump() -- Call dump here
 --  dig.right()
 -- end --if/else

 if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check

 checkAndSendStatus() -- Check and send status periodically at the end of a step
 return true
end --function


local function turnRight()
 checkAndSendStatus() -- Check and send status periodically
 if not manageSupplies() then return false end -- Check and manage supplies before a turn
 turtle.select(2)
 dig.right()
 if not dig.up(height-2) then checkAndSendStatus(); return false end -- Added status check
 dig.blockLavaUp()

 dig.left()
 if not dig.down() then checkAndSendStatus(); return false end -- Added status check
 if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
 dig.blockLavaUp()
 for x=1,height-3 do
  dig.blockLava()
  if not dig.down() then checkAndSendStatus(); return false end -- Added status check
  checkAndSendStatus() -- Check and send status periodically
 end --for
 dig.blockLava()
 if not dig.placeDown() then checkAndSendStatus(); return false end -- Added status check

 dig.left()
 if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
 for x=1,height-3 do
  dig.blockLava()
  if not dig.up() then checkAndSendStatus(); return false end -- Added status check
  checkAndSendStatus() -- Check and send status periodically
 end --for
 dig.blockLava()
 dig.blockLavaUp()

 dig.right()
 for x=1,height-3 do
  dig.blockLava()
  if not dig.down() then checkAndSendStatus(); return false end -- Added status check
  checkAndSendStatus() -- Check and send status periodically
 end --for
 dig.blockLava()
 if not dig.placeDown() then checkAndSendStatus(); return false end -- Added status check

 dig.left(2)
 if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
 dig.right()
 if not dig.placeDown() then checkAndSendStatus(); return false end -- Added status check
 for x=1,height-2 do
  dig.blockLava()
  if not dig.up() then checkAndSendStatus(); return false end -- Added status check
  checkAndSendStatus() -- Check and send status periodically
 end --for
 dig.blockLava()
 dig.blockLavaUp()

 dig.right(2)
 if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
 if not dig.down(height-1) then checkAndSendStatus(); return false end -- Added status check
 if not dig.placeDown() then checkAndSendStatus(); return false end -- Added status check
 dig.left()
 if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
 dig.blockLava()
 if not dig.placeDown() then checkAndSendStatus(); return false end -- Added status check
 if not dig.back() then checkAndSendStatus(); return false end -- Added status check
 dig.right()
 if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check

 torchNum = torchNum + 1
 checkAndSendStatus() -- Check and send status periodically at the end of a turn
 return true
end --function


function endcap(h,stop)
 checkAndSendStatus() -- Check and send status periodically
 if not manageSupplies() then return false end -- Check and manage supplies before endcap
 stop = ( stop ~= nil )
 h = h or 0 -- Height to dig layer
 local x

 dig.right()
 if not dig.placeDown() then checkAndSendStatus(); return false end -- Added status check
 dig.checkBlocks()
 for x=1,height-2-h do
  dig.blockLava()
  if not dig.up() then checkAndSendStatus(); return false end -- Added status check
  checkAndSendStatus() -- Check and send status periodically
 end --for
 dig.blockLava()
 dig.blockLavaUp()

 dig.left(2)
 if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
 dig.blockLavaUp()
 for x=1,height-2-h do
  dig.blockLava()
  if not dig.down() then checkAndSendStatus(); return false end -- Added status check
  checkAndSendStatus() -- Check and send status periodically
 end --for
 dig.blockLava()
 if not dig.placeDown() then checkAndSendStatus(); return false end -- Added status check
 dig.checkBlocks()
 if not dig.back() then checkAndSendStatus(); return false end -- Added status check

 dig.right()

 if stop then
  dig.blockLava()
  for x=1,height-2-h do
   if not dig.up() then checkAndSendStatus(); return false end -- Added status check
   dig.blockLava()
   checkAndSendStatus() -- Check and send status periodically
  end --for
  dig.blockLavaUp()
  dig.left()

  if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
  dig.blockLavaUp()
  dig.right()
  dig.blockLava()
  for x=1,height-2-h do
   if not dig.down() then checkAndSendStatus(); return false end -- Added status check
   dig.blockLava()
   checkAndSendStatus() -- Check and send status periodically
  end --for

  dig.left()
  if not dig.back() then checkAndSendStatus(); return false end -- Added status check
  dig.right()

 end --if

 checkAndSendStatus() -- Check and send status periodically at the end of endcap
 return true
end --function



local direction

function avoidBedrock()
 checkAndSendStatus() -- Check and send status periodically
 if not manageSupplies() then return false end -- Check and manage supplies before avoiding bedrock
 if dig.isStuck() then
  -- Hit Bedrock/Void
  if dig.getStuckDir() == "fwd" then
   if not dig.up() then checkAndSendStatus(); return false end
   if not dig.placeDown() then checkAndSendStatus(); return false end
   dig.checkBlocks()
   dig.setymin(dig.gety())
   if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
  elseif dig.getStuckDir() == "down" then
   dig.setymin(dig.gety())
  end --if
 end --if

 -- Get X and Z on the inner stair block
 if dig.getx() >= dx+2 then
  if not dig.gotox(dx+1) then checkAndSendStatus(); return false end

 elseif dig.getx() <= -1 then
   if not dig.gotox(0) then checkAndSendStatus(); return false end

 end --if/else

 if dig.getz() >= dz+1 then
   if not dig.gotoz(dz) then checkAndSendStatus(); return false end

 elseif dig.getz() <= -2 then
   if not dig.gotoz(-1) then checkAndSendStatus(); return false end

 end --if/else

 if not dig.gotor(direction) then checkAndSendStatus(); return false end
 if not dig.gotoy(dig.getymin()) then checkAndSendStatus(); return false end
 checkAndSendStatus() -- Check and send status periodically
 return true
end --function



-- Start Digging

turtle.select(2)

x = 0
direction = dig.getr()

-- **ADDED: Set initial dig.getymin() to the starting Y level**
-- This is needed for the estimated time calculation in sendStatus
dig.setymin(dig.gety())

sendStatus() -- Send initial status before starting

local digging_active = true
while digging_active do
 -- **MODIFIED: Removed modem message event handling loop**
 -- The script will no longer listen for commands here.
 checkAndSendStatus() -- Check and send status periodically
 if not manageSupplies() then digging_active = false; break end -- Check and manage supplies at the start of the main loop iteration

 for n=0,dz-1 do
  if not stepDown() then digging_active = false; break end
  x = x + 1
  if x >= dy then break end
  -- status checks are inside stepDown now
 end
 if not digging_active or dig.isStuck() or x >= dy then break end
 if not turnRight() then digging_active = false; break end -- turnRight includes status checks and manageSupplies
 x = x + 1
 -- status checks are inside turnRight now


 direction = dig.getr()
 for n=0,dx-1 do
  if not stepDown() then digging_active = false; break end
  x = x + 1
  if x >= dy then break end
   -- status checks are inside stepDown now
 end
 if not digging_active or dig.isStuck() or x >= dy then break end
 if not turnRight() then digging_active = false; break end -- turnRight includes status checks and manageSupplies
 x = x + 1
  -- status checks are inside turnRight now

 direction = dig.getr()
end --while

if digging_active then -- Only proceed with endcap if digging was not aborted
 if not avoidBedrock() then digging_active = false end -- includes status checks and manageSupplies
 if digging_active and not dig.fwd() then digging_active = false else if digging_active then avoidBedrock() end end -- dig.fwd includes status checks
 if digging_active and not endcap(1) then digging_active = false else if digging_active then avoidBedrock() end end -- endcap includes status checks and manageSupplies
 if digging_active and not dig.fwd() then digging_active = false else if digging_active then avoidBedrock() end end -- dig.fwd includes status checks
 if digging_active and not endcap(1,true) then digging_active = false else if digging_active then avoidBedrock() end end -- endcap includes status checks and manageSupplies

 if digging_active then
  if not dig.left(2) then digging_active = false end
  while digging_active and not turtle.detect() do
   if not dig.fwd() then digging_active = false; break end -- dig.fwd includes status checks
   checkAndSendStatus() -- Check and send status periodically
  end
  if digging_active and not dig.back() then digging_active = false end -- dig.back includes status checks
 end
end


-- This bit compensates for random Bedrock (mostly)
if digging_active and #dig.getKnownBedrock() > 0 then
 -- Check and manage supplies before compensating for bedrock
 if not manageSupplies() then digging_active = false end
 if digging_active then
  for x=1,4 do
   if not dig.placeDown() then digging_active = false; break end -- Added status check
   if not dig.right() then digging_active = false; break end -- Added status check
   if not dig.fwd() then digging_active = false; break end -- Added status check
   checkAndSendStatus() -- Check and send status periodically
  end --for
 end
end --for



----------------------------------------------
--  /¯] |¯\  /\  |¯¯] [¯¯] [¯¯] |\ ||  /¯¯] --
-- | [  | / |  | |  ]   ||   ][ | \ | | [¯| --
--  \_] | \ |||| ||    ||  [__] || \|  \__| --
----------------------------------------------


local function placeStairs()
 checkAndSendStatus() -- Check and send status periodically
 if not manageSupplies() then return false end -- Check and manage supplies before placing stairs
 local x,y,z,slot
 slot = turtle.getSelectedSlot()
 y = turtle.getItemCount(2) -- Check count in block slot

 if y < 2 or not (flex.isItem(name_cobble, 2) or flex.isItem(name_stairs, 2)) then -- Check block slot (slot 2)
  send_log_message("Low on stairs/blocks ("..tostring(y).."), managing supplies...", colors.yellow)
  -- manageSupplies is already called, which handles getting blocks if needed and pausing
  -- If manageSupplies returned false, the caller should handle it.
  -- Here, just check if we have blocks after manageSupplies
   if turtle.getItemCount(2) < 2 or not (flex.isItem(name_cobble, 2) or flex.isItem(name_stairs, 2)) then
       send_log_message("Could not obtain enough stairs/blocks.", colors.red)
       return false -- Cannot place stairs
   end
 end --if

 -- Ensure block slot (slot 2) is selected before placing
 turtle.select(2)

 if not dig.placeDown() then checkAndSendStatus(); return false end
 if not dig.right() then checkAndSendStatus(); return false end
 if not dig.fwd() then checkAndSendStatus(); return false end
 if not dig.left() then checkAndSendStatus(); return false end
 if not dig.placeDown() then checkAndSendStatus(); return false end
 if not dig.left() then checkAndSendStatus(); return false end
 if not dig.fwd() then checkAndSendStatus(); return false end
 if not dig.right() then checkAndSendStatus(); return false end

 checkAndSendStatus() -- Check and send status periodically after placing stairs
 return true
end --function


send_log_message("Returning to surface",
  colors.yellow)
sendStatus() -- Send status after logging return to surface

local ascending_active = true
function isDone()
 -- Reached Surface
 return dig.gety() >= 0
end

-- Follow the Spiral [and place Stairs]
-- **MODIFIED: Variable to track if ascending is finished**
local ascending_done = false
while not isDone() and not ascending_done and ascending_active do
 -- **MODIFIED: Removed modem message event handling loop**
 checkAndSendStatus() -- Check and send status periodically
 if not manageSupplies() then ascending_active = false; break end -- Check and manage supplies at the start of the ascending loop iteration

 if dig.getr()%360 == 0 then
  while ascending_active and dig.getz() < dig.getzmax()-1 do
   if not dig.fwd() then ascending_active = false; break end -- dig.fwd includes status checks
   if not dig.up() then ascending_active = false; break end -- dig.up includes status checks
   if not placeStairs() then ascending_active = false; break end -- placeStairs includes status checks and manageSupplies
   if isDone() then break end
   checkAndSendStatus() -- Check and send status periodically
  end

 elseif dig.getr()%360 == 90 then
  while ascending_active and dig.getx() < dig.getxmax()-1 do
   if not dig.fwd() then ascending_active = false; break end -- dig.fwd includes status checks
   if not dig.up() then ascending_active = false; break end -- dig.up includes status checks
   if not placeStairs() then ascending_active = false; break end -- placeStairs includes status checks and manageSupplies
   if isDone() then break end
   checkAndSendStatus() -- Check and send status periodically
  end

 elseif dig.getr()%360 == 180 then
  while ascending_active and dig.getz() > dig.getzmin()+1 do
   if not dig.fwd() then ascending_active = false; break end -- dig.fwd includes status checks
   if not dig.up() then ascending_active = false; break end -- dig.up includes status checks
   if not placeStairs() then ascending_active = false; break end -- placeStairs includes status checks and manageSupplies
   if dig.gety() > -4 and dig.getz()
      == dig.getzmin()+1 then
    -- Up at the top
    if not dig.fwd() then ascending_active = false; break end -- dig.fwd includes status checks
    if not dig.up() then ascending_active = false; break end -- dig.up includes status checks
    if not placeStairs() then ascending_active = false; break end -- placeStairs includes status checks and manageSupplies
   end --if
   if isDone() then break end
   checkAndSendStatus() -- Check and send status periodically
  end

 elseif dig.getr()%360 == 270 then
  while ascending_active and dig.getx() > dig.getxmin()+1 do
   if not dig.fwd() then ascending_active = false; break end -- dig.fwd includes status checks
   if not dig.up() then ascending_active = false; break end -- dig.up includes status checks
   if not placeStairs() then ascending_active = false; break end -- placeStairs includes status checks and manageSupplies
   if isDone() then break end
   checkAndSendStatus() -- Check and send status periodically
  end

 end --if/else

 if not isDone() and ascending_active then -- Only attempt to turn if not done or stuck during step
     if not dig.left() then ascending_active = false; end -- dig.left includes status checks
 end

end --while


-- All Done!
-- Determine final status message based on whether digging/ascending completed or got stuck
if not digging_active or not ascending_active then
    send_log_message("Stairway operation stopped due to an issue.", colors.red)
else
    send_log_message("Stairway finished!", colors.lightBlue)
end


sendStatus() -- Send final status update

-- Attempt to go to origin (0,0,0) and face South (180) after finishing/stopping
-- We are already at the presumed home base location (0,0,0 facing South) if the script started there
-- If it couldn't reach there or was already at base, this goto might be redundant but harmless
-- Adding a direct check after the final goto as well, in case the workaround is needed at the very end
local final_goto_success = dig.goto(home_base_coords.x, home_base_coords.y, home_base_coords.z, home_base_coords.r)
if not final_goto_success then
    -- **WORKAROUND CHECK AT END:** Check if the turtle is actually AT the home base coords/rotation
    if dig.getx() == home_base_coords.x and
       dig.gety() == home_base_coords.y and
       dig.getz() == home_base_coords.z and
       dig.getr() % 360 == home_base_coords.r then -- Use modulo for rotation comparison
       send_log_message("Confirmed final position at origin despite goto failure.", colors.lightBlue)
       -- Treat as success and proceed with final dump
       final_goto_success = true
    else
        send_log_message("Could not reach origin ("..tostring(home_base_coords.x)..","..tostring(home_base_coords.y)..","..tostring(home_base_coords.z)..") after completing tasks.", colors.orange)
        -- Attempt to dump remaining inventory at current location if cannot reach base
        send_log_message("Attempting to dump remaining inventory at current location.", colors.yellow)
        dump() -- dump now handles going to home base or dropping (will drop if cannot reach base)
    end
end

if final_goto_success then
    -- Successfully reached origin/home base (or confirmed position), manage any remaining inventory at base
    send_log_message("Managing final inventory at origin.", colors.lightBlue)
    -- We are already at home base (0,0,0, facing South)
    local original_selected_slot = turtle.getSelectedSlot()
    local chest = peripheral.wrap(home_chest_side)
    if chest and chest.pushItems then -- Check if it's a valid inventory peripheral
         send_log_message("Dumping final items into chest...", colors.yellow)
         for slot = 1, 16 do
             if turtle.getItemCount(slot) > 0 then
                turtle.select(slot)
                local success, dumped_count = chest.pushItems(home_chest_side, slot, turtle.getItemCount(slot)) -- Dump item into chest
                if success then
                     local item_detail = turtle.getItemDetail(slot)
                     send_log_message("Dumped "..tostring(dumped_count).." "..(item_detail and item_detail.name or "items"), colors.lightBlue)
                end
                checkAndSendStatus() -- Send status after each dump attempt
             end
         end
         send_log_message("Final dumping complete.", colors.lightBlue)
    else
        send_log_message("No chest found on side '"..home_chest_side.."' at origin to dump final items.", colors.red)
        send_log_message("Dropping final items at origin instead.", colors.orange)
        turtle.select(original_selected_slot) -- Restore selected slot temporarily
        for slot = 1, 16 do
             if turtle.getItemCount(slot) > 0 then
                turtle.select(slot)
                turtle.drop() -- Drop the item
                 local item_detail = turtle.getItemDetail(slot)
                 send_log_message("Dropped "..tostring(turtle.getItemCount(slot)).." "..(item_detail and item_detail.name or "items"), colors.lightBlue)
                 checkAndSendStatus() -- Send status after each drop
             end
        end
    end
    turtle.select(original_selected_slot) -- Restore selected slot
end


flex.modemOff()
os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")