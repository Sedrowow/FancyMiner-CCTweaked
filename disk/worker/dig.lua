-- This is an API for digging and
-- keeping track of motion

-- x is right, y is up, z is forward
-- r is clockwise rotation in degrees

-------------------------------------
-- |¯\  [¯¯]  /¯¯]    /\\  |¯\\ [¯¯] --
-- |  |  ][  | [¯|   |  | | /  ][  --
-- |_/  [__]  \\__|   |||| ||  [__] --
-------------------------------------

os.loadAPI("flex.lua")

local options = {
  "outputblocks",
  "blacklist",
  "buildingblocks",
  "dumplist",
  "fluids"  }


-- Fluids, aka blocks treated as "Empty"
options[options[5]] = {
  ":air", "water", "lava", "acid", "poison",
  "sewage", "sludge", "blood"  }


-- Turtle will only drop loot into blocks
-- that contain any of these keywords.
options[options[1]] = {
  "chest", "storage", "box", "turtle",
  "hopper", "dropper", "backpack" }


-- Turtle will avoid breaking (or getting
-- stuck by) these blocks.
-- Disabled by default;
-- enable with dig.doBlacklist()
options[options[2]] = { "chest", "spawn",
    "hopper", "dropper", "portal", "turtle",
    "hive", "openblocks:grave" }
doblacklist = false
function doBlacklist(x)
  if x == nil then
  x = true
  end --if
  doblacklist = (x==true)
end --function


-- Run dig.setBlockSlot(n) to choose
-- a slot to keep building blocks stocked
-- The list of valid keywords:
options[options[3]] = { "cobblestone",
  "minecraft:stone", "dirt", "netherrack",
  "basalt", "soul_s", "magma_block",
  "terracotta", "rock", "sandstone",
  "andesite", "diorite", "granite",
  "marble", "bricks", "smooth_stone",
  "glass" }
function isBuildingBlock(n)
  return flex.isItem(options[options[3]],n)
end --function



-- Turtle will dispose of these blocks
-- at the command dig.doDump()/
-- dig.doDumpUp()/dig.doDumpDown().
-- You may add/remove entries by using
-- dig.addToDumpList(<string>) or
-- dig.removeFromDumpList(<string>).
local dump = options[4]
options[dump] = {}

function resetDumpList(n)
  if n == 0 then
  options[dump] = {}
  else
  options[dump] = {
      "cobblestone", "dirt", "gravel",
      "andesite", "diorite", "granite",
      "netherrack", "soul_s", "magma_block",
      "rotten_flesh", "rock", "marble",
      "limestone", "soapstone", "dolomite",
      "gabbro", "scoria" }
  end --if/else
end --function

function isDumpItem(x)
  return flex.isItem(options["dump"],x)
end --function

function addToDumpList(newkey)
  options[dump][#options[dump]+1] =
      tostring(newkey)
end --function

function removeFromDumpList(key)
  local x,z
  z = {}
  for x=1,#options[dump] do
  if string.find(options[dump][x],key)==nil then
   z[#z+1] = options[dump][x]
  end --if
  end --for
  options[dump] = z
end --function

resetDumpList()


function doDump(z)
  z = z or "fwd"
  local slot = turtle.getSelectedSlot()
  local blockCount = blockStacks
  local x
  for x=1,16 do
  turtle.select(x)
  if flex.isItem(options[dump]) then

    if flex.isItem(options["buildingblocks"]) then
    blockCount = blockCount - 1
    end --if

    if blockCount <= 0 then
    if z == "fwd" then
      turtle.drop()
    elseif z == "down" then
      turtle.dropDown()
    elseif z == "up" then
      turtle.dropUp()
    end --if/else (direction)
    end --if (no more blocks needed)

  end --if dump item
  end --for
  checkBlocks()
  flex.condense(blockSlot)
  turtle.select(slot)
end --function

function doDumpDown() doDump("down") end
function doDumpUp() doDump("up") end




-- Attack entities that block the way
attack = false
function doAttack(x)
  if x == nil then
  x = true
  end --if
  attack = ( x == true )
end --function


function isChest(dir)
  return flex.isBlock(
    options["outputblocks"],dir)
end --function
function isChestUp()
  return isChest("up")
end
function isChestDown()
  return isChest("down")
end


local knownBedrock = {}
function getKnownBedrock()
  return knownBedrock
end --function




------------------------------------
--  /¯\ |¯\[¯¯][¯¯] /¯\ |\\ ||/¯¯\\ --
-- | O || / ||  ][ | O || \\ |\_¯\\ --
--  \\_/ ||  || [__] \\_/ || \\|\\__/ --
------------------------------------
--      |¯¯][¯¯]||  |¯¯]          --
--      | ]  ][ ||_ | ]          --
--      ||  [__]|__]|__]          --
------------------------------------

