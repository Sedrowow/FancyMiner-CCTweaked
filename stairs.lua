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


-- Stair blocks crafting material
local name_cobble = {
  "minecraft:cobblestone",
  "forge:cobblestone" }

-- Items needed for crafting torches at base
local name_wood_log = {
    "minecraft:oak_log", "minecraft:spruce_log", "minecraft:birch_log",
    "minecraft:jungle_log", "minecraft:acacia_log", "minecraft:dark_oak_log",
    "forge:logs" -- Include forge tag for logs
}
local name_planks = {
    "minecraft:oak_planks", "minecraft:spruce_planks", "minecraft:birch_planks",
    "minecraft:jungle_planks", "minecraft:acacia_planks", "minecraft:dark_oak_planks",
    "forge:planks" -- Include forge tag for planks
}
local name_coal = { "minecraft:coal", "forge:coal" }
local name_stick = { "minecraft:stick", "forge:sticks" }


-- Side that swaps with crafting bench
local tool_side = "none"
-- Removed crafting bench peripheral logic: if not peripheral.find("workbench") then ... end


-- **MODIFIED: Home Base Location - Chest is behind at start**
-- Assuming the home chest is at the turtle's starting position (0,0,0)
-- and the turtle turns 180 degrees to face South to interact with it.
local home_base_coords = { x = 0, y = 0, z = 0, r = 180 } -- At origin, facing South
local home_chest_side = "south" -- The side the chest is on when at home_base_coords (behind the turtle)

local saved_location -- Variable to store the location before going to home base

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


-- **ADDED: Functions to go to and return from Home Base**
local function gotoHomeBase()
    -- Save the current location *before* moving
    saved_location = dig.location()
    send_log_message("Returning to home base...", colors.yellow)

    -- Move to home base coordinates (0, 0, 0) and face South (180)
    -- dig.goto handles movement in the correct order (Y then X then Z)
    dig.goto(home_base_coords.x, home_base_coords.y, home_base_coords.z, home_base_coords.r)
    checkAndSendStatus() -- Send status after arriving at base

    return saved_location -- Return the saved location
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
    dig.goto(loc[1], loc[2], loc[3], loc[4])

    -- After returning, perform checks
    checkAndSendStatus() -- Send status after returning
    -- checkFuel() -- Check fuel after moving back (already handled in manageSupplies)
    -- manageTorchesAtBase() -- Check torches after moving back (already handled in manageSupplies)
    -- checkInv() -- Check inventory after moving back (already handled in manageSupplies)
    dig.checkBlocks() -- Check building blocks

    return true -- Indicate successful return
end


-- **MODIFIED: dump function - Use home base for dumping**
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
     -- Interact with the home chest to dump items
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
     else
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
     -- Removed backpack/shulker box logic from dump, assuming it's handled elsewhere or not used this way with home chest
     dig.checkBlocks() -- Ensure building blocks are in selected slot
     flex.condense() -- Condense inventory
     returnFromHomeBase(loc) -- Return from home base
 end


 -- **MODIFIED: Craft coal into blocks using turtle.craft() - Keep this outside of dumping logic**
 -- This can happen anywhere the turtle has 9 coal, not just at base.
 local coal_count = 0
 for x=1,16 do
     local item = turtle.getItemDetail(x)
     if item and flex.isItem(name_coal, x) then -- Check if it's coal using the name_coal table
         coal_count = coal_count + item.count
     end
 end

 if coal_count >= 9 then
     local num_blocks_to_craft = math.floor(coal_count / 9)
     send_log_message("Crafting "..tostring(num_blocks_to_craft).." coal blocks...", colors.yellow) -- Use wrapper
     local original_slot = turtle.getSelectedSlot()
     -- To craft coal blocks, need 9 coal in a 3x3 grid.
     -- Clear crafting slots (1-9) first
     for i = 1, 9 do clearCraftingSlot(i) end
     -- Find coal and move 9 to crafting slots (e.g., 1-9)
     local coal_placed = 0
     for slot = 1, 16 do
         if flex.isItem(name_coal, slot) then
             local count_in_slot = turtle.getItemCount(slot)
             local amount_to_move = math.min(count_in_slot, 9 - coal_placed)
             if amount_to_move > 0 then
                 for i = 1, 9 do
                     if turtle.getItemCount(i) == 0 then
                         turtle.select(slot)
                         turtle.transferTo(i, 1) -- Move 1 coal at a time to fill grid
                         coal_placed = coal_placed + 1
                         amount_to_move = amount_to_move - 1
                         if coal_placed >= 9 or amount_to_move <= 0 then break end
                     end
                 end
             end
         end
         if coal_placed >= 9 then break end
     end

     if coal_placed >= 9 then
         turtle.select(1) -- Select any slot for crafting output (coal blocks can go anywhere)
         local success = turtle.craft() -- Crafting Coal Blocks
         if success then
             send_log_message("Crafting successful.", colors.lightBlue) -- Use wrapper
             -- Clear crafting slots after crafting
             for i = 1, 9 do clearCraftingSlot(i) end
         else
             send_log_message("Crafting failed.", colors.orange) -- Use wrapper
             -- Attempt to move items back to temporary slots or consolidate
             for i = 1, 9 do clearCraftingSlot(i) end
         end
     else
         send_log_message("Not enough coal in inventory to craft coal blocks.", colors.orange)
         -- Clear crafting slots if partially filled
         for i = 1, 9 do clearCraftingSlot(i) end
     end

     turtle.select(original_slot) -- Restore selected slot
     checkAndSendStatus() -- Send status after crafting
 end
 -- End of modified crafting logic

