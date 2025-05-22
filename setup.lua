-- --- Configuration ---
local githubBaseUrl = "https://raw.githubusercontent.com/Sedrowow/FancyMiner-CCTweaked/main/"

-- List the exact filenames for each setup type.
local minerScripts = {"flex.lua", "dig.lua", "quarry.lua", "stairs.lua"} -- Add any other miner scripts here
local receiverScripts = {"flex.lua", "receive.lua","advancedperipherals/receiver0.lua"}
local oreminerScripts = {"advancedperipherals/flex.lua", "advancedperipherals/dig.lua", "advancedperipherals/oreminer.lua"} -- Added ore miner scripts
-- -------------------

-- Function to download a script and provide feedback
local function downloadScript(scriptName)
    local fullUrl = githubBaseUrl .. scriptName
    print("Downloading " .. scriptName .. "...")
    local success = shell.run("wget " .. fullUrl .. " " .. scriptName)
    if success then
        print(scriptName .. " installed.")
        return true
    else
        print("Error downloading " .. scriptName .. ".")
        print("Please check the URL: " .. fullUrl)
        print("And ensure you have an internet connection.")
        return false
    end
end

-- --- Main Setup Logic ---

print("##Universal Setup Script##")
print("--------------------------")
print("Is this the 1=Miner, 2=receiver or 3=oreminer?")

local setupType = io.read()

if setupType == "1" then
    -- --- Miner Setup ---
    print("Setting up as Miner...")

    -- Download Miner Scripts
    local allDownloaded = true
    for _, scriptName in ipairs(minerScripts) do
        if not downloadScript(scriptName) then
            allDownloaded = false
            -- Optionally stop if a critical script fails to download
            -- break
        end
    end

    if allDownloaded then
        -- Label the turtle if it is one
        if turtle then
            print("What should be the name of this Turtle?")
            name = io.read()
            if name == "" then
                name = "FancyMiner"
            end
            shell.run("label set " .. name)
            print("Turtle labeled '" .. name .. "'.")
        else
            print("Not a turtle. Skipping labeling.")
        end

        os.sleep(2)

        -- Ask about automatic setup
        print("automatically set up? 1:yes 2:no")
        local autoSetup = io.read()

        if autoSetup == "1" then
            print("Running flex.lua for initial setup...")
            shell.run("flex.lua")
            print("flex setup done.")
            os.sleep(1)

            print("Running dig.lua for setup...")
            shell.run("dig.lua")
            print("dig setup done.")
            os.sleep(1)

            print("------------------------------------")
            print("Setup complete!")
            print("use command 'quarry' or 'stairs help' for usage")
            print("or check flex_options.cfg for settings")
            print("------------------------------------")
        else
            print("Manual setup selected.")
            print("Please run 'flex.lua' and 'dig.lua' manually to configure.")
            print("Check flex_options.cfg for settings.")
        end
    else
        print("Some scripts failed to download. Please check the error messages above.")
    end

elseif setupType == "2" then
    -- --- Receiver Setup ---
    print("Setting up as Receiver...")
    print("1= pocket computer or 2= normal computer?")
    local computerType = io.read()

    if computerType == "1" then
        -- Pocket Computer Setup
        print("Setting up on Pocket Computer...")

        -- Download Receiver Scripts
        local allDownloaded = true
        for _, scriptName in ipairs(receiverScripts) do
            if not downloadScript(scriptName) then
                allDownloaded = false
                 -- Optionally stop if a critical script fails to download
                 -- break
            end
        end

        if allDownloaded then
            print("download done.")

            print("Running flex.lua for initial setup...")
            shell.run("flex.lua")
            os.sleep(1)

            print("---------------------------------------")
            print("'check flex_options.cfg' for settings")
            print("or run 'recieve' to start recieving")
            print("---------------------------------------")
        else
             print("Some scripts failed to download. Please check the error messages above.")
        end

    elseif computerType == "2" then
        -- Normal Computer Setup
        print("Setting up on Normal Computer...")

        -- Download Receiver Scripts
         local allDownloaded = true
        for _, scriptName in ipairs(receiverScripts) do
            if not downloadScript(scriptName) then
                allDownloaded = false
                 -- Optionally stop if a critical script fails to download
                 -- break
            end
        end

        if allDownloaded then
            print("download done.")

            print("Running flex.lua for initial setup...")
            shell.run("flex.lua")
            os.sleep(1)

            -- Ask about creating startup.lua
            print("create startup.lua for advanced monitor usage? 1=Yes/2=No")
            local createStartup = io.read()

            if createStartup == "1" then
                print("2x2 monitor on:")
                print("1=top")
                print("2=left")
                print("3=right")
                print("4=bottom")
                local monitorPositionChoice = io.read()
                local monitorPosition = nil

                if monitorPositionChoice == "1" then
                    monitorPosition = "top"
                elseif monitorPositionChoice == "2" then
                    monitorPosition = "left"
                elseif monitorPositionChoice == "3" then
                    monitorPosition = "right"
                elseif monitorPositionChoice == "4" then
                    monitorPosition = "bottom"
                else
                    print("Invalid choice. Skipping startup.lua creation.")
                end

                if monitorPosition then
                    local startupFile = fs.open("startup.lua", "w")
                    if startupFile then
                        startupFile.write('shell.run("monitor scale ' .. monitorPosition .. ' 0.5")\n')
                        startupFile.write('shell.run("monitor ' .. monitorPosition .. ' recieve")\n')
                        startupFile.close()
                        print("startup.lua created successfully.")
                    else
                        print("Error creating startup.lua.")
                    end
                end
            end

            print("---------------------------------------")
            print("'check flex_options.cfg' for settings")
            print("or run 'recieve' to start recieving")
            print("---------------------------------------")
         else
             print("Some scripts failed to download. Please check the error messages above.")
        end

    else
        print("Invalid choice for computer type. Please enter 1 or 2.")
    end

elseif setupType == "3" then
    -- --- Ore Miner Setup ---
    print("Setting up as Ore Miner...")

    -- Download Ore Miner Scripts
    local allDownloaded = true
    for _, scriptName in ipairs(oreminerScripts) do
        if not downloadScript(scriptName) then
            allDownloaded = false
        end
    end

    if allDownloaded then
        -- Label the turtle if it is one
        if turtle then
            print("What should be the name of this Turtle?")
            name = io.read()
            if name == "" then
                name = "OreMiner"
            end
            shell.run("label set " .. name)
            print("Turtle labeled '" .. name .. "'.")
        else
            print("Not a turtle. Skipping labeling.")
        end

        os.sleep(2)

        -- Ask about automatic setup
        print("automatically set up? 1:yes 2:no")
        local autoSetup = io.read()

        if autoSetup == "1" then
            print("Running flex.lua for initial setup...")
            shell.run("flex.lua")
            print("flex setup done.")
            os.sleep(1)

            print("Running dig.lua for setup...")
            shell.run("dig.lua")
            print("dig setup done.")
            os.sleep(1)

            print("------------------------------------")
            print("Setup complete!")
            print("use command 'oreminer' for usage")
            print("or check flex_options.cfg for settings")
            print("------------------------------------")
        else
            print("Manual setup selected.")
            print("Please run 'flex.lua' and 'dig.lua' manually to configure.")
            print("Check flex_options.cfg for settings.")
        end
    else
        print("Some scripts failed to download. Please check the error messages above.")
    end
else
    print("Invalid choice for setup type. Please enter 1, 2 or 3.")
end

print("Setup script finished.")