local options_file = "dig_options.cfg"

function optionsEdit()
  shell.run("edit "..options_file)
  optionsImport()
end --function


function optionsImport()
  if not fs.exists(options_file) then
  return false
  end --if
  local file,x,y,z

  for y=1,#options do
  z = options[y]
  file = fs.open(options_file,"r")

  x = file.readLine()
  while x ~= nil do

    if x == "["..z.."]" then
    options[z] = {}
    x = file.readLine()
    while x ~= "[/"..z.."]" and x ~= nil do
      options[z][#options[z]+1] = x
      x = file.readLine()
    end --while
    break
    end --if

    x = file.readLine()
  end --while

  file.close()
  end --for

  return true
end --function


function optionsExport()
  if fs.exists(options_file) then
  fs.delete(options_file)
  end --if

  local file,x,y,z
  while file == nil do
  file = fs.open(options_file,"w")
  end --while
  file.writeLine("# Dig API Options File #\n")

  for y=1,#options do
  z = options[y]
  file.writeLine("["..z.."]")
  for x=1,#options[z] do
    file.writeLine(options[z][x])
  end --for
  file.writeLine("[/"..z.."]\n")
  end --for

  file.close()
  return true
end --function


if not optionsImport() then
  optionsExport()
end --if




----------------------------------
--    /¯\\  /\\  ||  || |¯¯]     --
--    \\_¯\\ |  |  \\//  | ]     --
--    \\__/ ||||    \\/  |__]     --
----------------------------------
-- |¯\\  /\\  /¯] ||// || || |¯\\ --
-- | < |  | | [  | <  ||_|| | / --
-- |_/ ||||  \\_] ||\\\\  \\__| || --
----------------------------------

local save = {"dig_save", ".cfg"}
local savefile = save[1] .. save[2]
local start = {"startup", ".lua"}
local startfile = start[1] .. start[2]

function saveExists()
  return ( fs.exists(startfile) and
    fs.exists(savefile) )
end --function

function saveClear()
  if fs.exists(startfile) then
  fs.delete(startfile)
  end --if
end --function
function clearSave()
  saveClear()
end --function


local args = {...}
if #args > 0 then
  local a,file

  if args[1] == "save" then
  if not saveExists() then
    flex.send("Nothing to save",colors.yellow)
    return
  end --if
  if #args == 1 then
    a = 1
    while fs.exists(start[1].."_"..
        tostring(a)..start[2]) do
    a = a + 1
    end --while
  else -- #args > 1
    a = args[2]
  end --if
  a = tostring(a)
  shell.run("mv "..startfile.." "..
      start[1].."_"..a..start[2])
  shell.run("mv "..savefile.." " ..
      save[1].."_"..a..save[2])
  flex.send("Enter 'dig load "..a..
      "' to restore",colors.lightBlue)

  elseif args[1] == "load" then
  if #args == 1 then
    flex.send("Please specify load file",
      colors.red)
    return
  end --if
  saveClear()
  a = args[2]
  shell.run("mv "..start[1].."_"..a..
      start[2].." "..startfile)
  shell.run("mv "..save[1].."_"..a..
      save[2].." "..savefile)
  flex.send("Save files restored",
      colors.lightBlue)

  elseif args[1] == "clear" then
  saveClear()
  flex.send("Save files cleared",
      colors.lightBlue)

  elseif args[1] == "edit" then
  optionsEdit()

  else -- not save/load/clear/edit
  flex.send("Invalid parameter: "..
      args[1],colors.red)

  end --if/else save/load
  return
end --function


-----------------------------------------
-- ||   /¯\\  /¯] /\\ [¯¯][¯¯] /¯\\ |\\ || --
-- ||_ | O || [ |  | ||  ][ | O || \\ | --
-- |__] \\_/ |||||_/ //  \\__/||||  \\/  |__]--
-----------------------------------------
--||  || /\\ |¯\\[¯¯] /\\ |¯\\||  |¯¯]/¯¯\\ --
-- \\// |  || / ][ |  || <||_ | ] \\_¯\\ --
--  \\/  ||||| \\[__]|||||_/|__]|__]\\__/ --
-----------------------------------------

xdist = 0
xlast = -1
xmin = 0
xmax = 0

ydist = 0
ylast = -1
ymin = 0
ymax = 0

zdist = 0
zlast = -1
zmin = 0
zmax = 0

rdist = 0
rlast = -1

lastmove = "r-"
dugtotal = 0
blocks_processed_total = 0 -- Added: Variable to track total blocks processed

function getx() return xdist end
function gety() return ydist end
function getz() return zdist end
function getr() return rdist end

