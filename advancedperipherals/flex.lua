-- Misc Useful Functions
-- Required by most other programs


-------------------------------------------
-- |¯¯] ||   |¯¯] \\//     /\  |¯\ [¯¯]  --
-- | ]  ||_  | ]   ><     |  | | /  ][   --
-- ||   |__] |__] //\\    |||| ||  [__]  --
-------------------------------------------

local log_file = "log.txt"
local options_file = "flex_options.cfg"

-- Defaults; can be changed in config file
local modem_channel = 6464
local name_color
if term.isColor() then
 name_color = "yellow"
else
 name_color = "lightGray"
end --if/else


function getPeripheral(name)
 local x,sides
 sides = { "top", "bottom", "left",
           "right", "front", "back" }
 local periph = {}
 for x=1,#sides do
  if peripheral.getType(sides[x]) == name then
   periph[#periph+1] = sides[x]
  end --if
 end --for
 return periph
end --function


local modem
local hasModem = false
local x = getPeripheral("modem")
if #x > 0 then
 hasModem = true
 modem = peripheral.wrap(x[1])
 modem.open(modem_channel)
end --if

function modemOff()
 local x = getPeripheral("modem")
 if #x > 0 then
  modem.close(modem_channel)
 end --if
end --function


local file
if not fs.exists(log_file) then
 file = fs.open(log_file,"w")
 file.close()
end --if



function optionsExport()
 if fs.exists(options_file) then
  fs.delete(options_file)
 end
 local file
 while file == nil do
  file = fs.open(options_file,"w")
 end
 file.writeLine("# Flex API Options File #\n")
 file.writeLine("modem_channel="
   ..tostring(modem_channel))
 file.writeLine("name_color="..name_color.."\n")
 file.close()
 return true
end --function


function optionsImport()
 if not fs.exists(options_file) then
  return false
 end
 local file
 while file == nil do
  file = fs.open(options_file, "r")
 end
 
 local x = file.readLine()
 while x ~= nil do
  if string.find(x,"modem_channel")==1 then
   modem_channel = tonumber(string.sub(x,15))
  elseif string.find(x,"name_color")==1 then
   name_color = string.sub(x,12)
  end --if/else
  x = file.readLine()
 end --while
 
 file.close()
 return true
end --function


if not optionsImport() then
 optionsExport()
end --if



--==============================--


-- Inventory Condense
function condense(n)
 if n == nil then n = 1 end
 n = math.floor(n)
 if n < 1 or n > 16 then
  n = 1
 end --if
 
 local x,y,slot
 slot = turtle.getSelectedSlot()
 for x=n+1,16 do
  if turtle.getItemCount(x) > 0 then
   
   for y=n,x-1 do
    if turtle.getItemCount(y) == 0 or
       turtle.getItemDetail(x)["name"] ==
       turtle.getItemDetail(y)["name"] and
       turtle.getItemSpace(y) > 0 then
     turtle.select(x)
     turtle.transferTo(y)
    end --if
    if turtle.getItemCount(x) == 0 then
     break
    end --if
   end --for
   
  end --if
 end --for
 turtle.select(slot)
end --function


-- Round n to p decimal places
function round(n,p)
 if p == nil then p = 0 end
 n = n*math.pow(10,p)
 local m = n - math.floor(n)
 if m < 0.5 then
  return math.floor(n) / math.pow(10,p)
 else
  return math.ceil(n) / math.pow(10,p)
 end --if/else
end --function


-- Number to String
-- Optionally a max length if not an integer
function tostr(num,len)
 num = tostring(num)
 local sci = ""
 
 local e = string.find(num,"e")
 if e ~= nil then
  -- Separate exponent from number
  sci = string.sub(num,e,-1)
  num = string.sub(num,1,e-1)
 end --if
 
 if string.find(num,"%.") ~= nil then
  -- Remove extra zeroes from decimal
  while string.sub(num,string.len(num)) == "0" do
   num = string.sub(num,1,string.len(num)-1)..""
  end --while
 end --if
 
 if string.sub(num,-1) == "." then
  -- If all trailing zeroes are gone, erase decimal point
  num = string.sub(num,1,-2)..""
 end --if
 
 if len == nil then
  -- If no max length specified
  return num..sci..""
 end --if
 
 while string.len(num) + string.len(sci) > len do
  -- If too long, cut off a decimal digit
  num = string.sub(num,1,-2)..""
 end --while
 
 return num..sci..""
 
end --function


-- Evaluate Expression
function eval(expression)
 local solution, err = loadstring(
   "return "..expression)
 if err then error(err,2) end
 local sol = pcall(solution)
 if not sol then
  error("Invalid Expression",2)
 end
 return solution()
end --function


-- Press any Key
function getKey()
 local event, key_code = os.pullEvent("key")
 return key_code
end --function
function keyPress() return getKey() end




-------------------------------
--    [¯¯] |¯¯] \\// [¯¯]    --
--     ||  | ]   ><   ||     --
--     ||  |__] //\\  ||     --
-------------------------------
--  /¯]  /¯\  ||    /¯\  |¯\ --
-- | [  | O | ||_  | O | | / --
--  \_]  \_/  |__]  \_/  | \ --
-------------------------------

