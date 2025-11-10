-- Auto-update script for FancyMiner orchestration system
-- This script checks for updates and re-runs setup if a new version is detected

local COMPONENT_TYPE = "COMPONENT_TYPE_PLACEHOLDER"  -- Will be replaced by setup script

local function checkVersion()
    print("Checking for updates...")
    
    local versionUrl = 'https://raw.githubusercontent.com/NoahGori/FancyMiner-CCTweaked/main/version.txt'
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
    
    if remoteVersion and remoteVersion ~= localVersion then
        print('New version detected: ' .. remoteVersion)
        print('Current version: ' .. (localVersion or 'none'))
        print('Updating ' .. COMPONENT_TYPE .. '...')
        
        -- Download updated files based on component type
        local baseUrl = 'https://raw.githubusercontent.com/NoahGori/FancyMiner-CCTweaked/main/'
        
        if COMPONENT_TYPE == "server" then
            print("Downloading orchestrate_server.lua...")
            fs.delete('orchestrate_server.lua')
            shell.run('wget', baseUrl .. 'orchestrate_server.lua', 'orchestrate_server.lua', '-f')
            
            -- Update firmware disk if present
            local drive = peripheral.find('drive')
            if drive and drive.isDiskPresent() then
                print("Updating firmware disk...")
                local mountPath = drive.getMountPath()
                if not fs.exists(mountPath .. '/worker') then
                    fs.makeDir(mountPath .. '/worker')
                end
                
                local firmwareFiles = {'bootstrap.lua', 'quarry.lua', 'dig.lua', 'flex.lua', 'gps_nav.lua'}
                for _, filename in ipairs(firmwareFiles) do
                    print("  Updating " .. filename .. "...")
                    local targetPath = mountPath .. '/worker/' .. filename
                    fs.delete(targetPath)
                    shell.run('wget', baseUrl .. 'disk/worker/' .. filename, targetPath, '-f')
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
    end
    
    return false
end

-- Export the check function so it can be called from startup
return checkVersion