function setx(x) xdist = x end
function sety(y) ydist = y end
function setz(z) zdist = z end
function setr(r) rdist = r end

function getxmin() return xmin end
function getxmax() return xmax end
function getymin() return ymin end
function getymax() return ymax end
function getzmin() return zmin end
function getzmax() return zmax end

function setxmin(x) xmin = x end
function setxmax(x) xmax = x end
function setymin(y) ymin = y end
function setymax(y) ymax = y end
function setzmin(z) zmin = z end
function setzmax(z) zmax = z end

function getxlast() return xlast end
function getylast() return ylast end
function getzlast() return zlast end
function getrlast() return rlast end

function setxlast(x) xlast = x end
function setylast(y) ylast = y end
function setzlast(z) zlast = z end
function setrlast(r) rlast = r end

function getlast() return lastmove end
function setlast(lm) lastmove = lm end

function getdug() return dugtotal end
function setdug(d) dugtotal = d end

-- Added: Getter and setter for blocks_processed_total
function getBlocksProcessed() return blocks_processed_total end
function setBlocksProcessed(d) blocks_processed_total = d end
function addBlocksProcessed(d) blocks_processed_total = blocks_processed_total + d end


-------------------------------------------
--||   /¯\\  /\\ |¯\\   ///¯¯\\ /\\ ||  |||¯¯]--
--||_ | O ||  ||  | // \\_¯\\|  | \\// | ] --
--|__] \\_/ |||||_/ //  \\__/||||  \\/  |__]--
-------------------------------------------

function location()
  return
  { xdist, ydist, zdist, rdist,
    xmin, xmax, ymin, ymax, zmin, zmax,
    xlast, ylast, zlast, rlast,
    lastmove, dugtotal,
    blocks_processed_total -- Added: Include blocks_processed_total
     }
end


function saveCoords(loc,save)
  loc = loc or location()
  save = save or savefile
  local file,x

  --if fs.exists(save.."_old") then
  -- fs.delete(save.."_old")
  --end
  --if fs.exists(save) then
  --fs.move(save, save.."_old")
  --end

  while file == nil do
  file = fs.open(save,"w")
  end --while

  for x=1,#loc do
  file.writeLine(tostring(loc[x]))
  -- Removed the explicit file.flush() here.
  -- File buffering is usually handled by the system
  -- and flushes on close or when the buffer is full.
  end --for

  file.close()
end --function



function loadCoords(save)
  save = save or savefile
  local file
  if fs.exists(save) then
  while file == nil do
    file = fs.open(save,"r")
  end --while
  xdist = tonumber(file.readLine() or xdist)
  ydist = tonumber(file.readLine() or ydist)
  zdist = tonumber(file.readLine() or zdist)
  rdist = tonumber(file.readLine() or rdist)
  xmin = tonumber(file.readLine() or xmin)
  xmax = tonumber(file.readLine() or xmax)
  ymin = tonumber(file.readLine() or ymin)
  ymax = tonumber(file.readLine() or ymax)
  zmin = tonumber(file.readLine() or zmin)
  zmax = tonumber(file.readLine() or zmax)
  xlast = tonumber(file.readLine() or xlast)
  ylast = tonumber(file.readLine() or ylast)
  zlast = tonumber(file.readLine() or zlast)
  rlast = tonumber(file.readLine() or rlast)
  lastmove = file.readLine() or lastmove
  dugtotal = tonumber(file.readLine() or dugtotal)
  -- Added: Load blocks_processed_total from the save file
  blocks_processed_total = tonumber(file.readLine() or blocks_processed_total)

  -- Ensure all lines are read if the file format changed
  -- while file.readLine() ~= nil do end -- Read and discard any extra lines
  file.close()
  return true

  else
  --if fs.exists(save.."_old") then
  -- loadCoords(save.."_old")
  -- return true
  --end

  return false
  end --if/else

end -- function



function makeStartup(command, args)
  command = tostring(command)
  args = args or {}
  local x
  for x=1,#args do
  command = command.." "..args[x]
  end --for

  local file = fs.open(startfile,"w")
  file.writeLine("print(\"> "..command.."\")")
  file.writeLine("for x=5,1,-1 do")
  file.writeLine(" term.write(tostring(x)..\" \")")
  file.writeLine(" sleep(1)")
  file.writeLine("end --for")
  file.writeLine("print(\" \")")
  file.writeLine("shell.run(\""..command.."\")")
  file.close()
end --function




-------------------------------------
--[¯¯]|¯\\ /\\  /¯]||//[¯¯]|\\ || /¯¯]--
-- || | /|  || [ | <  ][ | \\ | ||  --
-- || | \\|||| \\_]|\\\\\[__]|| \\| \\__|--
-------------------------------------

