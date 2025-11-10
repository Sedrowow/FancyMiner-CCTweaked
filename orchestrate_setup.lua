-- Orchestration System Setup Helper
-- Simplifies the setup process for the multi-turtle quarry system

local function printTitle(text)
    term.clear()
    term.setCursorPos(1, 1)
    print("================================")
    print(text)
    print("================================")
    print()
end

local function printStep(num, text)
    print("[" .. num .. "] " .. text)
end

local function confirm(prompt)
    print()
    print(prompt .. " (y/n)")
    local key = read()
    return key:lower() == "y"
end

local function setupWorkerTurtle()
    printTitle("Worker Turtle Setup")
    print("This will install the bootstrap loader")
    print("that allows the turtle to receive firmware.")
    print()
    
    if not confirm("Continue with worker setup?") then
        return false
    end
    
    print()
    print("Downloading bootstrap loader...")
    
    local url = "https://raw.githubusercontent.com/NoahGori/FancyMiner-CCTweaked/main/disk/worker/bootstrap.lua"
    local success = shell.run("wget", url, "startup.lua", "-f")
    
    if success then
        print()
        print("SUCCESS! Worker turtle is ready.")
        print()
        print("The turtle will:")
        print("  - Auto-start bootstrap on boot (startup.lua created)")
        print("  - Download firmware from orchestration server")
        print("  - Resume mining after restart from saved position")
        print()
        print("Place this turtle in the deployment turtle's inventory.")
        return true
    else
        print()
        print("ERROR: Failed to download bootstrap loader.")
        print("You can manually copy bootstrap.lua to startup.lua")
        return false
    end
end

local function setupDeploymentTurtle()
    printTitle("Deployment Turtle Setup")
    print("This will install the deployment program and APIs.")
    print()
    
    print("Requirements:")
    printStep(1, "Ender modem equipped")
    printStep(2, "Floppy disk with worker firmware in drive")
    printStep(3, "Inventory loaded:")
    print("    - Slot 1: Output chest")
    print("    - Slot 2: Fuel chest")
    print("    - Slots 3-16: Pre-programmed worker turtles")
    print()
    
    if not confirm("Are all requirements met?") then
        print("Please prepare the turtle and run setup again.")
        return false
    end
    
    print()
    print("Downloading deployment program...")
    
    local files = {
        {url = "orchestrate_deploy.lua", name = "deploy.lua"},
        {url = "dig.lua", name = "dig.lua"},
        {url = "flex.lua", name = "flex.lua"},
        {url = "disk/worker/bootstrap.lua", name = "bootstrap.lua"}
    }
    
    local baseUrl = "https://raw.githubusercontent.com/NoahGori/FancyMiner-CCTweaked/main/"
    
    for _, file in ipairs(files) do
        print("Downloading " .. file.name .. "...")
        local success = shell.run("wget", baseUrl .. file.url, file.name, "-f")
        if not success then
            print("ERROR: Failed to download " .. file.name)
            return false
        end
    end
    
    print()
    print("Creating startup file for auto-resume...")
    
    -- Create startup file that runs deploy.lua
    local startupFile = fs.open("startup.lua", "w")
    startupFile.writeLine("-- Auto-resume for Deployment Turtle")
    startupFile.writeLine("print('Deployment Turtle Starting...')")
    startupFile.writeLine("sleep(0.5)")
    startupFile.writeLine("")
    startupFile.writeLine("shell.run('deploy.lua')")
    startupFile.close()
    
    print()
    print("SUCCESS! Deployment turtle is ready.")
    print()
    print("The turtle will:")
    print("  - Auto-resume deployment after restart")
    print("  - Resume worker operations if deployment done")
    print()
    print("Next steps:")
    printStep(1, "Position turtle at quarry origin")
    printStep(2, "Turtle will auto-start on next reboot, or run: deploy")
    printStep(3, "Enter server channel and quarry dimensions")
    
    return true
end

