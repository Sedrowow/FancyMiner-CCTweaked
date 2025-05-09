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

    print("--- Turtle Status ---")
    if last_status == nil then
        print("Waiting for status update...") -- Default white
    else
        -- Use colors from flex.lua's colors table (flex.lua is already loaded)
        local colors = colors

        term.setTextColor(colors.white)
        print("Turtle ID: " .. tostring(last_status.id))
        if last_status.label and last_status.label !== "" then
            term.setTextColor(colors.white)
            print("Turtle Label: " .. tostring(last_status.label))
        end

        term.setTextColor(colors.orange) -- Fuel color (Matches turtle UI)
        print("Fuel: " .. tostring(last_status.fuel))

        term.setTextColor(colors.lightGray) -- Position color (Requested color)
        print("Position: X=" .. tostring(last_status.position.x) .. ", Y=" .. tostring(last_status.position.y) .. ", Z=" .. tostring(last_status.position.z))

        term.setTextColor(colors.white) -- Mining status color (Keep white)
        print("Mining: " .. tostring(last_status.is_mining))

        -- Display the estimated completion time string
        term.setTextColor(colors.white) -- Color for completion time (Keep white or choose another)
        print("ETA: " .. tostring(last_status.estimated_completion_time or "Calculating..."))

        -- Display processed vs total blocks for context
        if last_status.total_quarry_blocks !== nil and last_status.processed_blocks !== nil then
             term.setTextColor(colors.lightBlue) -- Color for blocks
             print("Processed: "..tostring(last_status.processed_blocks).." / "..tostring(last_status.total_quarry_blocks).." blocks")
        end

        term.setTextColor(colors.lightBlue) -- Dug blocks color (Matches turtle UI)
        print("Dug: " .. tostring(last_status.dug_blocks) .. " blocks")


        term.setTextColor(colors.green) -- Depth color (Matches turtle UI)
        -- Construct the depth display using the sent ymin and current y
        local depth_display = tostring(-last_status.position.y) .. "m"
        if last_status.ymin !== nil then -- Check if ymin was included in the status table
            depth_display = depth_display .. " / " .. tostring(-last_status.ymin) .. "m"
        end
        print("Depth: " .. depth_display)


        term.setTextColor(colors.white) -- Inventory header color (Keep white)
        print("\nInventory Summary:")
        if last_status.inventory_summary and #last_status.inventory_summary > 0 then
            term.setTextColor(colors.white) -- Inventory items color (Keep white)
            for _, item in ipairs(last_status.inventory_summary) do
                print("  " .. item.name .. " (" .. tostring(item.count) .. ")")
            end
        else
            term.setTextColor(colors.white) -- Inventory empty message color (Keep white)
            print("  Inventory empty or not detailed.")
        end
    end

    term.setTextColor(colors.white) -- Waiting message color (Keep white)
    print("\nWaiting for next update...")
    term.setTextColor(colors.white) -- Reset color before ending the display function
    -- print("DEBUG: Display updated.") -- Optional debug
end
term.setTextColor(colors.white) -- Ensure color is white initially
print("Waiting for status message on channel " .. tostring(modem_channel ) .. "...")

while true do
    displayStatus() -- Update display
    -- Use os.pullEvent with a timeout to allow display updates even without messages
    local event, modemSide, senderChannel, replyChannel, message, senderDistance =
        os.pullEvent("modem_message", 0.5) -- Add a small timeout

    if event == "modem_message" then
        -- print("DEBUG: Received modem message event on channel " .. tostring(senderChannel)) -- Optional debug
        -- Check if the message is a status update and from the expected channel
        if senderChannel == modem_channel  and type(message) == "table" and message.type == "status_update" then
            -- print("DEBUG: Received valid status update.") -- Optional debug
            last_status = message -- Store the latest status
        -- else
            -- print("DEBUG: Received unexpected message format or channel.") -- Optional debug
            -- if type(message) == "table" then
            --     print("DEBUG: Sender Channel: "..tostring(senderChannel)..", Message Type: "..(message.type or "no_type").. ", Message: "..textutils.serialize(message))
            -- else
            --      print("DEBUG: Sender Channel: "..tostring(senderChannel)..", Message Type: "..type(message).. ", Message: "..tostring(message))
            -- end

        end
    end
    -- The loop will naturally call displayStatus() again after the event or timeout
end

-- No cleanup needed as the script runs in a loop until stopped