function update(n)

  if n=="fwd" then

  if rdist%360 == 0 then -- 12:00
    zdist = zdist + 1
    zlast = 1
    lastmove = "z+"

  elseif rdist%360 == 90 then -- 3:00
    xdist = xdist + 1
    xlast = 1
    lastmove = "x+"

  elseif rdist%360 == 180 then -- 6:00
    zdist = zdist - 1
    zlast = -1
    lastmove = "z-"

  elseif rdist%360 == 270 then -- 9:00
    xdist = xdist - 1
    xlast = -1
    lastmove = "x-"

  end --if/else


  elseif n=="back" then

  if rdist%360 == 0 then -- 12:00
    zdist = zdist - 1
    zlast = -1
    lastmove = "z-"

  elseif rdist%360 == 90 then -- 3:00
    xdist = xdist - 1
    xlast = -1
    lastmove = "x-"

  elseif rdist%360 == 180 then -- 6:00
    zdist = zdist + 1
    zlast = 1
    lastmove = "z+"

  elseif rdist%360 == 270 then -- 9:00
    xdist = xdist + 1
    xlast = 1
    lastmove = "x+"

  end --if/else


  elseif n=="up" then
  ydist = ydist + 1
  ylast = 1
  lastmove = "y+"

  elseif n=="down" then
  ydist = ydist - 1
  ylast = -1
  lastmove = "y-"

  elseif n=="right" then
  rdist = rdist + 90
  rlast = 1
  lastmove = "r+"
  while rdist > 999 do
    rdist = rdist - 360
  end --while

  elseif n=="left" then
  rdist = rdist - 90
  rlast = -1
  lastmove = "r-"
  while rdist < -999 do
    rdist = rdist + 360
  end --while

  end --if/else


  if xdist < xmin then
  xmin = xdist
  elseif xdist > xmax then
  xmax = xdist
  end

  if ydist < ymin then
  ymin = ydist
  elseif ydist > ymax then
  ymax = ydist
  end

  if zdist < zmin then
  zmin = zdist
  elseif zdist > zmax then
  zmax = zdist
  end

  saveCoords()

end




------------------------------------------
-- |\/| /¯\\ ||  |||¯¯]|\\/||¯¯]|\\ ||[¯¯] --
-- |  || O | \\// | ] |  || ] | \\ | ||  --
-- |||| \\_/    \\/  |__]|||||__]|| \\| ||  --
------------------------------------------


stuck = false
function isStuck()
  return stuck
end
stuckDir = "none"
function getStuckDir()
  return stuckDir
end


function left(n)
  n = (n or 1)
  if n < 0 then
  return right(-n)
  end --if
  local x
  for x=1,n do
  turtle.turnLeft()
  update("left")
  end --if
  -- Rotations don't represent processed blocks in the same way as linear movement
  return true
end --function


function right(n)
  n = (n or 1)
  if n < 0 then
  return left(-n)
  end --if
  local x
  for x=1,n do
  turtle.turnRight()
  update("right")
  end --if
  -- Rotations don't represent processed blocks in the same way as linear movement
  return true
end --function



local unbreak = "Unbreakable block detected"
local protect = "Cannot break protected block"



function up(n)
  n = n or 1
  if n < 0 then return down(-n) end

  local x,a,b,t
  for x=1, n do
    refuel()
    
    if turtle.detectUp() then
      -- If there's a block above, we need to dig it
      while not turtle.up() do
        a,b = turtle.digUp()
        if a then
          dugtotal = dugtotal + 1 -- Count successful dig
          addBlocksProcessed(1)
        end
        if b then break end
        if attack then turtle.attackUp() end
      end
      -- Count the movement itself as processed
      addBlocksProcessed(1)
    else
      -- No block above, just move
      if turtle.up() then
        addBlocksProcessed(1)
      else
        return false
      end
    end
    
    update("up")
  end
  return true
end

function down(n)
  n = n or 1
  if n < 0 then return up(-n) end

  local x,a,b,t
  for x=1, n do
    refuel()
    
    if turtle.detectDown() then
      -- If there's a block below, we need to dig it
      while not turtle.down() do
        a,b = turtle.digDown()
        if a then
          dugtotal = dugtotal + 1 -- Count successful dig
          addBlocksProcessed(1)
        end
        if b then break end
        if attack then turtle.attackDown() end
      end
      -- Count the movement itself as processed
      addBlocksProcessed(1)
    else
      -- No block below, just move
      if turtle.down() then
        addBlocksProcessed(1)
      else
        return false
      end
    end
    
    update("down")
  end
  return true
end