local function setupOrchestrationServer()
    printTitle("Orchestration Server Setup")
    print("This will install the server program on this computer.")
    print("The server will auto-restart and resume operations.")
    print()
    
    print("Requirements:")
    printStep(1, "Computer (not turtle)")
    printStep(2, "Modem attached (ender modem recommended)")
    printStep(3, "Floppy disk with worker firmware in drive")
    print()
    
    if not confirm("Continue with server setup?") then
        return false
    end
    
    print()
    print("Downloading orchestration server...")
    
    local url = "https://raw.githubusercontent.com/NoahGori/FancyMiner-CCTweaked/main/orchestrate_server.lua"
    local success = shell.run("wget", url, "orchestrate_server.lua", "-f")
    
    if not success then
        print()
        print("ERROR: Failed to download server program.")
        return false
    end
    
    print()
    print("Creating startup file for auto-restart...")
    
    -- Create startup file
    local startupFile = fs.open("startup.lua", "w")
    startupFile.writeLine("-- Auto-restart for Orchestration Server")
    startupFile.writeLine("print('Starting Orchestration Server...')")
    startupFile.writeLine("sleep(1)")
    startupFile.writeLine("")
    startupFile.writeLine("local success, err = pcall(function()")
    startupFile.writeLine("    shell.run('orchestrate_server.lua')")
    startupFile.writeLine("end)")
    startupFile.writeLine("")
    startupFile.writeLine("if not success then")
    startupFile.writeLine("    print('Server error: ' .. tostring(err))")
    startupFile.writeLine("    print('Press any key to restart...')")
    startupFile.writeLine("    os.pullEvent('key')")
    startupFile.writeLine("    os.reboot()")
    startupFile.writeLine("end")
    startupFile.close()
    
    print()
    print("SUCCESS! Server is ready.")
    print()
    print("The server will:")
    print("  - Auto-start on computer boot")
    print("  - Resume operations after restart")
    print("  - Track worker states across reboots")
    print()
    print("Server channel ID: " .. os.getComputerID())
    print("Note this ID for deployment turtle.")
    print()
    print("To disable auto-start, delete 'startup.lua'")
    
    return true
end

local function setupFirmwareDisk()
    printTitle("Firmware Disk Setup")
    print("This will download worker firmware to a floppy disk.")
    print()
    
    -- Check for disk drive
    local drive = peripheral.find("drive")
    if not drive then
        print("ERROR: No disk drive found!")
        print("Attach a disk drive and insert a floppy disk.")
        return false
    end
    
    if not drive.isDiskPresent() then
        print("ERROR: No floppy disk in drive!")
        print("Insert a floppy disk and try again.")
        return false
    end
    
    local mountPath = drive.getMountPath()
    print("Found disk at: " .. mountPath)
    print()
    
    if not confirm("Download firmware to this disk?") then
        return false
    end
    
    -- Create directory structure
    print()
    print("Creating directories...")
    if not fs.exists(mountPath .. "/worker") then
        fs.makeDir(mountPath .. "/worker")
    end
    
    print("Downloading firmware files...")
    
    local baseUrl = "https://raw.githubusercontent.com/NoahGori/FancyMiner-CCTweaked/main/disk/worker/"
    local files = {"bootstrap.lua", "quarry.lua", "dig.lua", "flex.lua", "gps_nav.lua"}
    
    for _, filename in ipairs(files) do
        print("Downloading " .. filename .. "...")
        local success = shell.run("wget", baseUrl .. filename, mountPath .. "/worker/" .. filename, "-f")
        if not success then
            print("ERROR: Failed to download " .. filename)
            return false
        end
    end
    
    print()
    print("SUCCESS! Firmware disk is ready.")
    print("Insert this disk into the deployment turtle.")
    
    return true
end

local function mainMenu()
    while true do
        printTitle("Orchestration System Setup")
        print("Choose what you want to set up:")
        print()
        print("1. Worker Turtle (run on each worker)")
        print("2. Deployment Turtle")
        print("3. Orchestration Server (computer)")
        print("4. Firmware Disk (floppy disk)")
        print("5. Exit")
        print()
        print("Enter choice (1-5):")
        
        local choice = read()
        
        if choice == "1" then
            setupWorkerTurtle()
            print()
            print("Press any key to continue...")
            os.pullEvent("key")
        elseif choice == "2" then
            setupDeploymentTurtle()
            print()
            print("Press any key to continue...")
            os.pullEvent("key")
        elseif choice == "3" then
            setupOrchestrationServer()
            print()
            print("Press any key to continue...")
            os.pullEvent("key")
        elseif choice == "4" then
            setupFirmwareDisk()
            print()
            print("Press any key to continue...")
            os.pullEvent("key")
        elseif choice == "5" then
            printTitle("Setup Complete")
            print("Thank you for using the orchestration system!")
            return
        else
            print("Invalid choice. Press any key to continue...")
            os.pullEvent("key")
        end
    end
end

-- Run main menu
mainMenu()
