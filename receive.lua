-- Program to receive messages from computers/
-- turtles using flex.lua "send" function


local log_file = "log.txt"
local options_file = "flex_options.cfg"
os.loadAPI("flex.lua")
local modem_channel = 6464

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

local status_listen_channel = modem_channel -- Channel to listen on for status updates from the turtle

-- print("DEBUG: Starting receive_pocket.lua (Status Monitor)") -- Debug print

local modem
-- print("DEBUG: Looking for modem peripheral.") -- Debug print
local p = flex.getPeripheral("modem")
if #p > 0 then
    -- print("DEBUG: Modem peripheral found: " .. tostring(p[1])) -- Debug print
    modem = peripheral.wrap(p[1])
    modem.open(status_listen_channel) -- Open the modem on the status listen channel
    -- print("DEBUG: Modem opened on channel " .. tostring(status_listen_channel)) -- Debug print
else
    -- print("DEBUG: No modem peripheral found.") -- Debug print
    flex.printColors("Please attach a wireless or ender modem\n", colors.red)
    sleep(2)
    return
end

local last_status = nil -- Variable to store the last received status

local function displayStatus()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white) -- Set default text color

    -- **MODIFIED: Robust check for stairs log history**
    if type(last_status) == "table" and last_status.script == "stairs" and type(last_status.log_history) == "table" and #last_status.log_history > 0 then
        -- Display Stairs Log History
        print("--- Stairs Log from ID: " .. tostring(last_status.id or "Unknown") .. " ---") -- Header with Turtle ID
        local terminal_height = term.getSize()
        -- Calculate start index to show recent messages, accounting for header and waiting message
        local log_start_index = math.max(1, #last_status.log_history - (terminal_height - 3)) -- 3 lines for header and waiting message

        for i = log_start_index, #last_status.log_history do
            -- Print each log message, ensure it's a string
            print(tostring(last_status.log_history[i]))
        end

         -- Add padding lines if log is shorter than screen to clear previous content
        local lines_displayed = #last_status.log_history - log_start_index + 1
        for i = 1, terminal_height - lines_displayed - 2 do -- Account for header and waiting message line
            print("")
        end

    else
        -- **Existing standard status display logic (for quarry or other scripts)**
        print("--- Turtle Status ---")
        if last_status == nil then
            print("Waiting for status update...") -- Default white
        else
            -- Use colors from flex.lua's colors table (flex.lua is already loaded)
            local colors = colors

            term.setTextColor(colors.white)
            print("Turtle ID: " .. tostring(last_status.id or "Unknown")) -- Handle potential nil ID
            if last_status.label and last_status.label ~= "" then
                term.setTextColor(colors.white)
                print("Turtle Label: " .. tostring(last_status.label))
            end

            term.setTextColor(colors.orange) -- Fuel color (Matches turtle UI)
            print("Fuel: " .. tostring(last_status.fuel or "N/A")) -- Handle potential nil fuel

            term.setTextColor(colors.lightGray) -- Position color (Requested color)
            if last_status.position then -- Check if position table exists
                 print("Position: X=" .. tostring(last_status.position.x or "N/A") .. ", Y=" .. tostring(last_status.position.y or "N/A") .. ", Z=" .. tostring(last_status.position.z or "N/A"))
            else
                 print("Position: N/A")
            end

            term.setTextColor(colors.white) -- Mining status color (Keep white)
            print("Mining: " .. tostring(last_status.is_mining or "N/A")) -- Handle potential nil is_mining

            -- Display the estimated completion time string
            term.setTextColor(colors.white) -- Color for completion time (Keep white or choose another)
            print("DONE AT: " .. tostring(last_status.estimated_completion_time or "Calculating..."))
            print("ETA: " .. tostring(last_status.estimated_time_remaining or "Calculating..."))

            -- Display processed vs total blocks for context
            if last_status.total_quarry_blocks ~= nil and last_status.processed_blocks ~= nil then
                 term.setTextColor(colors.lightBlue) -- Color for blocks
                 print("Processed: "..tostring(last_status.processed_blocks).." / "..tostring(last_status.total_quarry_blocks).." blocks")
            else
                 term.setTextColor(colors.lightBlue) -- Color for blocks
                 print("Processed: N/A / N/A blocks") -- Handle cases where blocks info is not sent
            end


            term.setTextColor(colors.lightBlue) -- Dug blocks color (Matches turtle UI)
            print("Dug: " .. tostring(last_status.dug_blocks or "N/A") .. " blocks") -- Handle potential nil dug_blocks


            term.setTextColor(colors.green) -- Depth color (Matches turtle UI)
            -- Construct the depth display using the sent ymin and current y
            local depth_display = tostring(-(last_status.position and last_status.position.y or "N/A")) .. "m" -- Handle potential nil position.y
            if last_status.ymin ~= nil then -- Check if ymin was included in the status table
                 depth_display = depth_display .. " / " .. tostring(-last_status.ymin) .. "m"
            end
            print("Depth: " .. depth_display)


            term.setTextColor(colors.white) -- Inventory header color (Keep white)
            print("\nInventory Summary:")
            if last_status.inventory_summary and #last_status.inventory_summary > 0 then
                 term.setTextColor(colors.white) -- Inventory items color (Keep white)
                 -- Display only a few inventory slots if it's too long
                 local max_inventory_display = math.min(16, math.floor((term.getSize() - 18) / 2)) -- Estimate space needed by other standard info (approx 12 lines above inventory)

                 local displayed_count = 0
                 for _, item in ipairs(last_status.inventory_summary) do
                      if displayed_count < max_inventory_display then
                         print("  " .. (item.name or "nil") .. " (" .. tostring(item.count or 0) .. ")")
                         displayed_count = displayed_count + 1
                      else
                         print("  ...")
                         break
                      end
                 end
                 if displayed_count == 0 and #last_status.inventory_summary > 0 then
                     print("  Too many items to display.") -- Message if inventory exists but is too large for display limit
                 elseif #last_status.inventory_summary == 0 then
                     print("  Inventory empty or not detailed.")
                 end
            else
                 term.setTextColor(colors.white) -- Inventory empty message color (Keep white)
                 print("  Inventory empty or not detailed.")
            end
        end
    end

    term.setTextColor(colors.white) -- Waiting message color (Keep white)
    print("\nWaiting for next update...")
    term.setTextColor(colors.white) -- Reset color before ending the display function
    -- print("DEBUG: Display updated.") -- Optional debug
end

-- Read existing log file into filelist (keeping original log file logic)
local file, line
local filelist = {}
if fs.exists(log_file) then
    file = fs.open(log_file, "r")
    line = file.readLine()

    while line ~= nil do
        if line ~= "" or (line == "" and filelist[#filelist] ~= "") then
            filelist[#filelist + 1] = line
        end --if

        line = file.readLine()
    end --while
    file.close()
    file = fs.open(log_file, "a") -- Re-open in append mode
else
    -- Log file does not exist: make one!
    file = fs.open(log_file, "w")
    -- file.close() -- Don't close immediately, keep open for appending
    -- file = fs.open(log_file, "a") -- Ensure it's open in append mode after creation
end --if/else

-- Function to display messages and append to log file (keeping original logic)
-- This function is primarily for logging non-status messages.
local function displayAndLog(message)
    local timestamp = os.date("[%Y-%m-%d %H:%M:%S] ")
    local log_message = timestamp .. message
    -- This function currently scrolls the screen, which might interfere with the displayStatus logic
    -- Let's just append to the file and not modify the terminal display here
    -- The status display logic will handle terminal updates.
    if file then
        file.writeLine(log_message)
        file.flush() -- Ensure message is written to disk immediately
    end
    -- Removed terminal display and scrolling logic from here.
end

print("Waiting for message on channel " .. tostring(modem_channel ) .. "...")

while true do
    -- Use os.pullEvent with a timeout to allow display updates even without messages
    local event, modemSide, senderChannel, replyChannel, message, senderDistance =
        os.pullEvent("modem_message", 0.5) -- Add a small timeout

    if event == "modem_message" then
        -- print("DEBUG: Received modem message event on channel " .. tostring(senderChannel)) -- Optional debug
        -- Check if the message is a status update and from the expected channel
        if senderChannel == modem_channel  and type(message) == "table" and message.type == "status_update" then
            -- print("DEBUG: Received valid status update.") -- Optional debug
            last_status = message -- Store the latest status
            -- displayStatus() -- Moved displayStatus call to the end of the loop for consistent updates
        elseif senderChannel == modem_channel then -- Handle other message types on the same channel if needed
            -- This is where you might handle flex.send messages directly if they are not status_update type
            -- The original receive.lua was designed to log ANY message received on the channel.
            -- Let's keep that behavior for non-status messages and log them to file.
             if type(message) == "string" then
                 displayAndLog("Received: " .. message)
             elseif type(message) == "table" then
                  -- If it's a table but not a status update, serialize and log it
                  displayAndLog("Received table: " .. textutils.serialize(message))
             else
                  displayAndLog("Received non-string/table message: " .. tostring(message))
             end

        -- else
            -- print("DEBUG: Received unexpected message format or channel.") -- Optional debug
            -- if type(message) == "table" then
            --     print("DEBUG: Sender Channel: "..tostring(senderChannel)..", Message Type: "..(message.type or "no_type").. ", Message: "..textutils.serialize(message))
            -- else
            --      print("DEBUG: Sender Channel: "..tostring(senderChannel)..", Message Type: "..type(message).. ", Message: "..tostring(message))
            -- end

        end
    end
    -- Always call displayStatus() at the end of the loop to update the terminal
    -- based on the last received status (either new or from timeout)
    displayStatus()

end

-- Close the log file when the script stops (e.g., with Ctrl+T)
if file then
    file.close()
end
-- No cleanup needed for modem as it's handled by the OS on script termination