function fwd(n)
  n = n or 1
  if n < 0 then return back(-n) end

  local x,a,b,t
  for x=1, n do
    refuel()
    
    if turtle.detect() then
      -- If there's a block in front, we need to dig it
      while not turtle.forward() do
        a,b = turtle.dig()
        if a then
          dugtotal = dugtotal + 1 -- Count successful dig
          addBlocksProcessed(1)
        end
        if b then break end
        if attack then turtle.attack() end
      end
      -- Count the movement itself as processed
      addBlocksProcessed(1)
    else
      -- No block in front, just move
      if turtle.forward() then
        addBlocksProcessed(1)
      else
        return false
      end
    end
    
    update("fwd")
  end
  return true
end



function back(n)
  n = n or 1
  if n < 0 then
  return fwd(-n)
  end --if

  local x,turn
  turn = false
  for x=1,n do
  -- **MODIFIED: Increment dugtotal and blocks_processed_total on successful move**
  if turtle.back() then
      update("back")
      dugtotal = dugtotal + 1 -- Count successful move as dug/processed
      addBlocksProcessed(1) -- Count successful move as processed
  else
    turn = true
    gotor(rdist+180)
    if not fwd() then return false end
  end --if/else
  -- Removed addBlocksProcessed(1) here, handled above in the successful move check
  end --for

  if turn then gotor(rdist-180) end
  return true
end --function



function dig(x)
  local success = false
  x = x or "fwd"
  
  if x == "fwd" then
    if turtle.detect() then
      while turtle.dig() do
        dugtotal = dugtotal + 1
        addBlocksProcessed(1)
        success = true
      end
    end
  elseif x == "up" then
    if turtle.detectUp() then
      while turtle.digUp() do
        dugtotal = dugtotal + 1
        addBlocksProcessed(1)
        success = true
      end
    end
  elseif x == "down" then
    if turtle.detectDown() then
      while turtle.digDown() do
        dugtotal = dugtotal + 1
        addBlocksProcessed(1)
        success = true
      end
    end
  end
  
  return success
end

function digUp() dig("up") end
function digDown() dig("down") end



-- Agressive placement functions