end --function


-- Program parameter(s)
local args={...}

-- Tutorial, kind of
if #args > 0 and args[1] == "help" then
 send_log_message("Place just to the ".. -- Use wrapper
   "left of a turtle quarrying the same "..
   "dimensions.",colors.lightBlue)
 send_log_message("Include a chest at the origin (0,0,0) BEHIND the turtle\n".. -- Mention home chest is behind
   "to auto-dump items, refuel, and get/craft torches.", colors.yellow)
 send_log_message("Provide Wood Logs, Coal, and Sticks in the chest to craft torches.", colors.yellow) -- Mention crafting materials
 send_log_message("Usage: stairs ".. -- Use wrapper
   "[length] [width] [depth]",colors.pink)
 return
end --if


-- What Goes Where
send_log_message("Slot 1: Fuel\n".. -- Use wrapper
  "Slot 2: Blocks\nSlot 3: Torches\n"..
  "Home Chest (at 0,0,0 BEHIND the turtle): Dumping, Fuel, Torches, Crafting Materials (Wood Logs, Coal, Sticks)", -- Updated message
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

-- **ADDED: checkFuel function (modified)**
local function checkFuel()
    local current_fuel = turtle.getFuelLevel()
    local estimated_fuel_needed = 500 -- Simple estimate: always try to keep at least 500 fuel
    -- You might need a more sophisticated estimate based on remaining steps

    if current_fuel < estimated_fuel_needed then
        send_log_message("Fuel low, returning to home base for fuel...", colors.yellow)
        local loc = gotoHomeBase() -- Go to home base

        -- Interact with the home chest to get fuel
        local chest = peripheral.wrap(home_chest_side)
        if chest and chest.pullItems then -- Check if it's a valid inventory peripheral
            send_log_message("Attempting to get fuel from chest...", colors.yellow)
            local fuel_pulled_count = 0
            -- Try to pull fuel items (coal, lava buckets, etc.) from the chest
            local fuel_item_names = { "minecraft:coal", "minecraft:coal_block", "minecraft:lava_bucket" }
            local original_selected_slot = turtle.getSelectedSlot()
            turtle.select(1) -- Select fuel slot

            for _, fuel_name in ipairs(fuel_item_names) do
                local success, pulled = chest.pullItems(home_chest_side, -1, 64, fuel_name) -- Pull up to 64 of the fuel item from any slot (-1)
                if success then
                    fuel_pulled_count = fuel_pulled_count + pulled
                    turtle.refuel(pulled) -- Refuel with the pulled items
                    send_log_message("Pulled and used "..tostring(pulled).." "..fuel_name.." for fuel.", colors.lightBlue)
                     checkAndSendStatus() -- Send status after refueling
                end
                 if turtle.getFuelLevel() >= estimated_fuel_needed * 2 then break end -- Stop if enough fuel is acquired (refuel to double needed)
            end
            turtle.select(original_selected_slot) -- Restore selected slot


            if fuel_pulled_count > 0 then
                send_log_message("Refueling complete.", colors.lightBlue)
            else
                send_log_message("Could not find or get fuel from chest.", colors.orange)
            end
        else
            send_log_message("No chest found on side '"..home_chest_side.."' at home base. Cannot get fuel.", colors.red)
        end

        returnFromHomeBase(loc) -- Return from home base
        return true -- Indicate fuel was handled
    end
    return false -- Indicate fuel is sufficient
end

-- Helper to find the first slot with a specific item (excluding essential and crafting slots)
local function findCraftingMaterial(item_names, exclude_slots)
    local exclude = exclude_slots or {}
    for slot = 1, 16 do
        local is_excluded = false
        for _, exclude_slot in ipairs(exclude) do
            if slot == exclude_slot then
                is_excluded = true
                break
            end
        end
        if not is_excluded then
            local item = turtle.getItemDetail(slot)
            if item and flex.isItem(item_names, slot) then
                return slot
            end
        end
    end
    return nil -- Not found
end

-- Helper to move items for crafting
local function moveItemToCraftingSlot(from_slot, to_crafting_slot, amount)
    if turtle.getItemCount(from_slot) > 0 then
        turtle.select(from_slot)
        local success = turtle.transferTo(to_crafting_slot, amount)
        return success
    end
    return false
end

-- Helper to clear a crafting grid slot by moving its contents to a temporary slot (10-16)
local function clearCraftingSlot(crafting_slot)
    if turtle.getItemCount(crafting_slot) > 0 then
        for temp_slot = 10, 16 do
            if turtle.getItemCount(temp_slot) == 0 then
                turtle.select(crafting_slot)
                local success = turtle.transferTo(temp_slot)
                return success -- Successfully moved
            end
             -- Check if items can be stacked in the temp slot
            local temp_item = turtle.getItemDetail(temp_slot)
            local crafting_item = turtle.getItemDetail(crafting_slot)
            if temp_item and crafting_item and temp_item.name == crafting_item.name and turtle.getItemSpace(temp_slot) > 0 then
                 turtle.select(crafting_slot)
                 local success = turtle.transferTo(temp_slot)
                 return success -- Successfully stacked
            end
        end
        -- Could not find an empty or stackable temporary slot (unlikely with dumping first, but fallback)
        send_log_message("Warning: Could not clear crafting slot "..tostring(crafting_slot).." to temporary slots.", colors.orange)
        return false -- Failed to move
    end
    return true -- Slot is already empty
end


-- **MODIFIED: manageTorchesAtBase function - Enhanced Crafting Logic**
local function manageTorchesAtBase()
    local current_torches = turtle.getItemCount(3) -- Check torch slot (slot 3)
    local min_torches = 16 -- Keep at least 16 torches
    local needed_torches = min_torches - current_torches

    if needed_torches > 0 then
        send_log_message("Torch count low ("..tostring(current_torches).."), managing torches at base...", colors.yellow)
        local loc = gotoHomeBase() -- Go to home base

        local chest = peripheral.wrap(home_chest_side)
        if chest and chest.pullItems and chest.pushItems and chest.list then -- Check if it's a valid inventory peripheral with required methods
            send_log_message("Managing torches using chest...", colors.yellow)

            local original_selected_slot = turtle.getSelectedSlot()

            -- 1. Dump all non-essential items to the chest to free up inventory space
            -- Re-using logic from dump, but operating at home base
            local non_dump_slots = {1, 2, 3} -- Fuel, Blocks, Torches (these are essential for the task itself)
            local keepers = {name_box, name_chest} -- Items that should be kept if in other slots

            send_log_message("Dumping non-essential items to chest before crafting...", colors.yellow)
            for x=1,16 do
                 local item_detail = turtle.getItemDetail(x)
                 if item_detail and not flex.isItem(keepers, x) then
                      local is_nondump_slot = false
                      for _, non_dump_slot in ipairs(non_dump_slots) do
                           if x == non_dump_slot then
                                is_nondump_slot = true
                                break
                           end
                      end
                      if not is_nondump_slot then
                            turtle.select(x)
                            local success, dumped_count = chest.pushItems(home_chest_side, x, turtle.getItemCount(x))
                            if success then
                                 send_log_message("Dumped "..tostring(dumped_count).." "..item_detail.name, colors.lightBlue)
                            end
                             checkAndSendStatus()
                      end
                 end
            end
            send_log_message("Dumping complete.", colors.lightBlue)
             checkAndSendStatus()

             -- 2. Pull necessary crafting materials from chest
            local needed_sticks_total = math.ceil(needed_torches / 4) -- Total sticks needed
            local needed_coal_total = math.ceil(needed_torches / 4) -- Total coal needed
            local needed_planks_total = needed_sticks_total * 2 -- 2 planks per stick
            local needed_wood_total = math.ceil(needed_planks_total / 4) -- 1 wood log per 4 planks

             -- Try to pull more than exactly needed in case of crafting inefficiencies or stacking issues
             local pull_multiplier = 1.5 -- Pull 150% of what is theoretically needed

            send_log_message("Pulling crafting materials from chest...", colors.yellow)
             local materials_pulled = 0

            -- Pull Sticks first
            local sticks_to_pull = math.max(0, math.ceil(needed_sticks_total * pull_multiplier) - turtle.getItemCount(name_stick))
             if sticks_to_pull > 0 then
                 local success, pulled = chest.pullItems(home_chest_side, -1, sticks_to_pull, name_stick)
                 if success then materials_pulled = materials_pulled + pulled; send_log_message("Pulled "..tostring(pulled).." sticks.", colors.lightBlue); checkAndSendStatus(); end
             end

            -- Pull Coal
            local coal_to_pull = math.max(0, math.ceil(needed_coal_total * pull_multiplier) - turtle.getItemCount(name_coal))
             if coal_to_pull > 0 then
                 local success, pulled = chest.pullItems(home_chest_side, -1, coal_to_pull, name_coal)
                 if success then materials_pulled = materials_pulled + pulled; send_log_message("Pulled "..tostring(pulled).." coal.", colors.lightBlue); checkAndSendStatus(); end
             end

             -- Pull Planks
             local planks_to_pull = math.max(0, math.ceil(needed_planks_total * pull_multiplier) - turtle.getItemCount(name_planks))
             if planks_to_pull > 0 then
                 local success, pulled = chest.pullItems(home_chest_side, -1, planks_to_pull, name_planks)
                 if success then materials_pulled = materials_pulled + pulled; send_log_message("Pulled "..tostring(pulled).." planks.", colors.lightBlue); checkAndSendStatus(); end
             end

            -- Pull Wood Logs
            local wood_to_pull = math.max(0, math.ceil(needed_wood_total * pull_multiplier) - turtle.getItemCount(name_wood_log))
             if wood_to_pull > 0 then
                 local success, pulled = chest.pullItems(home_chest_side, -1, wood_to_pull, name_wood_log)
                 if success then materials_pulled = materials_pulled + pulled; send_log_message("Pulled "..tostring(pulled).." wood logs.", colors.lightBlue); checkAndSendStatus(); end
             end

             if materials_pulled == 0 then
                 send_log_message("Could not pull any crafting materials from chest.", colors.orange)
             end
             checkAndSendStatus()


            -- 3. Crafting Process (Wood -> Planks -> Sticks -> Torches)
            send_log_message("Starting crafting process...", colors.yellow)

             -- Helper function to get item count by name (faster than iterating every time)
             local function countItemsByName(item_names)
                 local count = 0
                 for slot = 1, 16 do
                     if flex.isItem(item_names, slot) then
                         count = count + turtle.getItemCount(slot)
                     end
                 end
                 return count
             end

             local current_wood_logs = countItemsByName(name_wood_log)
             local current_planks = countItemsByName(name_planks)
             local current_sticks = countItemsByName(name_stick)
             local current_coal = countItemsByName(name_coal)


            -- Craft Planks from Wood Logs
            while current_wood_logs > 0 and current_planks < needed_planks_total + 4 do -- Craft some extra planks
                 -- Clear crafting slots 1-9
                 for i = 1, 9 do if not clearCraftingSlot(i) then goto next_crafting_step end end -- Exit if cannot clear

                 -- Find and move 1 wood log to slot 1
                 local wood_slot = findCraftingMaterial(name_wood_log, non_dump_slots) -- Find wood outside essential slots
                 if not wood_slot then break end -- No more wood logs
                 if not moveItemToCraftingSlot(wood_slot, 1, 1) then break end -- Move 1 log to slot 1

                 -- Craft planks
                 send_log_message("Crafting planks...", colors.yellow)
                 turtle.select(1) -- Select a slot for output (e.g., slot 1)
                 local success = turtle.craft() -- Craft planks (1 log in grid)
                 if success then
                      send_log_message("Crafted planks.", colors.lightBlue); checkAndSendStatus()
                      current_wood_logs = current_wood_logs - 1 -- Assume 1 log was consumed
                      current_planks = current_planks + 4 -- Assume 4 planks crafted
                 else
                      send_log_message("Failed to craft planks.", colors.orange); checkAndSendStatus(); break
                 end
                 -- Clear crafting slots after crafting
                 for i = 1, 9 do clearCraftingSlot(i) end

                 current_wood_logs = countItemsByName(name_wood_log) -- Re-count
                 current_planks = countItemsByName(name_planks) -- Re-count
            end
            ::next_crafting_step::
             checkAndSendStatus()


             -- Craft Sticks from Planks
             while current_planks >= 2 and current_sticks < needed_sticks_total do
                 -- Clear crafting slots 1-9
                 for i = 1, 9 do if not clearCraftingSlot(i) then goto next_crafting_step2 end end -- Exit if cannot clear

                 -- Find and move 2 planks to slots 1 and 5
                 local plank_slot1 = findCraftingMaterial(name_planks, non_dump_slots)
                 if not plank_slot1 then break end
                 if not moveItemToCraftingSlot(plank_slot1, 1, 1) then break end

                 local plank_slot2 = findCraftingMaterial(name_planks, non_dump_slots)
                 if not plank_slot2 then -- If only 1 plank left, break
                    clearCraftingSlot(1) -- Clear slot 1 as we can't craft sticks
                    break
                 end
                 if not moveItemToCraftingSlot(plank_slot2, 5, 1) then clearCraftingSlot(1); break end -- Move 2nd plank to slot 5


                 -- Craft sticks
                 send_log_message("Crafting sticks...", colors.yellow)
                 turtle.select(1) -- Select a slot for output (e.g., slot 1)
                 local success = turtle.craft() -- Craft sticks (2 planks in grid)
                 if success then
                    send_log_message("Crafted sticks.", colors.lightBlue); checkAndSendStatus()
                    current_planks = current_planks - 2 -- Assume 2 planks consumed
                    current_sticks = current_sticks + 4 -- Assume 4 sticks crafted
                 else
                    send_log_message("Failed to craft sticks.", colors.orange); checkAndSendStatus(); break
                 end
                 -- Clear crafting slots after crafting
                 for i = 1, 9 do clearCraftingSlot(i) end

                 current_planks = countItemsByName(name_planks) -- Re-count
                 current_sticks = countItemsByName(name_stick) -- Re-count
            end
            ::next_crafting_step2::
             checkAndSendStatus()


            -- Craft Torches from Coal and Sticks
            while current_coal >= 1 and current_sticks >= 1 and turtle.getItemCount(3) < min_torches do
                 -- Clear crafting slots 1-9
                 for i = 1, 9 do if not clearCraftingSlot(i) then goto end_crafting_process end end -- Exit if cannot clear

                 -- Find and move 1 coal to slot 1
                 local coal_slot = findCraftingMaterial(name_coal, {1}) -- Find coal outside fuel slot
                 if not coal_slot then break end
                 if not moveItemToCraftingSlot(coal_slot, 1, 1) then break end

                 -- Find and move 1 stick to slot 5
                 local stick_slot = findCraftingMaterial(name_stick, {3}) -- Find stick outside torch slot
                 if not stick_slot then clearCraftingSlot(1); break end -- If no sticks, clear coal and break
                 if not moveItemToCraftingSlot(stick_slot, 5, 1) then clearCraftingSlot(1); break end -- Move stick to slot 5


                 -- Craft torches
                 send_log_message("Crafting torches...", colors.yellow)
                 turtle.select(3) -- Select torch slot for output
                 local success = turtle.craft() -- Craft torches (1 coal, 1 stick in grid)
                 if success then
                     send_log_message("Crafted torches.", colors.lightBlue)
                     checkAndSendStatus()
                     current_coal = current_coal - 1 -- Assume 1 coal consumed
                     current_sticks = current_sticks - 1 -- Assume 1 stick consumed
                     -- Torches crafted go directly to slot 3
                 else
                     send_log_message("Crafting failed.", colors.orange)
                     checkAndSendStatus(); break
                 end
                 -- Clear crafting slots after crafting
                 for i = 1, 9 do clearCraftingSlot(i) end

                 current_coal = countItemsByName(name_coal) -- Re-count
                 current_sticks = countItemsByName(name_stick) -- Re-count
            end
            ::end_crafting_process::
             checkAndSendStatus()


            -- 4. Return excess crafting materials to the chest
            send_log_message("Returning excess crafting materials to chest...", colors.yellow)
            local crafting_materials_to_return = { name_wood_log, name_planks, name_coal, name_stick }
            for x=1,16 do
                 local item_detail = turtle.getItemDetail(x)
                 if item_detail and flex.isItem(crafting_materials_to_return, x) then
                     turtle.select(x)
                      -- Ensure not in essential slots (fuel, blocks, torches)
                      local is_essential_slot = false
                      for _, essential_slot in ipairs({1, 2, 3}) do
                           if x == essential_slot then
                                is_essential_slot = true
                                break
                           end
                      end
                      if not is_essential_slot then
                          local success, returned_count = chest.pushItems(home_chest_side, x, turtle.getItemCount(x))
                          if success then
                               send_log_message("Returned "..tostring(returned_count).." "..item_detail.name, colors.lightBlue)
                          end
                           checkAndSendStatus()
                      end
                 end
            end
            send_log_message("Returning complete.", colors.lightBlue)
             checkAndSendStatus()

            turtle.select(original_selected_slot) -- Restore selected slot

            if turtle.getItemCount(3) >= min_torches then
                send_log_message("Torch management complete. Have "..tostring(turtle.getItemCount(3)).." torches.", colors.lightBlue)
            else
                send_log_message("Could not acquire enough torches. Have "..tostring(turtle.getItemCount(3)).." torches.", colors.orange)
            end

        else
            send_log_message("No chest found on side '"..home_chest_side.."' at home base or missing required peripheral methods. Cannot manage torches.", colors.red)
        end

        returnFromHomeBase(loc) -- Return from home base
        return true -- Indicate torch management was handled
    end
    return false -- Indicate enough torches are available
end

-- **ADDED: manageSupplies function**
local function manageSupplies()
    -- Check inventory first (dumps), then fuel, then torches.
    -- Dumping might free up space for fuel/torches.
    local inventory_handled = dump() -- dump now handles going to base, dumping, and returning
    local fuel_handled = checkFuel() -- checkFuel now handles going to base, refueling, and returning
    local torches_handled = manageTorchesAtBase() -- manageTorchesAtBase handles going to base, getting/crafting, and returning

    return inventory_handled or fuel_handled or torches_handled
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
 if flex.isItem(name_torch) then

  if not turtle.place() then
   if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
   turtle.select(2)
   dig.place()
   if not dig.back() then checkAndSendStatus(); return false end -- Added status check

   turtle.select(3)
   if not dig.place() then
    if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
    turtle.select(2)
    dig.placeUp()
    if not dig.back() then checkAndSendStatus(); return false end -- Added status check
    turtle.select(3)
    dig.place()
   end --if/else
  end --if
 end --if

 turtle.select(2)
 checkAndSendStatus() -- Check and send status periodically
end --function


function stepDown()
 local x

 checkAndSendStatus() -- Check and send status periodically
 manageSupplies() -- Check and manage supplies before a step
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
  placeTorch()
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
 manageSupplies() -- Check and manage supplies before a turn
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
 manageSupplies() -- Check and manage supplies before endcap
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
 manageSupplies() -- Check and manage supplies before avoiding bedrock
 if dig.isStuck() then
  -- Hit Bedrock/Void
  if dig.getStuckDir() == "fwd" then
   dig.up()
   dig.placeDown()
   dig.checkBlocks()
   dig.setymin(dig.gety())
   if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
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
 checkAndSendStatus() -- Check and send status periodically
end --function



-- Start Digging

turtle.select(2)

x = 0
direction = dig.getr()

-- **ADDED: Set initial dig.getymin() to the starting Y level**
-- This is needed for the estimated time calculation in sendStatus
dig.setymin(dig.gety())

sendStatus() -- Send initial status before starting

while true do
 -- **MODIFIED: Removed modem message event handling loop**
 -- The script will no longer listen for commands here.
 checkAndSendStatus() -- Check and send status periodically
 manageSupplies() -- Check and manage supplies at the start of the main loop iteration

 for n=0,dz-1 do
  if not stepDown() then break end
  x = x + 1
  if x >= dy then break end
  -- status checks are inside stepDown now
 end
 if dig.isStuck() or x >= dy then break end
 if not turnRight() then break end -- turnRight includes status checks and manageSupplies
 x = x + 1
 -- status checks are inside turnRight now


 direction = dig.getr()
 for n=0,dx-1 do
  if not stepDown() then break end
  x = x + 1
  if x >= dy then break end
   -- status checks are inside stepDown now
 end
 if dig.isStuck() or x >= dy then break end
 if not turnRight() then break end -- turnRight includes status checks and manageSupplies
 x = x + 1
  -- status checks are inside turnRight now

 direction = dig.getr()
end --while


avoidBedrock() -- includes status checks and manageSupplies
if not dig.fwd() then avoidBedrock() end -- dig.fwd includes status checks
if not endcap(1) then avoidBedrock() end -- endcap includes status checks and manageSupplies
if not dig.fwd() then avoidBedrock() end -- dig.fwd includes status checks
if not endcap(1,true) then avoidBedrock() end -- endcap includes status checks and manageSupplies

dig.left(2)
while not turtle.detect() do
 if not dig.fwd() then break end -- dig.fwd includes status checks
 checkAndSendStatus() -- Check and send status periodically
end
if not dig.back() then end -- dig.back includes status checks


-- This bit compensates for random Bedrock (mostly)
if #dig.getKnownBedrock() > 0 then
 -- Check and manage supplies before compensating for bedrock
 manageSupplies()
 for x=1,4 do
  if not dig.placeDown() then checkAndSendStatus(); break end -- Added status check
  if not dig.right() then checkAndSendStatus(); break end -- Added status check
  if not dig.fwd() then checkAndSendStatus(); return false end -- Added status check
  checkAndSendStatus() -- Check and send status periodically
 end --for
end --for



----------------------------------------------
--  /¯] |¯\  /\  |¯¯] [¯¯] [¯¯] |\ ||  /¯¯] --
-- | [  | / |  | |  ]   ||   ][ | \ | | [¯| --
--  \_] | \ |||| ||    ||  [__] || \|  \__| --
----------------------------------------------


local function placeStairs()
 checkAndSendStatus() -- Check and send status periodically
 manageSupplies() -- Check and manage supplies before placing stairs
 local x,y,z,slot
 slot = turtle.getSelectedSlot()
 y = turtle.getItemCount()
 z = true

 if y < 2 or not flex.isItem("stairs") then
  send_log_message("Low on stairs blocks, managing supplies...", colors.yellow)
  -- Stairs blocks are not managed by manageSupplies (only fuel/torches/dumping)
  -- You might need to add logic here to go to base and get more stair blocks if needed
  -- For now, it will just report low and potentially stop if it can't place.

  for x=1,16 do
   turtle.select(x)
   y = turtle.getItemCount()
   if y >= 2 and flex.isItem("stairs") then
    z = false
    send_log_message("Found stairs blocks in inventory.", colors.lightBlue)
    break
   end --if
  end --for

  if z then
   turtle.select(slot)
   checkAndSendStatus() -- Added status check before returning false
   send_log_message("Ran out of stairs blocks. Cannot continue.", colors.red)
   return false -- Cannot place stairs
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
 checkAndSendStatus() -- Check and send status periodically after placing stairs
 return true
end --function


send_log_message("Returning to surface",
  colors.yellow)
sendStatus() -- Send status after logging return to surface


function isDone()
 -- Reached Surface
 return dig.gety() >= 0
end

-- Follow the Spiral [and place Stairs]
-- **ADDED: Variable to track if ascending is finished**
local ascending_done = false
while not isDone() and not ascending_done do
 -- **MODIFIED: Removed modem message event handling loop**
 checkAndSendStatus() -- Check and send status periodically
 manageSupplies() -- Check and manage supplies at the start of the ascending loop iteration

 if dig.getr()%360 == 0 then
  while dig.getz() < dig.getzmax()-1 do
   if not dig.fwd() then ascending_done = true; break end -- dig.fwd includes status checks
   if not dig.up() then ascending_done = true; break end -- dig.up includes status checks
   if not placeStairs() then ascending_done = true; break end -- placeStairs includes status checks and manageSupplies
   if isDone() then break end
   checkAndSendStatus() -- Check and send status periodically
  end

 elseif dig.getr()%360 == 90 then
  while dig.getx() < dig.getxmax()-1 do
   if not dig.fwd() then ascending_done = true; break end -- dig.fwd includes status checks
   if not dig.up() then ascending_done = true; break end -- dig.up includes status checks
   if not placeStairs() then ascending_done = true; break end -- placeStairs includes status checks and manageSupplies
   if isDone() then break end
   checkAndSendStatus() -- Check and send status periodically
  end

 elseif dig.getr()%360 == 180 then
  while dig.getz() > dig.getzmin()+1 do
   if not dig.fwd() then ascending_done = true; break end -- dig.fwd includes status checks
   if not dig.up() then ascending_done = true; break end -- dig.up includes status checks
   if not placeStairs() then ascending_done = true; break end -- placeStairs includes status checks and manageSupplies
   if dig.gety() > -4 and dig.getz()
      == dig.getzmin()+1 then
    -- Up at the top
    if not dig.fwd() then ascending_done = true; break end -- dig.fwd includes status checks
    if not dig.up() then ascending_done = true; break end -- dig.up includes status checks
    if not placeStairs() then ascending_done = true; break end -- placeStairs includes status checks and manageSupplies
   end --if
   if isDone() then break end
   checkAndSendStatus() -- Check and send status periodically
  end

 elseif dig.getr()%360 == 270 then
  while dig.getx() > dig.getxmin()+1 do
   if not dig.fwd() then ascending_done = true; break end -- dig.fwd includes status checks
   if not dig.up() then ascending_done = true; break end -- dig.up includes status checks
   if not placeStairs() then ascending_done = true; break end -- placeStairs includes status checks and manageSupplies
   if isDone() then break end
   checkAndSendStatus() -- Check and send status periodically
  end

 end --if/else

 if not isDone() and not ascending_done then -- Only attempt to turn if not done or stuck during step
     if not dig.left() then ascending_done = true; end -- dig.left includes status checks
 end

end --while


-- All Done!
-- Determine final status message based on whether ascending completed or got stuck
if ascending_done then
    send_log_message("Stairway ascent stopped.", colors.red)
else
    send_log_message("Stairway finished!", colors.lightBlue)
end

sendStatus() -- Send final status update

-- Attempt to go to origin (0,0,0) and face South (180) after finishing/stopping
-- We are already at the presumed home base location (0,0,0 facing South) if the script started there
-- If it couldn't reach there or was already at base, this goto might be redundant but harmless
if not dig.goto(home_base_coords.x, home_base_coords.y, home_base_coords.z, home_base_coords.r) then -- goto includes status checks
    send_log_message("Could not reach origin ("..tostring(home_base_coords.x)..","..tostring(home_base_coords.y)..","..tostring(home_base_coords.z)..").", colors.orange)
    -- Attempt to dump remaining inventory at current location if cannot reach base
    send_log_message("Attempting to dump remaining inventory at current location.", colors.yellow)
    dump() -- dump now handles going to home base or dropping (will drop if cannot reach base)
else
    -- Successfully reached origin/home base, manage any remaining inventory at base
    send_log_message("Successfully returned to origin ("..tostring(home_base_coords.x)..","..tostring(home_base_coords.y)..","..tostring(home_base_coords.z).."). Managing final inventory.", colors.lightBlue)
    -- Manage any remaining inventory at the home base
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