hexchars = "0123456789ABCDEF"

-- Start with named value, get hex char
function getHex(x)
 if x == nil then
  error("Number expected, got nil", 2)
 end
 x = round(math.log(x)/math.log(2))
 if x < 0 or x > 15 then
  error("Invalid color number", 2)
 end --if
 return string.sub(hexchars,x+1,x+1)
end --function

-- Start with hex char, get named value
function getVal(x)
 local z = string.find(hexchars,x)
 if z == nil then return nil end
 return math.pow(2,z-1)
end --function

local send_depth, print_depth = 0, 0



-------------------------------
-- Multicolor Print Function --
-------------------------------

function printColors(message,textColor)
 local x,y,z,t,skip,margin
 local xmax,ymax = term.getSize()
 local oldColor = term.getTextColor()
 if textColor == nil then
  textColor = oldColor
 else
  
 end --if
 
 margin = ""
 for x=1,print_depth do
  margin = margin.."  "
 end --for
 
 if type(message) == "table" then
  if print_depth == 0 then
   printColors("#0{")
  end --if
  print_depth = print_depth + 1
  
  for x,y in pairs(message) do
   if type(y) == "table" then
    printColors(margin.."  "..tostring(x).." #0= {",textColor)
    printColors(y,textColor)
   else
    printColors(margin.."  "..tostring(x).." #0= #"..
        getHex(textColor)..tostring(y),textColor)
   end --if/else
  end --for
  
  print_depth = print_depth - 1
  printColors(margin.."#0}")
  return
  
 end --if
 
 if type(textColor) == "number" then
  message = "#"..getHex(textColor)
            ..tostring(message)
 end --if
 
 for t=1,string.len(message) do
  
  skip = false
  while string.sub(message,t,t) == "#" and
        not skip do
   
   -- Found legit "#"
   if string.sub(message,t+1,t+1) == "#" then
    message = string.sub(message,1,t)..
          string.sub(message,t+2)..""
    skip = true
    
   else
    textColor = getVal(string.sub(message,t+1,t+1))
    
    if textColor == nil then
     textColor = colors.white
    end --if
    
    -- This bit clears out # escapes
    if t == 1 then
     message = string.sub(message,3)..""
    elseif t < string.len(message) then
     message = string.sub(message,1,t-1)..
           string.sub(message,t+2)..""
    elseif t == string.len(message) then
     message = string.sub(message,1,t-1)..""
    end --if/else
    
   end --if
   
   if t > string.len(message) then
    break
   end --if
   
  end --while (is escape char)
  
  if t > string.len(message) then
   break
  end --if
  
  -- Actually Print Character
  x,y = term.getCursorPos()
  term.setTextColor(textColor)
  
  if textColor == colors.gray then
   --term.setBackgroundColor(colors.lightGray)
   
  elseif textColor == colors.black then
   term.setBackgroundColor(colors.lightGray)
   
  end --if/else
  term.write(string.sub(message,t,t))
  term.setBackgroundColor(colors.black)
  
  if t >= string.len(message) then
   break
  end --if
  
  -- Loop Around to Next Row
  xmax,ymax = term.getSize()
  if string.sub(message,t,t) == "\n" or x >= xmax then
   x = 1
   if y < ymax-1 then
    y = y + 1
   else
    print("")
   end --if/else
  else
   x = x + 1
  end --if/else
  term.setCursorPos(x,y)
  
 end --for
 
 term.setTextColor(oldColor)
 print("")
 
end --function



------------------------------
-- Print/Broadcast Function --
------------------------------