function place()
  local x = flex.getBlock("fwd")
  local t = os.time()
  while not turtle.place()
        and flex.isBlock(options["fluids"]) do
  if attack then
    turtle.attackUp()
    turtle.attack()
    turtle.attackDown()
  end --if

  if (os.time()-t)/24*20*60 > 20 then
    local z = { getx(), gety(),
          getz(), getr()%360 }
    if z[4] == 0 then
    z[3] = z[3] + 1
    elseif z[4] == 90 then
    z[1] = z[1] + 1
    elseif z[4] == 180 then
    z[3] = z[3] - 1
    elseif z[4] == 270 then
    z[1] = z[1] - 1
    end --if/else

    flex.send("#1End of world detected#0: {#8"..
      tostring(z[1]).."#0,#8"..
      tostring(z[2]).."#0,#8"..
      tostring(z[3]).."#0}")
    knownBedrock[#knownBedrock+1] =
      { z[1], z[2], z[3] }

    stuck = true
    stuckDir = "fwd"
    return false
  end --if

  sleep(0.1)
  x = flex.getBlock()
  end --while
  if turtle.getSelectedSlot() == blockSlot then
  checkBlocks()
  end --if
  -- Placing a block doesn't process a quarry location, so no increment here.
  return true
end --function


function placeUp()
  local x = flex.getBlockUp()
  local t = os.time()
  while not turtle.placeUp()
        and flex.isBlockUp(options["fluids"]) do
  if attack then
    turtle.attack()
    turtle.attackUp()
  end --if

  if (os.time()-t)/24*20*60 > 20 then
    flex.send("#1Edge of world detected#0: {#8"..
      tostring(getx()).."#0,#8"..
      tostring(gety()+1).."#0,#8"..
      tostring(getz()).."#0}")
    knownBedrock[#knownBedrock+1] = {
      getx(), gety()+1, getz() }

    stuck = true
    stuckDir = "up"
    return false
  end --if

  sleep(0.1)
  x = flex.getBlockUp()
  end --while
  if turtle.getSelectedSlot == blockSlot then
  checkBlocks()
  end --if
  -- Placing a block doesn't process a quarry location, so no increment here.
  return true
end --function


function placeDown()
  local x = flex.getBlockDown()
  local t = os.time()
  while not turtle.placeDown()
        and flex.isBlockDown(options["fluids"]) do
  if attack then
    turtle.attack()
    turtle.attackDown()
  end --if

  if (os.time()-t)/24*20*60 > 20 then
    flex.send("#1Edge of world detected#0: {#8"..
      tostring(getx()).."#0,#8"..
      tostring(gety()-1).."#0,#8"..
      tostring(getz()).."#0}")
    knownBedrock[#knownBedrock+1] = {
      getx(), gety()-1, getz() }
    up()
    placeDown()
    ymin = gety()

    stuck = true
    stuckDir = "down"
    return false
  end --if

  sleep(0.1)
  x = flex.getBlockDown()
  end --while
  if turtle.getSelectedSlot() == blockSlot then
  checkBlocks()
  end --if
  -- Placing a block doesn't process a quarry location, so no increment here.
  return true
end --function




----------------------------
--  /¯¯]  /¯\\  [¯¯]  /¯\\ --
-- | [¯| | O |  ||  | O | --
--  \\__| \\_/   ||   \\_/ --
----------------------------


function gotor(r)
  if r == nil then
  error("Number expected, got nil", 2)
  return
  end --if
  local x = (r-rdist)%360
  -- X is the target direction relative to current rotation

  if x == 90 then
  right()
  elseif x == 180 then
  left(rlast*2)
  -- Rotate opposite to last rotation
  elseif x == 270 then
  left()
  elseif x ~= 0 then
  error("Invalid rotation parameter", 2)
  return false
  end --if/else

  -- Rotations don't represent processed blocks in the same way as linear movement
  return true
end --function



function gotoy(y)
  if y == nil then
    error("Number expected, got nil", 2)
    return
  end
  
  -- Add skip depth validation
  if type(skip) == "number" and y > -skip then
    y = -skip -- Don't go above skip depth
  end
  
  while ydist < y do
    if not up() then return false end
  end
  while ydist > y do
    if not down() then return false end
  end
  return true
end


function gotox(x)
  if x == nil then
  error("Number expected, got nil", 2)
  return
  end --if

  if xdist < x then
  if rdist%360 == 270 then -- Facing West, need to go East
    gotor(90) -- Turn East
    -- Assume each step forward processes 1 block worth of movement in that direction
    while xdist < x do -- Move East until x is reached
        if not fwd() then return false end
    end
    return true
  else -- Not facing West, need to go East
    gotor(90) -- Turn East
    -- Assume each step forward processes 1 block worth of movement in that direction
    while xdist < x do -- Move East until x is reached
        if not fwd() then return false end
    end
    return true
  end
  end

  if xdist > x then
  if rdist%360 == 90 then -- Facing East, need to go West
    gotor(270) -- Turn West
    -- Assume each step forward processes 1 block worth of movement in that direction
    while xdist > x do -- Move West until x is reached
        if not fwd() then return false end
    end
    return true
  else -- Not facing East, need to go West
    gotor(270) -- Turn West
    -- Assume each step forward processes 1 block worth of movement in that direction
    while xdist > x do -- Move West until x is reached
        if not fwd() then return false end
    end
    return true
  end
  end

  return true
end


function gotoz(z)
  if z == nil then
  error("Number expected, got nil", 2)
  return
  end --if

  if zdist < z then
  if rdist%360 == 180 then -- Facing South, need to go North
    gotor(0) -- Turn North
    -- Assume each step forward processes 1 block worth of movement in that direction
    while zdist < z do -- Move North until z is reached
        if not fwd() then return false end
    end
    return true
  else -- Not facing South, need to go North
    gotor(0) -- Turn North
    -- Assume each step forward processes 1 block worth of movement in that direction
    while zdist < z do -- Move North until z is reached
        if not fwd() then return false end
    end
    return true
  end
  end

  if zdist > z then
  if rdist%360 == 0 then -- Facing North, need to go South
    gotor(180) -- Turn South
    -- Assume each step forward processes 1 block worth of movement in that direction
    while zdist > z do -- Move South until z is reached
        if not fwd() then return false end
    end
    return true
  else -- Not facing North, need to go South
    gotor(180) -- Turn South
    -- Assume each step forward processes 1 block worth of movement in that direction
    while zdist > z do -- Move South until z is reached
        if not fwd() then return false end
    end
    return true
  end
  end

  return true
end


function goto(x,y,z,r,lm)
  if type(x) == "table" then
  if #x < 4 then
    error("Invalid Goto Table",2)
  end
  y = x[2]
  z = x[3]
  r = x[4]
  lm = x[15]
  -- Also load blocks_processed_total if it exists in the table
  if #x >= 17 then blocks_processed_total = x[17] end -- Added
  x = x[1]
  end
  gotox(x or 0)
  gotoz(z or 0)
  gotor(r or 0)
  gotoy(y or 0)
  if lm~=nil then setlast(lm) end
end




---------------------------------------
-- |¯¯]|| |||¯¯]||     |¯\|¯\\ /¯\\     --
-- | ] ||_||| ] ||_   | /| /| O | == --
-- ||   \\__||__]|__] || | \\ \\_/     --
---------------------------------------
--   /¯]|¯¯]/¯¯\\/¯¯\\[¯¯]|\\ || /¯¯]   --
--  | [ | ] \\_¯\\\_¯\\ ][ | \\ || [¯|   --
--   \\_]|__]\\__/\\__/\\[__]|\\|\\ \\__|   --
---------------------------------------

