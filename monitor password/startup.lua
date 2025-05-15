-- Connect to the advanced monitor
local monitor = peripheral.find("monitor")
if not monitor then
    error("Advanced monitor not found")
end

-- Set up monitor
monitor.setTextScale(0.75) -- Changed back to 0.5
monitor.clear()

-- Keypad layout
local buttons = {
    {"1", "2", "3"},
    {"4", "5", "6"},
    {"7", "8", "9"},
    {"C", "0", "E"}
}

local password = ""
local correctPassword = "8642"

-- Draw a button
local function drawButton(x, y, text)
    monitor.setCursorPos(x * 2 - 1, y) -- More compact spacing
    monitor.write(text)
end

-- Draw the keypad
local function drawKeypad()
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.write("Enter: " .. string.rep("*", #password))
    
    for y, row in ipairs(buttons) do
        for x, button in ipairs(row) do
            drawButton(x, y + 2, button) -- Adjusted Y position
        end
    end
end

-- Main loop
while true do
    drawKeypad()
    local event, side, x, y = os.pullEvent("monitor_touch")
    
    -- Convert touch coordinates to button
    local buttonX = math.floor((x + 1) / 2) -- Adjusted for new spacing
    local buttonY = math.floor(y - 2) -- Adjusted for new spacing
    
    if buttonY >= 1 and buttonY <= 4 and buttonX >= 1 and buttonX <= 3 then
        local button = buttons[buttonY][buttonX]
        
        if button == "C" then
            password = ""
        elseif button == "E" then
            if password == correctPassword then
                monitor.clear()
                monitor.setCursorPos(1, 1)
                monitor.write("Access Granted!")
                redstone.setOutput("back", true)
                sleep(4)
                redstone.setOutput("back", false)
                password = ""
            else
                monitor.clear()
                monitor.setCursorPos(1, 1)
                monitor.write("Access Denied!")
                sleep(2)
                password = ""
            end
        else
            password = password .. button
        end
    end
end
