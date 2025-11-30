-- Auto-update script for FancyMiner orchestration system
-- This script checks for updates and re-runs setup if a new version is detected

local COMPONENT_TYPE = "COMPONENT_TYPE_PLACEHOLDER"  -- Will be replaced by setup script
local REPO_RAW_BASE = 'https://raw.githubusercontent.com/Sedrowow/FancyMiner-CCTweaked/aaaa/'

local function trim(s)
    if not s then return s end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseVersion(str)
    local parts = {}
    if not str then return parts end
    for token in str:gmatch("[^%.]+") do
        parts[#parts+1] = tonumber(token) or token
    end
    return parts
end

local function compareVersions(a, b)
    -- Return 1 if a>b, -1 if a<b, 0 if equal
    for i = 1, math.max(#a, #b) do
        local av = a[i] or 0
        local bv = b[i] or 0
        if type(av) == "number" and type(bv) == "number" then
            if av > bv then return 1 elseif av < bv then return -1 end
        else
            av, bv = tostring(av), tostring(bv)
            if av > bv then return 1 elseif av < bv then return -1 end
        end
    end
    return 0
end

local function checkVersion()
    print("Checking for updates...")

    local versionUrl = REPO_RAW_BASE .. 'version.txt'
    fs.delete('.remote_version.txt')
    shell.run('wget', versionUrl, '.remote_version.txt', '-f')

    local remoteVersion = nil
    if fs.exists('.remote_version.txt') then
        local f = fs.open('.remote_version.txt', 'r')
        remoteVersion = f.readAll()
        f.close()
        fs.delete('.remote_version.txt')
    end

    local localVersion = nil
    if fs.exists('.local_version.txt') then
        local f = fs.open('.local_version.txt', 'r')
        localVersion = f.readAll()
        f.close()
    end

    remoteVersion = trim(remoteVersion)
    localVersion = trim(localVersion)

    local remoteParts = parseVersion(remoteVersion)
    local localParts = parseVersion(localVersion)
    local cmp = compareVersions(remoteParts, localParts)

    if remoteVersion and (remoteVersion ~= localVersion or cmp == 1) then
        print('New version detected: ' .. remoteVersion)
        print('Current version: ' .. (localVersion or 'none'))
        print('Updating ' .. COMPONENT_TYPE .. '...')
        
        -- Download updated files based on component type
        local baseUrl = REPO_RAW_BASE
        
        if COMPONENT_TYPE == "server" then
            print("Downloading orchestrate_server.lua...")
            fs.delete('orchestrate_server.lua')
            shell.run('wget', baseUrl .. 'orchestrate_server.lua', 'orchestrate_server.lua', '-f')
            
            -- Download orchestrate modules
            print("Downloading orchestrate modules...")
            if not fs.exists('orchestrate') then
                fs.makeDir('orchestrate')
            end
            
            local orchestrateModules = {
                'display.lua', 'state.lua', 'firmware.lua',
                'resource_manager.lua', 'zone_manager.lua', 'message_handler.lua', 'log.lua'
            }
            
            for _, filename in ipairs(orchestrateModules) do
                print("  Updating orchestrate/" .. filename .. "...")
                local targetPath = 'orchestrate/' .. filename
                fs.delete(targetPath)
                shell.run('wget', baseUrl .. 'orchestrate/' .. filename, targetPath, '-f')
            end
            
            -- Update firmware disk if present
            local drive = peripheral.find('drive')
            if drive and drive.isDiskPresent() then
                print("Updating firmware disk...")
                local mountPath = drive.getMountPath()
                if not fs.exists(mountPath .. '/worker') then
                    fs.makeDir(mountPath .. '/worker')
                end
                if not fs.exists(mountPath .. '/worker/modules') then
                    fs.makeDir(mountPath .. '/worker/modules')
                end
                
                -- Update main firmware files
                local firmwareFiles = {'bootstrap.lua', 'quarry.lua', 'dig.lua', 'flex.lua'}
                for _, filename in ipairs(firmwareFiles) do
                    print("  Updating " .. filename .. "...")
                    local targetPath = mountPath .. '/worker/' .. filename
                    fs.delete(targetPath)
                    shell.run('wget', baseUrl .. 'disk/worker/' .. filename, targetPath, '-f')
                end
                
                -- Update worker modules
                local moduleFiles = {
                    'logger.lua', 'gps_utils.lua', 'gps_navigation.lua',
                    'state.lua', 'communication.lua', 'resource_manager.lua', 'firmware.lua'
                }
                for _, filename in ipairs(moduleFiles) do
                    print("  Updating modules/" .. filename .. "...")
                    local targetPath = mountPath .. '/worker/modules/' .. filename
                    fs.delete(targetPath)
                    shell.run('wget', baseUrl .. 'disk/worker/modules/' .. filename, targetPath, '-f')
                end
                
                print("Firmware disk updated!")
            end
            
        elseif COMPONENT_TYPE == "deployer" then
            print("Downloading deployment files...")
            fs.delete('deploy.lua')
            shell.run('wget', baseUrl .. 'orchestrate_deploy.lua', 'deploy.lua', '-f')
            fs.delete('dig.lua')
            shell.run('wget', baseUrl .. 'dig.lua', 'dig.lua', '-f')
            fs.delete('flex.lua')
            shell.run('wget', baseUrl .. 'flex.lua', 'flex.lua', '-f')
            fs.delete('bootstrap.lua')
            shell.run('wget', baseUrl .. 'disk/worker/bootstrap.lua', 'bootstrap.lua', '-f')
            
            -- Download deploy modules
            print("Downloading deploy modules...")
            if not fs.exists('deploy') then
                fs.makeDir('deploy')
            end
            
            local deployModules = {
                'state.lua', 'positioning.lua', 'worker_deployment.lua',
                'chest_manager.lua', 'communication.lua'
            }
            
            for _, filename in ipairs(deployModules) do
                print("  Updating deploy/" .. filename .. "...")
                local targetPath = 'deploy/' .. filename
                fs.delete(targetPath)
                shell.run('wget', baseUrl .. 'deploy/' .. filename, targetPath, '-f')
            end
        end
        
        -- Save new version
        local f = fs.open('.local_version.txt', 'w')
        f.write(remoteVersion)
        f.close()
        
        print('Update complete!')
        sleep(1)
        return true
    else
        print('Already on latest version: ' .. (localVersion or remoteVersion or 'unknown'))
        if remoteVersion and cmp == 1 then
            print('NOTE: Version parsing indicates remote is newer but strings matched; check formatting.')
        end
    end
    
    return false
end

-- Run the check automatically when the script is executed
checkVersion()