fuelSlot = {1,16}

function getFuelSlot()
  return fuelSlot[1],fuelSlot[2]
end --function

function setFuelSlot(a,b)
  if a == nil then
  return false
  end --if
  b = b or a
  if a < b then
  fuelSlot = {a,b}
  else
  fuelSlot = {b,a}
  end --if/else
  return true
end --function



function refuel(b)
  b = b or 1
  b = math.min(b, turtle.getFuelLimit())
  local a,x,z,slot
  slot = turtle.getSelectedSlot()
  a = true

  while turtle.getFuelLevel() < b do
  for x=fuelSlot[1],fuelSlot[2] do
    turtle.select(x)
    if turtle.refuel(1) then break end
    if x == fuelSlot[2] and a then
    if fuelSlot[1] == fuelSlot[2] then
	    flex.send("Waiting for fuel in "..
	      "slot "..tostring(fuelSlot[1])..
	      "...", colors.pink)
	   else
    flex.send("Waiting for fuel in "..
      "slots "..tostring(fuelSlot[1])..
      "-"..tostring(fuelSlot[2])..
      "...", colors.pink)
	   end --if/else
    a = false
    end --if
  end --for
  end --while

  if not a then
  flex.send("Thanks!",colors.lime)
  end --if
  turtle.select(slot)

end --function




local fuelvalue = {}
local fuelfile = "dig_fuel.cfg"
local file, line
if fs.exists(fuelfile) then
  file = fs.open(fuelfile, "r")
  line = file.readLine()
  while line ~= nil do
  fuelvalue[line] = tonumber(file.readLine())
  line = file.readLine()
  end --while
  file.close()
else
  file = fs.open(fuelfile, "w")
  file.close()
end --if/else


function checkFuelValue(x)
  if type(x) ~= "number" then
  local x = turtle.getSelectedSlot()
  end --if
  if turtle.getItemCount(x) == 0 then
  return 0
  end --if

  local a,b,c,d
  a = turtle.getItemDetail(x)["name"]
  b = fuelvalue[a]

  if b == nil then
  c = turtle.getFuelLevel()
  turtle.select(x)
  turtle.refuel(1)
  d = turtle.getFuelLevel() - c
  fuelvalue[a] = d

  file = fs.open(fuelfile, "a")
  file.writeLine(a)
  file.writeLine(tostring(d))
  file.close()

  if turtle.getItemCount(x) == 0 then
    return 0
  else
    return d
  end --if
  end --if

  return b
end --function




blockSlot = 0
blockStacks = 1
function getBlockSlot() return blockSlot end
function setBlockSlot(n) blockSlot = n end
function getBlockStacks() return blockStacks end
function setBlockStacks(n) blockStacks = n end


function checkBlocks()
  if blockSlot == 0 then return end
  local x,docondense

  if not flex.isItem(options["buildingblocks"],blockSlot) then
  if turtle.getItemCount(blockSlot) > 0 then
    for x=blockSlot+1,16 do
    if turtle.getItemCount(x) == 0 then
      turtle.select(blockSlot)
      turtle.transferTo(x)
      break
    end --if
    end --for
  end --if
  end --if

  if turtle.getItemCount(blockSlot) == 0 then
  for x=1,16 do
    if flex.isItem(options["buildingblocks"],x) then
    turtle.select(x)
    turtle.transferTo(blockSlot)
    turtle.select(blockSlot)
	   break
    end --if
  end --for
  flex.condense(blockSlot)
  end --if

  turtle.select(blockSlot)
end --function



function blockLava(dir)
  if not flex.isBlock("lava",dir) then
  return
  end --if
  local slot = turtle.getSelectedSlot()
  checkBlocks()
  turtle.select(blockSlot)
  if dir == "up" then
  turtle.placeUp()
  elseif dir == "down" then
  turtle.placeDown()
  else
  turtle.place()
  end --if/else
  turtle.select(slot)
  -- Placing a block doesn't process a quarry location, so no increment here.
end --function

function blockLavaUp() blockLava("up") end
function blockLavaDown() blockLava("down") end




-- Organize Inventory/Fuel
--    C
--  CTQQQ
--    QQQQ
-- (Chest/Turtle/Quarry)

