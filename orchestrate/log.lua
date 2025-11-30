-- Logging module for orchestration server
-- Provides simple file-based logging and print capture

local Log = {}
local logPath = 'server_log.txt'
local maxSizeBytes = 500 * 1024 -- rotate after ~500KB
local rotateCount = 3

local function rotateIfNeeded()
    if not fs.exists(logPath) then return end
    local size = fs.getSize(logPath)
    if size < maxSizeBytes then return end
    -- Shift older logs
    for i = rotateCount, 1, -1 do
        local old = logPath .. '.' .. i
        local older = logPath .. '.' .. (i + 1)
        if fs.exists(old) then
            if i == rotateCount then
                fs.delete(old)
            else
                fs.move(old, older)
            end
        end
    end
    -- Move current to .1
    fs.move(logPath, logPath .. '.1')
end

local function append(line)
    rotateIfNeeded()
    local f = fs.open(logPath, 'a')
    if f then
        f.writeLine(line)
        f.close()
    end
end

function Log.init(path)
    if path then logPath = path end
    append('=== Log started at ' .. textutils.formatTime(os.time(),'24h') .. ' ===')
end

function Log.write(line)
    append(line)
end

function Log.section(name)
    append('--- ' .. name .. ' ---')
end

function Log.wrapPrint()
    local oldPrint = print
    _G.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do
            parts[#parts+1] = tostring(select(i, ...))
        end
        local line = table.concat(parts, ' ')
        append(line)
        oldPrint(line)
    end
end

return Log