function send(message,textColor)
 local x,y,z,id,nameColor
 local oldColor = term.getTextColor()
 
 local margin = ""
 for x=1,send_depth do
  margin = margin.."  "
 end --for
 
 if type(message) == "table" then
  if send_depth == 0 then
   send("#0{")
  end --if
  send_depth = send_depth + 1
  
  for x,y in pairs(message) do
   if type(y) == "table" then
    send(margin.."  "..tostring(x).." #0= {",textColor)
    send(y,textColor)
   else
    send(margin.."  "..tostring(x).." #0= #"
       ..getHex(textColor)..tostring(y),textColor)
   end --if/else
  end --for
  
  send_depth = send_depth - 1
  send(margin.."#0}")
  return
  
 end --if
 
 
 if message == nil then
  message = "nil"
 end --if
 
 message = tostring(message)
 if textColor == nil then
  textColor = colors.white
 end --if
 nameColor = eval("colors."..name_color)
 
 printColors(message)
 
 file = fs.open(log_file,"a")
 file.writeLine(message)
 file.close()
 
 if hasModem then
  id = "#"..getHex(nameColor)..
       tostring(os.getComputerID()).."#0"
  
  if os.getComputerLabel() ~= nil then
   id = id.."|#"..getHex(nameColor)..
        os.getComputerLabel().."#0"
  end --if
  
  id = id..": #"..getHex(textColor)..
       message..""
  
  modem.transmit(modem_channel,
     modem_channel+1,id)
  sleep(0.1)
 end --if (hasModem)
 
 term.setTextColor(oldColor)
 sleep(0.02)
end --function (print/broadcast)


--================================--


args = {...}

if args[1]=="color" or args[1]=="colors" then
 z = ""
 for x=0,15 do
  y = string.sub(hexchars,x+1,x+1)..""
  z = z.."#"..y..y.."#0 "
 end --for
 printColors(z)
 return
 
elseif args[1] == "edit" then
 shell.run("edit "..options_file)
 optionsImport()
 
end --if/else



-------------------------------------------
-- /¯¯] |¯¯] [¯¯]    |¯\   /\  [¯¯]  /\  --
--| [¯| | ]   ||     |  | |  |  ||  |  | --
-- \__| |__]  ||     |_/  ||||  ||  |||| --
-------------------------------------------


function getBlock(dir)
 dir = dir or "fwd"
 local block,meta
 
 if dir=="fwd" then
  block,meta = turtle.inspect()
 elseif dir=="up" then
  block,meta = turtle.inspectUp()
 elseif dir=="down" then
  block,meta = turtle.inspectDown()
 end
 
 if block then
  block = meta["name"]
  meta = meta["metadata"]
  return block,meta
 else
  return "minecraft:air",nil
 end --if
 
end --function

function getBlockUp()
 return getBlock("up")
end

function getBlockDown()
 return getBlock("down")
end


function isBlock(key,dir)
 if type(key) == "string" then
  key = { key }
 end --if
 if type(key) ~= "table" then
  error("Expected string or table, got "
    ..type(key), 2)
  return false
 end --if
 
 local block = getBlock(dir)
 local x
 for x=1,#key do
  
  if string.find(key[x],":") ~= nil then
   if block == key[x] then
    return true
   end --if
   
  else
   if string.find(block,key[x]) ~= nil then
    return true
   end --if
   
  end --if/else
 end --for
 
 return false
end --function

function isBlockUp(key)
 return isBlock(key, "up")
end

function isBlockDown(key)
 return isBlock(key, "down")
end



local fluid = { "air", "water", "lava",
                "acid", "blood", "poison" }

function isFluid(dir)
 return isBlock(fluid, "fwd")
end

function isFluidUp()
 return isBlock(fluid, "up")
end

function isFluidDown()
 return isBlock(fluid, "down")
end



function isItem(key,slot)
 if key == nil then return false end
 
 local slot_old = turtle.getSelectedSlot()
 if type(slot) ~= "number" then
  slot = slot_old
 end --if
 
 if type(key) == "table" then
  local x
  for x=1,#key do
   if isItem(key[x],slot) then
    return true
   end --if
  end --for
  return false
 end --if
 
 if turtle.getItemCount(slot) == 0 then
  return false
 end --if
 
 local name = turtle.getItemDetail(slot)["name"]
 
 return ( string.find(name,key) ~= nil )
end --function