function dropNotFuel()

  local slot = turtle.getSelectedSlot()
  local a,b,c,f,x,y,z
  local crafty,usedbucketalready,blocksPresent
  turtle.select(1)
  if turtle.getItemCount(1) > 1 then
  flex.condense()
  end --if

  -- Check there's inventory to place loot
  a = true
  while true do
  if isChest() then
    break
  end
  if a then
    flex.send("Output inventory not found!",
      colors.red)
    a = false
  end --if
  sleep(1)
  end --while
  if not a then
  flex.send("Thanks!",colors.lightBlue)
  end --if


  -- Drop off what's not fuel
  blocksPresent = blockStacks
  for x=1,16 do
  turtle.select(x)
  if not turtle.refuel(0) then
    if flex.isItem(options["buildingblocks"]) then
    if blocksPresent <= 0 then
      turtle.drop()
    else
      blocksPresent = blocksPresent - 1
    end --if/else
    else
    turtle.drop()
    end --if/else
  end --if
  end --for
  checkBlocks()
  turtle.select(1)
  -- Retrieve surplus fuel from fuel chest
  while turtle.suckUp() do sleep(0) end
  if turtle.getItemCount(fuelSlot[1]) > 0 then
  flex.condense()
  end --if


  -- Craft coal into blocks
  if peripheral.find("workbench") and isChestUp() then

  z = 0
  for x=1,16 do
    if turtle.getItemCount(x) > 0 and
      turtle.getItemDetail(x)["name"]
      ~= "minecraft:coal" then
    turtle.select(x)
    turtle.dropUp()
    end --if
    z = z + turtle.getItemCount(x)
  end --for

  if z >= 9 then

    y = 13
    for x=1,12 do
    turtle.select(x)
    while turtle.getItemCount(x) > 0 do
      if y <= 16 then
      turtle.transferTo(y)
      else
      z = z - turtle.getItemCount(x)
      turtle.dropUp()
      end --if/else
      if turtle.getItemCount(x) > 0 then
      y = y + 1
      end --if
    end --while
    end --for

    y = math.floor(z/9)
    turtle.select(13)
    turtle.dropUp(z%9)
    a = 13
    b = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
    for x=1,#b do
    if turtle.getItemCount(a) < y then
      turtle.select(a+1)
      turtle.transferTo(a,
        y - turtle.getItemCount(a))
    end --if
    turtle.select(a)
    turtle.transferTo(b[x], y)
    if turtle.getItemCount(a) == 0 then
      a = a + 1
    end --if
    end --for

    if peripheral.getType("left") == "workbench" then
    crafty = peripheral.wrap("left")
    else
    crafty = peripheral.wrap("right")
    end --if/else
    turtle.select(1)
    crafty.craft()

  end --if
  while turtle.suckUp() do sleep(0) end
  checkBlocks()

  end --if


  --Tally up fuel sources
  z = {} -- slot #
  f = {} -- amount of fuel
  usedbucketalready = false

  for x=1,16 do
  turtle.select(x)

  if turtle.refuel(0) then
    y = turtle.getItemCount()

    if flex.isItem("bucket") and y==1 then
    if not usedbucketalready then
      -- Only use buckets one at a time
      turtle.refuel()
      usedbucketalready = true
      turtle.drop()
    end

    else -- Not a bucket
    a = checkFuelValue(x)
    if a > 0 then
      z[#z+1] = x
      f[#z] = a*turtle.getItemCount(x)
    end --if

    end --if/else (is bucket)

  end --if (is fuel)
  end --for (slots)


  -- Choose best fuel available
  a = 0
  for x=1, #f do
  a = math.max(a,f[x])
  end --for
  for x=1, #f do
  if f[x] == a then
    if z[x] > 1 then
    for b=2,16 do
      if turtle.getItemCount(b) == 0 then
      turtle.select(1)
      turtle.transferTo(b)
      break
      end --if
    end --for
    turtle.select(z[x])
    turtle.transferTo(1)
    end --if
    break
  end --if
  end --for


  -- Deposit surplus fuel
  for x=fuelSlot[1]+1,16 do
  if turtle.getItemCount(x) > 0 then

    turtle.select(x)
    if turtle.refuel(0) then
    if isChestUp() then
      -- Place in fuel chest
      turtle.dropUp()
    end --if
    if turtle.getItemCount() > 0 then
      -- Fuel chest is full or absent
      turtle.drop()
    end --if
    end --if

  end --if (more than zero items)
  end --for (all slots after fuel slot)

  turtle.select(fuelSlot[1])
  if not turtle.refuel(0) then
  for x=fuelSlot[1]+1,16 do
    turtle.transferTo(x)
    if turtle.getItemCount() == 0 then
    break
    end --if
  end --for
  end --if

  flex.condense(fuelSlot[1]+1)

  if turtle.getItemCount(16) > 0 then
  flex.send("Inventory full!",colors.red)
  turtle.select(16)
  while not turtle.drop() do sleep(5) end
  flex.send("Inventory has room!",colors.lightBlue)
  turtle.select(slot)
  return dropNotFuel()
  end --if

  turtle.select(slot)

end --function dropNotFuel()