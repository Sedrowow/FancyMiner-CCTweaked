version = 20250410.0800

local tkVersion = version -- otherwise over-written by clsTurtle when loaded


args = {...} -- eg "farm", "tree"

local menu, T
--[[
Computercraft started with mc version 1.7.10 and went to 1.8.9
ccTweaked started around mc 1.12.2 and currently at 1.21.1
mc 1.18 onwards has new blocks and bedrock at -64, so needs to be taken into account.
_HOST = The ComputerCraft and Minecraft version of the current computer environment.
For example, ComputerCraft 1.93.0 (Minecraft 1.15.2).
]]
local dbug = false -- debug is reserved word
local bedrock = 0
local netherBedrock = 0
local ceiling = 255
local deletesWater = false
local brick = "minecraft:nether_brick" -- pre 1.16+ name
local ccMajorVersion = _HOST:sub(15, _HOST:find("Minecraft") - 2) --eg ComputerCraft 1.93.0 (Minecraft 1.15.2)
local ccMinorVersion = 0
local barrelItems = nil	-- list of items and the barrels where they are usually found
local chestItems = nil	-- list of items and the chests where they are usually found
--[[
Netherite level stand on 14
Chunk borders F3+G or:
math.floor(x / 16) * 16 add 16 for each border. same for z
]]
function string:split(sSeparator, nMax, bRegexp, noEmpty)
	--[[return a table split with sSeparator. noEmpty removes empty elements
		use: tblSplit = SplitTest:split('~',[nil], [nil], false) or tblSplit = string.split(SplitTest, '~')]]   
	assert(sSeparator ~= '','separator must not be empty string')
	assert(nMax == nil or nMax >= 1, 'nMax must be >= 1 and not nil')
	if noEmpty == nil then noEmpty = true end

	local aRecord = {}
	local newRecord = {}
	-- self refers to the 'string' being split
	if self:len() > 0 then
		local bPlain = not bRegexp
		nMax = nMax or -1

		local nField, nStart = 1, 1
		local nFirst,nLast = self:find(sSeparator, nStart, bPlain)
		while nFirst and nMax ~= 0 do
			aRecord[nField] = self:sub(nStart, nFirst-1)
			nField = nField+1
			nStart = nLast+1
			nFirst,nLast = self:find(sSeparator, nStart, bPlain)
			nMax = nMax-1
		end
		aRecord[nField] = self:sub(nStart)
		
		if noEmpty then --split on newline preserves empty values
			for i = 1, #aRecord do
				if aRecord[i] ~= "" then
					table.insert(newRecord, aRecord[i])
				end
			end
		else
			newRecord = aRecord
		end
	end
	
	return newRecord
end

if tonumber(ccMajorVersion) == nil then -- 1.93.0 NAN
	--ccMajorVersion = ccMajorVersion:sub(1, ccMajorVersion:find(".", 3, true) - 1)
	local parts = ccMajorVersion:split(".")
	ccMajorVersion = parts[1]
	if parts[2] ~= nil then
		ccMajorVersion = ccMajorVersion.."."..parts[2]
	end
	ccMajorVersion = tonumber(ccMajorVersion)
	if parts[3] ~= nil then
		ccMinorVersion = tonumber(parts[3])
	end
end

local mcMajorVersion = _HOST:sub(_HOST:find("Minecraft") + 10, _HOST:find("\)") - 1) -- eg 1.18 or 1.20 -> 1.18, 1.20
local mcMinorVersion = 0
if tonumber(mcMajorVersion) == nil then -- 1.18.3 NAN
	--mcMajorVersion = tonumber(_HOST:sub(_HOST:find("Minecraft") + 10, _HOST:find("\)") - 3)) -- eg 1.19.4 -> 1.19
	local parts = mcMajorVersion:split(".")
	mcMajorVersion = parts[1]
	if parts[2] ~= nil then
		mcMajorVersion = mcMajorVersion.."."..parts[2]
	end
	mcMajorVersion = tonumber(mcMajorVersion)
	if parts[3] ~= nil then
		mcMinorVersion = tonumber(parts[3])
	end
end

if mcMajorVersion < 1.7  and mcMajorVersion >= 1.18 then -- 1.12 to 1.??
	bedrock = -64
	ceiling = 319
end
if mcMajorVersion < 1.7  and mcMajorVersion >= 1.16 then -- 1.12 to 1.??
	brick = "minecraft:nether_bricks"
end
if mcMajorVersion < 1.7  and mcMajorVersion <= 1.12 then --- turtle in source deletes it. 1.7.10 to 1.12
	deletesWater = true
end

local utils = {}
local network = {}

function network.addToStorageList(storageType, itemKey, storageName, writeToFile)
	-- itemKey is a table, so is passed byRef. No need to return a value
	-- eg itemKey: [ "minecraft:dark_oak_sapling" ] = {"minecraft:barrel_94", "minecraft:barrel_96"}
	-- storageName = "minecraft:barrel_99"
	local itemTable = {}
	if storageType == "chest" then
		itemTable = chestItems[itemKey]	-- eg [ "minecraft:dark_oak_sapling" ] = {"minecraft:barrel_94", "minecraft:barrel_96"}
	else
		itemTable = barrelItems[itemKey]
	end
	if itemTable == nil then				-- key does not match. This item not previously stored
		if storageType == "chest" then
			chestItems[itemKey] = {storageName}	-- eg U.chestItems[minecraft:diorite] = {chest_105}
		else
			barrelItems[itemKey] = {storageName}
		end
	else
		for _, storage in ipairs(itemTable) do	-- is "minecraft:barrel_99" already in the list?
			if storage == storageName then
				return	-- exit function
			end
		end
		-- not found so add to table. return not required as funcion is ended
		table.insert(itemTable, storageName)	-- add to table eg table[ "minecraft:dark_oak_sapling" ] = {"minecraft:barrel_94", "minecraft:barrel_96",, "minecraft:barrel_99"}
	end
	if writeToFile then
		network.updateList(storageType)
	end
end

function network.attachModem()
	-- modem cannot be "attached". Has to be player right-click!
	-- place on  top or next to a modem and ask player to right-click
	T:clear()
	menu.colourPrint("Please right-click on the modem(s) I am next to or above/below"..
					"\nThe centre square should be lit red.\n"..
					"If embedded use narrow gap at side\n", colors.red)
	local event, side = os.pullEvent("peripheral")
	for timer = 5, 0, -1 do
		-- text, fg, bg, width, isInput, cr
		menu.colourWrite("Thanks. continuing in ".. timer.." seconds", colors.lime, colors.black, 0, false, true)
		sleep(1)
	end
end

function network.checkInventory(inventory, itemName, itemsPerSlot, matchPart)
	--[[
	Find an item already in an inventory
	inventory = The wrapped inventory or it's name
	itemName = The name of the item to find.
	return no of items already present, and storage space for additional
	]]
	itemsPerSlot = itemsPerSlot or 64
	matchPart = matchPart or ""
	local contents = nil
	local numSlots = 0
	if type(inventory) == "string" then
		contents = peripheral.call(inventory, "list")
		numSlots = peripheral.call(inventory, "size")
		--assert(contents ~= nil, "Nil contents from inventory "..tostring(inventory))
		T:saveToLog("network.checkInventory('"..inventory.."', itemName = "..itemName..", itemsPerSlot = "..itemsPerSlot..", matchPart = "..tostring(matchPart))
	else
		contents = inventory.list()
		numSlots = inventory.size()
	end
	local inStock = 0
	local partMatch = false
	local canStore = 0
	if contents ~= nil then
		T:saveToLog("#slots in use = "..#contents)
		canStore = (numSlots - #contents) * itemsPerSlot 	-- capacity of empty slots
		for slot, item in pairs(contents) do
			if item.name == itemName then
				inStock = inStock  + item.count
				canStore = canStore + itemsPerSlot - item.count
			else
				if matchPart ~= "" then	-- eg check for "cobblestone" or "slab"
					if item.name:find(matchPart) ~= nil then
						partMatch = true
					end
				end
			end
		end
	end
	T:saveToLog("network.checkInventory return inStock = "..inStock..", canStore = "..canStore..", partMatch = "..tostring(partMatch))
	return inStock, canStore, partMatch -- eg 1, 3647, false if contains only 1 matching item in otherwise empty chest
end

function network.emptyInventory(R, barrels, chests, sticksAsFuel)
	--[[network.emptyInventory(R, {"sapling", "propagule", "dirt", "crafting"}, {"all"}, true)]]
	if not T:isEmpty() then
		if sticksAsFuel then
			utils.useSticksAsFuel()
		end
		for _, item in ipairs(barrels) do
			network.sendItemToNetworkStorage(R, "barrel", item, 0)
		end
		for _, item in ipairs(chests) do
			network.sendItemToNetworkStorage(R, "chest", item, 0)
		end
	end
end

function network.loadStorageLists()
	local lib = {}
	
	function lib.createList(storageType)
		local storage, turtleName, storageNames = network.wrapModem(R, storageType)	-- list of barrel/chest peripherals, name of turtle, names of barrels / chests
		local total = 0
		local locations = {}
		for _, store in pairs(storageNames) do					-- eg "minecraft:chest_1"
			T:clear()				
			T:saveToLog("Checking "..store.. " contents")		-- eg "checking minecraft:chest_1 contents"
			local contents = peripheral.call(store, "list")		-- list of items / slots for this chest
			for slot, item in pairs(contents) do				-- for each item check if this storage is listed
				if locations[item.name] == nil then				-- this item not yet found
					locations[item.name] = {store}				-- add to table eg locations["minecraft:cobblestone"] = {"minecraft:chest_1"}
				else											-- already has at least 1 location
					network.addToStorageList(storageType, locations[item.name], store, false)
				end
			end
			total = total + 1
		end
		T:saveToLog("found ".. total.." "..storageType)
		local output = textutils.serialize(locations)		-- serialise to json ready to write to file
		local fileName = storageType.."Items.lua"			-- barrelList.lua or chestList.lua
		local outputHandle = fs.open(fileName, "w")			-- open file
		outputHandle.writeLine("return")					-- start file with return
		outputHandle.write(output)							-- add serialised table
		outputHandle.close()								-- close file
		
		return locations
	end
	
	function lib.listNeedUpdating(storageType, list)
		-- see if named chest/barrel in list is found in fresh peripheral.find
		-- turtle may have moved to a different network
		-- list = eg [ "minecraft:stick" ] = {"minecraft:barrel_91","minecraft:barrel_114"}
		local rawStorage = {peripheral.find(storageType)}
		if not utils.isTableEmpty(rawStorage) then		-- chests / barrels are attached see if they match
			for item, storeList in pairs(list) do		-- existing storage names can be found here
				local found = false
				for key, value in ipairs(rawStorage) do	-- look in the fresh list of storage names to see if there are missing entries
					local name = peripheral.getName(value)				
					for _, storageName in ipairs(storeList) do 	-- check each storage name found
						if storageName == name then 	-- recorded name matches, check next one
							found = true
							break
						end
					end
					if found then break end
				end
				if not found then
					-- no match in existing list for this storage: list needs updating
					return true-- list does not match
				end
			end
		end
		return false	-- list is ok
	end
	
	local _, turtleName, storageNames = network.wrapModem(R, "chest")	-- _, name of turtle, list of names of storage
	if turtleName == "Modem not found" then return turtleName end
	local redo = false
	if barrelItems == nil then	-- not yet loaded
		T:saveToLog("barrelItems == nil")
		if fs.exists("barrelItems.lua") then
			T:saveToLog("require('barrelItems')")
			barrelItems = require("barrelItems")	-- global variable
			redo = lib.listNeedUpdating("barrel", barrelItems)
		else
			T:saveToLog("lib.createList('barrel'")
			barrelItems = lib.createList("barrel")
		end
	end
	if chestItems == nil then	-- not yet loaded
		T:saveToLog("chestItems == nil")
		if fs.exists("chestItems.lua") then
			T:saveToLog("require('chestItems')")
			chestItems = require("chestItems")	-- global variable
			redo = lib.listNeedUpdating("chest", barrelItems)
		else
			T:saveToLog("lib.createList('chest'")
			chestItems = lib.createList("chest")
		end	
	end
	if redo then
		barrelItems = lib.createList("barrel")
		chestItems = lib.createList("chest")
	end
end

function network.findEmptySlot(list, size)
	--[[ adapted from https://github.com/cc-tweaked/CC-Tweaked/discussions/1552
	Find the first empty slot in a chest.
	list = list of items in the chest/barrel/dropper
	size = The size of the inventory
	return integer? slot The slot number of the first empty slot, or nil if none are empty.
	]]
	for slot = 1, size do
		if not list[slot] then
			return slot
		end
	end
	
	return nil
end

function network.findItemCountInInventory(list, itemName, exactMatch)
	--[[
	Find an item in an inventory
	list = The list of items in the inventory
	itemName = The name of the item to find.
	return integer? The slot number of the item, or nil if not found.
	]]
	exactMatch = exactMatch or false
	if type(list) == "string" then
		list = peripheral.call(list, "list")
	end
	local retValue = nil
	local count = 0
	for slot, item in pairs(list) do
		local found = false
		if exactMatch then
			if item.name == itemName then found = true end
		else
			if item.name:find(itemName) ~= nil then found = true end
		end
		if found then
			if retValue == nil then
				retValue = {}
			end
			table.insert(retValue,{slot, item.count}) -- eg {1, 64}
			count = count + item.count
		end
	end
	return count, retValue -- either nil or eg {{1, 64},{4, 22}}
end

function network.findItemInInventory(inventory, itemName, exactMatch)
	--[[ adapted from https://github.com/cc-tweaked/CC-Tweaked/discussions/1552
	Find an item in an inventory
	inventory = name of inventory or wrapped peripheral
	itemName = The name of the item to find.
	return integer?, integer? The slot number and count of the item, or nil if not found.
	]]
	exactMatch = exactMatch or false
	if type(inventory) == "string" then
		T:saveToLog("network.findItemInInventory("..inventory..", "..itemName..", exactMatch = "..tostring(exactMatch)..")", true)
		contents = peripheral.call(inventory, "list")
	else	-- should be supplied with .list() already
		T:saveToLog("network.findItemInInventory(<inventory>, "..itemName..", exactMatch = "..tostring(exactMatch)..")", true)
		contents = inventory
	end
	--T:saveToLog("contents = "..table.concat(contents, ", "))
	--utils.writeTraceTable("contents = ", contents)
	if contents ~= nil then
		for slot, item in pairs(contents) do
			--T:saveToLog("item.name = "..item.name..", item.count = "..item.count)
			if exactMatch then
				if item.name == itemName then
					T:saveToLog("Item found in "..slot..", quantity = "..item.count)
					return slot, item.count
				end
			else
				if (item.name):find(itemName) ~= nil then
					T:saveToLog("Matching Item found in "..slot..", quantity = "..item.count)
					return slot, item.count
				end
			end
		end
	end
	T:saveToLog("Item not found")
	return 0,0
end

function network.getItemFromNetwork(storageType, itemRequired, countRequired, toTurtleSlot, ignoreStock)
	local lib = {}
	
	function lib.getItem(storageTable, turtleName, itemRequired, countRequired, toTurtleSlot, sent)
		local exit = false
		for k, storageName in pairs(storageTable) do 	-- eg {"minecraft:barrel_17", "minecraft:barrel_18"...}
			local available, data = network.findItemCountInInventory(storageName, itemRequired, false)		-- either nil or eg {{1, 64},{4, 22}}
			T:saveToLog("network.findItemCountInInventory("..storageName..", "..itemRequired..", false")
			if data ~= nil then
				for i = 1, #data do 
					local request = countRequired
					if countRequired > 64 then
						request = 64
					end
					local received = network.sendItemsToTurtle(turtleName, storageName, data[i][1], request, toTurtleSlot)	-- request items, returns number sent
					if received == nil then received = 0 end
					sent = sent + received
					T:saveToLog("received = "..received..", request = "..request.." from "..storageName..", sent = "..sent)
					if sent >= countRequired then
						exit = true
						break 
					end			-- job done, no need to check remaining slots
					countRequired = countRequired - sent			-- this line not reached if sent >= count
				end
			end
			--if sent >= countRequired then break end				-- no need to check other storage
			--if countRequired <= 0 then break end
			if exit then
				return sent, countRequired
			end
		end
		
		return sent, countRequired
	end
	
	-- eg slot, count = network.getItemFromNetwork("barrel", "minecraft:crafting_table", 1)
	-- storageType either "chest" or "barrel"
	if countRequired == nil then return 0,0 end
	--if toTurtleSlot not specified then nil = use any slot
	ignoreStock = ignoreStock or false	-- return only no of items obtained from storage
	T:saveToLog("network.getItemFromNetwork(storageType = "..storageType..", itemRequired = ".. itemRequired..
				", countRequired = ".. countRequired..", toTurtleSlot = "..tostring(toTurtleSlot)..", ignoreStock = "..tostring(ignoreStock))
	-- Must be next to a modem: MUST remove crafting table if modem on that side. Other tools ok
	local sent = 0
	local turtleSlot, turtleCount = T:getItemSlot(itemRequired)	-- check local stock
	if not ignoreStock then	-- take account of existing items and reduce count accordingly
		countRequired = countRequired - turtleCount
	end
	local savedItems = nil
	if storageType == "barrel" then
		savedItems = barrelItems
	elseif storageType == "chest" then
		savedItems = chestItems
	end
	local storage, turtleName, storageNames = network.wrapModem(R, storageType)	-- list of chest/barrel peripherals, name of turtle, list of storage names
	--if turtleName == "Modem not found" then return 0, nil, nil, turtleName end
	if countRequired > 0 then 						-- not enough in stock, or ignore current stock
		-- check if item in storageLists
		local testStores = nil
		if savedItems[itemRequired] ~= nil then	-- only works with full item names
			T:saveToLog("savedItems key in list: "..textutils.serialise(savedItems[itemRequired], {compact = true}))
			testStores = savedItems[itemRequired]
		else
			for key, value in pairs(savedItems) do 
				if key:find(itemRequired)~= nil then
					T:saveToLog("savedItems found in list: "..textutils.serialise(value, {compact = true}))
					testStores = value
					break
				end
			end
		end
		if testStores == nil then	-- no match in storage lists
			T:saveToLog("Unable to find recorded storage, using all "..storageType.."s")
			sent, countRequired = lib.getItem(storageNames, turtleName, itemRequired, countRequired, toTurtleSlot, sent)
		else -- match found, list of storage availble -- eg {"minecraft:barrel_17", "minecraft:barrel_18"...}
			T:saveToLog("Using recorded list alias 'testStores'")
			sent, countRequired = lib.getItem(testStores, turtleName, itemRequired, countRequired, toTurtleSlot, sent)
		end
	end
		-- slotData.lastSlot, total, slotData -- integer, integer, table
	local data = {}
	turtleSlot, turtleCount, data = T:getItemSlot(itemRequired)
	T:saveToLog("turtleSlot = "..turtleSlot..", turtleCount = "..turtleCount..", sent = "..sent) --..", data = "..textutils.serialise(data))
	if ignoreStock then
		return turtleSlot, sent	-- 0 -> count
	else
		return turtleSlot, turtleCount	-- 0 -> count
	end
end

function network.getSlotContains(inventoryName, inSlot)
	local list = peripheral.call(inventoryName, "list")
	for slot, item in pairs(list) do
		if inSlot == slot then
			return item.name
		end
	end
	return ""
end

function network.moveItem(inventoryName, itemName, toSlot)
	--[[ adapted from https://github.com/cc-tweaked/CC-Tweaked/discussions/1552
	Move a specific item to specific slot eg 1, moving other items out of the way if needed.
	inventoryName = The name of the chest/barrel/dropper to search.
	itemName = The name of the item to find.
	toSlot optional. default is slot 1
	return boolean success Whether or not the item was successfully moved to toSlot (or already existed there)
	]]
	toSlot = toSlot or 1
	local list = peripheral.call(inventoryName, "list")
	local size = peripheral.call(inventoryName, "size")
	local slot = network.findItemInInventory(list, itemName)

  -- If the item didn't exist, or is already in the first slot, we're done.
	if not slot then
		T:saveToLog("network.moveItem(): Item not found")
		return false
	end
	if slot == toSlot then
		return true
	end

	-- If an item is blocking the first slot (we already know it's not the one we want), we need to move it.
	if list[toSlot] then
		T:saveToLog("network.moveItem() Slot "..toSlot.." occupied, moving..")
		local emptySlot = network.findEmptySlot(list, size)

		-- If there are no empty slots, we can't move the item.
		if not emptySlot then
			T:saveToLog("network.moveItem(): No empty slots")
			return false
		end

		-- Move the item to the first empty slot.
		
		if not network.moveItemStack(inventoryName, toSlot, emptySlot) then
			T:saveToLog("network.moveItem(): Failed to move item to slot " .. emptySlot)
			return false
		end

		T:saveToLog("network.moveItem(): Moved item to slot " .. emptySlot)
	end

	-- Move the item to slot 1.
	if not network.moveItemStack(inventoryName, slot, toSlot) then
		T:saveToLog("network.moveItem(): Failed to move item to slot "..toSlot)
		return false
	end

	T:saveToLog("network.moveItem(): Moved item to slot "..toSlot)
	return true
end

function network.moveItemsFromTurtle(turtleName, toInventoryName, fromTurtleSlot, quantity, toSlot)
	--[[
	Move quantity of an item from one inventory to another. Turtles MUST use attachedInventory.pullItems()
	eg network.moveItemsFromTurtle(turtleName, chestName, turtleSlot, turtleCount, nil)
	turtleName:			The name of the turtle (via getLocalName())
	toInventoryName: 	The name of the inventory to move items into.
	fromTurtleSlot: 	The slot to move from. must be pre-determined for the item required
	quantity: 			The amount to transfer (nil for full stack)
	toSlot: 			The slot to move to. (nil will use any available slot(s))
	]]
	return peripheral.call(toInventoryName, "pullItems", turtleName, fromTurtleSlot, quantity, toSlot)
end

function network.moveItemStack(inventoryName, fromSlot, toSlot)
	--[[ adapted from https://github.com/cc-tweaked/CC-Tweaked/discussions/1552
	Move an item from one slot to another in a given inventory.
	inventoryName The name of the inventory to move items in.
	fromSlot The slot to move from.
	toSlot The slot to move to.
	]]
	return peripheral.call(inventoryName, "pushItems", inventoryName, fromSlot, nil, toSlot)
end

function network.sendItemToNetworkStorage(R, storageType, itemToSend, amountToSend)
	-- used to remove items from turtle inventory
	-- Must be next to a modem: MUST remove crafting table if modem on that side. Other tools ok
	local lib = {}
	
	function lib.sendItem(savedItems, peripheralNames, turtleName, turtleSlot, item, slotCount, itemsPerSlot)
		local storageToUse = ""
		local storageList = lib.getStorageFromList(savedItems, item, slotCount, itemsPerSlot)	-- try from savedList
		if storageList == nil then	-- no match found, but use first one found with network.wrapModem
			T:saveToLog("No storage with matching items found, using first empty chest")
			storageToUse = lib.findEmptyStorage(peripheralNames, item, itemsPerSlot, slotCount)
		else
			T:saveToLog("Storage with matching items found, checking capacity")
			storageToUse  = lib.checkCapacity(storageList, item, slotCount, itemsPerSlot)
			if storageToUse == "" then	-- no capacity in known storage list, so start a new one
				storageToUse = lib.findEmptyStorage(peripheralNames, item, itemsPerSlot, slotCount)
			end
		end
		--network.moveItemsFromTurtle(turtleName, toInventoryName, fromTurtleSlot, quantity, toSlot)
		T:saveToLog("network.moveItemsFromTurtle(turtleName = "..turtleName..", storageToUse = "..tostring(storageToUse)..", slot = "..tostring(turtleSlot)..", slotCount = "..tostring(slotCount)..")")
		network.moveItemsFromTurtle(turtleName, storageToUse, turtleSlot, slotCount)
	end
	
	function lib.findEmptyStorage(peripheralNames, itemName, itemsPerSlot, itemCount)
		T:saveToLog("lib.findEmptyStorage("..textutils.serialise(peripheralNames,{compact = true})..", itemName = "..itemName.. ", itemsPerSlot = "..itemsPerSlot)
		for store = 1, #peripheralNames do 
			inStock, canStore, partMatch = network.checkInventory(peripheralNames[store], itemName, itemsPerSlot, "")
			if canStore > itemCount then
				return peripheralNames[store]
			end
		end
		return nil
	end
	
	function lib.getStorageFromList(savedItems, item, sendAmount, itemsPerSlot)
		if savedItems[item] == nil then								-- no record of this item stored
			T:saveToLog("lib.getStorageFromList() "..item.." not found")
			local parts = T:getNames(item)								-- eg minecraft:jungle_planks = "minecraft", "jungle", "planks"
			for part = #parts, 1, -1 do 								-- iterate "planks", "jungle", "minecraft"
				local searchTerm = parts[part]
				if searchTerm ~= "minecraft" and searchTerm ~= "mysticalagriculture" then
					for itemName, storageList in pairs(savedItems) do	-- iterate items used as keys eg minecraft:jungle_log matches jungle
						if itemName:find(searchTerm) ~= nil then 		-- partial match eg "sapling" found in "minecraft:oak_sapling"
							T:saveToLog("lib.getStorageFromList() matched "..searchTerm.." with "..itemName)
							return storageList							-- eg {"minecraft:chest_22", "minecraft:chest_23"}
						end
					end
				end
			end
		else
			T:saveToLog("lib.getStorageFromList() ["..item.."] found")
			return savedItems[item]	-- list of chests with this item available
		end
		return nil
	end
	
	function lib.checkCapacity(storageList, item, sendAmount, itemsPerSlot)
		-- find a chest/barrel with sufficient capacity from list of storage
		for store = 1, #storageList do 
			local inStock, canStore, partMatch = network.checkInventory(storageList[store], item, itemsPerSlot, "")
			if canStore > sendAmount then
				return storageList[store]
			end
		end
		return ""
	end
	
	amountToSend = amountToSend or 0						-- 0 = remove all of this item
	local totalSent = 0										-- track quantity sent 
	local minSend = 0										-- minimum amount to send
	if amountToSend > 0 then minSend = amountToSend end		-- update minimum to send
	local _, turtleName, peripheralNames = network.wrapModem(R, storageType)	-- _, name of turtle, list of names of storage
	
	T:saveToLog("network.sendItemToNetworkStorage(R, storageType = '"..storageType.."', itemToSend = '"..itemToSend.."', amountToSend = "..amountToSend..")")
	T:saveToLog("network.wrapModem(R, storageType = "..storageType..", turtleName = "..turtleName..")")
	local savedItems = nil
	if storageType == "barrel" then
		savedItems = barrelItems
	elseif storageType == "chest" then
		savedItems = chestItems
	end
	
	if itemToSend == "all" then	-- empty Turtle, so item names not relevant
		T:saveToLog("itemToSend = all")
		repeat
			local item, turtleSlot, slotCount, itemsPerSlot = "", 0, 0, 64
			for slot = 1, 16 do
				item, slotCount = T:getSlotContains(slot)
				if slotCount > 0 then
					turtleSlot = slot
					T:saveToLog("for slot = 1, 16 do: item = "..item..", slotCount = "..slotCount)
					itemsPerSlot = utils.getSlotCapacity(slot)	-- most items capacity is 64 per slot
					T:saveToLog("sending'"..item.."' from slot "..slot..", quantity = "..slotCount)
					break
				end
			end
			if turtleSlot > 0 then
				lib.sendItem(savedItems, peripheralNames, turtleName, turtleSlot, item, slotCount, itemsPerSlot)
			end
		until turtleSlot == 0
		return 0	-- exit function
	else
		local storageToUse  = ""
		repeat	-- until item no longer present in inventory or requested amount has been sent
			local sourceSlot, total, data = T:getItemSlot(itemToSend)	-- which slot and how much of itemToSend is in turtle?
			local slotCount = data.leastCount
			T:saveToLog("T:getItemSlot('"..itemToSend.."' sourceSlot = "..sourceSlot..", total = "..total..")")
			if sourceSlot == 0 then
				T:saveToLog(itemToSend.." not found in turtle inventory")
				return 0	-- exit function
			else
				local itemsPerSlot = utils.getSlotCapacity(sourceSlot)	-- most items capacity is 64 per slot
				itemToSend = data.leastName								-- full name of item with lowest itemCount
				T:saveToLog("network.sendItemToNetworkStorage(R, '"..itemToSend.."', sourceSlot = "..sourceSlot..", slotCount = "..slotCount) --..", data = "..textutils.serialise(data)..")")
				if sourceSlot > 0 then									-- item is present in turtle inventory
					local newStore = false
					local sent = 0
					local storageList = lib.getStorageFromList(savedItems, itemToSend, slotCount, itemsPerSlot)
					if storageList == nil then
						T:saveToLog("not found in any storage, finding empty")
						storageToUse = lib.findEmptyStorage(peripheralNames, itemToSend, itemsPerSlot, total)
						T:saveToLog("new storage: "..storageToUse.." is available")
						network.addToStorageList(storageType, itemToSend, storageToUse, true)
						sent = network.moveItemsFromTurtle(turtleName, storageToUse, sourceSlot, slotCount)	
					else
						storageToUse  = lib.checkCapacity(storageList, itemToSend, slotCount, itemsPerSlot)
						if storageToUse == "" then	-- no capacity in known storage list, so start a new one
							storageToUse = lib.findEmptyStorage(peripheralNames, itemToSend, itemsPerSlot, total)
							newStore = true
						end
						T:saveToLog("sent = network.moveItemsFromTurtle(turtleName = "..turtleName..", storageToUse = "..storageToUse..", sourceSlot = "..sourceSlot..", slotCount = ".. slotCount)
						sent = network.moveItemsFromTurtle(turtleName, storageToUse, sourceSlot, slotCount)
					end
					totalSent = totalSent + sent
					if minSend > 0 and totalSent >= minSend then
						return totalSent
					end
					if amountToSend > 0 then	-- sending specified amount
						amountToSend = amountToSend - sent
					end
					if newStore then
						network.addToStorageList(storageType, itemToSend, storageName, true)
					end
				end
			end
		until sourceSlot == 0
	end
	
	return totalSent
end

function network.sendItemsToCrafter(crafterName, fromInventoryName, fromInventorySlot, quantity, toCrafterSlot)
	--[[
	fromInventoryName: 	The name of the inventory to move items from.
	fromInventorySlot: 	The slot to move from. must be pre-determined for the item required
	quantity: 			The amount to transfer (nil for full stack)
	toCrafterSlot: 		The slot to move to. (nil will use any available slot(s))
	]]
	return peripheral.call(fromInventoryName, "pushItems", crafterName, fromInventorySlot, quantity, toCrafterSlot)
end

function network.sendItemsToTurtle(turtleName, fromInventoryName, fromInventorySlot, quantity, toTurtleSlot)
	--network.sendItemsToTurtle(turtleName, storageName, storageSlot, count, toTurtleSlot)
	--[[
	Move quantity of an item from one inventory to another. Turtles MUST use attachedInventory.pushItems()
	eg network.sendItemsToTurtle(turtleName, chestName, chestSlot, chestCount, 16) -- move to slot 16 so must be empty
	fromInventoryName: 	The name of the inventory to move items from.
	fromInventorySlot: 	The slot to move from. must be pre-determined for the item required
	quantity: 			The amount to transfer (nil for full stack)
	toTurtleSlot: 		The slot to move to. (nil will use any available slot(s))
	]]
	return peripheral.call(fromInventoryName, "pushItems", turtleName, fromInventorySlot, quantity, toTurtleSlot)
end

function network.transferItem(fromInventoryName, toInventoryName, itemName, quantity, toSlot)
	--[[
	Move a specific number of an item from one inventory to another
	fromInventoryName:	The name of the chest/barrel/dropper to search.
	toInventoryName:	The name of the receiving inventory (chest/barrel/dropper/smelter)
	itemName: 			The name of the item to find.
	toSlot: 			optional. nil picks any slot
	return: 			boolean success Whether or not the item was successfully moved to toSlot (or already existed there)
	]]
	--T:saveToLog("network.transferItem(from: "..fromInventoryName..", to: "..toInventoryName..", itemName = "..itemName..", quantity = "..tostring(quantity)..", toSlot = "..tostring(toSlot))
	local list = peripheral.call(fromInventoryName, "list")
	local size = peripheral.call(fromInventoryName, "size")
	--T:saveToLog("network.transferItem() size = "..size..", list = \n"..textutils.serialize(list))
	local count, data = network.findItemCountInInventory(list, itemName)	-- either nil or eg {{1, 64},{4, 22}}
	--T:saveToLog("network.transferItem() data = "..textutils.serialize(data, {compact = true}))
	local remaining = quantity			-- eg 22 items needed

	if data == nil then	-- Item not found
		return quantity	-- return amount requested = nothing sent
	end
	
	local fromSlot = 0
	local count = 64
	local available = 0
	for _, v in pairs(data) do	-- eg {1, 64},{2, 64}
		if v[2] < count and v[2] >= quantity then
			fromSlot = v[1]
			count = v[2]
		else
			available = available + v[2]
		end
	end
	if fromSlot > 0 then						-- now have slot with min required quantity
		T:saveToLog("network.transferItem() from: "..fromInventoryName..", to: "..toInventoryName..", fromSlot: "..fromSlot..", toSlot: "..tostring(toSlot)..", quantity: "..tostring(quantity))
		network.transferItems(fromInventoryName, toInventoryName, fromSlot, toSlot, quantity)
		return 0
	else									-- available must be at least 1
		for i = 1, #data do					-- itreate all slots containg at least 1 item
			fromSlot = data[i][1]			-- eg slot 1
			local send = data[i][2]			-- eg 10 items
			if remaining - send < 0 then	-- eg 22 - 10 = 12
				send = remaining
				remaining = 0
			else
				remaining = remaining - send-- eg remaining = 22 - 10 = 12
			end
			network.transferItems(fromInventoryName, toInventoryName, fromSlot, toSlot, send)
			if remaining <= 0 then			-- all required items transferred
				return 0
			end
		end
	end
	
	return remaining						-- return remaining items to be found from a  different inventory
end

function network.transferItems(fromInventoryName, toInventoryName, fromSlot, toSlot, quantity)
	--[[
	Move quantity of an item from one inventory to another
	fromInventoryName:	The name of the inventory to move items from.
	toInventoryName: 	The name of the inventory to move items into.
	fromSlot: 			The slot to move from. must be pre-determined for the item required
	toSlot: 			The slot to move to. (nil will use any available slot(s))
	quantity: 			The amount to transfer (nil for full stack)
	]]
	T:saveToLog("network.transferItems(from: "..fromInventoryName..", to: "..toInventoryName..", fromSlot: "..fromSlot..", toSlot: "..tostring(toSlot)..", quantity: "..tostring(quantity)..")")
	return peripheral.call(fromInventoryName, "pushItems", toInventoryName, fromSlot, quantity, toSlot)
end

function network.transferItemToTurtle(availableStorage, availableStorageKeys, turtleName, crafterData)
	-- network.transferItemToTurtle(<availableStorage>, data = {{1, 64},{4, 22}}, "crafter_01", <crafterData>)
	-- availableStorage.minecraft:chest_114 = {count = 86, data = {{1, 64},{4, 22}},
	-- availableStorage.minecraft:chest_115 = {count = 1024, data = {{1, 64},{2, 64},{3, 64}, ... }
	-- crafterData = {{2,64}, {4,64}, {6,64}, {8,64}} 64 items in each of 4 slots in the crafter
	-- glitch? in crafter inventory, cannot add sequentially to existing items. 
	-- send to turtle slot first, then transfer
	T:saveToLog("network.transferItemToTurtle(availableStorage = "..textutils.serialise(availableStorage, {compact = true})..
				"\navailableStorageKeys = "..textutils.serialise(availableStorageKeys, {compact = true})..
				"\n"..turtleName..", crafterData = "..textutils.serialise(crafterData, {compact = true}))
				
	local total = 0
	local numSlots = 0
	local sent = 0
	for _, v in ipairs(crafterData) do								-- how many items required in total?
		total = total + v[2]										-- how many slots does it go in
		numSlots = numSlots + 1
	end
	for _, availableStorageKey in ipairs(availableStorageKeys) do	-- eg {minecraft:chest_114, minecraft:chest_115}
		local storageName = availableStorageKey						-- eg minecraft:chest_114
		local object = availableStorage[storageName]				-- availableStorage.minecraft:chest_114 = {count = 90, data = {{14,64},{15,26}}
		local storageData = object.data								-- eg data = {{14,64},{15,26}}
		local storageCount = object.count							-- eg count = 90
		for _, crafterSlotData in ipairs(crafterData) do			-- eg {{2,22}, {4,22}, {6,22}, {8,22}} -> iteration 1 = {2, 22} iterate crafter slots to be filled
			local toCrafterSlot = crafterSlotData[1]				-- eg slot 2 in turtle
			local amountToSend = crafterSlotData[2]					-- eg place 22 items in slot 2
			T:saveToLog("storageData = "..textutils.serialise(storageData, {compact = true}))
			T:saveToLog("crafterSlotData = "..textutils.serialise(crafterSlotData, {compact = true}))
			for i = 1, #storageData do								-- {{14,64},{15,26}}					
				local slotData = storageData[i]						-- {14,64}
				local availableToSend = slotData[2]					-- 64
				local fromStorageSlot = slotData[1]					-- 14
				local confirmedSent = 0
				
				T:saveToLog("i = "..i..", slotData = "..textutils.serialise(slotData, {compact = true}))
				if availableToSend >= amountToSend then
					T:saveToLog("availableToSend ("..availableToSend..") >= amountToSend: ("..amountToSend.."), current value of sent = "..sent)
					T:saveToLog("?confirmedSent = peripheral.call("..storageName..", 'pushItems', "..turtleName..
								", from slot "..fromStorageSlot..", amountToSend = "..
								amountToSend..", to turtle slot "..toCrafterSlot)
					confirmedSent = peripheral.call(storageName, "pushItems", turtleName, fromStorageSlot, amountToSend, toCrafterSlot)
					sent = sent + confirmedSent
					T:saveToLog("verified confirmedSent = "..confirmedSent..", sent = "..sent)
					slotData[2] = slotData[2] - confirmedSent
					crafterSlotData[2] = 0
					T:saveToLog("slotData[2] = "..slotData[2]..", crafterSlotData[2] = "..crafterSlotData[2])
				else
					T:saveToLog("availableToSend ("..availableToSend..") < amountToSend: ("..amountToSend.."), current value of sent = "..sent)
					T:saveToLog("?confirmedSent = peripheral.call("..storageName..", 'pushItems', "..turtleName..
								", from slot "..fromStorageSlot..", availableToSend = "..
								availableToSend..", to turtle slot "..toCrafterSlot)
					-- taking items from multiple storage slots requires loading into turtle first
					confirmedSent = peripheral.call(storageName, "pushItems", turtleName, fromStorageSlot, availableToSend, toCrafterSlot)
					sent = sent + confirmedSent
					T:saveToLog("verified confirmedSent = "..confirmedSent..", sent = "..sent)
					amountToSend = amountToSend - confirmedSent
					slotData[2] = slotData[2] - confirmedSent
					crafterSlotData[2] = amountToSend
					T:saveToLog("slotData[2] = "..slotData[2]..", crafterSlotData[2] = "..crafterSlotData[2])
				end
				
				if crafterSlotData[2] == 0 then
					T:saveToLog("crafterSlotData[2]("..crafterSlotData[2]..") == 0: breaking\n")
					break	-- already sent correct amount
				end
			end
		end
		if sent >= total then 
			T:saveToLog("sent("..sent..") >= total ("..total.."): breaking\n")
			break
		end
	end

	return sent
end

function network.pullItems(fromName, fromSlot, quantity, toName, toSlot)
	quantity = quantity or 1
	toSlot = toSlot or nil
	if type(fromName) == "table" then			-- already a wrapped peripheral
		fromName = peripheral.getName(fromName)
	end
	if type(toName) == "string" then
		toName = peripheral.wrap(toName)
	end
	toName.pullItems(fromName, fromSlot, quantity, toSlot)
end

function network.updateList(storageType)
	local output = ""
	if storageType == "barrel" then
		output = textutils.serialize(barrelItems)		-- serialise to json ready to write to file
	elseif storageType == "chest" then
		output = textutils.serialize(chestItems)		-- serialise to json ready to write to file
	end
	local fileName = storageType.."Items.lua"			-- barrelList.lua or chestList.lua
	local outputHandle = fs.open(fileName, "w")			-- open file
	outputHandle.writeLine("return")					-- start file with return
	outputHandle.write(output)							-- add serialised table
	outputHandle.close()								-- close file
end

function network.wrapModem(R, storageType)
	--[[To move turtle inventory items use the target peripheral:
		local modem = peripheral.wrap("front")		-- wrap modem next to turtle (beware crafting table!)
		local turtleName = modem.getNameLocal()		-- get name of the turtle
		local barrel = peripheral.find("barrel")	-- find barrel name you want to receive goods
		barrel.pushItems(turtleName, 1, 1)			-- push items FROM turtle to barrel  pushItems(toName, fromSlot , limit , toSlot)
		barrel.pullItems(turtleName, fromSlot , limit , toSlot)
	]]
	local modem = peripheral.find("modem")		-- find modem
	if modem == nil then
		return nil, "Modem not found"
	end
	local turtleName = modem.getNameLocal()		-- get name of the turtle
	local rawStorage = nil						-- peripheral find can return duplicate values
	if storageType:find("barrel") ~= nil then
		rawStorage = {peripheral.find("minecraft:barrel")}
	elseif storageType:find("chest") ~= nil then
		rawStorage = {peripheral.find("minecraft:chest")}
	end
	local storage = {}
	local names = {}
	for k, value in ipairs(rawStorage) do
		local name = peripheral.getName(value)
		if not utils.tableContains(names, name, true) then	-- use exact match as checking peripherals
			table.insert(storage, value)
			table.insert(names, name)
		end
	end
	return storage, turtleName, names
end

function utils.assessFarm(R)
	-- sets R.networkFarm and R.mysticalAgriculture
	menu.colourPrint("Assessing farm properties...", colors.yellow)
	--local storage = true
	for turns = 1, 4 do
		T:turnRight(1)
		local itemAhead = T:getBlockType("forward")
		if itemAhead:find("modem") ~= nil then
			if not R.networkFarm then	-- prevents repeated text display
				R.networkFarm = true
				menu.colourPrint("Network storage in use.", colors.magenta)
			end
		end
		if itemAhead:find("mysticalagriculture") ~= nil then
			R.mysticalAgriculture = true
			menu.colourPrint("Mystical Agriculture deployed.", colors.lime)
		end
	end
	sleep(1.5)
	
	return R
end

function utils.assessTreeFarm(R)
	local lib = {}
	
	function lib.getSaplingType(R, blockType)
		if blockType == "minecraft:mangrove_log" then
			R.logType = "mangrove"
			R.useBlockType ="mangrove_propagule"
		else
			local parts = T:getNames(blockType)
			if parts[2] == "dark" then
				R.logType = "dark_oak"
				parts[2] = "dark_oak"
			else
				R.logType = parts[2]				-- eg "oak"
			end
			
			R.useBlockType = parts[2].."_sapling"	-- eg "oak_sapling"
		end
		utils.goBack(1)
		turtle.turnLeft()
		
		return R
	end
	
	local blockType = T:getBlockType("down")
	if blockType:find("modem") ~= nil then
		R.networkFarm = true
	else
		if blockType:find("polished") == nil then
			R.message = "Not on modem or polished. Check position"
			return R
		end
	end
	if R.networkFarm then
		T:forward(1)
		blockType = T:getBlockType("down")
		T:saveToLog("T:forward(1): blockType = "..blockType)
		if blockType:find("log") ~= nil then
			R = lib.getSaplingType(R, blockType)
		elseif blockType:find("barrel") ~= nil then
			T:go("R2F2")
			blockType = T:getBlockType("down")
			if blockType:find("log") ~= nil then
				R = lib.getSaplingType(R, blockType)
			end
		else	-- if in correct position water is 2 blocks below
			if turtle.down() then
				blockType = T:getBlockType("down")
				if blockType:find("water") == nil then
					R.message = "No modem below. Check position"
					return R
				else
					turtle.up()
					utils.goBack(1)
					T:go("R1F1")
					blockType = T:getBlockType("down")
					if blockType:find("log") ~= nil then
						R = lib.getSaplingType(R, blockType)
					else
						R.message = "Unable to determine location. Check position"
						return R
					end
				end
			else
				R.message = "Unable to determine location. Check position"
				return R
			end
		end
	end
	
	return R	-- sets R.networkFarm and R.useBlockType to sapling type
end

function utils.calculateDimensions(R)
	if R.data == "" then -- not being called from other functions
		if R.width == 0 then -- user chose auto settings
			R.length = utils.calculateDistance(R.length) -- still facing forward
			print("Calculated Length = "..R.length)
			T:turnRight(1) -- ready to check width
			R.width = utils.calculateDistance(R.width) -- now facing right
			print("Calculated width = "..R.width)
			T:go("R2F"..R.width - 1 .."L1".. "F"..R.length - 1 .."R2") -- back at start. width/length confirmed
		end
	end
	if R.height == 0 then -- use auto settings based on water detection
		R.height = 64
	end
	return R
end

function utils.calculateDistance(estDistamcMajorVersionnce)
	--[[
	measure length
	movement stops when either solid block in front or solid below
	called from utils.calculateDimensions
	]]
	local moves = 1
	local nonSolidBelow = utils.clearVegetation("down")
	if estDistance == 0 then
		while nonSolidBelow and turtle.forward() do -- while able to move and air/water below
			moves = moves + 1
			nonSolidBelow = utils.clearVegetation("down")
		end
	else
		while moves < estDistance * 2 do -- loop can only run for max of double estimated distance
			if turtle.forward() then -- able to move forward
				moves = moves + 1
			else
				break
			end
			if not utils.clearVegetation("down") then -- solid below
				turtle.back()
				moves = moves - 1
				break
			end
		end
	end
	return moves
end

function utils.checkFarmPosition(R)
	local discovered = ""
	local success, storage, detected = false, "", 0
	local blockType = T:getBlockType("down")
	T:saveToLog("Checking position "..blockType.. " down")
	if blockType:find("water") ~= nil then -- over water, ? facing E (crops)
		-- network: E = __modem_, N = _modem__, W = modem___, S = ___modem
		-- storage: E = _chestchest_, N = chestchest__, W = chest__chest, S = __chestchest
		-- storage: E = _barrelbarrel_, N = barrelbarrel__, W = barrel__barrel, S = __barrelbarrel
		T:saveToLog("? over water = true")
		for i = 1, 4 do
			success, storage = utils.isStorage("forward")	-- true/false, chest, barrel, modem / ""
			local itemAhead = T:getBlockType("forward")
			if success then
				discovered = discovered .. storage
				if storage == "modem" then
					R.networkFarm = true
				end
			else
				discovered = discovered .. "_"
			end
			if itemAhead:find("mysticalagriculture") ~= nil then
				R.mysticalAgriculture = true
			end
			T:turnRight(1)
		end
		T:saveToLog("Storage blocks found:"..discovered)
		if R.networkFarm then
			if discovered == "modemmodem__" then
			   T:turnLeft(1)
			elseif discovered == "modem__modem" then
			   T:turnLeft(2)
			elseif discovered == "__modemmodem" then
			   T:turnRight(1)
			end
			R.ready = true
		else
			if discovered == "barrelbarrel__" or
			   discovered == "barrelchest__" or
			   discovered == "chestchest__" then
			   T:turnLeft(1)
			elseif discovered == "barrel__barrel" or discovered == "chest__chest" then
			   T:turnLeft(2)
			elseif discovered == "__barrelbarrel" or discovered == "__chestchest" then
			   T:turnRight(1)
			end
			R.ready = true
		end
	end	-- else not over water
		
	T:saveToLog("utils.checkFarmPosition(R) return R = "..textutils.serialise(R, {compact = true}))
	return R -- now facing crops, R.ready = true/false, R.networkFarm = true/false
end

function utils.checkFuelNeeded(quantity)
	local fuelNeeded = quantity - turtle.getFuelLevel() -- eg 600
	if fuelNeeded > 0 then
		if T:checkInventoryForItem({"minecraft:lava_bucket"}, {1}, false) == nil then	
			if T:checkInventoryForItem({"coal"}, {math.ceil(fuelNeeded / 60)}, false) == nil then
				T:checkInventoryForItem({"planks"}, {math.ceil(fuelNeeded / 15)})
			end
		end
		T:refuel(quantity, true)
	end
end

function utils.clearVegetation(direction)
	local isAirWaterLava = true	-- default true value air/water/lava presumed
	-- blockType, data
	local blockType = T:getBlockType(direction)
	if blockType ~= "" then --not air
		if T:isVegetation(blockType) then
			T:dig(direction)
		elseif blockType:find("water") == nil
			   and blockType:find("lava") == nil
			   and blockType:find("bubble") == nil
			   and blockType:find("ice") == nil then
			-- NOT water, ice or lava 
			isAirWaterLava = false -- solid block
		end
	end
	
	return isAirWaterLava --clears any grass or sea plants, returns true if air or water, bubble column or ice
end

function utils.convertEssence(R)
	-- R.subChoice = 1 to 5
	-- R.size = quantity
	-- 1 = inferium to prudentium
	-- 2 = prudentium to tertium
	-- 3 = Tertium to Imperium
	-- 4 = Imperium to Supremium
	-- 5 = Supremium to Insanium
	local lib = {}
	
	function lib.getCrystal()
		local turtleSlot, turtleCount = 0, 0
		if utils.isStorage("up") then
			turtle.select(2)
			turtle.suckUp()
		end
		turtleSlot = T:getItemSlot("crystal")
		if turtleSlot == 0 then
			turtleSlot, turtleCount = network.getItemFromNetwork("chest", "infusion_crystal", 1)
		end
		if turtleSlot > 0 then
			turtle.select(turtleSlot)
			turtle.transferTo(2)
			return true
		end
		
		return false
	end
		
	function lib.loadCrafter(crafterName)
		-- up to 64 essences stored in turtle slots 2, 4, 6, 8
		local slots = {2, 4, 6, 8}
		for _, slot in ipairs(slots) do		-- drop each slot contents into crafter ? slot 1
			turtle.select(slot)
			turtle.drop()
			peripheral.call(crafterName, "pushItems", crafterName, 1, nil, slot)	-- move to correct place
		end
	end
	
	function lib.loadTurtle(availableStorage, availableStorageKeys, turtleName, essence, loaded)
		-- collect essence as above and place in minecraft:crafter slots 2, 4, 6, 8
		local crafterData = {{2, loaded}, {4, loaded}, {6, loaded}, {8, loaded}} -- eg 64 items in each of 4 slots in the crafter
		network.transferItemToTurtle(availableStorage, availableStorageKeys, turtleName, crafterData)
	end
		
	function lib.runCrafter(crafterName, count)
		-- can only craft once, then crystal + output is returned to turtle
		-- repeat process count times
		-- drop crystal into crafter, move to slot 5
		for i = 1, count do
			local slot = T:getItemSlot("crystal")
			if slot > 0 then
				turtle.select(slot)
				turtle.drop()
				network.moveItem(crafterName, "crystal", 5)
				for i = 1, 3 do
					rs.setAnalogOutput("front",15)
					sleep(0.1)
					rs.setAnalogOutput("front", 0)
				end
			end
		end
		while turtle.suck() do end
	end
	
	function lib.storeCrystal()
		if utils.isStorage("up") then
			T:dropItem("crystal", "up")
		else
			network.sendItemToNetworkStorage(R, "chest", "crystal", 0)	-- empty turtle to storage chests
		end
	end
	
	function lib.storeOutput()
		if utils.isStorage("up") then
			T:dropItem("crystal", "up")
		end
		network.sendItemToNetworkStorage(R, "chest", "all", 0)	-- empty turtle to storage chests
	end
	
	function lib.getStorageData(essence)
		local _, turtleName, storageNames = network.wrapModem(R, "chests")	-- _, turtleName, list of chest names
		if turtleName == "Modem not found" then return 0, nil, nil, turtleName end
		local availableStorage = {}
		local availableStorageKeys = {}
		local total = 0
		for _, storageName in pairs(storageNames) do 
			local storageCount, storageData = network.findItemCountInInventory(storageName, essence)	-- eg 86, {{1, 64},{4, 22}}
			if storageCount > 0 then		-- eg 86: storage has some items
				T:saveToLog("storageCount = "..storageCount)
				availableStorage[storageName] = {}
				availableStorage[storageName].count = storageCount
				availableStorage[storageName].data = storageData
				table.insert(availableStorageKeys, storageName)
				total = total + storageCount
			end
		end
		
		return total, availableStorage, availableStorageKeys, turtleName
		--[[
			availableStorage.minecraft:chest_114 = {count = 86, data = {{1, 64},{4, 22}},
			availableStorage.minecraft:chest_115 = {count = 1024, data = {{1, 64},{2, 64},{3, 64}, ... }
		]]
	end
	
	local essences = {"mysticalagriculture:inferium_essence",
					"mysticalagriculture:prudentium_essence",
					"mysticalagriculture:tertium_essence",
					"mysticalagriculture:imperium_essence",
					"mysticalagriculture:supremium_essence",
					"mysticalagriculture:insanium_essence"}
	
	local message = network.loadStorageLists()
	if message ~= nil then return {message} end
	local essence = essences[R.subChoice]
	local missing = ""
	local crafter = peripheral.find("minecraft:crafter")
	local crafterName = ""
	local completed = 0
	if R.size > 0 then
		R.size = math.floor(R.size / 4) * 4
		if R.size == 0 then R.size = 4 end
	end
	if crafter == nil then
		return {"No crafter found"}
	else
		crafterName = peripheral.getName(crafter)
		T:saveToLog("utils.convertEssence started using "..essence..", quantity = "..R.size )
		while turtle.suck() do end						-- empty crafter
		lib.storeOutput()	-- empty turtle to storage chests, (except crystal if storage above)
		if not lib.getCrystal() then
			return {"Failed: missing infusion crystal"}
		end
		lib.storeCrystal()
		local totalInStorage, availableStorage, availableStorageKeys, turtleName = lib.getStorageData(essence)
		if totalInStorage < 4 then
			return {"Only "..totalInStorage.." ".. essence:sub(20).." available"}
		else
			-- can only transfer full amount direct to crafter
			-- if a chest has 32 items in 1 slot and 32 in another Slot
			-- these have to be sent into the turtle first, dropped into crafter slot 1 and moved to correct position
			totalInStorage = math.floor(totalInStorage / 4) * 4
			if R.size == 0 then	-- process all
				T:saveToLog("initial call lib.loadTurtle("..turtleName..", "..totalInStorage.." essence")
				local processed = 0
				local loaded = 0
				
				while totalInStorage > 0 do		-- use ALL stored essence
					if totalInStorage - 256 > 0 then
						loaded = 64
					else
						loaded = totalInStorage / 4
					end
					lib.loadTurtle(availableStorage, availableStorageKeys, turtleName, essence, loaded)
					lib.loadCrafter(crafterName)
					lib.getCrystal()
					processed = processed + loaded
					totalInStorage = totalInStorage - loaded * 4
					lib.runCrafter(crafterName, loaded)
					lib.storeOutput()
				end
			elseif R.size <= 64 then
				local loaded = math.min(R.size, totalInStorage)	-- process requested or available if less
				if loaded > 0 then
					lib.loadTurtle(availableStorage, availableStorageKeys, turtleName, essence, loaded)
					lib.loadCrafter(crafterName)
					lib.getCrystal()
					lib.runCrafter(crafterName, loaded)
					lib.storeOutput()
				end
			else	-- amount > 64
				local processed = 0
				local loaded = 0
				while totalInStorage > 0 and processed < R.size do	-- stop if run out of essence, or reached target
					if totalInStorage - 256 > 0 and R.size - processed >= 64 then
						loaded = 64
					elseif totalInStorage - 256 > 0 and R.size - processed > 0 then
						loaded = R.size - processed
					end
					lib.loadTurtle(availableStorage, availableStorageKeys, turtleName, essence, loaded)
					lib.loadCrafter(crafterName)
					lib.getCrystal()
					processed = processed + loaded
					totalInStorage = totalInStorage - loaded * 4
					lib.runCrafter(crafterName, loaded)
					lib.storeOutput()
				end
			end
			lib.storeOutput()
		end
		return {"success"}
	end
end

function utils.craftItem(R)
	local message = network.loadStorageLists()	-- initialises or creates lists of where an item can be found: GLOBAL LISTS!
	if message ~= nil then return {message} end
	T:saveToLog("call network.emptyInventory(R, {'sapling', 'propagule', 'dirt', 'crafting'}, {'all'}, true)")
	network.emptyInventory(R, {"sapling", "propagule", "dirt", "crafting"}, {"all"}, true)	-- 2 lists, one for barrels, one for chests
	T:saveToLog("\ncall network.getItemFromNetwork('barrel', 'minecraft:dirt', 169)")
	--network.getItemFromNetwork(storageType, itemRequired, countRequired, toTurtleSlot, ignoreStock)
	local turtleSlot, turtleCount = network.getItemFromNetwork("barrel", "minecraft:dirt", 169, nil, false)
	T:saveToLog("Get from barrel completed: turtleSlot = "..turtleSlot..", turtleCount = "..turtleCount..", ignoreStock = "..tostring(ignoreStock))
	if turtleCount < 169 then
		T:saveToLog("\ncall network.getItemFromNetwork('chest', 'minecraft:dirt', ".. 169 - turtleCount..", ignoreStock = "..tostring(ignoreStock)..")")
		turtleSlot, turtleCount = network.getItemFromNetwork("chest", "minecraft:dirt", 169 - turtleCount, nil, true)
		if turtleCount < 169 then	-- ask player for saplings
			T:checkInventoryForItem({"dirt"}, {169 - turtleCount})
		end
	end
	return {""}
end

function utils.createPath(R) -- 51
	--[[places a path in air/lava/water. R can also be of type int]]
	local length = 0
	local reduce = false
	local torchInterval = 8
	if type(R) == "table" then
		length = R.length
		if R.data == "reduce" then
			reduce = true
		end
		torchInterval = R.torchInterval
	else
		length = R
	end
	local numBlocks = 0
	
	if reduce then
		T:forward(1)
		local blockType = T:getBlockType("down")
		local useBlock = blockType
		while blockType == useBlock do
			T:go("x2F1")
			numBlocks = numBlocks + 1
			blockType = T:getBlockType("down")
		end
		utils.goBack(numBlocks + 1)
	else
		for i = 1, 2 do
			T:fillVoid("down", {}, false)
			T:forward(1)
			numBlocks = numBlocks + 1
		end
		local place = utils.clearVegetation("down")
		while place do -- while air, water, normal ice, bubble column or lava below
			if T:fillVoid("down", {}, false) then -- false if out of blocks
				T:forward(1)
				numBlocks = numBlocks + 1
				if numBlocks % torchInterval == 1 or numBlocks == 0 then
					if T:getItemSlot("minecraft:torch", -1) > 0 then
						T:turnRight(2)
						T:place("minecraft:torch", "forward", false)
						T:turnRight(2)
					end
				end
			else
				break
			end
			if length > 0 and numBlocks >= length then -- not infinite path (length = 0)
				break
			end
			place = utils.clearVegetation("down")
		end
	end
	return {numBlocks} -- returned as a table in case called as task 51 back to main()
end

function utils.createStorage()
	-- start in centre, above 1st level
	T:place("modem", "down")
	utils.goBack(1)
	
	T:place("chest", "down")	-- places with handle at back of turtle
	T:go("R1F1L1")
	T:place("chest", "down")	-- 2nd of pair
	for i = 1, 3 do
		T:go("F1L1")
		T:place("chest", "down")
		T:go("R1F1L1")
		T:place("chest", "down")
	end
	
	T:go("F1L1F1")	-- end at starting position
	network.attachModem()
end

function utils.createWalledSpace(D)
	--[[
	D.width  = #
	D.length = #
	D.height = #
	D.ceiling = false
	D.floor = false
	D.vDirection = "U" or "D"
	D.hDirection = "LR" or "RL"
	D.goHome = true
	T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
	]]
	local turn  = "R1"
	local oTurn = "L1"
	if D.hDirection == "RL" then
		turn    = "L1"
		oTurn   = "R1"
	end
	local placeF = "C1"

	local lib = {}
	
	function lib.getPlace(D, start, finish)
		if start then						-- start of build
			if D.vDirection == "U" then 	-- bottom and going up
				if D.floor then
					return "C2"
				end
			else							-- D.vDirection == "D"
				if D.ceiling then
					return "C0"
				end
			end
		elseif finish then					-- end of build
			if D.vDirection == "U" then 	-- bottom and going up
				if D.ceiling then
					return "C0"
				end
			else
				if D.floor then
					return "C2"
				end
			end
		end

		return ""							-- start and finish both false
	end
	
	function lib.layer(D, start, finish)
		local outward = true
		local place = lib.getPlace(D, start, finish)
		for width = 1, D.width do
			for length = 1, D.length do
				if start or finish then
					T:go(place, false, 0, true)-- place floor / ceiling
				end
				if width == 1 then
					T:go(oTurn..placeF..turn, false, 0, true)		-- face wall and check if block
				elseif width == D.width then						-- checking opposite wall
					if outward then									-- travelling away from start
						T:go(turn..placeF..oTurn, false, 0, true)	-- face wall and check if block
					else											-- travelling towards start
						T:go(oTurn..placeF..turn, false, 0, true)	-- face wall and check if block 
					end					
				end
				-- move forward
				if length < D.length then
					T:forward(1)
				end
			end
			if width < D.width then
				-- change direction
				if outward then
					T:go(placeF..turn.."F1"..oTurn..place..placeF..turn..turn, false, 0, true)
				else
					T:go(placeF..oTurn.."F1"..turn..place..placeF..oTurn..oTurn, false, 0, true)
				end
				outward = not outward
			else
				if outward then
					T:go(placeF..oTurn.."F"..D.width -1 ..oTurn.."F"..D.length - 1 .."C1R2", false, 0, true)
				else
					T:go(placeF..turn.."F"..D.width -1 ..oTurn..placeF..turn..turn, false, 0, true)
				end
			end
		end
	end
	
	T:go("R2"..placeF.."R2", false, 0, true)			-- place block behind
	for height = 1, D.height do
		if height == 1 then
			lib.layer(D, true, false)					-- first layer, so start = true, finish = false
		elseif height == D.height then		
			lib.layer(D, false, true)					-- final layer, so start = false, finish = true
		else
			lib.layer(D, false, false)					-- mid build layer, so start = false, finish = false
		end
		if height < D.height then						-- go up or down unless finished build
			T:go(D.vDirection.."1")
		end
	end
	if D.goHome then-- ends at starting point
		if D.vDirection == "U" then
			T:down(D.height - 1)
		else
			T:up(D.height - 1)
		end
	end
end

function utils.createWaterSource(level)
	if level == nil then
		level = 0
	end
	if level > 0 then
		T:up(level)
	elseif level < 0 then
		T:down(math.abs(level))
	end
	-- assume on flat surface, but allow for blocks above
	T:go("x0C2F1 x0C2F1 x0C2F1 x0C2R1 F1 x0C2F1 x0C2F1 x0C2R1 F1 x0C2F1 x0C2F1 x0C2R1 F1 x0C2F1 x0C2", false, 0, false)
	T:go("R1F1D1", false, 0, false) --move to corner and drop down
	T:go("C2F1R1 C2F1R1 C2F1R1 C2F1R1", false, 0, false)
	T:go("U1")
	for i = 1, 2 do
		T:placeWater("down")
		T:go("F1R1F1R1", false, 0, false)
	end
	-- refill water buckets
	for i = 1, 2 do
		sleep(0.5)
		T:placeWater("down")
	end
	T:go("R2F1R1F1R1")
	-- end above lower left of pond (starting point)
	return {}
end

function utils.drainWaterLava(R) -- 84
	local lib = {}
		
	function lib.startCorner()
		-- assume starting mid 3 high column
		T:go("D1C1R1C1 U1C1 L1C1 U1C1 R1C1 L1D1 C2C0", false, 0, true)
		-- finished on same mid 3 high column with wall in front and right completed
	end
	
	function lib.midWall()
		-- assume starting mid 3 high column
		T:go("D1R1C1 U1C1 U1C1 L1D1 C2C0", false, 0, true)
		-- finished on same mid 3 high column with wall on right completed
	end
	
	function lib.endCorner()
		-- assume starting mid 3 high column
		T:go("D1R1C1 R1C1 U1C1 L1C1 U1C1 R1C1 L2D1 C2C0", false, 0, true)
		-- finished on same mid 3 high column with wall behind and right completed
	end
	
	function lib.backTurn(offset)
		-- assume starting mid 3 high column with completed wall behind
		T:go("L1F"..offset.."L2C1 R1D1C1 U1C1 U1C1 D1")
		-- end next row along the width, facing the back, mid point
		-- wall ahead completed
	end
	
	function lib.frontTurn()
		-- assume starting mid 3 high column facing back
		-- next move is to turn toward previous wall and remove

		T:go("L2D1C1 U1C1 U1C1 D1R1 C2C0 F1R2C1 L1")
		-- end facing back ready to remove wall
	end
	
	function lib.placeRetainingWall(distance)
		-- assume starting above 3 block high area facing front (player)
		--T:down(1)
		for i = 1, distance do
			if i == 1 then -- start wall
				lib.startCorner()
			else
				if i < distance then -- mid wall
					lib.midWall()
				else -- end of the wall
					lib.endCorner()
				end
			end
			if i < distance then
				if not turtle.back() then
					T:go("R2F1R2")
				end
				T:go("C1", false, 0, true)
			end
		end
		return 1
	end
		
	function lib.placeDam(distance)
		--T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
		local waterPresent = false
		for i = 1, distance do
			if T:isWater("down") then
				waterPresent = true
			end
			T:go("C0C2")
			if i < distance then
				if not turtle.back() then
					T:go("R2F1R2")
				end
				T:go("C1", false, 0, true)
			end
		end
		return waterPresent
	end
	
	function lib.removeDam(distance)
		-- facing towards back, dig wall up down and ahead
		for i = 1, distance do
			T:go("x0x2")
			if i < distance then
				T:forward(1)
			end
		end
		T:turnRight(2)
		-- end up back to retaining wall, mid point
	end
	
	if R.data == "" then
		if turtle.detectDown() then -- on solid surface
			turtle.forward()
		end
	end
	if deletesWater then --turtle replaces source so use clearSolid()
		R.silent = true
		R.down = true
		R.up = false
		clearSolid(R)
	else -- mc 1.12.15+ turtle does NOT replace source blocks
		-- place first stone along the length of water and measure length
		R = utils.calculateDimensions(R)
		local depth = 0
		for h = 1, R.height do
			local waterPresent = false -- resets at each level
			local row = 0
			T:go("R2D2", false, 0, true)	-- at start, level 2, facing towards the front, move backards
			--lib.startCorner()
			row = row + lib.placeRetainingWall(R.length)
			lib.backTurn(1)
			if lib.placeDam(R.length) then
				waterPresent = true
			end
			row = row + 1
			-- left side wall has been built, 2 rows of walls laid. row = 2
			while row < R.width - 1 do -- eg width=2, row=2, this will not run. width=5, row=2
				lib.frontTurn()
				lib.removeDam(R.length)
				lib.backTurn(2)
				if lib.placeDam(R.length) then
					waterPresent = true
				end
				row = row + 1
			end
			-- lay right wall
			lib.frontTurn()
			lib.removeDam(R.length)
			lib.backTurn(2)
			row = row + lib.placeRetainingWall(R.length)
			lib.frontTurn()
			lib.removeDam(R.length) -- faces to front on finish
			T:go("L1F1R1")
			lib.removeDam(R.length) -- faces to front on finish
			depth = depth + 3
			T:go("L1F"..R.width - 1 .."R1D1")
			if depth == R.height or not waterPresent then -- still replacing water
				T:up(depth - 1) -- when h == R.height will go up
				break -- in case water dries up before loop has completed
			end
		end
	end
	return {}
end

function utils.dropSand()
	while not turtle.detectDown() do -- over water. will be infinite loop if out of sand
		if not T:place("sand", "down", false) then
			print("Out of sand. Add more to continue...")
			sleep(2)
		end
	end
	return true --will only get to this point if turtle.detectDown() = true
end

function utils.pause(R)
	--[[
	allows 2 turtles to co-operate
	When they face each other and move together
	R.side = "R" or "L"
	]]
	local rsIn = rs.getAnalogueInput("front")
	local rsOut = 1
	local present = false
	local confirmed = false
	local timer = 0
	local endTimer = 0
	local finished = false
	T:go(R.side.."1")
	rs.setAnalogueOutput("front", 0) -- switch off output
	local blockType = T:getBlockType("forward")
	while blockType:find("turtle") == nil do
		menu.colourWrite("Waiting for other turtle "..endTimer, colors.orange, nil, nil, false, true)
		blockType = T:getBlockType("forward")
		sleep(0.1)
		timer = timer + 0.1
		if timer >= 1 then
			timer = 0
			endTimer = endTimer + 1
		end
	end
	timer = 0
	endTimer = 0
	
	while not finished do
		if endTimer == 0 then
			if present then
				if confirmed then
					menu.colourWrite("Turtle confirmed: input = "..rsIn.." output = "..rsOut, colors.orange, nil, nil, false, true)
				else
					menu.colourWrite("Other turtle ok: input = "..rsIn.." output = "..rsOut, colors.orange, nil, nil, false, true)
				end
			else
				menu.colourWrite("Waiting: input = "..rsIn.." output = "..rsOut, colors.orange, nil, nil, false, true)
			end
		end
		sleep(0.1)
		timer = timer + 1
		if endTimer > 0 then
			endTimer = endTimer + 1
		end
		if endTimer >= 10 then -- allows time for other computer to get ready
			finished = true
		end
		rs.setAnalogueOutput("front", 1) -- output 1 as a signal initially
		if present then
			rs.setAnalogueOutput("front", rsOut) -- output 1 as a signal initially
		end
		rsIn = rs.getAnalogueInput("front")
		if rsIn == 1 then
			present = true
			if not confirmed then
				rsOut = 7
			end
		elseif rsIn == 7 then
			present = true
			confirmed = true
			rsOut = 15
		elseif rsIn == 15 or confirmed then
			menu.colourWrite("endTimer active = "..endTimer, colors.orange, nil, nil, false, true)
			endTimer = endTimer + 1 -- start endTimer
		end
	end
	T:go(R.side.."3")
	
	return rsIn -- 15
end

function utils.startWaterFunction(inWater, onWater, maxDescent, goIn)
	--[[
		Use with utils.getWaterStatus
		could be inWater and not onWater if on single layer of water with floor below
	]]
	maxDescent = maxDescent or 1 -- prevents continuous down due to lack of water
	if goIn == nil then	-- turtle should submerge
		goIn = true
	end
	local descent = 0 -- counter for going down
	if inWater then -- job done
		return inWater, onWater
	end
	if onWater and goIn then --inWater already returned so must be false
		if turtle.down() then
			if T:getBlockType("forward"):find("water") ~= nil or T:getBlockType("forward"):find("bubble") ~= nil then
				inWater = true
				return inWater, onWater
			end
		end
	end
	if not onWater then
		T:forward(1)
	end
	-- should now be above water, but may be further down so onWater still false
	while T:getBlockType("down"):find("water") == nil and T:getBlockType("down"):find("bubble") == nil do-- go down until water below
		if turtle.down() then
			descent = descent + 1
			if descent >= maxDescent then -- limit descent in case no water present
				onWater = false
				return inWater, onWater -- false,false
			end
		else
			onWater = false
			return inWater, onWater -- false,false
		end
	end
	-- now above water
	if goIn then
		turtle.down() -- now inside water block
		inWater = true
	end
	return inWater, onWater
end

function utils.fillBucket(direction)
	if T:getWater(direction)  then
		sleep(0.3)
		return true
	else
		return false
	end
end

function utils.getEmptyBucketCount()
	local lastSlot, leastModifier, total, slotData = T:getItemSlot("minecraft:bucket")
	return total
end

function utils.getRoofStats(R)
	local isWidthOdd = R.width % 2 == 1 			-- is the width odd or even?
	local isLengthOdd = R.length % 2 == 1 			-- is the length odd or even?
	if isWidthOdd then
		R.height = math.floor(R.width / 2)			-- eg 7 x 5 roof, layers = 5 / 2 = 2
	else
		R.height = R.width / 2						-- eg 17 x 8 roof, layers = 8 / 2 = 4
	end
	
	local width = 2									-- assume even width with  2 block roof ridge
	local length = R.length - R.height - 1			-- assume even width with  2 block roof ridge
	if isWidthOdd then
		width = 3									-- adjust to allow for single width roof ridge
	end
	if isLengthOdd then
		length = R.length - R.height				-- adjust as 1 layer less
	end
	
	return R, isWidthOdd, isLengthOdd, width, length
end

function utils.getSlotCapacity(slot)
	return turtle.getItemSpace(slot) + turtle.getItemCount(slot)
end

function utils.getWater()
	if deletesWater then
		T:getWater("down") -- take water from source
		sleep(0.2)
		T:getWater("down") -- take water from source
	else
		if not turtle.detectDown() then
			T:go("C2", false, 0, false)
		end
		T:getWater("forward") -- take water from source
		sleep(0.2)
		T:getWater("forward") -- take water from source
	end
end

function utils.getWaterBucketCount()
	-- lastSlot, leastModifier, total, slotData  = T:getItemSlot(item)
	local lastSlot, leastModifier, total, slotData = T:getItemSlot("minecraft:water_bucket")
	return total
end

function utils.getWaterStatus()
	--[[ Usage:
	local inWater, onWater = utils.getWaterStatus() -- returns turtle position near water
	utils.startWaterFunction(onWater, inWater, 2, true) -- move INTO water max 2 blocks down
	utils.startWaterFunction(onWater, inWater, 5, false) -- move ABOVE water max 5 blocks down
	]]
	local onWater = false
	local inWater = false
	for i = 1, 4 do
		if T:getBlockType("forward"):find("water") ~= nil  or T:getBlockType("forward"):find("bubble") ~= nil then
			inWater = true
		end
		T:turnRight(1)
	end
	if T:getBlockType("down"):find("water") ~= nil or T:getBlockType("down"):find("bubble") ~= nil then
		onWater = true
	end
	return inWater, onWater
end

function utils.goBack(blocks)
	blocks = blocks or 1
	local success = true
	for i = 1, blocks do
		if not turtle.back() then
			success = false
			T:go("R2F1R2")
		end
	end
	
	return success
end

function utils.getPrettyPrint(promptColour, menuPromptColour)
	promptColour = promptColour or colors.yellow
	menuPromptColour = menuPromptColour or colors.white
	
	local pp = {}
	pp.prompt = promptColour
	pp.itemColours = {}
	pp.menuPrompt = menuPromptColour
	pp.allowModifier = true -- can the menu return 'q' or 'h' / 'i'
	
	return pp
end

function utils.isStorage(direction)
	local blockType = T:getBlockType(direction)
	if blockType:find("barrel") ~= nil then
		return true, "barrel"
	elseif blockType:find("chest") ~= nil then
		return true, "chest"
	elseif blockType:find("modem") ~= nil then
		return true, "modem"
	end
	
	return false, blockType
end

function utils.isTableEmpty(aTable)
	if next(aTable) == nil then
		return true
	end
	return false
end

function utils.move(R, blocks, reverse)
	if blocks == 0 then return 0 end
	if reverse == nil then
		reverse = false
	end
	if reverse then
		--if R.subChoice == 2 then -- reverse direction
		if R.direction == "down" or R.subChoice == 2 then -- reverse direction
			T:up(blocks)
		else
			T:down(blocks)
		end
		return blocks * -1
	else
		--if R.subChoice == 1 then
		if R.direction == "up" or R.subChoice == 1 then
			T:up(blocks)
		else
			T:down(blocks)
		end
		return blocks
	end
end

function utils.printR(R)
	--[[
		choice = 0,
		subChoice = 0,
		size = 0,
		width = 0,
		length = 0,
		height = 0,
		depth = 0,
		up = false,
		down = false,
		silent = false,
		data = {},
		torchInterval = 0,
		useBlockType = "",
		auto = false,
		side = "",
		direction = "",
		ready = false,
		networkFarm = false,
		mysticalAgriculture = false,
		logType = "",
		treeSize = "",
		message = ""
	]]
	T:clear()
	print("choice= ".. tostring(R.choice)..", subChoice= ".. tostring(R.subChoice))
	print("size= ".. tostring(R.size)..", width= ".. tostring(R.width))
	print("length= ".. tostring(R.length)..", height= ".. tostring(R.height)..", depth= ".. tostring(R.depth))
	print("silent= "..tostring(R.silent)..", up= ".. tostring(R.up)..", down= "..tostring(R.down))
	print("torchInterval= ".. tostring(R.torchInterval))
	print("useBlockType= "..tostring(R.useBlockType))
	print("auto= ".. tostring(R.auto)..", side= "..tostring(R.side)..", direction= "..tostring(R.direction))
	print("ready= ".. tostring(R.ready)..", networkFarm= "..tostring(R.networkFarm)..", mysticalAgriculture= "..tostring(R.mysticalAgriculture))
	print("logType= ".. tostring(R.logType)..", treeSize= "..tostring(R.treeSize)..", message= "..tostring(R.message))
	if type(R.data) == "table" then
		io.write("data= ")
		for k,v in pairs(R.data) do
			print(k ..": "..tostring(v))
		end
	else
		print("data= ".. tostring(R.data))
	end
	io.write("Enter to continue")
	read()
end

function utils.setStorageOptions()
	local storage = ""
	local storageBackup = ""
	if T:getItemSlot("barrel") > 0 then
		storage = "barrel"
		storageBackup = "barrel"
	end
	if T:getItemSlot("chest") > 0 then
		if storage == "" then
			storage = "chest"
		end
		storageBackup = "chest"
	end
	return storage, storageBackup
end

function utils.tableConcat(tbl, sep)
    local output = ""
    for i,value in pairs(tbl) do
        output = output .. tostring(value)
        if i ~= #tbl then
            output = output .. sep
        end
    end

    return output
end

function utils.tableContains(tableName, value, exactMatch)
	exactMatch = exactMatch or false
	for k, v in ipairs(tableName) do
		if exactMatch then
			if v == value then
				return true
			end
		else
			if v:find(value) ~= nil then
				return true
			end
		end
	end
	return false
end

function utils.useSticksAsFuel()
	local slot = T:getItemSlot("minecraft:stick") 
	if slot > 0 then -- use any sticks to refuel
		turtle.select(slot)
		turtle.refuel()
	end
	slot = T:getItemSlot("minecraft:mangrove_roots") 
	if slot > 0 then -- use any roots to refuel
		turtle.select(slot)
		turtle.refuel()
	end
end

function utils.waitForInput(message)
	-- debugging. Pause script and asks user to continue
	-- global dbug flag has to be set first
	if dbug then 
		if message ~= nil then
			print(message)
			T:saveToLog(message, false)
		end
		menu.colourPrint("Enter to continue...", colors.lightBlue)
		--io.write("Press Enter to continue...")
		return read()
	end
end

function utils.writeTraceTable(description, tbl)
	local text = ""
	for key, value in pairs(tbl) do
		if type(value) == "table" then
			for k,v in pairs(value) do
				text = text.."k = "..k..", v = "..v.."; "
			end
		else
			text = "key = "..key..", value = "..value
		end
	end
	T:saveToLog(description.."\n".. text)
end

local pp = utils.getPrettyPrint()

local function buildWall(R)
	-- T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
	local lib = {}
	
	function lib.singleLayer(R)
		for l = 1, R.length do
			if l == R.length and R.data == "house" then
				T:turnRight(1)
			end
			utils.goBack(1)
			T:go("C1", false, 0, false, R.useBlockType)
		end
	end
	
	function lib.doubleLayer(R)
		for l = 1, R.length do
			T:go("C2", false, 0, false, R.useBlockType)
			if l == R.length and R.data == "house" then
				T:turnRight(1)
			end
			utils.goBack(1)
			T:go("C1", false, 0, false, R.useBlockType)
		end
	end
	
	function lib.tripleLayer(R)
		for l = 1, R.length do
			T:go("C2C0", false, 0, false, R.useBlockType)
			if l == R.length and R.data == "house" then
				T:turnRight(1)
			end
			utils.goBack(1)
			T:go("C1", false, 0, false, R.useBlockType)
		end
	end
	
	-- R.width preset to 1
	local remaining = R.height
	
	if R.subChoice == 1 then
		T:forward(1)			-- face forward, move over first block
	end
	if R.height > 1 then
		T:up(1)					-- go up 1 block
	end
	if R.data ~= "house" then
		T:turnRight(2)				-- rotate 180
	end
	if R.height == 1 then		-- single block: place in front
		lib.singleLayer(R)
	elseif R.height == 2 then	-- 2 blocks, go backwards, place below and ahead
		lib.doubleLayer(R)
	else
		while remaining >= 3 do
			lib.tripleLayer(R)
			remaining = remaining - 3
			if remaining == 1 then
				T:go("U2F1R2")
			elseif remaining > 1 then
				T:go("U3F1R2")
			end
		end
		if remaining == 1 then
			lib.singleLayer(R)
		elseif remaining == 2 then
			lib.doubleLayer(R)
		end
	end
	if not R.silent then
		while turtle.down() do end
	end
	
	return {}
end

local function buildStructure(R)
	local lib = {}
	
	function lib.goDown(R)
		--T:go("L1F1 R1F1 L1")	-- now on ground floor
		if R.height > 1 then
			T:down(1)
		end
	end
	local buildHeight = R.height
	local height = R.height
	local width = R.width
	local length = R.length
	
	if R.subChoice == 1 then
		T:forward(1)			-- face forward, move over first block
	end
	if R.height > 3 then
		R.height = 3
	end
	T:turnRight(2)
	R.data = "house"
	R.silent = true	-- prevent return to ground after buildWall(R)
	R.subChoice = 2	-- do not move forward when building walls
	while height > 0 do
		buildWall(R)
		
		lib.goDown(R)
		R.length = width - 1
		buildWall(R)
		lib.goDown(R)
		
		R.length = length - 1
		buildWall(R)
		lib.goDown(R)
		
		R.length = width - 2
		buildWall(R)
		height = height - R.height	-- 1, 2 or 3
		if height > 0 then
			T:go("U2 R1F1 L1F1")
			R.height = height
			if height > 3 then
				R.height = 3
			end
			R.length = length
		end
	end
	
	T:go("U2F2")
	while turtle.down() do end
	T:go("R1F1R1")
	
	return {}
end

local function buildGableRoof(R)
	--[[
	stairs placement:
	   _|   up
	  
	   T L  forward
	   _
	    |   down

	]]
	local lib = {}
	
	function lib.placeRoof(R, outward)
		for i = 1, R.length + 2 do
			if R.useBlockType:find("stairs") ~= nil then
				T:place("stairs", "up")
			else
				T:go("C0", false, 0, false, R.useBlockType)
			end
			if i < R.length + 2 then
				if outward then
					T:go("L1F1R1")
				else
					T:go("R1F1L1")
				end
			end
		end
	end
	
	function lib.placeGable(R, outward)
		local width = R.width
		for h = 1, R.height do
			for w = 1, width do
				T:go("C1")
				if w < width then
					if outward then
						T:go("L1F1R1")
					else
						T:go("R1F1L1")
					end
				end
			end
			if h < R.height then
				if outward then
					T:go("R1F1L1U1")
				else
					T:go("L1F1R1U1")
				end
			end
			width = width - 2
			outward = not outward
		end
		return outward
	end
	
	local outward = true
	-- go to centre of end wall if odd no, or half width if even
	R.height = math.floor(R.width / 2)
	local isOdd = R.width % 2 == 1 
	
	utils.goBack(1)
	T:go("R1F"..R.height - 1 .."U"..R.height - 1)	-- top of roof, under top layer
	for h = 1, R.height + 1 do						-- place tiles on left side of roof
		lib.placeRoof(R, outward)
		if h < R.height + 1 then
			utils.goBack(1)
			T:down(1)
			outward = not outward
		end
	end
	if isOdd then
		T:go("F"..R.height + 2 .."R2U"..R.height)
	else
		T:go("F"..R.height + 1 .."R2U"..R.height)
	end
	for h = 1, R.height + 1 do						-- place tiles on right side of roof
		lib.placeRoof(R, outward)
		if h < R.height + 1 then
			utils.goBack(1)
			T:down(1)
			outward = not outward
		end
	end
	-- gable ends
	if outward then
		T:go("F1R1U1")
	else
		T:go("F1L1U1")
	end
	outward = lib.placeGable(R, outward)
	T:go("F2R2 C1R2F"..R.length - 1 .."D"..R.height - 1)
	if outward then
		T:go("R1F"..R.height - 1 .."R1")
	else
		T:go("L1F"..R.height - 1 .."L1")
	end
	outward = not outward
	outward = lib.placeGable(R, outward)
	if isOdd then
		if outward then
			T:go("L1F1R1U2F1")
		else
			T:go("R1F1L1U2F1")
		end
		for i = 1, R.length do
			T:go("C2F1", false, 0, false)
		end
		for i = 1, R.length + 2 do
			utils.goBack(1)
			T:place("slab", "forward")
		end
	end
	while turtle.down() do end
	
	return {}
end

local function buildPitchedRoof(R)
	--[[
	stairs placement:
	   _|   up
	  
	   T L  forward
	   _
	    |   down

	]]
	local lib = {}
		
	function lib.placeRoofSection(length)
		-- starts facing centre of building
		for i = 1, length do
			if i < length then
				if R.useBlockType:find("stairs") ~= nil then
					T:place("stairs", "up")
				else
					T:go("C0", false, 0, false, R.useBlockType)
				end
				T:go("L1F1R1")
			end
		end
		-- ends facing centre of building
	end
	
	function lib.placeRoof(R, width, length)
		lib.placeRoofSection(length)
		T:go("R1")
		lib.placeRoofSection(width)
		T:go("R1")
		lib.placeRoofSection(length)
		T:go("R1")
		lib.placeRoofSection(width)
	end
	
	function lib.placeSlabs(length)
		-- add slabs at top
		T:go("U2F1L1")
		if length > 1 then
			T:forward(length - 3)
			for i = 1, length - 3 do
				T:place("slab", "forward")
				utils.goBack(1)
			end
			T:place("slab", "forward")
		else
			T:place("slab", "forward")
		end
		T:go("D2R1")
		utils.goBack(1)
	end
	--[[
	Turtle MUST be placed on left corner of shortest dimension
	
	****   or T******
	****      *******
	****      *******
	****
	T***
	shortest dimension is R.width
	if width is odd, ignore top layer as is only 1 block wide
	]]
	local isWidthOdd, isLengthOdd, width, length = false, false, 0, 0
	R, isWidthOdd, isLengthOdd, width, length = utils.getRoofStats(R)
	T:go("F"..R.height - 1 .."R1F"..R.height - 1 .."U"..R.height - 1)		-- top of roof, under top layer
	if isWidthOdd then
		lib.placeSlabs(length)
	end
	for h = 1, R.height + 1 do						-- place tiles on left side of roof
		lib.placeRoof(R, width, length)
		length = length + 2							-- increase dimensions
		width = width + 2
		if h < R.height + 1 then
			utils.goBack(1)
			T:go("D1R1")
			utils.goBack(1)
		end
	end
	while turtle.down() do end
	
	return {}
end

local function clearAndReplantTrees() -- 25
	--[[ clear all trees in a rectangle area defined by walls, fences or non-dirt blocks
	replant with same type of sapling. If original tree 2 blocks wide, replant 4 if possible. ]]
	
	local lib = {}
	
	function lib.getSaplingFromLogType(log)
		--[[ get type of sapling to plant from log type ]]
		if log:find("oak") ~= nil then
			return "minecraft:oak_sapling"
		elseif log:find("spruce") ~= nil then
			return "minecraft:spruce_sapling"
		elseif log:find("birch") ~= nil then
			return "minecraft:birch_sapling"
		elseif log:find("jungle") ~= nil then
			return "minecraft:jungle_sapling"
		elseif log:find("acacia") ~= nil then
			return "minecraft:acacia_sapling"
		elseif log:find("dark_oak") ~= nil then
			return "minecraft:dark_oak_sapling"
		end
		return "sapling"
	end
	
	function lib.plantSapling(sapling, double)
		--[[ plant sapling(s) ]]
		if sapling == "" or sapling == nil then sapling = "sapling" end
		T:up(1)
		lib.suck()
		if double then	-- check if enough saplings
			--slotData.lastSlot, slotData.leastModifier, total, slotData = T:getItemSlot(sapling, -1)
			local a, b, total, _ = T:getItemSlot(sapling, -1)
			if total >= 4 then
				for i = 1, 4 do
					T:place(sapling, "down")
					T:go("F1R1")
				end
				T:forward(1)		-- above pre-planted sapling
			else
				if not T:place(sapling, "down") then
					T:place("sapling", "down")
				end
			end
		else
			if not T:place(sapling, "down") then
				T:place("sapling", "down")
			end
		end
		turtle.select(1)
	end
		
	function lib.suck()
		--[[ Collect saplings, sticks and apples ]]
		turtle.select(1)
		turtle.suck()
		turtle.suckUp()
		turtle.suckDown()
	end
	
	function lib.turn(direction)
		--[[ change direction and return new value for direction ]]
		if direction == "r" then
			T:turnRight(1)
			direction = "l"
		else
			T:turnLeft(1)
			direction = "r"
		end
		return direction	-- will only change direction variable if return value is used
	end
	
	function lib.emptyInventory(blockTypeD)
		--[[ Empty all except 32 of each sapling and 1 chest ]]
		if blockTypeD == nil then
			blockTypeD = T:getBlockType("down")
		end
		if blockTypeD:find("chest") ~= nil or blockTypeD:find("barrel") ~= nil then
			-- empty logs, apples, sticks and all but 1 stack of each sapling type
			T:emptyInventorySelection("down", {"chest", "oak_sapling", "birch_sapling", "spruce_sapling", "acacia_sapling", "jungle_sapling","dark_oak_sapling"},{1, 32, 32, 32, 32, 32, 32})
			return true
		else
			return false
		end
	end
	
	function lib.moveDown(blockTypeD)
		--[[ move down until hit ground. Break leaves and continue ]]
		if blockTypeD == nil then
			blockTypeD = T:getBlockType("down")
		end
		while blockTypeD == "" or blockTypeD:find("leaves") ~= nil do	-- move down, breaking leavse
			T:down(1)
			lib.suck()
			blockTypeD = T:getBlockType("down")
		end
		return blockTypeD
	end
	
	function lib.moveForward()
		--[[ Move forward 1 block only, go down to ground while air or leaves below ]]
		local blockTypeF = T:getBlockType("forward")
		local blockTypeD = T:getBlockType("down")
		if blockTypeF == "" or blockTypeF:find("leaves") ~= nil then	-- air or leaves ahead
			T:forward(1)												-- move forward, breaking leaves
			T:dig("up")													-- remove leaves / low branches above to allow space for player
			lib.suck()
			blockTypeD = lib.moveDown()
			if not lib.emptyInventory(blockTypeD) then					-- check if above a corner chest / barrel
				if lib.isBorder(blockTypeD) then						-- not above chest so check if above border
					return false, blockTypeD							-- above a border block so stop
				end
			end
			blockTypeF = T:getBlockType("forward")
			return true, blockTypeF										-- moved ok, could be air or block in front
		end
		return false, blockTypeF 										-- did not move, obstacle in front NOT leaves or air
	end
	
	function lib.moveUp(blockTypeF)
		--[[ Move up until air in front (dig leaves / harvest tree) ]]
		if blockTypeF == nil then
			blockTypeF = T:getBlockType("forward")
		end
		while blockTypeF:find("dirt") ~= nil or
			  blockTypeF:find("grass_block") ~= nil or
			  T:isVegetation(blockTypeF) do	-- go up while dirt, grass-block or any vegetation in front
			T:up(1)
			blockTypeF = T:getBlockType("forward")
			if blockTypeF:find("log") ~= nil then
				lib.harvestTree(blockTypeF)
				return T:getBlockType("forward")
			elseif blockTypeF:find("leaves") ~= nil then
				T:dig("forward")
				return ""
			end
		end
		return blockTypeF	-- should be "" (air) or any border block
	end
	
	function lib.harvestTree(blockTypeF)
		--[[ Fell tree, returns true if double size ]]
		-- clsTurtle.harvestTree(extend, craftChest, direction)
		local saplingType = lib.getSaplingFromLogType(blockTypeF)
		local double = T:harvestTree(false, false, "forward")	-- assume single tree, will auto-discover
		lib.plantSapling(saplingType, double)
	end
	
	function lib.safeMove()
		--[[ move forward until border reached. loop breaks at that point ]]
		local blockTypeF = ""
		local success = true
		while success do
			success, blockTypeF = lib.moveForward()				-- move forward 1 block, return block type ahead
			if not success then 								-- did not move forwards, block in the way: either log, dirt/grass, border block or vegetation
				if blockTypeF:find("log") then 					-- tree found
					lib.harvestTree(blockTypeF)
					success = true								-- block (log) removed, try again
				else
					success = not lib.isBorder(blockTypeF)		-- Is at border?: if is at border success = false so loop stops
					if success then								-- Not at border. Dirt/grass vegetation in front
						blockTypeF = lib.moveUp(blockTypeF)		-- move up until leaves/log/air
						success = not lib.isBorder(blockTypeF)	-- Is at border?: if is at border success = false so loop stops
						if success then							-- keep moving forward
							if blockTypeF:find("log") then 		-- tree found
								lib.harvestTree(blockTypeF)	
							end
																-- else blockTypeF is air/leaves  border has been checked
						end
					end
				end
			end													-- else success = true, 1 block moved so continue
		end
	end
	
	function lib.isBorder(blockType)
		--[[ Is the block log, dirt, grass_block, vegetation: non-border, or other:border]]
		if blockType == nil then 					-- not passed as parameter
			blockType = T:getBlockType("forward")
		end
		if blockType == "" then 					-- air ahead: not border
			return false, ""
		else										-- could be border or other
			if blockType:find("dirt") ~= nil or blockType:find("grass_block") ~= nil or blockType:find("log") ~= nil then -- either dirt, grass block or log
				return false, blockType				-- dirt, grass, log: not border
			end
			if T:isVegetation(blockType) then 		-- vegetation found: not border
				return false, blockType
			end
		end
		return true, blockType						-- dirt, grass_block, log and vegetation eliminated:must be border
	end
	
	function lib.inPosition()
		--[[ check if in lower left corner ]]
		local inPosition = true 		-- assume correct
		if not turtle.detectDown() then	-- hanging in mid-air
			return false
		end
		T:turnLeft(1)
		if lib.isBorder() then
			-- so far so good
			T:turnLeft(1)
			if not lib.isBorder() then 	-- not in correct place
				inPosition = false
			end
			T:turnRight(2) 				-- return to original position
		else
			inPosition = false
			T:turnRight(1) 				-- return to original position
		end
		return inPosition
	end
	
	function lib.findBorder()
		--[[ assume started after reset. if log above harvest tree else return to ground. Find starting corner]]
		local blockType = T:getBlockType("up")					-- dig any logs above, return to ground
		local log = "sapling"
		if blockType:find("log") ~= nil then					-- originally felling a tree so complete it
			log = lib.getSaplingFromLogType(blockType)
			local double = T:harvestTree(false, false, "up")	-- assume single tree, will auto-discover
			lib.plantSapling(log, double)
		else													-- no log above so go downm
			blockType = lib.moveDown()							-- return to ground (or vegetation)
		end
		lib.safeMove()											-- move forward until border reached
		T:turnRight(1)
		lib.safeMove()											-- move forward until second border reached
		T:turnRight(1)											-- should now be in correct position
		lib.emptyInventory()									-- empty inventory if above a chest
	end
	
	local direction = "r"
	local blockTypeF = ""
	local success = false
	if not lib.inPosition() then 
		lib.findBorder()
	end
	local secondBorderFound = false
	while not secondBorderFound do
		lib.safeMove()														-- moves forward until reaches border forward or below
		lib.turn(direction)													-- turn r or l. direction is not changed
		success, blockTypeF = lib.isBorder()								-- no blockType passed as parameter so will return current block in new forward direction
		if success then
			secondBorderFound = true										-- game over
		elseif blockTypeF:find("log") ~= nil then							-- tree in front
			lib.harvestTree(blockTypeF)
		elseif blockTypeF == "" or blockTypeF:find("leaves") ~= nil then	-- air or leaves in front
			T:forward(1)													-- move forward 1 block
			lib.moveDown()													-- go down if required
		elseif	blockTypeF:find("dirt") ~= nil or
				blockTypeF:find("grass_block") ~= nil or
				T:isVegetation(blockTypeF) then								-- dirt, grass_block or vegetation in front
			blockTypeF = lib.moveUp(blockTypeF)								-- move up until air or border ahead.
			if lib.isBorder(blockTypeF) then								-- border ahead
				secondBorderFound = true
			else															-- air ahead									
				T:forward(1)												-- move forward 1 block
			end
		end
		direction = lib.turn(direction)										-- turn r or l. direction is changed to opposite
	end
	lib.moveDown()															-- return to ground level
	lib.emptyInventory()
	return {}
end

local function clearArea(R) -- 71, called from 22
	local evenWidth = false
	local evenHeight = false
	local loopWidth
	-- go(path, useTorch, torchInterval, leaveExisting)
	if R.width % 2 == 0 then
		evenWidth = true
		loopWidth = R.width / 2
	else
		loopWidth = math.ceil(R.width / 2)
	end
	if R.length % 2 == 0 then
		evenHeight = true
	end
	turtle.select(1)
	-- clear an area between 2 x 4 and 32 x 32
	-- if R.width is even no, then complete the up/down run
	-- if R.width odd no then finish at top of up run and reverse
	-- should be on flat ground, check voids below, harvest trees
	for x = 1, loopWidth do
		-- Clear first column (up)
		for y = 1, R.length do
			if R.useBlockType == "dirt" then
				if not turtle.detectDown() then
					T:place("minecraft:dirt", "down", true)
				else --if not water, dirt, grass , stone then replace with dirt
					blockType = T:getBlockType("down")
					if blockType ~= "" then
						if blockType ~= "minecraft:dirt" and blockType ~= "minecraft:grass_block" then
							turtle.digDown()
							T:place("minecraft:dirt", "down", true)
						end
					end
				end
			end
			if y < R.length then
				T:go("F1+1", false,0,false)
			end
		end
		-- clear second column (down)
		if x < loopWidth or (x == loopWidth and evenWidth) then -- go down if on R.width 2,4,6,8 etc
			T:go("R1F1+1R1", false,0,false)
			for y = 1, R.length do
				if R.useBlockType == "dirt" then
					if not turtle.detectDown() then
						T:place("minecraft:dirt", "down", true)
					else
						blockType = T:getBlockType("down")
						if blockType ~= "" then
							if blockType ~= "minecraft:dirt" and blockType ~= "minecraft:grass_block" then
								turtle.digDown()
								T:place("minecraft:dirt", "down", true)
							end
						end
					end
				end
				if y < R.length then
					T:go("F1+1", false, 0, false)
				end
			end
			if x < loopWidth then 
				T:go("L1F1+1L1", false,0,false)
			else
				T:turnRight(1)
				T:forward(R.width - 1)
				T:turnRight(1)
			end
		else -- equals R.width but is 1,3,5,7 etc
			T:turnLeft(2) --turn round 180
			T:forward(R.length - 1)
			T:turnRight(1)
			T:forward(R.width - 1)
			T:turnRight(1)
		end
	end
	return {}
end

local function clearRectangle(R) -- 72
	--local function clearRectangle(width, length, up, down)
	-- height = 0: one level, 1 = +up, 2 = +down, 3 = +up/down
	local lib = {}
	function lib.UpDown(length)
		for l = 1, length do
			--T:go("x0x2F1x0x2")
			turtle.digDown()				-- dig below
			while turtle.digUp() do end		-- dig up including gravity blocks
			while not turtle.forward() do	-- if no block in front, moves forward
				turtle.dig()				-- block in front, so dig it
			end
			turtle.digDown()				-- now moved forward so dig down again
			while turtle.digUp() do end		-- dig up again including gravity blocks
		end
	end
	
	function lib.Up(length)
		for l = 1, length do
			--T:go("x0F1x0")
			while turtle.digUp() do end
			while not turtle.forward() do	-- if no block in front, moves forward
				turtle.dig()				-- block in front, so dig it
			end
			while turtle.digUp() do end
		end
	end
	
	function lib.Down(length)
		for l = 1, length do
			--T:go("x2F1x2")
			turtle.digDown()
			while not turtle.forward() do	-- if no block in front, moves forward
				turtle.dig()				-- block in front, so dig it
			end
			turtle.digDown()
		end
	end
	
	function lib.Forward(length)
		T:forward(length)
	end
	
	-- could be 1 wide x xx R.length (trench) R.up and return
	-- could be 2+ x 2+
	-- even no of runs return after last run
	-- odd no of runs forward, back, forward, reverse and return
	turtle.select(1)
	if R.width == 1 then 					-- single block trench ahead only
		if R.up and R.down then				-- single block wide trench dig R.up and R.down = 3 blocks deep
			lib.UpDown(R.length - 1)
		elseif R.up then					-- single block wide trench dig R.up = 2 blocks deep
			lib.Up(R.length - 1)
		elseif R.down then					-- single block wide trench dig R.down = 2 blocks deep
			lib.Down(R.length - 1)
		else 								-- single block wide = 1 block deep
			lib.Forward(R.length - 1)
		end
		T:turnRight(2)						-- turn at the top of the run
		T:forward(R.length - 1)				-- return to start
		T:turnRight(2)						-- turn round to original position
	else 									-- R.width 2 or more blocks
		local iterations = 0 				-- R.width = 2, 4, 6, 8 etc
		if R.width % 2 == 1 then  			-- R.width = 3, 5, 7, 9 eg R.width 7
			iterations = (R.width - 1) / 2 	-- iterations 1, 2, 3, 4 for widths 3, 5, 7, 9
		else
			iterations = R.width / 2		-- iterations 1, 2, 3, 4 for widths 2, 4, 6, 8
		end
		for i = 1, iterations do 			-- eg 3 blocks wide, iterations = 1
			if R.up and R.down then							-- dig R.up and R.down
				lib.UpDown(R.length - 1)
				T:go("x0x2R1F1x0x2R1x0x2")				-- turn round
				lib.UpDown(R.length - 1)
			elseif R.up then								-- dig R.up
				lib.Up(R.length - 1)
				T:go("x0R1F1x0R1x0")
				lib.Up(R.length - 1)
			elseif R.down then							-- dig R.down
				lib.Down(R.length - 1)
				T:go("x2R1F1x2R1x2")
				lib.Down(R.length - 1)
			else										-- no digging R.up or R.down
				lib.Forward(R.length - 1)
				T:go("R1F1R1")
				lib.Forward(R.length - 1)
			end
			-- if 1 less than end, reposition for next run
			if i < iterations then
				T:go("L1F1L1", false, 0, false)
			end
		end
		if R.width % 2 == 1 then  -- additional run and return to base needed
			T:go("L1F1L1", false, 0, false)
			if R.up and R.down then
				lib.UpDown(R.length - 1)
			elseif R.up then
				lib.Up(R.length - 1)
			elseif R.down then
				lib.Down(R.length - 1)
			else
				lib.Forward(R.length - 1)
			end
			T:turnRight(2)
			T:forward(R.length - 1)
		end
		T:go("R1F"..R.width - 1 .."R1", false, 0, false)
	end
	return {}
end

local function clearPerimeter(R) -- 74
	local lib = {}
	function lib.UpDown(length)
		for l = 1, length do
			T:go("x0x2F1x0x2")
		end
	end
	
	function lib.Up(length)
		for l = 1, length do
			T:go("x0F1x0")
		end
	end
	
	function lib.Down(length)
		for l = 1, length do
			T:go("x2F1x2")
		end
	end
	
	function lib.Forward(length)
		T:forward(length)
	end
	
	if R.up and R.down then
		for i = 1, 2 do
			lib.UpDown(R.length - 1)
			T:turnRight(1)
			lib.UpDown(R.width - 1)
			T:turnRight(1)
		end
	elseif R.up then
		for i = 1, 2 do
			lib.Up(R.length - 1)
			T:turnRight(1)
			lib.Up(R.width - 1)
			T:turnRight(1)
		end
	elseif R.down then
		for i = 1, 2 do
			lib.Down(R.length - 1)
			T:turnRight(1)
			lib.Down(R.width - 1)
			T:turnRight(1)
		end
	else
		for i = 1, 2 do
			lib.Forward(R.length - 1)
			T:turnRight(1)
			lib.Forward(R.width - 1)
			T:turnRight(1)
		end
	end
	return {}
end

local function clearBuilding(R) -- 75, 43
	--[[
	menu item: Clear hollow structure
	Clear the outer shell of a building, leaving inside untouched. Optional floor/ceiling removal
	if outside active area will have already moved in
	R.direction = "up" or "down" as direction of travel
	R.up = true / false to dig up as well 
	R.down = true / false to dig down as well
	R.data.ceiling = true / false to remove ceiling
	R.data.floor = true / false to remove floor
	examples use a 5 x 5 x 7 cube
	]]
--utils.printR(R)									-- debug values in R
	local height = 1								-- current level of turtle
	local cleared = false
	R.silent = true
	R.up = false
	R.down = false
	-- check if floor/ceiling is to be cleared
	if R.direction == "up" then						-- from bottom to top
		if R.data.floor then
			clearRectangle(R)
			cleared = true
		end
	else											-- from top to bottom
		if R.data.ceiling then
			clearRectangle(R)
			cleared = true
		end
	end
	
	if R.height == 1 and not cleared then			-- only 1 layer, perimeter only eg R.height = 7
		clearPerimeter(R)
	elseif R.height == 2 and not cleared then		-- only 2 layers, perimeter only
		if R.direction == "up" then					-- from bottom to top
			R.up = true
		else
			R.down = true
		end
		clearPerimeter(R)
	elseif R.height >= 3 then 						-- 3 or more levels, floor/ceiling already assessed eg R.height = 7
		R.up = true
		R.down = true
		height = height + utils.move(R, 1)			-- move up/down 1 block for first layer eg height: 1 + 1 = 2
		-- height h + 3 R.height   loop
		--	2		5		5		end
		--	2		5		7		+
		--	5		8		7		end
		repeat 			
			clearPerimeter(R)						-- runs at least once, removes 3 layers: 1,2,3
			local move = 3
			--if height + 3 < R.height then			-- range with min 3(0), 4(1), 5(2), 6(3), 7(4), 8(5), 9(6) etc			
				--height = height + utils.move(R, move)	-- move up/down 3 blocks eg height 5, 8, 11, 14
			--else
				--move = R.height - height - 1
				--height = height + utils.move(R, move)	-- move up/down 1-2 blocks eg height = 2 + 3 = 5
			--end
			
			if height + 3 >= R.height then			-- range with min 3(0), 4(1), 5(2), 6(3), 7(4), 8(5), 9(6) etc			
				move = R.height - height
			end
			height = height + utils.move(R, move)	-- move up/down 1-2 blocks eg height = 2 + 3 = 5
		until height > R.height - 3				-- min 3 levels eg height = 2, R.height - 3 --> 7 - 3 = 4, 4 - 3 = 1
		R.up = false
		R.down = false	
		if height == R.height then						-- already on top/bottom layer eg height = 5, R.height = 5
			if R.direction == "up" then						-- reverse digging direction. Up = move to top and dig down
				R.down = true
			else										-- reverse digging direction. Up = move to floor and dig up
				R.up = true
			end
			clearPerimeter(R)
		else
			if R.direction == "up" then						-- reverse digging direction. Up = move to top and dig down
				R.down = true
			else										-- reverse digging direction. Up = move to floor and dig up
				R.up = true
			end

			clearPerimeter(R)
		end
	end
	
	R.up = false
	R.down = false
	if R.direction == "up" then
		if R.data.ceiling then		-- from bottom to top
			clearRectangle(R)
		end
	elseif R.direction == "down" then
		if R.data.floor then	-- from top to bottom
			clearRectangle(R)
		end
	end
	
	if height > 1 then
		utils.move(R, height - 1, true) -- reverse direction
	end
	
	return {}
end

local function clearMineshaft(R, equippedRight, equippedLeft, inInventory) -- 19
	local lib = {}
	
	function lib.checkCobweb(directions, inInventory)
		assert(type(directions) == "table", "directions must be a table eg {'up','down'}")
		for _, direction in ipairs(directions) do
			local blockType = T:getBlockType(direction)
			if inInventory == "minecraft:diamond_sword" then -- using a sword
				local side = "left"
				
				if blockType:find("cobweb") ~= nil then
					--clsTurtle.equip(self, side, useItem, useDamage)
					if equippedRight == "minecraft:diamond_pickaxe" then
						side = "right"
					end
					T:equip(side, "minecraft:diamond_sword")
					T:dig(direction)
					T:equip(side, "minecraft:diamond_pickaxe")
				elseif blockType ~= "" then
					T:dig(direction)
				end
			else
				T:dig(direction)
			end
		end
	end

	-- check position by rotating until facing away from wall
	length = 0
	torch = 0
	turns = 0
	while not turtle.detect() do
		T:turnRight(1)
		turns = turns + 1
		if turns > 4 then
			return {"I am not facing a wall. Unable to continue"}
		end
	end
	T:turnRight(2)
	-- move forward until obstructed, digging up/down. place torches
	while not turtle.detect() do
		lib.checkCobweb({"up","down"}, inInventory) -- dig cobweb or any other block up/down
		length = length + 1
		torch = torch + 1
		if torch == R.torchInterval then
			torch = 0
			T:place("minecraft:torch", "down", false) ---(self, blockType, damageNo, direction, leaveExisting, signText)
		end
		lib.checkCobweb({"forward"}, inInventory) -- dig cobweb or any other block in front
		T:forward(1)
	end
	-- turn right, forward, right, return to start with up/down dig
	T:go("R1")
	lib.checkCobweb({"up","down"}, inInventory) -- dig cobweb or any other block up/down
	T:go("F1R1")
	for i = 1, length, 1 do
		lib.checkCobweb({"up", "down", "forward"}, inInventory) -- dig cobweb or any other block up/down/forward
		T:forward(1)
	end
	-- move to other wall and repeat.
	T:go("R1")
	lib.checkCobweb({"up","down"}, inInventory) -- dig cobweb or any other block up/down
	T:go("F1")
	lib.checkCobweb({"up","down"}, inInventory) -- dig cobweb or any other block up/down
	T:go("F1R1")
	lib.checkCobweb({"up","down"}, inInventory) -- dig cobweb or any other block up/down
	for i = 1, length, 1 do
		lib.checkCobweb({"up", "down", "forward"}, inInventory) -- dig cobweb or any other block up/down/forward
		T:forward(1)
	end
	lib.checkCobweb({"up", "down"}, inInventory) -- dig cobweb or any other block up/down/forward
	
	return {}
end

local function clearMonumentLayer(R) -- 85
	R.up = true
	R.down = true
	R.silent = true
	if R.subChoice == 0 then
		R.up = false
		R.down = false
	end
	-- send turtle down until it hits bottom
	-- then clear rectangle of given size
	-- start above water, usually on cobble scaffold above monument
	if T:detect("down") then -- in case not over wall
		T:forward(1)
	end
	local height = 1
	-- go down until solid block detected
	while utils.clearVegetation("down") do
		T:down(1)
		height = height + 1
	end
	T:down(1)
	height = height + 1
	clearRectangle(R)
	T:up(height - 1)
	
	return {}
end

local function clearWaterPlants(R) -- 87
	local lib = {}
	
	function lib.getLength()
		local length = 1
		print("Checking water length")
		while utils.clearVegetation("forward") do
			T:forward(1)
			length = length + 1
		end
		for i = 1, length do
			turtle.back()
		end
		return length
	end
	
	function lib.clearDown(D)
		while utils.clearVegetation("down") do --clears any grass or sea plants, returns true if air or water, bubble column or ice
			T:down(1)
			D.depth = D.depth + 1
		end
		-- if slab at bottom, replace with solid block
		D.blockType = T:getBlockType("down")
		if D.blockType:find("slab") ~= nil then
			T:go("C2")
		end
		if D.depth > D.maxDepth then
			D.maxDepth = D.depth
		end
		
		return D
	end
	
	function lib.clearLength(D)
		local moves = 0
		local blockHeight = 1
		D.floorLength = 0 -- reset
		while moves < D.length - 1 do
			if utils.clearVegetation("forward") then
				T:forward(1)
				moves = moves + 1 
				if turtle.detectUp() then -- could be on monument going under arch, or faulty monument floor
					if not D.monumentArchesClear then
						D = lib.checkArches(D)
					end
				end
				local temp = D.depth
				D = lib.clearDown(D) -- go down if in water/air
				if blockHeight == 4 and D.depth - temp == 3 then -- could be just gone over 3 block high column in ocean monument
					if not D.monumentTopClear then
						D = lib.checkTop(D)
					end
					blockHeight = 1
				end
				if D.useBlockType == "prismarine" then
					if D.blockType:find("prismarine") == nil then
						-- on monument floor so restrict forward movement to 8 blocks
						D.floorLength = D.floorLength + 1
						if D.floorLength == 8 then
							D.blockType = T:getBlockType("forward")
							while D.blockType:find("prismarine") == nil do
								T:up(1)
								D.blockType = T:getBlockType("forward")
							end
							D.floorLength = 0
						end
					end
				end
				if moves >= D.length - 1 then
					D.width = D.width + 1	-- another length completed so increase width
					return D
				end
			else -- block in front
				blockHeight = 1
				local waterAbove = utils.clearVegetation("up")
				local waterAhead = utils.clearVegetation("forward") -- true if air/water in front
				while not waterAhead do 	-- solid block in front
					if waterAbove then 		-- move up
						T:up(1)
						D.depth = D.depth - 1
						blockHeight = blockHeight + 1
						if D.depth < 1 then
							D.width = D.width + 1	-- another length completed so increase width
							return D
						end
					else 					-- block above so go back
						while not waterAbove do
							utils.goBack()	--  returns true if no object behind, but moves anyway
							waterAbove = utils.clearVegetation("up")
							moves = moves - 1
							if moves == 0 then
								T:up(1)
								D.depth = D.depth - 1
								waterAbove = utils.clearVegetation("up")
								while not waterAbove do
									T:up(1)
									D.depth = D.depth - 1
								end
							end
						end
						-- go up 1 to prevent loop
						T:up(1)
						D.depth = D.depth - 1
					end
					waterAbove = utils.clearVegetation("up")
					waterAhead = utils.clearVegetation("forward")
				end
			end
		end
		D.width = D.width + 1	-- another length completed so increase width
		D.maxDepth = D.maxDepth + 1 -- +1 to allow for starting pos in top layer
		
		return D 
	end
	
	function lib.checkArches(D)
		-- gone under a block so could be monument arch (6)
		if T:getBlockType("up"):find("prismarine") ~= nil then -- confirm on monument, not previously cleared
			local direction = "" 	-- initialise direction
			T:go("B1U2F1R1")
			if T:getBlockType("forward"):find("prismarine") ~= nil then -- correct guess
				direction = "R"
			else	-- wrong direction. turn round and check other side
				T:go("R2")
				if T:getBlockType("forward"):find("prismarine") ~= nil then
					direction = "L"
				end
			end
			local path = "U1F1 U1F3 D1F1 D1R2 U2F5 D2"
			--for i = 1, 6 do
			T:go(path) -- clears arch top 1 and returns
			T:go(direction.."1F6"..direction.."1")
			T:go(path) -- clears arch top 2 and returns
			T:go(direction.."1F6"..direction.."1")
			T:go(path) -- clears arch top 3 and returns
			T:go(direction.."1F9"..direction.."1")
			T:go(path) -- clears arch top 4 and returns
			T:go(direction.."1F6"..direction.."1")
			T:go(path) -- clears arch top 5 and returns
			T:go(direction.."1F6"..direction.."1")
			T:go(path) -- clears arch top 6 and returns
			
			T:go(direction.."3F34"..direction.."2D2F1")
			D.monumentArchesClear =  true
		end
		return D
	end
	
	function lib.checkTop(D)
		-- gone over 3 block column so could be at the top of ocean monument
		if T:getBlockType("down"):find("prismarine") ~= nil then -- confirm on monument, not previously cleared
			local direction = "" 	-- initialise direction
			T:go("U3R1")			-- up to top of column and try right side
			if T:getBlockType("forward"):find("prismarine") ~= nil then -- correct guess
				direction = "L"
			else	-- wrong direction. turn round and check other side
				T:go("R2")
				if T:getBlockType("forward"):find("prismarine") ~= nil then
					direction = "R"
				end
			end
			if direction ~= "" then -- facing single block on layer 2
				T:go("U1F6"..direction.."1F5".. direction.."1F5"..direction.."1F5"..direction.."1") -- clear 4 single blocks
				T:go("F1U1"..direction.."1F1"..direction.."3") -- on top of monument
				T:go("F3".. direction.."1F3"..direction.."1F3"..direction.."1F3"..direction.."3") -- clear top, face return
				T:go("F2D5"..direction.."3B1")
			end
			D.monumentTopClear = true
		end
		return D
	end
	
	function lib.findBlockTypeEnd(D)
		D.blockType = "" -- reset
		repeat
			if utils.clearVegetation("forward") then
				T:forward(1)
				D = lib.clearDown(D) -- go down if in water/air, D.blockType is updated with floor type
			else -- block in front
				local waterAbove = utils.clearVegetation("up")
				local waterAhead = utils.clearVegetation("forward") -- true if air/water in front
				while not waterAhead do 	-- solid block in front
					if waterAbove then 		-- move up
						T:up(1)
					else 					-- block above so go back
						while not waterAbove do
							utils.goBack()	--  returns true if no object behind, but moves anyway
							waterAbove = utils.clearVegetation("up")
						end
					end
					waterAbove = utils.clearVegetation("up")
					waterAhead = utils.clearVegetation("forward")
				end
			end
		until D.blockType:find(D.useBlockType) == nil
		-- now above a non-prismarine block, facing away from monument
		T:turnRight(2) -- facing monument
		D.blockType = T:getBlockType("forward")
		while D.blockType:find(D.useBlockType) ~= nil do
			T:up(1)
			D.blockType = T:getBlockType("forward")
		end
		T:go("F1L1")
		D.blockType = T:getBlockType("down")
		while D.blockType:find(D.useBlockType) ~= nil do
			T:forward(1)
			D.blockType = T:getBlockType("down")
		end
		turtle.back()
		-- should now be at end of monument base
	end
	
	function lib.turn(D)
		local direction = "R"
		if not D.facingForward then
			direction = "L"
		end
		T:go(direction.. 1)
		if utils.clearVegetation("forward") then
			T:forward(1)
			--D.depth = D.depth + lib.clearDown(depth)
			D = lib.clearDown(D)
		else
			while not utils.clearVegetation("forward") do
				T:up(1)
				D.depth = D.depth - 1
			end
			T:forward(1)
		end
		T:go(direction.. 1)
		D.facingForward = not D.facingForward 
		
		return D
	end

	local D = {}
	D.depth = 0
	D.maxDepth = 0
	D.blockType = ""
	D.useBlockType = R.useBlockType -- "" or "prismarine"
	D.length = 0	-- copy of R.length used in lib.clearLength
	D.width = 0		-- increased every iteration
	D.facingForward = true
	D.monumentTopClear = false
	D.monumentArchesClear = false
	D.inWater = false
	D.onWater = false
	D.inWater, D.onWater = utils.getWaterStatus()
	D.floorLength = 0 -- used on monument floor
	
	if R.data == "clearWaterPlants" then -- NOT monument corner discovery
		D.inWater, D.onWater = utils.startWaterFunction(D.onWater, D.inWater, 2, true) -- move into water
		if R.length == 0 then
			R.length = lib.getLength()
		end
		if R.width == 0 then
			T:turnRight(1)
			R.width = lib.getLength()
			T:turnLeft(1)
		end
	end
	D.length = R.length
	D = lib.clearDown(D) -- go down to floor, set depth, maxDepth, blockType
	if R.data == "clearWaterPlants" then -- NOT monument corner discovery
		if R.width == 1 then
			print("Single row clearing")
			D = lib.clearLength(D) --D.width also increased
		else
			while D.width < R.width do -- D.width starts at 0
				-- now on floor, move along sea/river bed following contour
				D = lib.clearLength(D) --D.width also increased
				-- now turn and repeat
				if D.width < R.width then	
					D = lib.turn(D)
					if D.depth <= 0 then
						break
					end
				end
			end
		end
		-- finished so return to surface
		T:up(1) -- up 1 to check for water below
		while T:getBlockType("down"):find("water") ~= nil do
			T:up(1)
		end
		T:down(2) -- return to surface
		--[[while utils.clearVegetation("forward") do
			T:forward(1)
		end]]
	elseif R.data == "oceanMonumentColumns" then -- monument corner discovery
		-- this function used to find edge of monument base
		if D.blockType:find(D.useBlockType) ~= nil then
			lib.findBlockTypeEnd(D)
			return {""}
		else
			T:up(D.depth)
			return {"Prismarine not found on ocean floor"}
		end
	end
	if R.silent then
		return {D.maxDepth, R.length}
	else
		return {""}
	end
end

local function clearMountainSide(R) -- 78
	--[[
	First row              outward  l  s  f  mid    (length, start, finish, midPoint)

	      >|*|*|           true                     lib.clearRow() moves: 7-5=2, midPoint starts at 2 
	      +|*|*|
	      +|*|*|
	      ^|*|*|        <  false    7  5  6  2      lib.clearRow() moves: 9-2=7, midPoint starts at -4 -1 = -5
	       |*|*|*|	    +
	     |*|*|*|*|*|    +
	  >  |*|*|*|*|*|    ^  true     9  2  6  -4     lib.getStartingLength(). Ends 1 block after block finish
	  ^|*|*|*|*|*|*|*|*|                            starts here, moves up 1
	    1 2 3 4 5 6 7 8                             block index
		 
	Second row                outward l  s  f  mid
	             <            false
                 +
          |*|*|  +
	   >|*|*|*|*|^            true
	   +|*|*|*|*|
	   +|*|*|*|*|
	   ^|*|*|*|*|          <  false   6  5  6  2
	    |*|*|*|*|*|*|      +
	  |*|*|*|*|*|*|*|*|    +
	  |*|*|*|>|*|*|*|*|    ^  true    7+5   5 -7    lib.getHalf(R); goBack(7) 
	|*|*|*|*|*|*|*|*|*|*|*|                           starts at midPoint of previous row eg block 4
	 0 1 2 3 4 5 6 7 8 9 10
	]]
	
	-- variables declared before lib for them to be used within lib as is then in scope
	local turn = "R"
	local oTurn = "L"
	if R.subChoice == 1 then 	-- remove left side
		turn = "L"
		oTurn = "R"
	end
	local outward = true		-- direction flag
	
	local lib = {}
	
	function lib.isAnyAbove(above)
		T:saveToLog("lib.isAnyAbove: "..utils.tableConcat(above, ", "), false)
		for k,v in ipairs(above) do
			if v then
				T:saveToLog("lib.isAnyAbove Found: "..k , false)
				return true
			end
		end
		return false
	end
		
	function lib.clearLevel(R, above)	-- eg 9, 2, 6, -4 from lib.getStartingLength OR 7, 5, 6, 3 from previous
		-- clearLevel always follows either lib.getStartingLength or a previous lib.clearLevel
		-- midPoint should be adjusted as turtle moves to reflect current row length
		if #above == 0 then return above, 1 end
		--local index = 0
		local minMoves = math.floor(#above / 2)
		local up, forward, down = lib.getDetect()
		if outward then										-- follow table indexes
			for x = 1, minMoves do							-- clear first half
				above[x] = up								-- reset this with new value
				T:go("x0x2F1")								-- clear and move forward
				up, forward, down = lib.getDetect()
				--index = index + 1
			end
			for x = minMoves + 1, #above do					-- check remaing half and clear
				T:go("x0x2")								-- clear above / below
				if above[x] then							-- is a block recorded as present?(now below)
					above[x] = up							-- reset this with new value
					T:forward(1)							-- move forward
					up, forward, down = lib.getDetect()
					--index = index + 1
				else
					break
				end
			end
		else												-- iterate table in reverse
			--index = #above
			for x = #above, minMoves, -1 do					-- clear first half
				above[x] = up								-- reset this with new value
				T:go("x0x2F1")								-- clear and move forward
				up, forward, down = lib.getDetect()
				--index = index - 1
			end
			for x = minMoves - 1, 1, -1 do					-- check remaing half and clear
				T:go("x0x2")								-- clear up / down
				if above[x] then							-- is a block recorded as present?(now below)
					above[x] = up							-- reset this with new value
					T:forward(1)							-- move forward
					up, forward, down = lib.getDetect()
					--index = index - 1
				else
					break
				end
			end
		end
		T:go("x0x2 F1R2 x0x2 F1")							-- face opposite direction, delete blocks above and below
		outward = not outward								-- switch direction flag
		return above										-- eg {false, true, true, true, false}
	end
	
	function lib.getDetect()
		return turtle.detectUp(),  turtle.detect(),  turtle.detectDown()
	end
	
	function lib.getStartingLength(R)
		--[[
			length of column by excavating blocks above, ahead or below
			Rotate 180 at end of run ready to return
			already 1 block above ground
		]]
		local above = {}									-- empty table of boolean values
		local length = 0									-- used as counter							
		T:forward(1)										-- start check 1 block ahead
		local up, forward, down = lib.getDetect() 			-- check if anything around current block
		if up or forward or down then						-- block found nearby: continue
			while up or forward or down do					-- while blocks ahead / up / down move forward
				table.insert(above, up)
				T:go("x0x2F1")
				up, forward, down = lib.getDetect() 		-- check if anything around current block
				length = length + 1
				if length >= R.length then					-- check if going out of range
					T:saveToLog("lib.getStartingLength(R) : outward = "..tostring(outward).." MaxLength "..maxLength.." reached", false)
					break
				end
			end
			T:go("R2x0x2")									-- Rotate 180 and clear blocks above/below
		else												-- no blocks nearby: exit
			T:go("R2F1")									-- return to start position rotated 180
		end
		outward = not outward

		return above 										-- above = {false, true, true, true, true, false, false}
	end
	
	function lib.firstRow(R)
		local height = 1									-- starts at ground level, but forced up 1
		T:up(1)
		local above = lib.getStartingLength(R)				-- clear the ground level and 1 above eg 9, 2, 5, 4
		if T:saveToLog("startLength: "..#above, true) then
			T:saveToLog(utils.tableConcat(above, ", "), false)
			utils.waitForInput()
		end													-- at end of first row as already turned 180, outward set to false in getStartingLength
		while lib.isAnyAbove(above) do
			T:go("U3")	-- go up 3
			height = height + 3
			above = lib.clearLevel(R, above)	-- returns start and finish of blocks above, rotates 180
			if T:saveToLog("checking level: "..height, true) then
				T:saveToLog(utils.tableConcat(above, ", "), false)
				utils.waitForInput()
			end
		end													-- first row all levels completed. 
		T:down(height)										-- now on ground + 1, facing last column cleared.
		
		return above
	end
		
	function lib.deepCopy(tbl)
		local copy = {}
		for key, value in ipairs(tbl) do
			table.insert(copy, value)
		end
		return copy
	end
   
	function lib.getHalf(R, above)
		-- already 1 block above ground
		local maxLength = R.length
		local temp = {}
		local retValue = {}
		if #above > 0 then								-- not empty table, so must be second half
			temp = lib.deepCopy(above)					-- copy existing table
			above = {}									-- initialise above
		end
		local up, forward, down = lib.getDetect()
		
		while up or forward or down do					-- while blocks ahead / up / down move forward
			T:go("x0x2F1")
			table.insert(above, up)
			up, forward, down = lib.getDetect() 		-- check if anything around current block
			
			if #above >= math.floor(maxLength / 2) then	-- check if going out of range
				T:saveToLog("lib.getHalf(R) : outward = "..tostring(outward).." MaxLength "..maxLength.." reached", false)
				T:go("x0x2")
				break
			end
		end
		T:turnRight(2)									-- ready for next half or return
		outward = not outward
		if #temp > 0 then								-- completing a second half measurement
			for i = #above, 1, -1 do
				table.insert(retValue, above[i])		-- combine 2 tables into 1
			end
			for i = 1, #temp do
				table.insert(retValue, temp[i])
			end
		else
			retValue = above
		end
		return retValue
	end
	
	function lib.nextRow(R)
		local height = 1
		T:saveToLog("lib.nextRow(R)", false)
		T:up(1)
		local pattern = turn.."1F1"..turn.."1"
		if not outward then
			pattern = oTurn.."1F1"..oTurn.."1"
		end
		T:go(pattern)
		T:saveToLog("    T:go("..pattern..")", false)
		outward = not outward -- reverse direction flag
		-- now in next vertical row
		local above = lib.getHalf(R, {})
		local index = 0
		if T:saveToLog("\t  first half Length: "..#above.." Enter", true) then 
			T:saveToLog(utils.tableConcat(above, ", "), false)
			utils.waitForInput()
		end
		lib.returnToMidPoint(#above)					-- return to starting point
		T:forward(1)		
		above = lib.getHalf(R, above)					-- returns length - 1 eg 5, 4
		if T:saveToLog("\t  total length: "..#above.." Enter", true) then
			T:saveToLog(utils.tableConcat(above, ", "), false)
			utils.waitForInput()
		end
		
		while lib.isAnyAbove(above) do
			T:go("U3")				-- go up 3
			height = height + 3		-- increment height
			T:saveToLog("\tClear height loop: height = "..height, false)
			above = lib.clearLevel(R, above)	-- returns start and finish of blocks above
		end
		T:down(height)	-- now on ground + 1
		lib.returnToMidPoint(above)
	end
	
	function lib.returnToMidPoint(above)
		--[[ value can be integer or table]]
		if type(above) == "table" then
			T:saveToLog("lib.returnToMidPoint("..#above..")", false)
			if #above > 0 then
				local midPoint = math.floor(#above / 2)
				if #above % 2 == 1 and  not outward then -- length is odd no
					midPoint = math.ceil(#above / 2)
					T:saveToLog("    midPoint adjusted "..midPoint..")", false)
				end
				T:saveToLog("    T:forward("..midPoint..")", false)
				T:forward(midPoint)
			end
		else
			T:saveToLog("lib.returnToMidPoint("..above..")", false)
			if above > 0 then
				T:saveToLog("    T:forward("..above..")", false)
				T:forward(above)
			end
		end
		-- now back at starting point
	end
	
	-- Start here
	-- if "tk log d.." typed instead of "tk" will start logfile and display comments. read() will be activated for debugging
	T:saveToLog("Starting function clearMountainSide", false)
	local above = lib.firstRow(R) 			-- outward depends on height eg 1-2 = false, 3-5 = true, 6-8 = false
	lib.returnToMidPoint(above)				-- return to mid first row of blocks
	for row = 1, R.width -1 do
		lib.nextRow(R)
	end
	
	return {}
end

local function clearSandWall(R) -- 81
	--dig down while on top of sand/red_sand/soul_sand
	local lib = {}
	
	function lib.checkAbove(height)
		if turtle.detectUp() then -- moved under a ledge
			T:go("B1U1")
			height = height - 1
		end
		return height
	end
	
	function lib.moveDown(height)
		blockType = T:getBlockType("down")
		while blockType:find("sand") ~= nil do
			T:down(1)
			height = height + 1
			blockType = T:getBlockType("down")
		end
		return height
	end
	
	function lib.moveForward(length)
		lib.digForward()
		T:forward(1)
		length = length + 1
		local blockType = T:getBlockType("forward")
		return length, blockType
	end
	
	function lib.digForward()
		while T:dig("forward") do
			while T:suck("forward") do end
			while T:suck("up") do end
		end
	end
	
	local moves  = 0
	local height = 0
	local length = 0
	local search = 0
	local reverse = false
	local blockType = T:getBlockType("down")
	if R.length == 0 then
		R.length = 64
	end
	
	print("Checking for sand below")
	while blockType:find("sand") == nil do --move forward until sand detected or 3 moves
		T:forward(1)
		search = search + 1
		blockType = T:getBlockType("down")
		if search > 3 then
			T:go("B"..search)
			return {"Unable to locate sand"}
		end
	end
	-- must be sand below
	height = lib.moveDown(height)	-- go down if sand below
	-- repeat until height == 0
	repeat -- starts at bottom of sand wall
		blockType = T:getBlockType("forward")
		if blockType:find("sand") ~= nil then -- sand in front
			length, blockType = lib.moveForward(length) -- move forward 1 and dig sand
			if blockType == "" or  blockType:find("sand") ~= nil then -- sand or nothing in front
				height = lib.moveDown(height)	-- go down if sand below
			end
		else -- solid block, air or water, not sand so move up
			if turtle.detect() then -- block in front
				blockType = T:getBlockType("down")
				if blockType:find("sand") ~= nil then -- sand below
					T:dig("down")
				end
				T:up(1)
				height = height - 1
			else -- air/water in front so move forward
				if length < 60 then -- in case missing wall and in open ocean
					length, blockType = lib.moveForward(length) -- move forward 1 and dig sand
					height = lib.checkAbove(height)
				else -- already > monument length of 56
					T:up(1)
					height = height - 1
				end
			end
		end
	until height == 0 or length == R.length
	blockType = T:getBlockType("down")
	if blockType:find("sand") ~= nil then -- sand below
		T:dig("down")
	end
	if height > 0 then -- finished as length ran out
		T:up(height)
	end
	-- stay at end of cleared wall unless user chose to return
	if R.data == "return" then
		T:go("R2F"..length.."R2")
	end
	
	return {}
end

local function clearSolid(R) -- 76
	--[[ direction = R.direction "up" or "down" ]]
	local height = 1
	local remaining = R.height 
	local lib = {}
	
	function lib.singleLayer(R)
		R.up = false
		R.down = false
		clearRectangle(R)
	end
	
	function lib.doubleLayer(R)
		R.up = false
		R.down = false
		if R.direction == "up" then
			R.up = true
		else
			R.down = true
		end
		clearRectangle(R)
	end
		
	function lib.tripleLayer(R)
		-- turtle in centre layer
		R.up = true
		R.down = true
		clearRectangle(R)
	end

	R.silent = true
	if R.height < 3 then 							--1-3 layers only
		if R.height == 1 then 						--one layer only
			lib.singleLayer(R)
		elseif R.height == 2 then 					--2 layers only current + dig up/down
			lib.doubleLayer(R)
		end
	else -- 3 or more levels
		height = height + utils.move(R, 1)			-- move up/down 1 block for first layer
		while remaining >= 3 do 					-- min 3 levels
			lib.tripleLayer(R)
			remaining = remaining - 3
			if remaining == 0 then					-- all finished
				break
			elseif remaining == 1 then
				height = height + utils.move(R, 2)	-- move up/down 2 blocks
				lib.singleLayer(R)
			elseif remaining == 2 then
				height = height + utils.move(R, 2)	-- move up/down 2 blocks
				lib.doubleLayer(R)
			else
				height = height + utils.move(R, 3)	-- move up/down 3 blocks
				if remaining == 3 then
					finish = true
				end
			end
		end
	end
	
	if height > 1 then
		utils.move(R, height - 1, true) -- reverse direction
	end
	
	return {}
end

local function clearSandCube(R) -- 81
	R.data = ""
	for w = 1, R.width do
		clearSandWall(R)
		if w < R.width then
			if w % 2 == 1 then
				T:go("R1F1R1")
			else
				T:go("L1F1L1")
			end
		end
	end
	
	return {}
end

local function clearWall(R) -- 73
	local lib = {}
	
	function lib.move(direction, blocks, reverse)
		--[[ Move up or down by blocks count ]]
		if reverse == nil then
			reverse = false
		end
		if reverse then
			if direction == "down" then -- reverse direction
				T:up(blocks)
			else
				T:down(blocks)
			end
		else
			if direction == "up" then
				T:up(blocks)
			else
				T:down(blocks)
			end
		end
		return blocks
	end
	
	function lib.singleLayer(length)
		T:go("F"..length - 1)
	end
	
	function lib.doubleLayer(modifier, length)
		for i = 1, length do
			if i < length then
				T:go("x"..modifier.."F1")
			else
				T:go("x"..modifier)
			end
		end
	end
	
	function lib.tripleLayer(direction, length)
		for i = 1, length do
			if i < length then
				T:go("x0x2F1")
			else
				T:go("x0x2")
			end
		end
	end
	
	
	-- R.width preset to 1
	-- R.subChoice = 1 up / 2 down
	if R.height < 3 then
		R.silent = true
	end
	-- dig along and up/down for specified R.length
	local modifier = "0"
	local direction = "U"
	local outbound = true
	local height = 0
	if R.subChoice == 2 then
		 modifier = "2"
		 direction = "D"
	end
	if R.height == 1 then 				-- single block so dig and return
		lib.singleLayer(R.length)
	elseif R.height == 2 then
		lib.doubleLayer(modifier, R.length)
	else								-- 4 blocks or more. start with bulk 3 blocks
		local remaining = R.height
		T:go(direction.."1")			-- up 1 or down 1
		height = 1
		while remaining >= 3 do 
			lib.tripleLayer(direction, R.length)
			remaining = remaining - 3
			
			if remaining == 0 then		-- no more, return home, already in position
				
			elseif remaining == 1 or remaining == 2 then
				T:go(direction.."2")
				height = height + 2
			else
				T:go(direction.."3")
				height = height + 3
				if remaining >= 3 then -- another iteration
					T:go("R2")
					outbound = not outbound
				end
			end
		end
		-- 0, 1 or 2 layers left
		if remaining > 0 then
			T:go("R2")
			outbound = not outbound
			if remaining == 1 then
				lib.singleLayer(R.length)
			elseif remaining == 2 then
				lib.doubleLayer(modifier, R.length)
			end
		end
	end
	if outbound then
		T:go("R2F"..R.length)
	else
		T:forward(1)
	end
	direction = "D" -- reverse direction
	if R.subChoice == 2 then
		 direction = "U"
	end
	if height > 0 then
		T:go(direction..height.."R2")
	else
		T:go("R2")
	end
	return {}
end

local function convertWater(R) -- 88
	--[[
	if dry need enough buckets to place along (width + length - 1) / 2
	use 12 buckets
	start on floor + 1
	place slab down and water up along 2 edges. stay on this level
	return round same 2 edges removing slabs and and placing them 1 above
	placeUp water onto slabs on both edges
	repeat recover slabs, place 1 above , placeUp water
	
	for sloping water, place full area with slabs
	place sloping water on top of slabs
	remove slabs
	
	]]
	local lib = {}
	
	function lib.checkStartPosition()
		--[[
		0 T             -- T=turtle, W=wall, S=source, F=flowing
		1 W|S|F|F|F|F|F -- sloping flowing water
		2 W|F|F|F|F|F|F -- blocks removed after placing flowing water above
		3 W|S|S|S|S|S|S -- original sources
		4 W|?|?|?|?|?|? -- may be sources
		]]
		-- need to be on floor or R.height if specified
		local depth = 0
		local blockType = T:getBlockType("down")
		local isWaterUp, isSourceUp = T:isWater("up")
		local isWaterForward, isSourceForward = T:isWater("forward")
		local isWaterDown, isSourceDown = T:isWater("down")
		print("Block below is "..blockType)
		print("Water above is "..tostring(isWaterUp))
		print("Water forward is "..tostring(isWaterForward))
		print("Water below is "..tostring(isWaterDown))
		if blockType:find("water") == nil then -- on at least level 0
			print("Moving forward in 2 seconds...")
			sleep(2)
			T:forward(1)
			blockType = T:getBlockType("down")
			if blockType:find("water") ~= nil then
				print("Water found. Going down to floor")
				depth = -1
			else
				T:down(1)
				blockType = T:getBlockType("down")
				if blockType:find("water") ~= nil then
					depth = -2
				else
					return 0, "Not close to water. Aborting..."
				end
			end
		end
		while turtle.down() do
			depth = depth + 1
		end
		local emptyBuckets = utils.getEmptyBucketCount()
		for i = depth, 0, -1 do
			if emptyBuckets > 0 then
				lib.fillBuckets()
				emptyBuckets = utils.getEmptyBucketCount()
			end
			turtle.up()
		end
		
		return depth, ""
	end
	
	function lib.fillBuckets()
		local emptyBuckets = utils.getEmptyBucketCount()
		local direction = "forward"-- start with forward
		local isWater, isSource, isIce = T:isWater(direction)
		if emptyBuckets > 0 then
			if not isSource then
				direction = "down"
				isWater, isSource, isIce = T:isWater(direction)
				if not isSource then
					direction = "up"
					isWater, isSource, isIce = T:isWater(direction)
					if not isSource then
						direction = ""
					end
				end
			end
			if direction == "" then
				print("Unable to locate water source")
			else
				for i = 1, emptyBuckets do
					if utils.fillBucket(direction) then
						print("Bucket filled "..direction)
						sleep(0.3)
					else
						print("Unable to fill bucket ".. i .." / "..emptyBuckets)
					end
				end
			end
		end
		return utils.getWaterBucketCount()
	end
	
	function lib.placeSlabs(length)
		for i = 1, length do
			T:place("slab", "down", false)
			if i < length then
				T:forward(1)
			end
		end
	end
	
	function lib.placeSources(length, place)
		local moves = 1
		local waterBuckets = utils.getWaterBucketCount()
		-- place sources alternate positions + start and finish
		while moves < length do
			if place then
				if T:placeWater("up") then
					print("Placed source up")
					waterBuckets = waterBuckets - 1
				end
			end
			place = not place
			if moves < length then
				T:forward(1)
				moves = moves + 1
			end
			if waterBuckets == 0 then
				T:down(1) -- break the slab below
				waterBuckets = lib.fillBuckets()
				T:up(1)
				T:place("slab", "down", false)
			end
		end
		if T:placeWater("up") then -- end of length
			print("Placed final source up")
		end
		return place
	end
	
	function lib.moveSlabs(length)
		for i = 1, length do
			T:dig("down")
			T:up(1)
			T:place("slab", "down", true)
			if i < length then
				T:forward(1)
				T:down(1)
			end
		end
	end
	
	function lib.recoverSlabs(length)
		for i = 1, length do
			T:dig("down")
			if i < length then
				T:forward(1)
			end
		end
	end
	
	local depth, message = lib.checkStartPosition()
	if message ~= "" then
		return {message}
	end
	local maxDepth = R.height
	local buckets = utils.getWaterBucketCount()
	R = utils.calculateDimensions(R) -- if R.width or R.length == 0
	T:down(depth)
	lib.placeSlabs(R.length)
	T:go("R1")
	lib.placeSlabs(R.width)
	T:go("R2")
	
	while depth > 0 do
		local place = true
		lib.fillBuckets()
		place = lib.placeSources(R.width, place)
		T:go("L1")
		place = lib.placeSources(R.length, place)
		lib.fillBuckets()
		T:go("R2")
		lib.moveSlabs(R.length) -- dig slab from below, move up and replace below
		T:go("R1F1D1")
		lib.moveSlabs(R.width - 1)
		T:go("R2") -- now moved up 1 layer
		depth = depth - 1
		if depth == 0 then
			place = lib.placeSources(R.width, true)
			T:go("L1")
			place = lib.placeSources(R.length, place)
			T:go("R2")
			lib.recoverSlabs(R.length)
			T:go("R1")
			lib.recoverSlabs(R.width)
		end
	end
	
	return {}
end

local function createBoatLift(R) -- 59 state:0=new, size:1=extend, side:0=left, 1=right
	-- build stepped lift with fencing gates and soul sand
	local lib = {}
	
	function lib.getWater(backToWater, downToWater)
		if backToWater > 0 then
			utils.goBack(backToWater)
		end
		if downToWater > 0 then
			T:down(downToWater)
		end
		T:getWater("down") -- take water from source
		sleep(0.2)
		T:getWater("down") -- take water from source
		if downToWater > 0 then
			T:up(downToWater)
		end
		if backToWater > 0 then
			T:forward(backToWater)
		end
	end
	
	--T:place(blockType, direction, leaveExisting, signText)
	
	local backToWater = 0
	local downToWater = 0
	
	T:go("R1F1L1") 										-- over canal facing forward
	for h = 1, R.height do
		lib.getWater(backToWater, downToWater)			-- check water supplies, return to starting position
		T:go("L1C1 R1D1 L1C1 R1", false, 0, false)		-- place towpath, forward, down, place towpath, face forward
		T:place("soul", "down", false) 				-- place soulsand down
		T:place("soul", "forward", false) 			-- place soulsand forward
		T:go("R1F1C1L1", false, 0, false)				-- place right towpath face forward
		T:place("soul", "down", false) 				-- place soulsand down
		T:place("soul", "forward", false) 			-- place soulsand forward
		T:go("U1 R1C1 L1")								-- place towpath, face forward
		T:placeWater("down") 							-- place water down
		utils.goBack(1)
		T:place("gate", "forward", false) 			-- place fence gate
		T:go("R1C1 U1C1 D1 L2F1 C1R1 F1 L1C1R1")		-- over left soul sand
		T:placeWater("down") 							-- place water down
		utils.goBack(1)
		T:place("gate", "forward", false) 			-- place fence gate
		T:go("U1 L1C1 R1F1 L1C1 R1x1")					-- facing forward first unit complete
		T:go("R1F1 L1x1 R1C1")
		utils.goBack(1)
		T:go("L1F1")
		if backToWater == 0 then
			backToWater = 1
		end
		backToWater = backToWater + 1
		downToWater = downToWater + 1
	end
	
	-- now finish the canal
	lib.getWater(backToWater, downToWater)
	T:go("D1 L1C1 U1C1")					-- build left towpath, facing towpath, above water level
	T:go("R1F1 L1C1 D1C1")					-- move forward, build towpath, facing towpath ground level
	T:go("R1C1 R1F1 L1C1 R1C1 U1C1")		-- build right towpath, facing towpath, above water level
	T:go("R1F1 L1C1 D1C1 U1")				-- build right towpath next to gate, facing towpath, above water level
	T:placeWater("down") 
	utils.goBack(1)
	T:go("L1F1")
	T:placeWater("down")  
	
	return {}
end

local function createBorehole(R)
	--[[go down to bedrock and return. Chart all blocks dug/ passed through]]
	local diary = {}
	local lib = {}
	local depth = R.height	-- eg 63 start position
	local moves = 0
	--R.height = current level
	
	function lib.addBlock(depth, blockType, diary)
		if blockType == "" then
			blockType = "air"
		end
		table.insert(diary, blockType)
		
		
		--[[if blockType ~= "" then
			local add = true
			for k,v in pairs(diary) do
				if blockType == v then
					add = false
					break
				end
			end
			if add then
				diary[depth] = blockType
			end
		end]]
		
		return diary
	end
	
	function lib.processItem(item)
		if item:find("minecraft") ~= nil then
			return item:sub(11)
		end
		return item
	end
	
	function lib.writeReport(R, diary)
		local numLevels = #diary						-- eg 125 levels
		local levelsPerCol = math.ceil(numLevels / 4)	-- eg 31.25 -> 32
		local lines = {}
		for l = 1, levelsPerCol do						-- add 32 empty strings
			table.insert(lines, "")
		end
		local lineNo = 1
		for k, v in ipairs(diary) do
			local level = R.height - k 					-- eg 63 range 63 to -59
			local lev = "      "
			local item = lib.processItem(v)
			if level < -9 then
				lev = tostring(level).."   "			-- "-10   " to "-59   "
			elseif level < 0 then				
				lev = "-0"..math.abs(level).."   "		-- "-09   " to "-01   " 
			elseif level < 10 then
				lev = " 0"..level.."   "				-- " 01   " to " 09   "
			elseif level < 100 then
				lev = " "..level.."   "					-- " 10   " to " 99   "
			else
				lev = " "..level.."  " 					-- " 100  " to " 319  "
			end
			local output = lev..item					-- eg "-10   grass_block"
			if #output > 20 then						-- eg "-10   some_long_block_name"  
				output = output:sub(1, 20)				-- eg "-10   some_long_block_" 
			else
				output = menu.padRight(output, 20, " ")	-- eg "-10   grass_block     "
			end
			lines[lineNo] = lines[lineNo]..output		-- add new entry to this line
			lineNo = lineNo + 1							-- increase line no
			if lineNo > levelsPerCol then				-- past last line number
				lineNo = 1								-- reset to 1
			end
		end
		
		local fileName = "borehole"..os.getComputerID()..".txt"
		local handle = fs.open(fileName, "w") 		--create file eg "borehole0.txt"
		handle.writeLine("Level Block         Level Block         Level Block         Level Block")
		for k,v in ipairs(lines) do
			handle.writeLine(v)
		end
		
		handle.close()
		
		return fileName
	end
	
	local blockType = T:getBlockType("down")
	while T:down(1) do
		depth = depth - 1
		moves = moves + 1
		if depth == R.depth then
			break
		end
		diary = lib.addBlock(depth, blockType, diary)
		blockType = T:getBlockType("down")
	end
	local fileName = lib.writeReport(R, diary)
	T:up(moves)
	
	return {"File '"..fileName.."' written"}
end

local function createBubbleLift(R) -- 15
	local lib = {}
	
	function lib.addLayer()
		T:go("F2 L1C1 R1C1 R1C1 L1", false, 0, true)
		turtle.back()
		T:dig("up")	-- clear block above so completed lift can be found
		T:placeWater("forward") 
		turtle.back()
		T:go("C1x0")		
	end
	
	function lib.addSign()
		turtle.back()
		T:placeWater("forward") 
		T:go("L1C1B1")
		T:place("sign", "forward")
	end
	
	function lib.buildLift(toHeight)
		local built = lib.goToWater() 		-- returns lift blocks already placed, total height of drop from starting point
		local toBuild = toHeight - built 	-- no of blocks remaining to increase lift size
		local water = 0
		while toBuild > 0 do 				-- at least 1 block height remaining
			water = lib.fillBuckets(toBuild, false) -- no of water buckets onboard (could be more than required)
			if water > toBuild then			-- more water than required
				water = toBuild				-- reduce to correct amount
			end
			T:up(built)						-- climb to top of existing lift
			if T:getBlockType("forward"):find("sign") ~= nil then
				T:up(1)	
			end
			while water > 0 and toBuild > 0 do
				lib.addLayer()
				water = water - 1
				T:up(1)
				toBuild = toBuild - 1
			end
			-- may still be some height to complete, but needs refill
			if toBuild > 0 then
				built = lib.goToWater() --return to source
				toBuild = toHeight - built
			end
		end
	end
	
	function lib.cleanUp(fromHeight)
		local plug = false
		T:turnRight(2)
		for i = 1, fromHeight do
			plug = false
			if turtle.detect() then
				plug = true
			end
			turtle.down()
			if plug then
				T:place("stone", "up")
			end
		end
	end
		
	function lib.fillBuckets(withSort)
		local emptyBuckets = T:getItemCount("minecraft:bucket")
		for i = 1, emptyBuckets do
			if T:getWater("down") then
				sleep(0.5)
			end
		end
		
		return T:getItemCount("minecraft:water_bucket")
	end
	
	function lib.getEmptySlots()
		local empty = 0
		for i = 1, 16 do
			if turtle.getItemCount(i) == 0 then
				empty = empty + 1
			end
		end
		return empty
	end
	
	function lib.goToWater()
		local built = 0 -- measures completed lift height
		while turtle.down() do -- takes turtle to bottom of water source
			if turtle.detect() then
				built = built + 1
			end
		end
		T:up(1) -- above watersource ready to fill buckets
		-- height = height - 1
		-- built = built - 1 not required as next block is water source: not detected
		return built -- , height
	end
	
	function lib.stackBuckets(withSort)
		if withSort == nil then withSort = false end
		local data = {}
		local bucketSlot = 0
		local emptySlots = 0
		local water = 0
		if withSort then
			T:sortInventory()
		end
		for i = 1, 16 do
			-- find first empty bucket
			if turtle.getItemCount(i) > 0 then
				data = turtle.getItemDetail(i)
				if data.name == "minecraft:bucket" then
					if bucketSlot == 0 then
						bucketSlot = i
					else
						turtle.select(i)
						turtle.transferTo(bucketSlot)
					end
				elseif data.name == "minecraft:water_bucket" then
					water = water + 1
				end
			else
				emptySlots = emptySlots + 1
			end
		end
		return emptySlots, water
	end
	
	T:go("C1R1")												-- place block next to ladder support block, turn right to check ladder
	local blockType = T:getBlockType("forward") 				-- Is there a ladder to the right?
	if blockType:find("ladder") == nil then
		T:go("C1L2")											-- Place block as ladder not present
	else														-- ladder present
		T:go("L2")												-- ready to check other side
	end
	blockType = T:getBlockType("forward") 
	if blockType:find("ladder") == nil then
		T:go("C1R1")
	else
		T:go("R1")
	end
	blockType = T:getBlockType("down")
	local dirt = "minecraft:dirt"
	if T:getItemSlot("minecraft:soul_sand") > 0 then
		dirt = "minecraft:soul_sand"
	end
	if blockType:find("bedrock") ~= nil then
		utils.goBack(1)
		T:place(dirt, "forward", false) 					-- placed at end of potential water source, next to ladder
	else
		T:place(dirt, "down", false) 						-- placed in ground, next to ladder
		utils.goBack(1)
		T:placeWater("forward") 							-- place extra water source
	end
	T:go("R1C1 R2C1 L1F1C2 R1C1 L2C1 R1F1C2 R1C1 L1C1 L1C1 L1F1", false, 0, true)
	-- ready for water sources to be placed
	T:placeWater("forward") 								-- place front water source
	T:turnRight(2)											-- facing backward
	T:placeWater("forward") 								-- place back water source
	T:go("R2U1") 											-- facing forward, U1, above centre of water source

	--lib.fillBuckets(R.height, true)							-- fill as many buckets as required or until inventory full, sort inventory as well
	lib.fillBuckets(true)							-- fill as many buckets as required or until inventory full, sort inventory as well
	local nextToLadder = false
	--T:go("F2R1")
	T:go("x0F1 x0F1C1 R1") 									-- move forward 2 taking out blocks above, plug behind soul sand
	if T:getBlockType("forward"):find("ladder") == nil then	-- no ladder here
		T:turnLeft(2)
		if T:getBlockType("forward"):find("ladder") ~= nil then	-- ladder here
			nextToLadder = true
		end
		T:turnRight(1)
	else
		nextToLadder = true
		T:turnLeft(1)
	end
	-- now above soul sand, facing forward
	if nextToLadder then								-- if nextToLadder, no need for signs
		utils.goBack(2) 								-- return to source centre
	else
		T:go("L1C1 R1C1 R1C1 L1", false, 0, true)		-- prepare layer 1
		lib.addSign()
		T:go("U1F1 R1F1 L1C1 R1C1 R1C1 L1", false, 0, true)	-- prepare layer 2
		lib.addSign()
		T:go("L1F1 R1F1R1", false, 0, true)	 			-- above source, level 2
	end
	-- ready to build lift
	lib.buildLift(R.height - 1)
	lib.cleanUp(R.height - 1)
	
	return {"Bubble lift created", "Check correct operation", "Check exit before using" }
end

local function createBubbleTrap(R) -- 34
	--[[
	Replace floor of existing volume of water with soulsand
	Used in river biome for squid farm. Area should be enclosed
	with solid walls surface to floor.
	Usually 7 blocks wide
	]]
	local lib = {}
	
	function lib.clearDown(depth)
		while utils.clearVegetation("down") do
			T:down(1)
			depth = depth + 1
		end
		T:place("soul_sand", "down", false)
		return depth
	end
	
	function lib.clearLength(length, depth)
		local moves = 0
		while moves < length - 1 do
			if utils.clearVegetation("forward") then
				T:forward(1)
				moves = moves + 1 
				depth = lib.clearDown(depth) -- go down if in water/air
				if moves >= length - 1 then
					return depth
				end
			else -- block in front
				local waterAhead = utils.clearVegetation("forward") -- true if air/water in front
				while not waterAhead do 	-- solid block in front
					T:up(1)
					depth = depth - 1
					if depth < 1 then
						return 0
					end
					waterAhead = utils.clearVegetation("forward")
				end
			end
		end

		return depth
	end
	
	function lib.turn(facingForward, depth)
		local direction = "R"
		if not facingForward then
			direction = "L"
		end
		T:go(direction.. 1)
		if utils.clearVegetation("forward") then
			T:forward(1)
			depth = depth + lib.clearDown(depth)
		else
			while not utils.clearVegetation("forward") do
				T:up(1)
				depth = depth - 1
			end
		end
		T:go(direction.. 1)
		
		return depth
	end
	
	local depth = 0
	local length = 0
	local width = 0
	local outbound = true
	local facingForward = true
	local inWater, onWater = utils.getWaterStatus()
	inWater, onWater = utils.startWaterFunction(onWater, inWater, 2 ,true) -- move into water, max descent 2
	if R.length == 0 then
		R.length = lib.getLength()
	end
	if R.width == 0 then
		T:turnRight(1)
		R.width = lib.getLength()
		T:turnLeft(1)
	end
	-- go down to floor
	depth = lib.clearDown(depth)
	while width < R.width do
		-- now on floor, move along sea/river bed following contour
		depth = lib.clearLength(R.length, depth)
		width = width + 1
		-- now turn and repeat
		if width < R.width then	
			depth = lib.turn(facingForward, depth)
			facingForward = not facingForward
		end
	end
	-- finished so return to surface
	T:up(1) -- up 1 to check for water below
	while T:isWater("down") do
		T:up(1)
	end
	
	return {}
end

local function createCorridor(R) -- 52
	--[[create a corridoor 2 blocks high, with floor and ceiling guaranteed
	T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)]]
	local lib = {}
	
	function lib.continue(R, currentSteps, totalSteps)
		if not R.silent then
			if currentSteps >= 64 and R.length == 0 then
				-- request permission to continue if infinite
				T:clear()
				print("Completed "..totalSteps..". Ready for 64 more")
				print("Do you want to continue? (y/n)")
				response = read()
				if response:lower() ~= "y" then
					return true, 0
				else
					return false, currentSteps
				end
			end
		end
		return true, currentSteps
	end
	
	function lib.seal()	
		local blockType = T:getBlockType("forward")
		if blockType:find("water") ~= nil then
			T:place("stone", "forward", false)
			return "water"	-- water found
		elseif blockType:find("lava") ~= nil then
			T:place("stone", "forward", false)
			return "lava"	-- lava found
		end
		return ""	-- no water or lava
	end
	
	function lib.checkSeal(R)
		local fluidType = ""
		if R.data == "seal" then 		-- check for lava/water at the sides
			T:turnRight(1)
			fluidType = lib.seal()		-- could be "", "water", "lava"
			T:turnLeft(2)
			local blockType = lib.seal()
			if fluidType == "" then		-- no water / lava so far
				fluidType = blockType	-- could be "", "water", "lava"
			end
			T:turnRight(1)
		end
		return fluidType				-- could be "", "water", "lava"
	end
	
	function lib.placeTorch(R, torchSpaces, totalSteps)
		if R.torchInterval > 0 then -- torches onboard
			if torchSpaces == R.torchInterval then -- time to place another torch
				if totalSteps < R.length then -- not at end of run
					if T:getItemSlot("minecraft:torch") > 0 then
						T:place("minecraft:torch", "down")
					end
					torchSpaces = 1
				end
			end
		end
		return torchSpaces -- original value or 1
	end
	
	local currentSteps = 0					-- counter for infinite length. pause every 64 blocks
	local totalSteps = 0					-- counter for all steps so far
	local torchSpaces = R.torchInterval		-- if torches present, counter to place with 8 blocks between
	local fluidType = ""
	local damLength = 0
	local damStarted = false
	local doContinue = true
	if T:getItemSlot("minecraft:torch") == 0 then
		R.torchInterval = 0 -- set to default 9 in getTask()
	end
	for steps = 1, R.length do
		-- starts on floor of tunnel
		doContinue, currentSteps = lib.continue(R, currentSteps, totalSteps) -- continue tunnelling?
		if not doContinue then
			break
		end
		T:go("C2U1C0", false, 0, true)		-- place floor, up 1, place ceiling
		fluidType = lib.checkSeal(R)		-- if R.data == "seal", check for water/lava at ceiling level
		if fluidType == "" then	-- either R.data ~= "seal" or no fluid found
			torchSpaces = lib.placeTorch(R, torchSpaces, totalSteps) -- original value or 1 if torch placed
			T:go("F1D1")
		elseif fluidType == "water" then
			T:go("F1R2 C1D1 C1L2", false, 0, true)
			damStarted = true
			damLength = damLength + 1
		else	--lava
			T:go("F1D1")
		end
		blockType = lib.checkSeal(R)
		if blockType ~= "" then
			fluidType = blockType
		end
		currentSteps = currentSteps + 1
		totalSteps = totalSteps + 1
		torchSpaces = torchSpaces + 1
		if damStarted and fluidType == "" then -- was in water, but no more
			T:go("R2 F"..damLength + 1 .."U1L2F"..damLength + 1 .."D1")
			damStarted = false
		end
	end
	if fluidType ~= "" then -- water or lava found while tunnelling
		T:go("U1C0", false, 0, true)
		lib.checkSeal(R)
		T:go("C1", false, 0, true)
		T:down(1)
	end
	return {}
end

local function createDragonTrap() -- 49
	local lib = {}
	
	function lib.attack()
		local totalHitsF = 0
		local totalHitsU = 0
		local totalHitsD = 0
		while true do
			local hitF = false
			local hitU = false
			local hitD = false
			if turtle.attackUp() then
				hitU = true
				totalHitsU = totalHitsU + 1
			end
			if turtle.attackDown() then
				hitD = true
				totalHitsD = totalHitsD + 1
			end
			if turtle.attack() then
				hitF = true
				totalHitsF = totalHitsF + 1
			end
			if hitF or hitU or hitD then
				print("hits forward: "..totalHitsF..", up: "..totalHitsU..", down: "..totalHitsD)
			end
		end
	end
	-- build up 145 blocks with ladders
	T:clear()
	menu.colourPrint("Press Enter to start 1 minute delay\n", colors.red)
	menu.colourPrint("Run to island centre across the bridge\n", colors.orange)
	menu.colourPrint("You have already made the bridge?...", colors.lime)
	read()
	for t = 60, 1, -1 do
		sleep(1)
		T:clear()
		io.write("Starting in "..t.. " seconds ")
	end
	for i = 1, 145 do
		T:go("U1C2")
		turtle.back()
		T:place("minecraft:ladder", "down")
		turtle.forward()
	end
	T:go("R2F1C1 L1C1 L2C1 R1")
	for i = 1, 100 do
		T:go("F1C2U1C0D1")
	end
	T:forward(1)
	T:place("minecraft:obsidian", "down")
	T:go("R2F1x2R2")
	T:placeWater("forward") 
	T:go("R2F6R2")
	lib.attack()
	
	return {}
end
	
local function createEnderTower(stage) -- 66
	--[[ lower base = stage 1, upper base = 2, tower = 3 ]]
	local lib = {}
	--[[ go(path, useTorch, torchInterval, leaveExisting, preferredBlock) ]]
	function lib.getEmptySlots()
		local empty = 0
		for i = 1, 16 do
			if turtle.getItemCount(i) == 0 then
				empty = empty + 1
			end
		end
		return empty
	end

	function lib.getStone(direction, stacks)
		--[[ get block user wants to use ]]
		local suck = turtle.suck	
		if direction == "down" then
			suck = turtle.suckDown
		end
		if T:getBlockType(direction) == "minecraft:chest" then
			T:sortInventory()
			local slot = T:getFirstEmptySlot() --find spare slot
			if slot > 0 then --empty slot found
				turtle.select(1)
				if stacks == 0 then
					while suck() do end
				else
					for i = 1, stacks do -- get # stacks of stone from chest
						suck()
					end
				end
				if T:getSlotContains(slot) == "" then
					return T:getMostItem()				-- empty chest
				else
					return T:getSlotContains(slot) 		-- use this as default building block
				end
			else
				return T:getMostItem()				-- full inventory
			end
		else
			return T:getMostItem()				-- no chest
		end
	end
	
	function lib.stackBuckets()
		local data = {}
		local bucketSlot = 0
		local emptySlots = 0
		local water = 0
		T:sortInventory()
		for i = 1, 16 do
			-- find first empty bucket
			if turtle.getItemCount(i) > 0 then
				data = turtle.getItemDetail(i)
				if data.name == "minecraft:bucket" then
					if bucketSlot == 0 then
						bucketSlot = i
					else
						turtle.select(i)
						turtle.transferTo(bucketSlot)
					end
				elseif data.name == "minecraft:water_bucket" then
					water = water + 1
				end
			else
				emptySlots = emptySlots + 1
			end
		end
		return emptySlots, water
	end
	
	function lib.countWaterBuckets()
		local data = {}
		local buckets = 0
		for i = 1, 16 do
			data = turtle.getItemDetail(i)
			if data.name == "minecraft:water_bucket" then
				buckets = buckets + 1
			end
		end
		return buckets
	end
	
	function lib.baseRun(preferredBlock, count, turn)
		for i = 1, count do
			T:go("C2F1", false, 0, false, preferredBlock)
		end
		T:go("C2"..turn, false, 0, false, preferredBlock)
	end
	
	function lib.outsideRun(preferredBlock)
		T:place("fence", "down", false)
		T:forward(1)
		T:place(preferredBlock, "down", false)
		T:forward(1)
		T:place(preferredBlock, "down", false)
		T:forward(2)
		T:place(preferredBlock, "down", false)
	end
	
	function lib.signRun(preferredBlock ,message)
		T:place(preferredBlock, "down", false)
		T:forward(4)
		T:place(preferredBlock, "down", false)
		turtle.back()
		turtle.back()
		T:down(1)
		T:place("sign", "forward", false, message)
		T:go("U1F2")
	end
	
	function lib.goToWater(height)
		local built = 0 -- measures completed lift height
		while turtle.down() do -- takes turtle to bottom of water source
			height = height + 1
			if turtle.detect() then
				built = built + 1
			end
		end
		T:up(1) -- above watersource assuming it is 1-1.5 blocks deep
		height = height - 1
		-- built = built - 1 not required as next block is water source: not detected
		return built, height
	end
	
	function lib.fillBuckets(toBuild)
		local emptySlots, water = lib.stackBuckets() -- gets no of empty slots + no of water buckets
		if water < toBuild then -- no of water buckets onboard less than required quantity
			for i = 1, toBuild do -- fill required no of buckets up to max space in inventory
				emptySlots = lib.getEmptySlots()
				if emptySlots == 0 then -- inventory full
					break
				else
					if T:getWater("down") then
						water = water + 1
						sleep(0.5)
					end
				end
			end
		end
		
		return water
	end
	
	function lib.buildLift(preferredBlock)
		local built = 0 -- measures completed lift height
		local height = 0 -- measures total height from starting position
		built, height = lib.goToWater(height) -- returns lift blocks already placed, total height of drop from starting point
		local toBuild = height - built -- no of blocks to increase lift size
		while toBuild > 0 do -- at least 1 block height remaining
			local water = lib.fillBuckets(toBuild) -- no of water buckets onboard (could be more than required)
			if water > toBuild then
				water = toBuild
			end
			while turtle.detect() do -- climb to top of existing lift
				turtle.up()
				height = height - 1
			end
			T:forward(1)
			for i = 1, water do -- build lift by no of water buckets
				if T:placeWater("forward")  then
					T:up(1)
					height = height - 1
					toBuild = toBuild - 1
					T:place(preferredBlock, "down", false)
				end
			end
			turtle.back()
			-- may still be some height to complete, but needs refill
			if toBuild > 0 then
				lib.goToWater(0) --return to source
				lib.fillBuckets(toBuild)
			end
		end
		if height > 0 then -- if any remaining distance
			T:up(height)
		end
		
	end
	
	function lib.buildSection(preferredBlock, solid)
		-- builds a section without any blocks in the centre
		-- second layer of each section end walls have fence posts
		T:go("F1C2 F2C2 F1R1", false, 0, false, preferredBlock) -- first side solid row
		if solid then -- first layer of each section
			T:go("F1C2 F1R1", false, 0, false, preferredBlock) -- top side solid row
		else
			T:go("F1") -- top side solid row
			if not T:place("fence", "down", false) then-- first side
				T:place(preferredBlock, "down", false)
			end
			T:go("F1R1") -- top side solid row
		end
		T:go("F1C2 F2C2 F1R1", false, 0, false, preferredBlock) -- far side solid row
		T:go("F1C2 F1R1U1", false, 0, false, preferredBlock) -- bottom side solid row
	end	
	--[[
		clsTurtle methods:
		clsTurtle.place(self, blockType, damageNo, direction, leaveExisting)
		clsTurtle.go(self, path, useTorch, torchInterval, leaveExisting, preferredBlock)
	]]
	-- remove 1 stack stone from chest
	local preferredBlock = lib.getStone("down", 1) -- use this as default building block
	if stage == 1 then
		-- build base floor
		--T:go("R2F2R1F3R1", false, 0, false, preferredBlock)
		T:go("R2F1C2R1F1C2F1C2F1C2R1", false, 0, false, preferredBlock)
		for i = 1, 2 do
			lib.baseRun(preferredBlock, 8, "R1F1R1")
			lib.baseRun(preferredBlock, 8, "L1F1L1")
			lib.baseRun(preferredBlock, 8, "R1F4R1")
		end
		-- move back to centre, build water source, with soul sand at base of first source
		--T:go("R1F3L1C2F1C2F2D1", false, 0, false, preferredBlock) --just behind chest, 1 below ground level
		T:go("R1F3L1F2C2F1D1", false, 0, false, preferredBlock) --1 block behind chest, 1 below ground level
		T:place("minecraft:soul_sand", "down", false) -- over block 1 of water source
		T:go("F1C2F1C2", false, 0, false, preferredBlock) -- over block 2 of water source
		T:go("F1C2U1C2", false, 0, false, preferredBlock) -- over block 4 of water source
		T:go("F1C2F1C2R2F5R2", false, 0, false, preferredBlock) -- over block 1 of water source
		T:placeWater("down") 
		T:forward(2) -- over block 3 of water source
		T:placeWater("down")
		turtle.back() -- over block 2 of water source
		T:getWater("down")
		T:go("F2D1R2C2") -- over block 4 of water source
		T:go("U1", false, 0, false, preferredBlock)
		T:placeWater("down")
		T:forward(4)
		lib.stackBuckets() -- put all buckets in same slot
		T:dropItem("minecraft:dirt", "up", 0) -- drop dirt up:  clsTurtle.dropItem(self, item, direction, keepAmount)
		preferredBlock = lib.getStone("down", 6)
		T:go("R1F2R1U1") -- move to start position
		for i = 1, 2 do
			-- build first level of tower: 2 x outside run, 2 x sign run
			lib.outsideRun(preferredBlock)
			if i == 1 then -- place door
				T:go("L1F1L1F1L1D1")
				T:place("door", "forward", false)
				T:go("U1L1F1R1F1L1")
			end
			T:go("R1F1R1")
			lib.signRun(preferredBlock, "Pint size\nzombies\nProhibited")
			T:go("L1F1L1C2", false, 0, false, preferredBlock)
			T:forward(4) -- miss out centre block
			T:place(preferredBlock, "down", false)
			T:go("R1F1R1")
			lib.signRun(preferredBlock, "Pint size\nzombies\nProhibited")
			T:go("L1F1L1")
			lib.outsideRun(preferredBlock)
			if i == 1 then -- layer 1
				T:go("R1F1R1F1R1D1") -- place door
				T:place("door", "forward", false)
				T:go("U1 R1F1 L1F5 L1U1 F2D1  F2R2 U1") -- go over door
			else -- layer 2
				T:go("L1F5L1F6R2U1") -- over corner of lower platform
			end
		end
		for i = 1, 2 do -- build both sides of platform, leave centre missing
			lib.baseRun(preferredBlock, 8, "R1F1R1")
			lib.baseRun(preferredBlock, 8, "L1F1L1")
			lib.baseRun(preferredBlock, 8, "R1F4R1")
		end
		T:go("R1F3L1C2F1C2F1C2F4C2F1C2F1C2", false, 0, false, preferredBlock) --fill in centre row
		--T:go("R2F6R1F1R1U1") -- go to start of tower base
		T:go("R2F7R2D3") -- go to start on top of chest
		T:sortInventory()
	elseif stage == 2 then
		-- start on top of chest, should have sufficient stone in inventory
		T:go("U3L1F1R1F1U1") -- go to start of tower base
		for i = 1, 7 do -- build 14 block high tower
			lib.buildSection(preferredBlock, false)
			lib.buildSection(preferredBlock, true)
		end
		T:go("R2F4R1F4R1", false, 0, false, preferredBlock) -- build upper platform (154 blocks remaining)
		for i = 1, 2 do -- build both sides of upper platform, leave centre missing
			lib.baseRun(preferredBlock, 12, "R1F1R1")
			lib.baseRun(preferredBlock, 12, "L1F1L1")
			lib.baseRun(preferredBlock, 12, "R1F1R1")
			lib.baseRun(preferredBlock, 12, "L1F1L1")
			lib.baseRun(preferredBlock, 12, "R1F6R1")
		end
		T:go("R1F5 L1C2 F1C2 F1C2 F1C2 F1C2 F4C2 F1C2 F1C2 F1C2 F1C2 ", false, 0, false, preferredBlock) --fill in centre row
		T:go("R2F5") -- return to drop area
		lib.buildLift(preferredBlock) -- build bubble lift
		T:go("F3R1F1R1U1") -- go to start of tower base
		T:go("C2F4 C2R1F1R1", false, 0, false, preferredBlock) 		-- left side layer 21
		T:go("F2C2 F2C2 L1F1L1", false, 0, false, preferredBlock) 	-- centre layer 21
		T:go("C2F4 C2R2U1", false, 0, false, preferredBlock) 		-- right side layer 21
		T:go("C2F4 C2R1F1R1", false, 0, false, preferredBlock) 		-- right side layer 22
		T:place("fence", "down", false)							-- fence centre of bottom side layer 22
		T:go("F2C2 F2L1F1L1", false, 0, false, preferredBlock)		-- centre layer 22
		T:go("C2F4 C2R2F2L1F1R2D2", false, 0, false, preferredBlock) --ready to place ladder
		T:place("ladder", "forward", false)
		T:up(1)
		T:place("ladder", "forward", false)
		--T:go("U2R1F4R1F1R1") -- ready to make upper part of tower base
		T:go("U2R1F4R1F1R1") -- ready to make upper part of tower base
		for i = 1, 2 do -- build both sides of platform, leave centre missing
			lib.baseRun(preferredBlock, 8, "R1F1R1")
			lib.baseRun(preferredBlock, 8, "L1F1L1")
			lib.baseRun(preferredBlock, 8, "R1F4R1")
		end
		T:go("R1F3 L1C2 F1C2 F1C2 F1", false, 0, false, preferredBlock) --fill in centre row
		T:place("minecraft:soul_sand", "down", false) 
		T:go("F1C2 F2C2 F1C2 F1C2", false, 0, false, preferredBlock)
		T:go("R2F6R1F1R1U1") -- go to start of tower base
		-- build 2 levels, finish signs and ladders
		T:go("C2F2 R1D2 U1", false, 0, false, preferredBlock)
		T:place("ladder", "down", false)
		T:turnRight(1)
		T:place("sign", "forward", false, "UP\n^\n|\n|")
		T:go("U1R2F2C2 R1F2C2 R1", false, 0, false, preferredBlock) --top right corner
		T:go("F4C2B2D1", false, 0, false, preferredBlock)
		T:place("sign", "forward", false, "UP\n^\n|\n|")
		T:go("U1F2R1F1C2F1R1U1", false, 0, false, preferredBlock) --ready for second level
		T:go("C2F2 R2D1", false, 0, false, preferredBlock)
		T:place("sign", "forward", false, "UP\n^\n|\n|")
		T:go("U1R2F2C2R1", false, 0, false, preferredBlock) --top left corner
		T:go("F1R1C2F4C2", false, 0, false, preferredBlock) --mid bottom row
		T:go("L1F1L1C2", false, 0, false, preferredBlock) -- bottom right corner
		T:go("F2R2D1", false, 0, false, preferredBlock)
		T:place("sign", "forward", false, "UP\n^\n|\n|")
		T:go("U1R2F2C2", false, 0, false, preferredBlock) -- top right corner
		-- return to chest
		T:go("L1F1L1 F5D23R2", false, 0, false, preferredBlock) -- return to chest
		T:sortInventory()
	elseif stage == 3 then
		--[[ move to top of structure
		| 4 |
		|3 5|
		| X |
		|2 6|
		| 1 |
		]]
		local towerHeight = 128 -- even no only suggest 128
		while turtle.detect() do
			turtle.up()
		end
		T:go("F1U1", false, 0, false, preferredBlock) -- return to finish tower
		for i = 1, towerHeight do -- 1
			T:go("C2U1", false, 0, false, preferredBlock)
		end
		T:go("F1L1F1R1D2")
		while turtle.down() do -- 2
			T:fillVoid("up", {preferredBlock})
		end
		T:go("F1R2C1R2F1D1", false, 0, false, preferredBlock)
		for i = 1, towerHeight / 2 do -- 3
			T:go("U2C2", false, 0, false, preferredBlock)
		end
		T:go("U1F1R1F1R1D1", false, 0, false, preferredBlock) -- back of tower facing front
		local deviate = false
		while turtle.down() do -- 4
			T:place("fence", "up", false)
			if turtle.down() then
				T:fillVoid("up", {preferredBlock})
			else
				T:go("F1R2C1R1F1R1D1", false, 0, false, preferredBlock)
				deviate = true
				break
			end
		end
		if not deviate then
			T:go("F1L1F1R1D1", false, 0, false, preferredBlock)
		end
		for i = 1, towerHeight / 2 do -- 5
			T:go("U2C2", false, 0, false, preferredBlock)
		end
		T:go("F2R2", false, 0, false, preferredBlock) -- facing back of tower
		while turtle.down() do -- 6
			T:fillVoid("up", {preferredBlock}) --layer 129
		end
		T:go("F1L2C1U"..towerHeight)
		T:go("F4R1F3R1U1", false, 0, false, preferredBlock)
		-- add small platform at the top
		lib.baseRun(preferredBlock, 8, "R1F1R1")
		lib.baseRun(preferredBlock, 8, "L1F3L1")
		lib.baseRun(preferredBlock, 8, "L1F1L1")
		lib.baseRun(preferredBlock, 8, "R1F1R1")
		T:go("C2 F1C2 F1C2 F4C2 F1C2 F1C2 R2F3", false, 0, false, preferredBlock) --fill in centre row
		lib.buildLift(preferredBlock) -- build bubble lift
	end
	return {}
end

local function createFarmNetworkStorage(R, withStorage, removeLegacy)
	removeLegacy = removeLegacy or false
	-- new or converted farm will have:
	-- 2 modems, 1 barrel per plot
	-- primary plot and storage needs 1 modem, 1 barrel, 8 chests
	local lib = {}
	
	function lib.createBasement(R, up, down, width, length)
		-- start facing lower left
		R.up = up
		R.down = down
		R.width = width
		R.length = length
		clearRectangle(R)	-- dig 10 x 10 x 2 area, return to starting position
		-- add network cable, modems and chests
	end
	
	function lib.placeNetwork(count, pattern)
		for i = 1, count do
			T:place("computercraft:cable", "up", true)
			if i < count then
				T:go(pattern)
			end
		end
	end
	
	-- called when starting at lower left side of plot, facing crops
	if removeLegacy then
		T:go("L1F1")
		while turtle.suckDown() do end
		--T:dig("down", false)	-- do not bypass chests
		turtle.digDown()
		T:place("dirt", "down")
		T:go("R2F1")
		while turtle.suck() do end
		T:go("F1L1 F1U1 R2")	-- remove barrel/wall or double chest. face tree
		T:place("stone", "down")
		T:forward(1)
		T:place("modem", "down")
		-- could be tree/sapling in front
		T:forward(1)
		if T:getBlockType("down") == "minecraft:dirt" then
			T:place("barrel", "down")
			T:go("U1x0")
			T:place("dirt", "up")
			T:go("B1U2")
			if T:getBlockType("forward"):find("log") ~= nil then
				T:place("sapling", "forward")
			end
			T:go("D3F1 R1F1")
		else
			T:place("barrel", "down")
			T:go("R1F1")
		end
		while turtle.suckDown() do end
		T:place("modem", "down")
		network.attachModem()
		T:go("F1x2 R2C2 F1L1 F1D1")
	end
	T:go("L1D3") -- move below crop field, face N
	lib.createBasement(R, true, true, 10, 10)	-- ends facing N below water source
	T:go("U1 F9R1 F1R2 C1R2 F8R1 F1R2 C1R2 F8R1 F1R2 C1R2 F8") -- facing W below water source
	T:go("F1 R2C1 R1 F1L1 x0x2")	-- move to corner, face along front edge
	for c = 1, 4 do
		if c == 1 then
			lib.placeNetwork(12, "F1x0x2")
		else
			lib.placeNetwork(11, "F1x0x2")
		end
		if c < 4 then
			T:go("L1F1 x0x2 L1C1R1")
		end
	end
	-- now in bottom left facing S
	T:go("L2F1R1")	-- under modem/netwok cable facing in
	for i = 1, 3 do
		T:go("L1C1 R1C1 R1C1 L1D1")
		T:place("computercraft:cable", "up", true)
	end
	T:go("C1L1 C1L1 C1L1 C1L1 D1L1")-- ready for clearing rectangle up/down
	T:place("computercraft:cable", "up", true)
	T:down(1)
	T:place("computercraft:cable", "up", true)
	lib.createBasement(R, true, true, 11, 11)
	T:turnRight(1)
	lib.placeNetwork(11, "F1")
	T:go("R2F4 R1")
	lib.placeNetwork(11, "F1")
	T:go("L1F5 L1F9 R1D1 C1")	-- ready to make ladder column
	for i = 1, 5 do
		if i < 5 then
			T:go("U1C1")
		else
			T:up(1)
		end
		T:place("ladder", "down")
	end
	if withStorage then
		T:go("R1F4 R1F3 D1x2")
		T:place("computercraft:cable", "down", true) --ready to build chest storage area
		T:up(1)
		utils.createStorage()
		T:go("U1R1 F5R1 F5U1 C2U1 R2")	-- end on plot starting position, facing crops
	else
		T:go("U1F2 L1F1 U1C2 U1L1")	-- end on plot starting position, facing crops
	end
	
	return "Farm converted to network storage"
end

local function createFarm(R, extend) -- 31
	-- if extend ~= nil then this has been called from createFarmExtension()
	-- extend "right" or "forward". only adds a single new farm.

	if extend == nil then
		extend = ""
	end
	
	local lib = {}

	function lib.addWaterSource(R, pattern, storage)
		-- pattern = {"d","c","c","d"} t = place crafting  instead of dirt
		-- place(self, blockType, damageNo, direction, leaveExisting, signText)
		T:go("D1x2C2", false, 0, false, R.useBlockType)
		for i = 1, 4 do
			T:dig("forward")
			if pattern[i] == "d" then
				T:place("dirt", "forward", false)
			elseif pattern[i] == "t" then
				--if not T:place("minecraft:crafting_table", "forward", false) then
				if T:place(storage, "forward", false) then
					if T:dropItem("crafting", "forward", 0) then
						print("Crafting table -> buried storage")
					end
				else
					T:place("dirt", "forward", false) -- dirt if no storage available
				end
			else
				T:place(R.useBlockType, "forward", false)
			end
			T:turnRight(1)
		end
		T:up(1)
		T:placeWater("down")	-- ends facing same direction as started, over water source
	end
	
	function lib.placeDirt(count, atCurrent)
		if atCurrent then
			local blockType = T:getBlockType("down")
			if blockType:find("dirt") == nil and blockType:find("grass_block") == nil then
				T:place("dirt", "down", false)
			end
		end
		for  i = 1, count do
			T:forward(1)
			T:dig("up")
			local blockType = T:getBlockType("down")
			if blockType:find("dirt") == nil and blockType:find("grass_block") == nil then
				T:place("dirt", "down", false)
			end
		end
	end

	function lib.placeStorage(storage, storageBackup)
		T:dig("down")
		if not T:place(storage, "down", false) then-- place barrel/chest below
			T:place(storageBackup, "down", false) -- place chest below
		end
	end
	
	local blockType = ""
	-- current position if extend == nil is on ground/farm level facing N
	-- if extend = "right", "front" above water source facing crops
	local numPlots = 0
	local storage, storageBackup = utils.setStorageOptions()
	if extend == "right" then
		T:up(1)
		utils.goBack(1)
		repeat
			T:forward(11)
			numPlots = numPlots + 1
		until not utils.isStorage("down") -- on top of chest, barrel or modem
		T:go("R1F1R2")	-- move to front right corner of last plot on right side
		--T:go("R1U1 F1L1 F10L1") -- move to front right corner
	elseif extend == "forward" then
		T:go("L1U1")
		utils.goBack(1)
		repeat
			T:forward(11)
			numPlots = numPlots + 1
		until not utils.isStorage("down") -- on top of chest, barrel or modem
		T:go("L1F1 R1x2")	-- could dig tree or sapling + block below
		--T:go("L2U1 F1R1 F10")
	elseif extend == "convertWithStorage" then
		-- convert normal (storage) primary plot farm to networked storage
		--T:turnLeft(1)	-- over water source, facing N
		local response = createFarmNetworkStorage(R, true, true)
		return {response}
	elseif extend == "convert" or extend == "convertWithStorage" then
		-- convert normal (storage) extended farm to networked storage
		--T:turnLeft(1)	-- over water source, facing N
		createFarmNetworkStorage(R, false, true)
		return {"Farm converted to network storage"}
	else -- new farm.
		T:up(1) -- assume on the ground, go up 1
	end
	
	-- design change: sapling placed 2 blocks above corner for ease of walking round
	if R.networkFarm then	-- barrel on corner of plot, modems on each side N/E
		T:place("barrel", "down", false)
	else
		T:place(R.useBlockType, "down", false)
	end
	-- stage 2 place sapling
	T:up(3)
	T:place("dirt", "down")
	T:up(1)
	T:place("sapling", "down") -- plant sapling
	T:go("F1D4")
	if R.networkFarm then
		T:place("modem", "down", false)
		network.attachModem()
		T:forward(1)
		T:place(R.useBlockType, "down", false)
	else
		-- stage 2 place double barrel/chest
		T:go("L1")
		lib.placeStorage(storage, storageBackup)
		T:go("R1F1L1")
		lib.placeStorage(storage, storageBackup)
		T:turnRight(1)
	end
	if extend == "right" then -- cobble wall exists so go forward to its end
		T:forward(9)
	else -- new farm or extend forward
		for i = 1, 9 do -- complete left wall to end of farm
			T:go("F1 x0x2C 2", false, 0, false, R.useBlockType)
		end
	end
	T:go("R1F1 R1x0 x2C2 F1D1", false, 0, false, R.useBlockType)-- turn round ready for first dirt col
	lib.addWaterSource(R, {"d","c","c","d"}, storage) -- water at top of farm
	lib.placeDirt(9, false) 	-- place dirt back to start
	if R.networkFarm then	-- water source next to modem
		lib.addWaterSource(R, {"c","c","d","d"}, storage)
		-- T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock
		T:go("U1F1L1")
		T:place("modem", "down", false)
		T:go("F1C2 L1F1 D1", false, 0, false, R.useBlockType)
	else
		lib.addWaterSource(R, {"c","c","t","d"}, storage)  -- put barrel / chest in floor
		T:go("U1F1R2")
		if T:getBlockType("down"):find(storage) == nil and T:getBlockType("down"):find(storageBackup) == nil then
			lib.placeStorage(storage, storageBackup)
		end
		T:go("R1F1L1")
		if T:getBlockType("down"):find(storage) == nil and T:getBlockType("down"):find(storageBackup) == nil then
			lib.placeStorage(storage, storageBackup)
		end
		T:go("F1D1")
	end
	lib.placeDirt(9, true)
	local turn = "R"
	for i = 1, 7 do
		T:go("F1U1x0C2"..turn.."1F1"..turn.."1x0 x2C2 F1D1", false, 0, false, R.useBlockType)
		lib.placeDirt(9, true)
		if turn == "R" then
			turn = "L"
		else
			turn = "R"
		end
	end
	T:go("F1U1x0C2"..turn.."1F1"..turn.."1x0x2C2F1D1", false, 0, false, R.useBlockType)
	lib.addWaterSource(R, {"d","c","c","d"}, storage)	-- bottom right
	lib.placeDirt(9, false)
	lib.addWaterSource(R, {"c","c","d","d"}, storage)	-- top right, facing away from plot
	T:go("F1U1 R1C2 x0F1 x0x2 C2R1", false, 0, false, R.useBlockType)
	for i = 1, 11 do	-- build right wall from top of plot to bottom
		T:go("F1x0x2C2", false, 0, false, R.useBlockType)
	end
	T:go("R1F10")				-- ends on top of front storage/ modem facing tree
	if R.networkFarm then		-- network storage
		network.attachModem()
		T:go("R1F1D1R1")	-- over water source, facing E (crops)
		if extend == "" then	-- primary plot
			createFarmNetworkStorage(R, true)
		else
			createFarmNetworkStorage(R, false)
		end
	end
	if extend == "right" then
		T:up(1)
		utils.goBack(numPlots * 11)
		T:down(1)
	elseif extend == "forward" then
		T:go("R1U1F".. numPlots * 11 .."D1L1")
	end
	return {"Modular farm completed"}
end

local function createFarmExtension(R) -- 32
	-- assume inventory contains 4 chests, 64 cobble, 128 dirt, 4 water, 1 sapling
	-- check position by rotating to face tree/sapling
	
	--T:setUseLog(true, "farmCreateLog.txt", true)
	--dbug = true	-- set dbug flag
	--utils.waitForInput("Logging and debugging enabled")	--utils.waitForInput(message)
	
	local extend = "right" -- default
	if R.subChoice == 1 then
		extend = "forward"
	end
	
	R = utils.checkFarmPosition(R)
	
	if not R.ready then
		return {"Unable to determine starting position"}
	end
	
	createFarm(R, extend)
	return {"Modular crop farm extended"}
end

local function createFloorCeiling(R) -- 79 size integer 1 to 4
	--[[
	R.up = true for ceiling
	R.down = true for floor
	R.height = 0 for normal
	R.height combined with R.up/R.down used for remote access
	R.data == "random" for random floor placement
	]]
	
	local lib = {}
	
	function lib.goToRemote(R)
		R.silent = true
		local depth = 0
		if R.down then -- floor could be under water
			while turtle.down() do
				depth = depth + 1
			end
		elseif R.up then
			while turtle.up() do
				depth = depth + 1
				if depth > R.height + 3 then
					break
				end
			end
		end
		if not(R.height - depth <= 2 or depth - R.height <= 2) then
			T:up(depth)
			return "Measured depth/height of "..depth.." > setting: "..R.height
		end
		-- not returned so depth acceptable
		return ""
	end
	
	function lib.checkPosition(R)
		-- check if block above/below
		local blockBelow = turtle.detectDown()
		local blockAbove = turtle.detectUp()
		if R.subChoice == 2 then -- New floor over existing
			-- if no block below, assume in correct position and continue
			-- else move up 1 and continue
			if blockBelow then T:up(1) end
		elseif R.subChoice == 4 then -- New ceiling under existing
			-- if no block above, assume in correct position and continue
			-- else move down 1 and continue
			if blockAbove then T:down(1) end
		end
	end
	
	function lib.placeRow(R, direction, waterPresent)
		for y = 1, R.length do
			local blockType = T:getBlockType("forward")
			if not waterPresent then
				if blockType:find("lava") ~= nil or blockType:find("water") ~= nil then
					waterPresent = true
				end
			end
			R = lib.getRandomBlock(R)	-- changes block randomly ONLY if R.data == "random"
			R = lib.changeCheckered(R)	-- changes to next block type ONLY if R.data == "checked"
			-- ONLY if R.data == "striped" has already been changed for whole row
			T:place(R.inventory.useBlock, direction, false) -- leaveExisting = false
			if y < R.length then
				T:forward(1)
			end
		end
		return waterPresent, R
	end
	
	function lib.getRandomBlock(R)
		if R.data == "random" then
			local index = math.random(1, #R.inventory.names)	-- random index between 1 and no of block types
			local success = false
			for i = index, R.inventory.blockTypeCount do		-- iterate from index upwards
				if R.inventory.quantities[i] > 0 then			-- at least 1 block left
					R.inventory.useBlock = R.inventory.names[i]
					R.inventory.quantities[i] = R.inventory.quantities[i] - 1
					R.inventory.blockCount = R.inventory.blockCount - 1
					success = true
					break
				end
			end
			
			if not success then								-- no blocks left in the range of index -> no of block types
				for i = index, 1, -1 do						-- go backwards from index to 1
					if R.inventory.quantities[i] > 0 then		-- at least 1 block left
						R.inventory.useBlock = R.inventory.names[i]
						R.inventory.quantities[i] = R.inventory.quantities[i] - 1
						R.inventory.blockCount = R.inventory.blockCount - 1
						success = true
						break
					end
				end
			end
		end	
		
		return R
	end
	
	function lib.changeStripe(R)
		if R.data == "striped" then
			R.size = R.size + 1
			if R.size > R.inventory.blockTypeCount then
				R.size = 1
			end
			R.inventory.useBlock = R.inventory.names[R.size]
		end
		return R
	end
	
	function lib.changeCheckered(R)
		--swap between 2 block types
		if R.data == "checked" then
			if R.inventory.useBlock == R.inventory.names[1] then
				R.inventory.useBlock = R.inventory.names[2]
			else
				R.inventory.useBlock = R.inventory.names[1]
			end
		end
		return R
	end
	
	local waterPresent = false
	
	if R.data == "random" then
		math.randomseed(R.inventory.blockCount)
		print("Using random blocks")
	elseif R.data == "striped" then
		print("Using striped pattern")
	elseif R.data == "checked" then
		print("Using checkered pattern")
	end
	local direction = "down"
	if R.up then
		direction = "up"
	end
	
	if R.height > 0 then -- remote placing. go up/down R.height first
		local message = lib.goToRemote(R)
		if message ~= "" then	-- error encountered
			return {message}
		end
	end
	
	lib.checkPosition(R)
	-- based on clearRectangle code
	if R.width == 1 then 					-- single block ahead only
		waterPresent, R = lib.placeRow(R, direction, waterPresent)
		T:turnRight(2)						-- turn at the top of the run
		T:forward(R.length - 1)				-- return to start
		T:turnRight(2)						-- turn round to original position
	else
		local iterations = 0 				-- R.width = 2, 4, 6, 8 etc
		if R.width % 2 == 1 then  			-- R.width = 3, 5, 7, 9 eg R.width 7
			iterations = (R.width - 1) / 2 	-- iterations 1, 2, 3, 4 for widths 3, 5, 7, 9
		else
			iterations = R.width / 2		-- iterations 1, 2, 3, 4 for widths 2, 4, 6, 8
		end
		R = lib.changeStripe(R)
		R = lib.changeCheckered(R)
		for i = 1, iterations do 			-- eg 3 blocks wide, iterations = 1
			waterPresent, R = lib.placeRow(R, direction, waterPresent)
			T:go("R1F1R1")
			R = lib.changeStripe(R)
			--R = lib.changeCheckered(R)
			waterPresent, R = lib.placeRow(R, direction, waterPresent)
			-- if 1 less than end, reposition for next run
			if i < iterations then
				T:go("L1F1L1", false, 0, false)
				R = lib.changeStripe(R)
			end
		end
		if R.width % 2 == 1 then  -- additional run and return to base needed
			T:go("L1F1L1", false, 0, false)
			R = lib.changeStripe(R)
			waterPresent, R = lib.placeRow(R, direction, waterPresent)
			T:turnRight(2)
			T:forward(R.length - 1)
		end
		T:go("R1F"..R.width - 1 .."R1", false, 0, false)
	end

	if waterPresent then
		return {"water or lava found"}
	end
	
	return {""}
end

local function createIceCanal(R) -- 55
	--[[
		R.subChoice = 
		1: move right into canal, build left towpath
		2: build left towpath
		3: build right towpath
		4: move left into canal, build right towpath
		5/8: clear path 3 blocks high, place slabs/torches
		6/7: build alternating ice road / create 3 block high air gap (2 over water)
	]]
	local oTurn = "R"
	if R.side == "R" then
		oTurn = "L"
	end
	local lib = {}
	
	function lib.convertTowpath(R)
		-- only used to convert existing water canal, so assume towpath already present
		-- starting position 1 block above existing towpath
		for i = 1, R.length do
			if turtle.detectDown() then							-- eg existing torch
				T:dig("down")
			end
			local placeSlab = true
			if R.torchInterval > 0 then							-- place torches
				if i == 1 or i % R.torchInterval == 0 then		-- ready to place torch
					--go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
					T:go("C2x0", false, 0, false, R.useBlockType)-- place solid block below
					T:go("F1R2x0")
					T:place("torch", "forward")				-- place torch, move forward
					T:turnRight(2)								-- turn round
					placeSlab = false
				end
			end
			if placeSlab then
				T:dig("up")
				if not T:place("slab", "down") then			-- break if out of slabs
					break
				end
				if i < R.length then
					T:forward(1)								-- move forward
				end
			end
		end
	end
	
	function lib.iceCanalTowpath(R)
		-- move forward placing slabs along the way. If existing water canal, ceiling will be raised by 1 block
		local torchInterval = 0
		local placeIce = true
		for i = 1, R.length do
			local addTorch = false
			if R.torchInterval > 0 then
				if i == 1 then addTorch = true end
				if torchInterval >= R.torchInterval then
					addTorch = true
					torchInterval = 0
				end
			end
			lib.iceCanalEdge(R, addTorch, i, placeIce)
			torchInterval = torchInterval + 1
			placeIce = not placeIce
		end
		T:go(oTurn.."1")
	end
	
	function lib.iceCanalEdge(R, addTorch, numBlocks, placeIce)
		-- starting position facing canal side
		local blockType = T:getBlockType("forward")			-- ? air / slab / other
		local isWater, isSource, isIce = T:isWater("down")	-- water / ice below
		if blockType:find("slab") == nil then 				-- add slab
			if addTorch then								-- check if torch needed
				-- T:place(blockType, direction, leaveExisting, signText)
				if not T:place("stone", "forward", false) then
					T:checkInventoryForItem({"stone"}, {math.ceil(R.length / R.torchInterval)}, true)
				end
				T:go("U1x1 U1x1 D1")	 				-- water level to 2 above water level
				if T:getItemSlot("minecraft:torch") > 0 then
					T:place("torch", "forward", false)
				end
				T:down(1)								-- back to above water level
				if not isIce then						-- break block below if NOT ice
					T:dig("down")
				end
			else
				if not T:place("slab", "forward", false) then
					T:checkInventoryForItem({"slab"}, {R.length - numBlocks}, true)
				end
				if not isSource then					-- NOT on water, so dig above
					T:go("U1x1 U1x1 D2")
				end
				if not isIce and not isSource then
					T:dig("down")
				end
			end
		else -- slab already on side
			if addTorch then							-- check if torch needed
				T:dig("forward")
				if not T:place("stone", "forward", false) then
					T:checkInventoryForItem({"stone"}, {math.ceil(R.length / R.torchInterval)}, true)
				end
				T:go("U1x1 U1x1 D1")	 				-- water level to 2 above water level
				if T:getItemSlot("minecraft:torch") > 0 then
					T:place("torch", "forward", false)
				end
				T:down(1)								-- back to above water level
				if not isIce then						-- break block below if NOT ice
					T:dig("down")
				end
			end
		end
		if R.data == "ice" and placeIce and not isIce then -- R.data = "ice", placeIce = true, not already ice present
			T:place("ice", "down", true)
		end
		if numBlocks < R.length then
			T:go(oTurn.."1F1"..R.side.."1")
		end
	end
	
	function lib.convertIcepath(length)
		-- use only for placing ice to convert a water canal
		-- place ice on alternate blocks until length reached or run out of ice
		local placeIce = true
		for i = 1, length do
			if T:getBlockType("down"):find("ice") == nil then -- no ice below
				T:dig("down") -- remove any existing block
				if placeIce then
					if not T:place("ice", "down", true) then -- out of ice
						break
					end
					if i == length - 1 then
						break
					end
				end
			else -- ice already below
				placeIce = true
			end
			T:go("U1x0 D1F1")
			placeIce = not placeIce -- reverse action
		end
	end
	
	function lib.convertToAir(length)
		-- use only for converting a water canal. start at ground level
		-- dig up/down/forward to clear space
		for i = 1, length + 1 do
			T:go("U1x0D1")
			if i < length + 1 then
				T:go("x2F1")
			else
				T:dig("down")
			end
		end
	end
	
	function lib.initialise(R)
		if R.subChoice == 1 or R.subChoice == 4 then		
			local blockType = T:getBlockType("down")		-- ? at ground/water level or on top of existing slab
			if blockType:find("slab") ~= nil then 			-- slab already present
				T:go(oTurn.."1F1D1"..R.side.."2")			-- move right/left forward, down onto ice canal top, face canal wall
			elseif blockType:find("torch") ~= nil then
				T:go(oTurn.."1F1D2"..R.side.."2")			-- move right/left forward, down onto ice canal top, face canal wall
			else											-- assume on ground / water level
				T:go(oTurn.."1F1"..R.side.."2")				-- move right/left forward onto ice canal top, face canal wall
			end
		else
			if T:isWater("forward") then 					-- player put turtle inside canal water
				T:up(1)
			end
			T:go(R.side.."1")								-- face canal wall
		end
	end
	
	if R.length == 0 then R.length = 1024 end

	if R.subChoice <= 4  then								-- towpath 1,2,3,4
		lib.initialise(R)									-- reposition
		lib.iceCanalTowpath(R)								-- build towpath
	elseif R.subChoice == 5 or R.subChoice == 8 then		-- assume placed on towpath
		if T:getBlockType("down"):find("slab") ~= nil then 	-- slab already present
			T:go("F1")
		else
			T:up(1)
		end
		lib.convertTowpath(R)
	elseif R.subChoice == 6 or R.subChoice == 7 then	
		if R.data == "ice" then							-- assume placed on existing ice or initial ice position
			lib.convertIcepath(R.length)-- place ice
		else											-- assume placed on empty path
			lib.convertToAir(R.length)					-- clear 3 high area
		end
	end
	
	return {}
end

local function createLadder(R) -- 12
	-- createLadder(R.data ="bedrock", R.height = 70, R.depth = -48)
	-- go(path, useTorch, torchInterval, leaveExisting)
	-- place(blockType, damageNo, direction, leaveExisting)
	local lib = {}
	
	function lib.placeLadder(direction, ledge, i, height)
		-- 1 check both sides and behind
		local fluid = false
		local block = T:isWaterOrLava("forward", ledge)
		if block:find("water") ~= nil or block:find("lava") ~= nil then
			--[[ surround 2 block shaft with blocks ]]
			T:go("R1C1 R1C1 R1C1 R1F1 L1C1 R1C1 R1C1 R1C1F1 R2C1 x1")
		else
			--[[ no water/lava so prepare ladder site]]
			T:go("F1 L1C1 R1C1 R1C1 L1B1", false, 0, true)
		end
		if not T:place("ladder", "forward", false) then
			T:checkInventoryForItem({"ladder"}, {height - i}, false)
		end
		-- 3 check if ledge, torch
		if ledge == 0 and i > 1 then -- place block above unless new ladder
			T:place("common", direction, false) -- any common block
		elseif ledge == 1 then
			T:place("minecraft:torch", direction, false)
		elseif ledge == 2 then
			ledge = -1
		end
		
		return ledge
	end
	
	local retValue = {}
	local ledge = 0
	local height = math.abs(R.depth - R.height) --height of ladder
	local blockType = T:getBlockType("forward")
	if R.up then -- create ladder from current level to height specified
		for i = 1, height do -- go up, place ladder as you go
			ledge = lib.placeLadder("down", ledge, i, height) -- ladder placed forward, stone ledge for torch placed down
			if i <  height then
				T:up(1)
				ledge = ledge + 1
			end
		end		
	else -- R.down = true: ladder towards bedrock		
		local success = true
		local numBlocks, errorMsg = 0, ""
		T:down(1)
		for i = 1, height do -- go down, place ladder as you go
			ledge = lib.placeLadder("up", ledge, i, heigt) -- ladder placed forward, stone torch placed up
			--success, blocksMoved, errorMsg, blockType = clsTurtle.down(self, steps, getBlockType)
			if i < height then
				success, numBlocks, errorMsg, blockType = T:down(1, true) -- true = return blockType
				ledge = ledge + 1
			end
			-- if looking for stronghold then check for stone_bricks 
			if blockType:find("stone_bricks") ~= nil then
				table.insert(retValue, "Stronghold discovered")
				break -- stop descent at stronghold
			end
		end
		-- if user requested shelter create chamber at this level
		if R.data == "chamber" then -- user has chosen to build a chamber
			table.insert(retValue, "Shelter constucted at level".. R.depth)
			if blockType:find("bedrock") ~= nil then
				T:findBedrockTop(0) -- test to check if on safe level immediately above tallest bedrock
			end
			-- In shaft, facing start direction, on lowest safe level
			-- create a square space round shaft base, end facing original shaft, 1 space back
			T:go("L1n1 R1n3 R1n2 R1n3 R1n1", false, 0, true)
			T:go("U1Q1 R1Q3 R1Q2 R1Q3 R1Q1 R1D1", false, 0, true)
		end
	end
	
	return retValue
end

local function createLadderToWater(R) -- 86
	-- go down to water/lava with alternaate solid/open layers
	-- create a working area at the base
	-- Return to surface facing towards player placing ladders
	local inAir = true
	local numBlocks, errorMsg = 0, ""
	local height = 2
	local blockType = T:getBlockType("down")
	if blockType ~= "" then -- not over air
		T:forward(1)
	end
	T:go("R2D1") -- face player, go down 2
	while inAir do --success = false when hits water/lava
		blockType = T:isWaterOrLava("down")
		if blockType:find("water") ~= nil or blockType:find("lava") ~= nil then
			inAir = false
		end
		T:go("C1R1 C1R2 C1R1", false, 0, false)	-- surround front  and sides with cobble
		if inAir then
			T:down(1)
			height = height + 1
		end
		T:place("ladder", "up")
	end
	-- In shaft, facing opposite start direction, on water/lava, ladders above
	T:go("C2", false, 0, false)
	utils.goBack(1)
	T:place("ladder", "forward")
	T:up(3)
	height = height - 3
	for i = 1, height do
		if i < height then
			T:go("C2U1", false, 0, false)
		else
			T:go("C2", false, 0, false)
		end
	end

	return {}
end

local function createMine() -- 11
	-- go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
	T:clear()	
	T:go("m32U1R2M16", true, 8, true) -- mine ground level, go up, reverse and mine ceiling to mid-point
	T:go("U2D2") -- create space for chest
	T:place("minecraft:chest", "up", false)
	T:emptyTrash("up")
	T:go("D1R1m16U1R2M16", true, 8, true) -- mine floor/ceiling of right side branch
	T:emptyTrash("up")
	T:go("D1m16U1R2M16", true, 8, true) -- mine floor/ceiling of left side branch
	T:emptyTrash("up")
	T:go("L1M15F1R1D1", true, 8, true) -- mine ceiling of entry corridor, turn right
	T:go("F1x0 F1x0 n14 R1n32 R1n32 R1n32 R1n14 F1x0 F1U1", true, 8, true)-- mine floor of 36 x 36 square corridor
	T:go("R1F16R2") --return to centre
	T:emptyTrash("up")
	T:go("F16R1") --return to entry shaft
	T:go("F2Q14R1Q32R1Q32R1Q32R1Q14F2R1", true, 8, true) --mine ceiling of 36x36 square corridor. return to entry shaft + 1
	T:go("F16R2") --return to centre
	T:emptyTrash("up")
	-- get rid of any remaining torches
	while T:getItemSlot("minecraft:torch") > 0 do
		turtle.select(T:getItemSlot("minecraft:torch"))
		turtle.dropUp()
	end
	T:go("F16R1F1R1") --return to shaft + 1
	for i = 1, 8 do
		T:go("N32L1F1L1", true, 8, true)
		T:go("N16L1F"..(i * 2).."R2", true, 8, true)
		T:emptyTrash("up")
		if i < 8 then
			T:go("F"..(i * 2).."L1N16R1F1R1", true, 8, true)
		else
			T:go("F"..(i * 2).."L1N16L1", true, 8, true)
		end
	end
	T:go("F17L1") -- close gap in wall, return to ladder + 1
	for i = 1, 8 do
		T:go("N32R1F1R1", true, 8, true)
		T:go("N16R1F"..(i * 2).."R2", true, 8, true)
		T:emptyTrash("up")
		if i < 8 then
			T:go("F"..(i * 2).."R1N16L1F1L1", true, 8, true)
		else
			T:go("F"..(i * 2).."R1N16R1", true, 8, true)
		end
	end
	T:go("F16R1")
	T:clear()
	return{"Mining operation complete"}
end

local function createMobFarmCube(R) -- 61, 62
	--[[
	Part 1 / 3 Mob Spawner Farm
	blaze = true: blaze spawner in nether
		R.subChoice is set to:
		1 = on top of spawner
		2 = line of sight
		3 = room below
	blaze = false: overworld mob spawner
		R.subChoice is set to:
		1 = on top of spawner
		2 = bottom left corner
		3 = top left corner
		4 = bottom right, corner
		5 = top right corner
		R.width / R.length set by player (external size)
	]]
	local blaze = true
	if R.data == "spawner" or R.data == "chest" then
		blaze = false
	end
	local continue = false
	if R.data == "restart" then
		continue = true
	end
	R.direction = "clock"		-- starting on right side
	if not blaze then
		print("R.width: "..tostring(R.width))
		R.width = R.width - 2		-- internal width
		R.length = R.length - 2		-- internal length
		
		if R.subChoice == 2 or R.subChoice == 3 then
			R.direction = "anticlock"
		end
	end
	-- R.data allows for 2-part operation "blaze" = main cube, "restart" = killzone
	T:clear()
	local lib = {}
	
	function lib.floorSection(length)
		for i = 1, length do		-- starts on top left corner
			T:go("C2")
			if i < length then
				T:forward(1)
			else
				T:go("R1F1")
			end
		end
	end
	
	function lib.wallSection(blaze)
		blaze = blaze or false
		for i = 1, 4 do
			for j = 1, 11 do
				if blaze then
					T:place("slab", "up", false)
					T:go("C2", false, 0, false)
				else
					T:go("C0C2", false, 0, false)
				end
				if j < 11 then
					T:forward(1)
					T:go("R2C1L2", false, 0, false)
				else
					T:turnRight(1)
				end
			end
		end
	end
	
	function lib.ceiling(blaze)
		-- T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
		-- all outer walls complete, now for remaining 9x9 ceiling
		blaze = blaze or false
		for i = 1, 9 do
			for j = 1, 9 do
				if blaze then
					T:place("slab", "up", false)
					T:dig("down")
				else
					T:go("C0x2", false, 0, true)
				end
				if j < 9 then
					T:forward(1)
				else	-- end of length
					local place = false
					if i%2 == 1 then -- odd numbers 1,3,5,7,9
						if i < 9 then
							place = true
							T:go("R1F1 R1")
						end
					else
						place = true
						T:go("L1F1 L1")
					end
					if place then
						if blaze then
							T:place("slab", "up", false)
							T:dig("down")
						else
							T:go("C0x2", false, 0, true)
						end
					end
				end
			end
		end
	end
	
	function lib.clearWall(length)
		for i = 1, 4 do
			for j = 1, length do 
				if j < length then
					T:go("x0x2F1")
				else
					T:go("x0x2R1")
				end
			end
		end
	end
	
	function lib.isSpawner()
		local blockType = T:getBlockType("down")
		if blockType:find("spawner") ~= nil then
			return true, "top"
		end
		blockType = T:getBlockType("up")
		if blockType:find("spawner") ~= nil then
			return true, "bottom"
		end
		blockType = T:getBlockType("forward")
		if blockType:find("spawner") ~= nil then
			return true, "forward"
		end
		return false, ""
	end
	
	function lib.placeFloor(width, length, blockType)
		-- T:place(blockType, direction, leaveExisting, signText)
		for i = 1, width do				
			for j = 1, length do
				T:place(blockType, "down", false)
				if j < length then
					T:forward(1)
				else
					if i%2 == 1 then -- odd numbers 1,3,5,7,9
						if i < width then
							T:go("R1F1R1", false, 0, true)
						end
					else
						T:go("L1F1L1", false, 0, true)
					end
				end
			end
		end
	end
	
	function lib.searchStrip(distance)
		--go forward until hit either a wall or a chest
		local blocks = 1
		print("Searching strip, distance = "..distance)
		while blocks < distance do --max travel is external width/length
			if turtle.forward() then
				blocks = blocks + 1
			else
				print("Checking for chest")
				if lib.isChest("forward") then
					if turtle.forward() then
						blocks = blocks + 1
					end
				else
					break
				end
			end
		end
	end
	
	function lib.findChests(R)
		for i = 1, 4 do
			print("Searching wall "..i)
			if i == 1 or i == 3 then
				lib.searchStrip(R.width) 	-- find and empty chests along width
			else
				lib.searchStrip(R.length) 	-- find and empty chests along length
			end
			if R.direction == "clock" then
				T:turnRight(1)
			else
				T:turnLeft(1)
			end
		end

		-- checked all walls
		T:go("F".. math.floor(R.width / 2)) -- now at mid-dungeon, next to wall
		if T:getItemSlot("chest") > 0 then
			if R.direction == "clock" then
				T:turnLeft(1)
			else
				T:turnRight(1)
			end
			-- now at mid-dungeon, facing wall
			-- deposit chest outside the dungeon
			while turtle.back() do end -- backing spawner
			T:go("x0 F1x0 F1x0 F1x0 F1x0 F1x0 F1x0 x1x2")
			-- place(self, blockType, damageNo, direction, leaveExisting, signText)
			T:place("chest", "forward", false)
			-- empty out all except stone and slab
			T:emptyInventorySelection("forward", {"cobble", "tuff", "slab", "granite", "andesite", "diorite" }, {0,0,0,0,0,0})
			T:turnLeft(2)
			T:checkInventoryForItem({"stone"}, {512}, false, "Full cube uses ~700 blocks\nEstimate your requirements")
			while turtle.forward() do end -- facing spawner
		else
			if R.direction == "clock" then
				T:turnRight(1)
			else
				T:turnLeft(1)
			end
		end -- now at mid-dungeon, facing spawner
	end
	
	function lib.enterDungeon(R)
		--[[ find and empty any chests, return to dungeon wall ]]
		print("Entering dungeon")
		local blockType = T:getBlockType("forward")
		if blockType == "" then -- nothing in front.Error
			return false, "No block in front: Check position."
		else -- attempt entry into dungeon wall
			if R.subChoice == 2 then 		-- bottom left
				T:go("R1F1 L1U2 F2R1")
			elseif R.subChoice == 3 then	-- top left
				T:go("R1F1 L1D1 F2R1")
			elseif R.subChoice == 4 then	-- bottom right
				T:go("L1F1 R1U2 F2L1")
			elseif R.subChoice == 5 then	-- top right
				T:go("L1F1 R1D1 F2L1")
			end
			while turtle.down() do end -- either on floor or chest
			if lib.isChest("down") then
				turtle.down()
			end
			print("Searching for chests")
			lib.findChests(R)	-- go round inside walls  emptying chests. Finish mid-wall
		end
		return true, ""-- success, message
	end
	
	function lib.isChest(direction)
		direction = direction or "forward"
		local blockType = T:getBlockType(direction)
		if blockType:find("chest") ~= nil then -- chest found. early stages so empty and break it
			print("Chest found")
			while T:suck(direction) do end
			T:dig(direction, false) -- false prevents checking for chests
			return true
		elseif blockType:find("torch") ~= nil then 
			print("Torch found")
			T:dig(direction, false) -- false prevents checking for chests
			return true
		end
		return false
	end
		
	function lib.findSpawner(blaze)
		local moves  = 0
		local quit = false
		-- assume turtle placed on centre of inside spawner wall in front of spawner
		-- or as close as possible in Nether
		print("Checking if next to spawner")
		local found, position = lib.isSpawner() -- true/false, top/bottom/nil
		if not found then -- move forward towards spawner
			print("Not close to spawner")
			while turtle.forward() and not quit do
				moves = moves + 1
				if moves > 16 then
					quit = true
				end
			end
			found, position = lib.isSpawner() -- true/false, top/bottom/nil
			if not found then
				if blaze then -- could be behind a wall
					print("Assuming blaze spawner behind a wall")
					T:forward(1)
					moves = moves + 1
					while turtle.forward() and not quit do 
						moves = moves + 1
						if moves > 16 then
							quit = true
						end
					end
					found, position = lib.isSpawner() -- true/false, top/bottom/nil
					if not found then
						T:go("R2F"..moves + 2 .."R2")
					end
				end
			end
		end
		
		return found, position
	end
	
	
	if not continue then -- new mob cube either dungeon or blaze
		-- clsTurtle.go(self, path, useTorch, torchInterval, leaveExisting, preferredBlock)
		-- determine spawner position level 4, move to top of spawner (level 6)
		print("Checking if already at spawner")
		local found, position = lib.isSpawner() -- already on spawner?
		if blaze then 
			if not found then -- away from spawner
				if R.subChoice == 3 then
					T:go("U5")
				end
				found, position = lib.findSpawner(blaze)
			end
		else -- go to bottom of dungeon and empty chests
			if not found then --outside dungeon
				local success, message = lib.enterDungeon(R)
				if not success then
					return {message}
				end
				found, position = lib.findSpawner(blaze) -- is spawner in front / above / below?
			end 
		end
		
		if found then -- true: move to correct starting position
			--[[
			1 |c|c|c|c|c|c|c|c|c|c|c|
			2 |w| | | | | | | | | |w|
			3 |w| | | | | | | | | |w|
			4 |w| | | | | | | | | |w|
			5 |w| | | | | | | | | |w|
			6 |w| | | | |s| | | | |w|
			7 |w| | | | | | | | | |w|
			8 |w| | | | | | | | | |w|
			9 |w| | | | | | | | | |w|
		   10 |w| | | | | | | | | |w| exit level for overworld
		   11 |f|f|f|f|f|f|f|f|f|f|f|
		   12 |f|f|f|f|f|f|f|f|f|f|f| sub floor for overworld
			   1 2 3 4 5 6 7 8 9 1 1
			                     0 1
			]]
			-- T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
			if position == "bottom" then
				T:go("B1U2F1")
			elseif position == "forward" then
				T:go("U1F1")
			end
			
			T:up(1)
			T:place("slab", "down", true) 				-- place slab on top T:place(blockType, direction, leaveExisting)
			-- go up 2 blocks, forward 5, right, forward 5, right
			T:go("U2F5 R1F5 R1") 							-- Level 2: now placed 1 below ceiling inside wall, top right corner of new dungeon
			lib.wallSection(blaze) 							-- fix layers 1, 2, 3 including ceiling margin turtle at Level 2			
			T:go("F1R2 C1L1 F1R2 C1R1", false, 0, false)	-- exit wall, repair behind, still Level 2
			lib.ceiling(blaze)								-- fix ceiling, end opposite corner to start
			T:go("R2D3")									-- clear the inner walls inside original dungeon
			lib.clearWall(9)								-- clear the 9 x 9 area around the spawner
			T:go("F1R1F1L1")
			lib.clearWall(7)								-- clear the 7 x 7 area around the spawner
			T:go("F1R1F1L1")
			lib.clearWall(5)								-- clear the 5 x 5 area around the spawner. Also needed for cave spiders
			T:go("R2F1R1F1R1")
			T:go("F7R1 F8L1F1R2", false, 0, false)			-- return from ceiling, enter wall below previous section: Level 5
			lib.wallSection() 								-- deal with areas from spawner level up (4,5,6). walls only	
			T:go("F1R2 C1L1 F1R2 C1R1 D3", false, 0, false) -- exit wall, repair behind, embed 1 below original floor: Level 8
			clearRectangle({width = 9, length = 9, up = true, down = true}) -- clear levels 7,8,9
			T:go("L1F1 L1F1L2", false, 0, false) 			-- go inside wall sectio, ready for next wall section
			lib.wallSection() 								-- deal with walls on levels 7,8,9
			T:go("F1R2 C1L1 F1R2 C1R1 D3", false, 0, false) -- exit wall, repair behind, embed 4 below original floor: Level 11
			--print("Check: about to clear 3 floors 3 below spawner") read()
			clearRectangle({width = 9, length = 9, up = true, down = true}) -- clear levels 10,11,12 
			
			if blaze then
				T:go("L1F1 L1F1L2", false, 0, false) 			-- ready for next wall section
				lib.wallSection() 								-- wall on layers 10,11,12
				T:go("F1R2 C1L1 F1R2 C1R1 D3", false, 0, false) -- exit wall, repair behind, embed 1 below original floor: Level 8
				clearRectangle({width = 9, length = 9, up = true, down = true}) -- clear levels 13, 14, 15
			end
			
			T:go("L1F1L1F1L2", false, 0, false) -- ready for next wall section
			--print("Check: level 11, 5 north, 5 east")
			--read()
			lib.wallSection() 	-- wall on layers 10,11,12 or 12,13,14 if blaze
			T:go("F1R1 F1R2 C1R1 U1", false, 0, false) -- exit wall, repair behind: Level 10, facing entry point top right corner
			T:down(1)
			if blaze then
				lib.placeFloor(9, 9, brick) 			-- place brick floor on level 14
				T:go("L1F4 R1F2 U4")					-- ends facing out to lower chamber ?below staircase
				-- now needs to build killzone
			else
				lib.placeFloor(9, 9, "stone") 			-- ends facing wall on entrance side
				T:go("U1R2")
				lib.placeFloor(9, 9, "stone") 			-- ends facing wall on opposite side
				-- return to mid-point front
				T:go("R2F8 R1F4 L1F2")					-- exit at bottom of dungeon
				T:go("x1U1 x1U1 x1U1 x1D3 R2") 			-- rise to chest, then return ready for next stage	
				-- ends with turtle facing spawner, in front of exit hole				
			end
		else
			return
			{
				"Spawner not found. Place me on top,",
				"immediately below, or facing it.",
				"\nEnter to quit"
			}
		end
	end
	if continue then
		T:clear()
		local text =
[[~yellow~Items required to continue:

~lightGray~slabs            81
~orange~nether bricks    88
~yellow~lava buckets     4
~brown~chest / barrel   1
~gray~hopper           1      

~red~WARNING ~yellow~Inventory ejects items if you
continue! ~orange~(Choose at next menu.)

~white~Next -> Enter]]
		menu.colourText(nil, text, true)
		read()
		pp.itemColours = {colors.red, colors.lime}
		local choice = menu.new("Choose your option", {"Continue with build", "Re-start later"}, pp, "Type number + Enter") -- 1 = continue, 2= quit
		if choice == 1 then
			choice = menu.new("Choose your option", {"Turtle is above me", "Turtle is below or next to me"}, pp, "Type number + Enter") -- 1 = up, 2= down
			if choice == 1 then
				T:emptyInventory("down")
			else
				T:emptyInventory("up")
			end
		else
			return {"Blaze spawner partial build halted"}
		end
		
		--clsTurtle.getItemSlot(self, item, useDamage): return slotData.lastSlot, slotData.leastModifier, total, slotData
		T:checkInventoryForItem({brick}, {88})
		T:checkInventoryForItem({"slab"}, {81})
		T:checkInventoryForItem({"lava"}, {4})
		T:checkInventoryForItem({"sign"}, {1})
		T:checkInventoryForItem({"hopper"}, {1})
		T:checkInventoryForItem({"chest", "barrel"}, {1, 1})
		print("Stand clear. Starting in 2 secs")
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		-- place upper floor and slabs under it
		T:go("R2D4F2 L1F4 R1U4")	
		lib.placeFloor(9, 9, brick) 			-- place brick floor on level 10
		T:down(2)
		T:place(brick, "up")
		T:go("D1R2")
		lib.ceiling(true)						-- true uses slabs
		
		-- place lava
		T:go("L1F4 L1F4 U4")					-- through hole in ceiling
		T:go("F4 L1F4 R2")
		for i = 1, 4 do
			T:place("lava", "down")
			T:go("F8 R1")
		end
		T:go("F4 R1F4 D2 F1 R2")
		-- place sign and repair above
		T:dig("forward")
		T:place("sign", true, "")
		T:down(1)
		T:place(brick, "up")
		T:forward(1)
		-- place blocks under exit hole
		for i = 1, 4 do
			T:place(brick, "forward")
			T:turnRight(1)
		end
		-- place chest and hopper
		
		T:go("D2x2")
		if not T:place("chest", "down") then
			T:place("barrel", "down")
		end
		T:up(1)
		T:place("hopper", "down")
		utils.goBack(1)
		T:place("slab", "forward")
		T:go("R2F5U3")-- return to starting point and create entrance
	end
	return {}
end

local function floodMobFarm(R) -- 63
	--[[Part 2 / 3 Mob Spawner Farm turtle on floor, pointing towards water source wall, single hole]]
	local lib ={}
	
	function lib.setPosition(addWater)
		local width = 0
		while turtle.forward() do end					-- move forward until hit wall
		T:go("U1L1")
		while turtle.forward() do end					-- move forward until hit left wall
		if addWater then
			T:placeWater("down") 			 			-- place water down
		end
		T:turnLeft(2)									-- turn round
		while turtle.forward() do
			width = width + 1 
		end			-- go forward 7
		if addWater then								-- back 1
			T:placeWater("down") 						-- place water					
		end
		T:go("L2F".. math.floor(width / 2) .."L1")		-- turn round, go forward 3 (centre of wall), turn left
	end

	function lib.digFloor()
		T:go("x2F1 x2")									-- first block, move forward
		
		T:turnLeft(1)									-- left turn, go back into right side, facing left
		utils.goBack(1)
		T:go("x2 F1x2 F1x2 R1F1")						-- go right to left dig 3 blocks, forward on left side
		
		T:turnRight(1)									-- right turn, go back into left side, facing right
		utils.goBack(1)
		T:go("x2 F1x2 F1x2 F1x2 F1x2 L1F1")				-- go left to right dig 5 blocks, forward on right side
		
		T:turnLeft(1)									-- left turn, go back into right side, facing left
		utils.goBack(1)
		T:go("x2 F1x2 F1x2 F1x2 F1x2 F1x2 F1x2 R1F1")	-- go right to left dig 7 blocks, forward on left side
		
		T:turnRight(1)									-- right turn, go back into left side, facing right
		utils.goBack(1)
		T:go("x2 F1x2 F1x2 F1x2 F1x2 F1x2  F1x2  F1x2  F1x2 L1")	-- go left to right dig 5 blocks, face forward on right side
	end
	
	lib.setPosition(false)					-- move to back of cube and verify position
	if R.subChoice == 1 then
		T:forward(3)						-- forward 4 (centre of chamber)
	else
		T:forward(2)						-- forward 3
	end
	T:down(1)
	lib.digFloor()
	if R.subChoice == 1 then		
		T:go("D1F1 L1F8")
		utils.goBack(4)
		T:go("L1U1")
		lib.setPosition(true)				-- place water sources
		T:go("F8D2")
		-- go down 2, check floor, up 1, place fence
		T:go("D2C2U1", false, 0, true)
		T:place("fence", "down", false)
		T:go("F1D1C2U1", false, 0, true)
		T:place("fence", "down", false)
		T:go("F1U1R2", false, 0, true)
		T:go("F1R1U1")
		T:place("sign", "down", false)
		T:go("U1C0D1")
		T:place("slab", "up", false)
		T:go("R2F1R2")
		T:place("sign", "forward", false)
		T:go("R1F1R2C1R1F1D1L1") --sitting on soul sand/dirt facing spawner
		if not T:place("minecraft:soul_sand", "down", false) then
			T:place("minecraft:dirt", "down", false)
		end
	else
		T:go("D1F1 L1F8")
		T:go("R1F1 R1F8")
		utils.goBack(4)
		T:go("R1U1")
		lib.setPosition(true)		-- place water sources
		T:go("F8D2 F1C2C0 F1")		-- exit leaving single hole in wall, facing away from spawner
	end
	
	return {}
end

local function createMobBubbleLift(R) -- 64
	-- Part 3 / 3 Mob Spawner Farm
	-- R.subChoice = 1 or 2 (left/right)
	local lib = {}
	
	function lib.initialise()
		local blockType = T:getBlockType("down")
		if blockType ~= "minecraft:soul_sand" then
			T:dig("down")
			if not T:place("minecraft:soul_sand", "down", false) then
				return {"Unable to find or place soulsand."}
			end
		end
		-- check facing sign, rotate if not
		blockType = T:getBlockType("forward")
		local turns = 0
		while blockType:find("sign") == nil do
			T:turnRight(1)
			turns = turns + 1
			if turns == 4 then
				return {"Unable to find sign."}
			end
			blockType = T:getBlockType("forward")
		end
		return {""}
	end
	
	function lib.createWaterSource(oTurn)
		T:go(oTurn.."1") 			-- turn to opposite side of dropzone
		T:go("F1x0D1")
		for i = 1, 3 do
			T:go("C2 L1C1 R2C1 L1")
			if i < 3 then
				T:go("F1x0")
			end
		end
		T:go("R2F1") 				-- face column move to middle
		T:placeWater("forward")
		T:go("R2")					-- face away
		T:placeWater("forward")
		T:go("U1x0 R2F1x0 F1x0"..oTurn.."1")	-- face column, return to soul sand, face spawner
	end
	
	function lib.goToWater(moves)
		T:down(moves)
		T:getWater("down")
		sleep(0.1)
		T:getWater("down")
	end
	
	function lib.placeCollector(turn, oTurn)
		local hopperSlot = T:getItemSlot("hopper")
		local chestSlot = T:getItemSlot("chest")
		if hopperSlot > 0 and chestSlot > 0 then
			T:dig("down")
			T:place("chest", "down")
			T:go(turn.."1F1"..oTurn.."1")
			T:dig("down")
			T:place("chest", "down")
			T:go(turn.."1")
			utils.goBack(3)
			T:go("D1x1")
			T:place("hopper", "forward")
			T:go("U1C2F2"..oTurn.."1")
		end
	end
	
	function lib.up()
		local moves = 0
		while turtle.detect() do
			turtle.up()
			moves = moves + 1
		end

		return moves
	end
	
	function lib.createChamber()
		local D = {}
		D.width  = 4
		D.length = 7
		D.height = 4
		D.ceiling = true
		D.floor = true
		D.vDirection = "D"
		D.hDirection = "RL"
		D.goHome = true

		utils.createWalledSpace(D)
	end
	
	function lib.mobTransporter()
		for i = 1, 9 do -- fill in a solid block bar from bubble column for 8 spaces
			T:go("F1C0C2 R1C1 R1C1 R1C1 R1C1")
		end
		T:go("D1C2C1 R1C1 R2C1 L1 C0x0") -- move down column
		for i = 1, 8 do -- go under solid block bar
			T:go("F1C2 R1C1 L2C1 R1x0")
		end
	end
	
	local turn = "R"
	local oTurn = "L"
	if R.subChoice == 1 then
		turn = "L"
		oTurn = "R"
	end
	
	local data = lib.initialise()			-- check if in the right position
	if data[1] ~= "" then
		return data 						-- eg {"Unable to find sign."}
	end
	lib.createWaterSource(oTurn)			-- everything in place, build a water source, facing spawner
	for i = 1, 3 do		-- fill in back and one side, go up
		T:go(turn.."1C1"..turn.."1C1"..turn.."1x1"..turn.."1U1", false, 0, true)
	end
	-- dungeon wall, above mob exit, facing spawner
	local colHeight = 19
	for i = 1, colHeight do		-- tunnel up, filling 3 sides
		T:go(turn.."1C1"..turn.."1C1"..turn.."1x1"..turn.."1C1 U1", false, 0, true)
	end
	-- facing spawner 20 blocks up. move either left/right 8 blocks, repairing ceiling and sides
	T:go("C0"..turn.."2C1"..turn.."1F1 C0C1"..turn.."1C1"..turn.."2C1"..oTurn.."1", false, 0, true) -- fill top of column
	
	lib.mobTransporter()
	T:go("x2x0 F1x2x0 F1x2x0 R2") -- over water source
	-- now create bubble column
	T:down(colHeight + 2)
	local moves = 0
	repeat
		lib.goToWater(moves)	-- get water
		moves = lib.up()
		T:go("F1")
		T:placeWater("forward")
		T:go("U1C2")
		T:placeWater("forward")
		utils.goBack(1)
		T:go("C1")
		moves = moves + 1
	until moves >= colHeight + 1
	lib.goToWater(moves)	-- get water for last time
	lib.up()				-- finishes above lower part of the transport bar
	T:go("F2R2C1D1")		-- seal off bubble column
	utils.goBack(1)
	T:placeWater("forward")	-- place source on top of bubble column
	utils.goBack(7)			-- over down shaft
	T:down(1)				-- start shaft, facing bubble column
	for i = 1, 17 do
		-- tunnel down, filling all 4 sides
		T:go("R1C1 R1C1 R1C1 R1C1 D1", false, 0, true)
	end
	lib.createChamber()
	T:go("x0")
	T:go(oTurn.."1C1".. turn.."1D1C2"..oTurn.."1C1"..turn.."1F1".. oTurn.."1F1"..oTurn.."1") -- facing end wall ready to place slabs
	for i = 1, 6 do
		T:place("slab", "down")
		if i == 6 then
			T:go(oTurn.."1")
		end
		utils.goBack(1)
		T:go("C1")
	end
	
	T:go("D2F2"..turn.."1F5")
	T:placeWater("forward")
	T:go(turn.."1F1"..oTurn.."1") -- facing down mob channel floor
	for i = 1, 5 do
		T:go("C1")
		utils.goBack(1)
	end
	T:go("C1"..turn.."1F1"..turn.."1F1")
	for i = 1, 7 do
		T:go("C2x0")
		if i < 7 then
			T:forward(1)
		end
	end
	T:go("U3R2")
	for i = 1, 7 do
		T:go("F1x2")
	end
	T:go("D3")
	
	lib.placeCollector(turn, oTurn) -- if hopper / chests present
	
	return {}
end

local function createPlatform(R) -- 56
	-- T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
	local forward = true
	for w = 1, R.width do
		for l = 1, R.length do
			T:go("x2C2", false, 0, false, R.useBlockType)
			if R.up then
				T:dig("up")
			end
			if l < R.length then
				T:forward(1)
			end
		end
		if w < R.width then
			if forward then
				if R.up then
					T:go("R1F1 x0R1")
				else
					T:go("R1F1 R1")
				end
			else
				if R.up then
					T:go("L1F1 x0L1")
				else
					T:go("L1F1 L1")
				end
			end
		end
		forward = not forward
	end
	return {}
end

local function createPortal(R) -- 42
	--[[
	R.length = length of portal NOT width default 4
	R.height = height of portal default 5
	R.width = thickness of portal default 1
	R.data = "bury" to embed bottom into ground
	R.subChoice 1 = facing portal, 2 = aligned
	]]
	local lib = {}
	
	function lib.buildBase()
		--T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
		T:go("C2", false, 0, false, R.useBlockType)
		T:forward(1)
		for i = 1, R.length - 2 do -- R.length = 4: place when i=1,2
			T:place("minecraft:obsidian", "down", false)
			T:forward(1)
		end
		T:go("C2", false, 0, false, R.useBlockType)
	end
	
	function lib.buildLayer()
		T:place("minecraft:obsidian", "down", false)
		for i = 1, R.length - 1 do -- R.length = 4: forward when i=1,2,3
			T:forward(1)
		end
		T:place("minecraft:obsidian", "down", false)
	end
	
	if R.data ~= "bury" then
		T:up(1)
	end
	if R.subChoice == 1 then
		T:go("F1R1")
	end
	local out = true
	for width = 1, R.width do
		lib.buildBase()
		for i = 1, R.height - 2 do
			T:go("R2U1")
			out = not out
			lib.buildLayer()
		end
		T:go("R2U1")
		out = not out
		lib.buildBase()
		if out then
			T:go("R2F"..R.length - 1)
		end
		if width < R.width then
			T:go("R1F1D"..R.height.."R1")
			out = true
		else
			T:go("L1F"..R.width.."D"..R.height - 1 .."R2")
			if R.data ~= "bury" then
				T:down(1)
			end
		end
	end
	
	return {}
end

local function createPortalPlatform() -- 48
	--[[ Used in End World to use a trapdoor to push player through portal ]]
	local lib ={}
	
	function lib.findPortal()
		local found = false
		local onSide = false
		for i = 1, 64 do
			if not turtle.up() then -- hit block above
				found = true
				break
			end
		end
		if found then
			-- are we under the centre block, or one of the sides?
			if turtle.detect() then -- under a side
				onSide = true
			else	-- nothing in front, probably under centre, or facing wrong direction so check
				for i = 1, 4 do
					turtle.turnRight()
					if turtle.detect() then
						onSide = true
						break
					end
				end
			end
			if onSide then-- move to centre
				T:go("D1F1")
			end
		end
		local height = 3 -- allows for 2 bedrock + starting space
		while turtle.down() do
			height = height + 1
		end
		return found, height
	end
	
	function lib.addFloor(length)
		for i = 1, length do
			if i < length then
				T:go("C2F1", false, 0, true)
			else
				T:go("C2", false, 0, true)
			end
		end
	end
	
	function lib.buildLadder(height)
		for i = 1, height do
			--T:go("F1C1 R1C1 L2C1 L1F1L2", false, 0, true)
			T:go("F1C1 R1C1 L2C1 R1", false, 0, true)
			utils.goBack(1)
			if i > 3 then
				T:go("C2")
			end
			T:place("minecraft:ladder", "forward", true)
			T:up(1)
		end
	end
	
	local found, height = lib.findPortal()
	if found then	-- position under centre of beacon
		-- build ladder up and create platform
		T:go("L1F1L1F2L2")
		T:checkInventoryForItem({"minecraft:ladder"},{height})
		T:checkInventoryForItem({"stone"},{height * 4 + 18})
		T:checkInventoryForItem({"trapdoor"},{1})
		lib.buildLadder(height) -- ends facing ladder, 1 block above
		
		T:go("R1")
		utils.goBack(1)
		T:go("C2F1 C2F1 C2F1 C2")
		T:go("R1F1R1")
		T:go("C2F1 C2F1 C2F1 C2")
		utils.goBack(2)
		T:go("R1F1")			-- facing portal entrance
		T:place("trapdoor", "up", false)
	else
		return {"Portal not found. Move me under","the centre if possible.", "wait for purple beacon."}
	end
	return {}
end

local function createRailway(R) -- 93
	-- go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
	--[[
		Build steps up or down ready for railtrack
		R.depth = headroom, default 2
	]]
	if R.down then
		if R.height == 0 then
			local blockType = ""
			while blockType == "" do
				T:go("F1D1", false, 0, true)
				blockType = T:getBlockType("down")
				if blockType == "" then
					T:go("C2", false, 0, true)
				end
			end
		else
			for i = 1, R.height - 1 do
				--T:go("U1x0 D1x1 F1x0x1 D1x1 C2", false, 0, false)
				T:go("U"..R.depth - 1 .."x0 D"..R.depth - 1 .."x1 F1x0x1 D1x1 C2", false, 0, false)
			end
		end
	elseif R.up then
		for i = 1, R.height do
			--T:go("C1U2 x0D1F1", false, 0, false) --put stone in front, up 2 excavate 1, down 1, forward 1
			T:go("C1U"..R.depth.." x0D"..R.depth.."F1", false, 0, false) --put stone in front, up 2 (or headroom) excavate 1, down 1, forward 1
		end
	end
	return {}
end

local function createRectanglePath(R) -- 710, 83 direct commands
	-- allow user to control length / width of each path
	-- T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
	--local pp = utils.getPrettyPrint()
	local lib = {}
	
	function lib.forward(R)
		if R.subChoice == 1 then
			for i = 1, R.length do
				T:go("F1x0C2", false, 0, true)
			end
		else
			for i = 1, R.length do
				T:go("F1U1C0D1C2", false, 0, true)
			end
		end
	end
	
	function lib.back(R)
		for i = 1, R.length do
			turtle.back()
		end
	end
	
	function lib.left(R)
		T:turnLeft(R.length)
	end
	
	function lib.right(R)
		T:turnRight(R.length)
	end
	
	function lib.up(R)
		if R.subChoice == 1 then
			T:go("U2R2 x1R2 D1C2", false, 0, true)
		else
			T:go("U2R2 x1R2C0 D1C2", false, 0, true)
		end
	end
	
	function lib.down()
		T:go("D1C2", false, 0, true)
	end
	
	if R.data == "menu" then
		-- mimics direct commands using f.lua, r.lua etc with space between commands and number
		local width = 0
		local length = 0
		local choices =
		{
			"Forward 1 block",
			"Forward # blocks",
			"Back 1 block",
			"Back # blocks",
			"Turn Right",
			"Turn Left",
			"Up 1 block",
			"Down 1 block",
			"Quit"
		}
		local choice, modifier
		pp.itemColours = {colors.lime, colors.lime, colors.green, colors.green, colors.orange, colors.orange, colors.cyan, colors.cyan, colors.gray}
		while choice ~= 9 do
			choice, modifier = menu.menu("Choose next step", choices, pp, "Type number + Enter ")
			if choice == 1 then
				R.length = 1
				lib.forward(R)
			elseif choice == 2 then
				-- getInteger(prompt, minValue, maxValue, row, fg, bg, default) 
				R.length = menu.getInteger("Move forward how many blocks?", 1, 250, nil, colors.lime)
				lib.forward(R)
			elseif choice == 3 then
				R.length = 1
				lib.back(R)
			elseif choice == 4 then
				R.length = menu.getInteger("Move back how many blocks?", 1, 250, nil, colors.green)
				lib.back(R)
			elseif choice == 5 then
				R.length = 1
				lib.right(R)
			elseif choice == 6 then
				R.length = 1
				lib.left(R)
			elseif choice == 7 then
				lib.up(R)
			elseif choice == 8 then
				lib.down()
			end
		end
	else
		local instructions = 
[[~lightGray~Commands:

direction + ~blue~number ~yellow~eg ~white~f2 ~yellow~= forward ~blue~2
~lightGray~direction without number = ~blue~1

~yellow~f = forward  ~orange~b = backward
~lime~l = left     ~red~r = right
~lightGray~u = up       ~cyan~d = down

~red~q = quit

]] -- Direct control
		local cmd = ""
		while cmd ~= "q" do
			local line = menu.clear()
			line = menu.colourText(line, instructions)
			-- menu.getString(prompt, withTitle, minValue, maxValue, row, fg, bg, default) 
			input = menu.getString("command ", false, 1, 5, line, colors.yellow, colors.black):lower()
			-- remove spaces
			input = input:gsub( " ", "")
			cmd = input:sub(1,1)
			R.length = 1
			if #input > 1 then
				R.length = tonumber(input:sub(2))
			end
			if cmd == "q" then
				return{"User has quit application"}
			end
			if cmd == "f" then
				lib.forward(R)
			elseif cmd == "b" then
				lib.back(R)
			elseif cmd == "l" then
				lib.left(R)
			elseif cmd == "r" then
				lib.right(R)
			elseif cmd == "u" then
				lib.up(R)
			elseif cmd == "d" then
				lib.down()
			end
		end
	end
	return {}
end

local function createRetainingWall(R) -- 34, 82
	-- facing direction wall will take
	-- will need to rotate 180 to build
	-- if R.height > 0 then build to specified depth
	local lib = {}
		
	function lib.checkFloor()
		local newDepth = 0
		place = utils.clearVegetation("down") -- in case col in front is deeper
		while place do -- loop will be entered at least once
			T:down(1)
			newDepth = newDepth + 1
			place = utils.clearVegetation("down")
		end
		if newDepth > 0 then
			for j = 1, newDepth do	-- go up until column base is met
				T:go("U1C2")
			end
		end
	end
	
	function lib.patchMissingBlock()
		if turtle.back() then
			T:go("C1")
		else
			T:go("B1C1")
		end
	end
	
	function lib.placeSingle(height)
		local y = 0
		if height > 0 then
			T:go("D"..height)
			y = height
		else
			local place = utils.clearVegetation("down")
			while place do -- loop will be entered at least once
				place = utils.clearVegetation("down")
				if place then
					T:down(1)
					y = y + 1
				end
			end
		end
		-- return to surface, placing below
		for i = 1, y do
			T:go("U1C2", false, 0, true)
		end
	end
	
	function lib.placeDouble(height)
		--T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
		local y = 0
		if not turtle.back() then
			T:go("B1")
		end
		if height > 0 then
			for i = 1, height do
				T:go("C1D1", false, 0, true)
			end
			T:go("C1", false, 0, true)
			y = height
		else
			local place = utils.clearVegetation("down")
			-- build back column
			while place do -- loop will be entered at least once
				place = utils.clearVegetation("down")
				if place then
					T:go("C1D1", false, 0, true)
					y = y + 1
				end
			end
			-- reached bottom. floor in front could drop down
			T:go("F1") -- move under first column
			lib.checkFloor()
			turtle.back() -- back at starting point
			T:go("C1", false, 0, true) 
		end
		-- return to surface, placing below
		for i = 1, y do
			T:go("U1C2", false, 0, true)
		end
	end
		
	function lib.placeTriple(height)
		--T:go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
		local y = 0
		if turtle.back() then
			T:go("C1")
		else
			T:go("B1C1")
		end
		if height > 0 then
			for i = 1, height do
				T:go("C1D1", false, 0, true)
			end
			for i = 1, height do
				T:go("C1D1", false, 0, true)
			end
			T:go("C1R2C1", false, 0, true) --fill last block, then turn 180 to build opposite side
			y = height
		else
			local place = utils.clearVegetation("down")
			-- build back column
			while place do -- loop will be entered at least once
				place = utils.clearVegetation("down")
				if place then
					T:go("C1D1", false, 0, true)
					y = y + 1
				end
			end
			-- reached bottom. floor in front could drop down
			T:go("F1") -- move under first column
			lib.checkFloor()
			T:go("B1C1R2F1", false, 0, true) 
			lib.checkFloor()
			T:go("B1C1")
			-- return to surface , placing below and to front
		end
		for i = 1, y do
			T:go("C1U1C2", false, 0, true)
		end
		T:go("F1R2C1", false, 0, true)
		-- facing back again inside edge of col 3
		return y -- depth of this run
	end
	
	local topInPlace = false -- topInPlace = true already a path across the water eg monument rectangle
	if R.data == "withPath" then
		topInPlace = true
	end
	local place = false
	local inWater = false
	local onWater = false
	if not topInPlace then
		if R.length > 1 then
			inWater, onWater = utils.getWaterStatus() -- returns whether above water, or immersed
		end
	end
	
	local maxDepth = 5 --initial estimated value
	-- start at surface, move back 1 block
	-- each iteration completes 3 columns
	local numBlocks = T:getSolidBlockCount()
	print("Solid blocks in inventory: "..numBlocks)
	
	if R.length == 1 then -- single column down to water bed
		lib.placeSingle(R.height)
	elseif R.length == 2 then--down then up: 2 cols
		inWater, onWater = utils.startWaterFunction(onWater, inWater, 2, true) -- move into water
		T:go("R2") -- move to face player
		lib.placeDouble(R.height)
		if not inWater then
			T:go("U1C2", false, 0, true)
		end
	else -- R.length 3 or more
		if topInPlace then
			T:down(1) -- break through top
		else
			inWater, onWater = utils.startWaterFunction(onWater, inWater, 2, true) -- move into water
		end
		T:go("R2") -- move to face player
		-- now at water surface
		local remain = R.length
		while remain >= 3 do
			numBlocks = T:getSolidBlockCount()
			print("Inventory blocks: "..numBlocks.." depth: "..maxDepth)
			if numBlocks < maxDepth * 3 then
				--ask player for more
				T:checkInventoryForItem({"stone"}, {maxDepth * remain}, false)
			end
			local y = lib.placeTriple(R.height) -- moves back, places col in front, centre and behind. R.height = 0 for auto depth
			if y > maxDepth then
				maxDepth = y
			end
			remain = remain - 3
			if remain > 1 then
				lib.patchMissingBlock()
			end
		end
		if remain == 1 then -- 1 more column
			lib.patchMissingBlock()
			lib.placeSingle(R.height)
		elseif remain == 2 then -- 2 cols
			lib.placeDouble(R.height)
		end
		T:go("U1C2") -- above surface
	end
	return {}
end

local function createSafeDrop(R) -- 14
	-- dig down height blocks, checking for blocks on all sides
	local drop = 0
	local isBedrock = false
	T:down(2)
	drop = 2
	for i = 1, R.height - 1 do
		for j = 1, 4 do
			-- go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
			T:go("C1R1", false, 0, true)
		end
		if T:down(1) then
			 drop = drop + 1
		else
			isBedrock = true
			break
		end
		if T:isWaterOrLava("up") ~= "" then
			T:go("C0x0", false, 0, false) -- delete water/ lava block
		end
	end
	if not isBedrock then -- not sitting on bedrock, so break foot level exit block
		T:go("U1R2x1")
	end
	T:placeWater("down")
	if isBedrock then
		T:go("U1x1 U1x1")
	else
		T:go("U1x1")
	end
	T:up(drop - 2)
	
	return {"Safe drop completed "..drop .. " blocks"}
end

local function createSlopingWater(R) -- 34, 89
	--[[
	creates a sloping water area above existing lake/river/ocean
	R.width is usually 7 with an existing wall on 8th row
	R.length  is user choice, limited to bucket/slab quantities
	Places slabs into existing surface, places row of sources
	Removes slabs
	]]
	local lib = {}
	
	function lib.fillBuckets()
		local emptyBuckets = utils.getEmptyBucketCount()
		for i = 1, emptyBuckets do
			if utils.fillBucket("down") then
				print("Bucket filled down")
				sleep(0.3)
			else
				print("Unable to fill bucket ".. i .." / "..emptyBuckets)
			end
		end
		return utils.getWaterBucketCount()
	end
	
	local outbound = true
	local inWater, onWater = utils.getWaterStatus()
	inWater, onWater = utils.startWaterFunction(onWater, inWater, 2 ,false) -- move above water, max descent 2
	local waterBuckets = lib.fillBuckets()
	for w = 1, R.width do
		for l = 1, R.length do
			T:place("slab", "down", false)
			if l < R.length then
				T:forward(1)
			end
		end
		if w < R.width then
			if outbound then
				T:go("R1F1R1")
			else
				T:go("L1F1L1")
			end
			outbound = not outbound
		end
	end
	if outbound then
		T:go("L1F"..R.width - 1 .."L1")
	else
		T:go("R1F"..R.width - 1 .."R1")
	end
	T:placeWater("up")  -- place in corner
	local move = true
	while move do
		move = turtle.forward()
		move = turtle.forward() -- false if at end of run
		T:placeWater("up")  -- alternate positions + end of run
	end
	T:go("R2D1")
	T:sortInventory() -- get all buckets into 1 slot
	for w = 1, R.width do
		for l = 1, R.length do
			if l < R.length then
				T:forward(1)
			end
		end
		if w < R.width then
			if outbound then
				T:go("R1F1R1")
			else
				T:go("L1F1L1")
			end
			outbound = not outbound
		end
	end
	if outbound then
		T:go("L1F"..R.width - 1 .."L1")
	else
		T:go("R1F"..R.width - 1 .."R1")
	end
	T:go("U2")
	
	return {}
end

local function createSquidFarmBase(R) -- 34
	-- dig down to y=45. assume starting at water level (64)
	local depth = 0
	local message =
[[Place the turtle under the grid
left corner above current pit
opening.
It will descend to the base and
continue to level y=45.

Enter to continue...
]]
	read()
	while turtle.down()do
		depth = depth + 1
	end
	T:down(1)
	R.height = 21 - depth
	R.width = 15
	R.length = 15
	R.silent = true
	R.data = "down"
	clearSolid(R)
	T:up(depth + 4)
	return {}
end

local function createSandWall(R) -- 81
	local success = true
	--move above water
	local maxMove = 2
	while turtle.detectDown() and maxMove > 0 do
		T:forward(1)
		maxMove = maxMove - 1
	end
	if R.length > 0 then
		for i = 1, R.length - 1 do
			success = utils.dropSand()
			T:forward(1, false)
		end
		success = utils.dropSand()
	else
		while not turtle.detectDown() do -- over water
			while not turtle.detectDown() do -- nested to allow forward movement
				success = utils.dropSand() -- drops sand and checks supplies
			end
			if success then
				T:forward(1, false)
			else -- out of sand
				break
			end
		end
	end
	return {}
end

local function createSinkingPlatform(R) -- 58
	local lib = {}
	
	function lib.stage1a(R)							-- build side wall left side
		for l = 1, R.length do 						--            | |*| |
			T:go("L1C1 R1C2", false, 0, false)		-- |*|>| | to |*|>| | place left wall
			if l == 1 then							-- first iteration
				T:go("U1C2 D1 F1C2", false, 0, false)-- |*|>| | to |*|*|>| up/down block to delete source at corner
			elseif l < R.length then				-- mid run
				T:go("F1C2", false, 0, false)		-- |*|>| | to |*|*|>| move forward
			else									-- end of run
				T:go("C1U1 C2D1", false, 0, false)	-- |*|>| | to |*|>|*| place end wall
			end
		end
	end
	
	function lib.stage1b(R)							-- same as stage1a on right side
		for l = 1, R.length do 
			T:go("R1C1 L1C2", false, 0, false)
			if l == 1 then
				T:go("U1C2 D1 F1C2", false, 0, false)
			elseif l < R.length then
				T:go("F1C2", false, 0, false)
			else
				T:go("C1U1 C2D1", false, 0, false)
			end
		end
	end
	
	function lib.stage2(forward)
		if forward then
			T:go("C1R1 F1L1 C1R2", false, 0, false)
		else
			T:go("C1L1 F1R1 C1L2", false, 0, false)
		end
	end
		
	local forward = true
	local goingRight = true
	local blockType = T:getBlockType("down")
	if blockType:find("water") ~= nil or blockType:find("lava") ~= nil then
		T:up(1)
	end
	for h = 1, R.height do						-- repeatedly create a platform, move down and repeat
		T:down(1) 								-- move down into existing platform
		if goingRight then 						-- first side
			if forward then						-- complete left side
				T:go("R2C1 L2", false, 0, false) -- | |>| | to |*|<| | to |*|>| | 
				lib.stage1a(R)					-- build left wall
				T:go("R1F1 L1C1 R2C2", false, 0, false)			-- turn ready for next side
			else
				T:go("L2C1 R2", false, 0, false) -- block 1, 1
				lib.stage1b(R)					-- turn ready for next side
				T:go("L1F1 R1C1 L2C2", false, 0, false)
			end
		else 									-- on right side so different approach
			if forward then
				T:go("L2C1 R2", false, 0, false) -- | |<| | to | |>|* | to | |<|*| 
				lib.stage1b(R)					
				T:go("C1L1 F1R1 C1L2 C2", false, 0, false)		-- turn ready for next side
			else								-- complete left side
				T:go("R2C1 L2", false, 0, false) -- block 1, 1
				lib.stage1a(R)					-- turn ready for next side
				T:go("C1R1 F1L1 C1R2 C2", false, 0, false)
			end
		end
		forward = not forward					-- continue strips across until at far edge
		for w = 1, R.width - 2 do
			for l = 1, R.length do
				if l < R.length then
					T:go("C2F1", false, 0, false)
				else
					T:go("C2", false, 0, false)
				end
			end
			if goingRight then
				lib.stage2(forward)
			else
				lib.stage2(not forward)
			end
			forward = not forward
		end										-- far side
		if goingRight then
			if forward then
				lib.stage1b(R)
			else
				lib.stage1a(R)
			end
		else
			if forward then
				lib.stage1a(R)
			else
				lib.stage1b(R)
			end
		end
		goingRight = not goingRight
		T:turnRight(2)
		forward = not forward
	end
	return {}
end

local function createStaircase(R) -- 13
	-- R# L# F# B# U# D# +0 -0 = Right, Left, Forward, Back, Up, Down, up while detect and return, down while not detect
	-- dig:			  x0,x1,x2 (up/fwd/down)
	-- suck:		  s0,s1,s2
	-- place chest:   H0,H1,H2 
	-- place sapling: S0,S1,S2
	-- place Torch:   T0,T1,T2
	-- place Hopper:  P0,P1,P2
	-- mine floor:	  m# = mine # blocks above and below, checking for valuable items below, and filling space with cobble or dirt
	-- mine ceiling:  M# = mine # blocks, checking for valuable items above, and filling space with cobble or dirt
	-- mine ceiling:  N# same as M but not mining block below unless valuable
	-- place:		  C,H,r,S,T,P,^ = Cobble / cHest / DIrT / Sapling / Torch / hoPper /stair in direction 0/1/2 (up/fwd/down) eg C2 = place cobble down
	
	-- 3| |B| |
	--   - - - 
	-- 2|A| |C|
	--   - - - 
	-- 1|^|D| |
	--   - - - 
	--   1 2 3 
	local lib = {}
	
	function lib.checkFluids()
		local isFluid = false
		-- check if water or lava present
		for i = 1, 4 do
			blockType = T:isWaterOrLava("forward")
			if blockType:find("lava") ~= nil or blockType:find("water") ~= nil then
				isFluid = true
			end
		end
		return isFluid
	end
	
	function lib.createStaircaseSection(onGround, levels, level)
		-- start 1,1,1, n
		-- stage A
		local isFluid = lib.checkFluids()
		local blockType = ""
		local data = T:getStock("stairs")
		if data.total == 0 then
			T:craft('stairs', 4)
		end
		if onGround and isFluid then
			-- add right side and block entrance
			T:go("R1C1R1C1R2")
		end
		if isFluid then
			T:go("L1C1 R1F1C2 L1C1 R1x1 R1C1 L1C2B1 C1x1 ^1C2", false, 0, true) --start:1,1,1,n stairs A on level 1, going back to 1,1,1,n
		else
			T:go("F1x1 R1C1 L1C2B1 ^1C2", false, 0, true)
		end
		if not onGround then
			-- stage A1
			T:go("L2C1L2", false, 0, true) -- start 1,1,1,n fix corner on level 1 end: 1,1,1,n
		end
		-- stage B
		T:go("U1L1", false, 0, true) -- end  1,1,1,w layer 2
		level = level + 1
		isFluid = lib.checkFluids()
		if isFluid then
			T:go("C1", false, 0, true) -- end  1,1,1,w layer 2
		end
		if not onGround then
			if isFluid then
				T:go("L1C1R1", false, 0, true) -- end  1,1,1,w layer 2
			end
		end
		-- stage C1
		if isFluid then
			T:go("R1C1F1C1x1 L1C1 R2C1 L1B1", false, 0, true)
		else
			T:go("R1F1 R1C1 L1B1", false, 0, true)
		end
		--level = level + 1
		--if level == levels then
			--return false, level
		--end
		-- stage C2
		T:go("U1")
		level = level + 1
		--if level == levels then
			--return true, level
		--end
		isFluid = lib.checkFluids()
		if isFluid then
			T:go("L1C1L1 C1L2 C1F1L1 C1R2 C1L1 B1C2 D1", false, 0, true) -- end 1,1,2,n
		else
			T:go("F1R1 C1L1 B1D1", false, 0, true) -- end 1,1,2,n
		end
		level = level - 1 -- went down in branch above
		--if level == levels then
			--return false, level
		--end
		-- stage D
		isFluid = lib.checkFluids()
		if isFluid then
			T:go("C1F1C1F1C1x1L1 C1R1 C1R1", false, 0, true) -- 3,1,2,e
		else
			T:go("F2 C1R1", false, 0, true) -- 3,1,2,e
		end
		
		return false, level
	end

	--local height = currentLevel -- eg 64 at top or 5 at bedrock
	local data = T:getStock("stairs")
	--{rt.total, rt.mostSlot, rt.leastSlot, rt.mostCount, rt.leastCount}
	local numStairs = data.total
	local levels = math.abs(R.depth - R.height) --height of stairs
	local numStairsNeeded = levels
	numStairsNeeded = numStairsNeeded - numStairs
	if numStairsNeeded > 40 then
		print('crafting '..numStairsNeeded..' : '..numStairs.. ' in stock')
		if T:craft('stairs', 40) then	-- max 40 so repeat
			data = T:getStock("stairs")
			if data.total == 0 then
				data = T:getStock("stairs")
			end
			numStairs = data.total
			numStairsNeeded = numStairsNeeded - numStairs
		else
			return {"Unable to craft stairs"}
		end
	end
	if numStairsNeeded > 0 then
		T:craft('stairs', numStairsNeeded)
	end
	local level = 0
	if R.down then -- go down towards bedrock
		local atBedrock = false
		for i = 1, levels do
			level = level - 1
			if not T:down() then
				atBedrock = true
				break
			end
		end
		if atBedrock then -- hit bedrock so get to level 5 / -59
			level = T:findBedrockTop(level)
			T:go("R1F1R1", false, 0, true)
		end
	end
	local onGround = true
	level = 0
	while level < levels do
		onGround, level = lib.createStaircaseSection(onGround, levels, level)
	end
	if not turtle.detectDown() then
		T:go("C2")
	end
	
	return{"Staircase completed"}
end

local function createStripMine(R)
	--[[
	R.length should be a multiple of 16
	mine a corridoor repairing floor and ceiling
	check sides, remove valuable items
	plug if lava present
	Every 16 blocks dig a side passage 1 block deep 2 blocks long
	]]
	local lib = {}
	
	function lib.seal(R)	
		if T:isValuable("forward") then	-- valuable block in front. If debris then refuse already dumped
			T:dig("forward")
		end
		local blockType = T:getBlockType("forward")
		if blockType:find("lava") ~= nil then
			--T:place("stone", "forward", false) -- place does not allow for specific blocktype
			T:go("C1", false, 0, false, R.useBlockType)
			return true
		end
		
		return false
	end
	
	function lib.checkSeal(R)
		local retValue = false
		T:turnRight(1)
		if lib.seal(R) then
			retValue = true
		end
		T:turnLeft(2)
		if lib.seal(R) then
			retValue = true
		end
		T:turnRight(1)
		return retValue
	end
		
	function lib.alcove(R)
		-- right side, starting at ceiling
		T:go("R1F1 C0", false, 0, false, R.useBlockType)-- stone ceiling, facing alcove wall (upper)
		lib.seal(R)										-- seal alcove wall (upper)	
		T:go("D1C2", false, 0, false, "cobble")			-- cobble floor, facing alcove wall (lower)	
		lib.seal(R)										-- seal alcove wall (lower)		
		T:go("L2 F1")									-- down 1, turn round, return to corridoor.
		-- left side	
		T:go("F1 C2", false, 0, false, "cobble")		-- cobble floor, facing alcove wall (lower)	
		lib.seal(R)										-- seal alcove wall (lower)
		T:go("U1 C0", false, 0, false, R.useBlockType)	-- stone ceiling, still facing alcove wall
		lib.seal(R)										-- seal alcove wall (upper)						
		T:go("L2F1L1")									-- return to corridoor at ceiling position
		lib.placeTorch(R)								
	end
	
	function lib.placeTorch(R)
		if R.torchInterval > 0 then 					-- torches onboard
			if T:getItemSlot("minecraft:torch") > 0 then
				T:place("minecraft:torch", "down")
			end
		end
	end
	
	local seal = false
	if T:getItemSlot("minecraft:torch") == 0 then
		R.torchInterval = 0 -- set to default 16 above
	end
	for steps = 1, R.length do
		-- go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
		T:go("C2U1C0", false, 0, true, R.useBlockType)		-- check and repair floor / ceiling
		if steps % 16 == 0 or steps % 16 == 1 then
			lib.alcove(R) -- enter and exit at ceiling position
		else
			seal = lib.checkSeal(R)
		end
		T:go("F1D1", false, 0, true)
		seal = lib.checkSeal(R)
	end
	if seal then -- water or lava found while tunnelling
		T:go("U1C0", false, 0, true, R.useBlockType)
		lib.checkSeal(R)
		T:go("C1", false, 0, true, R.useBlockType)
		T:down(1)
	end
	return {}
end

local function createTreefarm(R) -- 22
	local lib = {}
	--go(path, useTorch, torchInterval, leaveExisting, preferredBlock)
	function lib.buildWallSection(section, useBlockType)
		-- build a layer 1 block high below turtle
		for i = 1, #section do
			local block = section:sub(i, i)
			if block == "l" then
				T:place("log", "down")
			elseif block == "m" then
				T:place("modem", "down")
			elseif block == "b" then
				T:place("barrel", "down")
			elseif block == "c" then
				T:place("cable", "down")
			else
				T:place(useBlockType, "down")
			end
			if i < #section then
				T:forward(1)
			end
		end
	end
	
	function lib.placeFloor(length, useBlockType)
		for i = 1, length do
			while turtle.digUp() do end
			turtle.digDown()
			T:place(useBlockType, "down")
			--T:go("x0C2", false, 0, false, useBlockType)
			if i < length then
				while not turtle.forward() do
					turtle.dig()
				end
				--T:forward(1)
			end
		end
	end
	
	function lib.placeWater(length)
		T:placeWater("down") 
		T:go("F"..length.."R1")
	end
	
	function lib.placeCorners(length, numBlocks, useBlockType)
		for i = 1, numBlocks do
			T:go("C2F1", false, 0, false, useBlockType)
		end
		-- now at 5th space
		T:forward(length - (numBlocks * 2))
		for i = 1, numBlocks do
			T:go("C2", false, 0, false, useBlockType)
			if i < numBlocks then
				T:forward(1)
			end
		end
	end
	
	function lib.turn(outward)
		if outward then
			T:go("R1F1R1")
		else
			T:go("L1F1L1")
		end
		return not outward
	end
	
	function lib.findLegacyStart()
		T:turnRight(1)
		local block = T:getBlockType("down")
		if block:find("polished") ~= nil then
			return ""	-- in correct position, facing centre of front wall
		end
		-- assume on left corner
		T:forward (1)
		local couint = 0
		while (T:getBlockType("down")):find("polished") == nil do
			T:forward(1)
			count = count + 1
			if count > 10 then
				return "Unable to locate polished block"
			end
		end
		return ""
	end
	
	function lib.floodFarm(R)
		local outward = true
		T:sortInventory(false)
		for i = 1, R.width - 2 do
			lib.placeFloor(R.length - 2, R.useBlockType)
			if i < R.width - 2 then
				outward = lib.turn(outward)
			end
		end
		T:go("U1R2") -- over 13 x 13 internal area opposite corner
		-- now add corners
		lib.placeCorners(R.length - 2, 4, R.useBlockType)
		outward = lib.turn(outward)
		lib.placeCorners(R.length - 2, 3, R.useBlockType)
		outward = lib.turn(outward)
		lib.placeCorners(R.length - 2, 2, R.useBlockType)
		outward = lib.turn(outward)
		lib.placeCorners(R.length - 2, 1, R.useBlockType)
		if outward then
			T:go("R1F"..R.width - 9 .."R1")
		else
			T:go("L1F"..R.width - 9 .."L1")
		end
		outward = not outward
		lib.placeCorners(R.length - 2, 1, R.useBlockType)
		outward = lib.turn(outward)
		lib.placeCorners(R.length - 2, 2, R.useBlockType)
		outward = lib.turn(outward)
		lib.placeCorners(R.length - 2, 3, R.useBlockType)
		outward = lib.turn(outward)
		lib.placeCorners(R.length - 2, 4, R.useBlockType) -- should be back in starting corner facing front
		
		T:go("U1R1")
		lib.placeWater(R.length - 3) -- place water down then move forward, turn right
		lib.placeWater(R.width - 3)
		lib.placeWater(R.length - 3) 
		lib.placeWater(R.width - 3)
		T:go("F".. math.floor((R.length - 2) / 2).."R1F".. math.floor((R.width - 2) / 2)) -- should be in centre
		
		--T:go("D6x2 F1x2 F1x2 F1x2 F1x2 F1x2 F1x2 F1x2 F1x2 F1x2 R1F7 R1U1")
		T:go("D6F7 R1F7 R1U1") -- end facing back at left corner, 1 block above floor/1 below ceiling
	end
	
	function lib.clearBasement()
		T:sortInventory(false)
		T:dropItem("seeds", "forward")
		T:dropItem("flint", "forward")
		clearRectangle({width = 15, length = 15, up = true, down = true})
		-- area has been cleared. starts facing back, 1 block above ground, 1 block below ceiling
		T:go("R1U1")
		for i = 1, 14 do	-- place cable into gutter beneath front of farm
			T:place("cable", "up")
			if i < 14 then
				T:forward(1)
			end
		end
		-- ends right side facing right, just below ceiling
	end
	
	local blockType
	local blockModifier
	
	-- R.data = "new", "left", "right" or "back" to extend tree farm
	-- R.up = true if clear area
	-- R.networkFarm to create storage area
	if R.up then
		clearArea(R)
	end
	-- R.data = "new", "left", "right", "back", "convertStorage", "convert"
	if R.data == "new" then -- new treeFarm, Start at current position
		-- build 4 wall sections in 2 passes
		T:down(1)
		lib.buildWallSection("---------------", R.useBlockType)		-- left wall (15 blocks)
		T:go("R1F1")
		for i = 1, 2 do
			lib.buildWallSection("--------------", R.useBlockType)	-- back/ right wall (14 blocks)
			T:go("R1F1")
		end
		lib.buildWallSection("------c------", R.useBlockType)		-- front wall (14 blocks) c = network cable
		T:go("U1F1R1")
		lib.buildWallSection("---------------", R.useBlockType)		-- left wall top (15 blocks)
		T:go("R1F1")
		for i = 1, 2 do
			lib.buildWallSection("--------------", R.useBlockType)	--back/right wall (14 blocks)
			T:go("R1F1")
		end
		--lib.buildWallSection("-----lmb-----", R.useBlockType)	--front wall (14 blocks) log/modem/barrel
		lib.buildWallSection("-----lmb", R.useBlockType)
		utils.goBack(1)
		network.attachModem()
		T:forward(2)
		lib.buildWallSection("-----", R.useBlockType)	
		T:go("R1F1 D2") -- over 13 x 13 internal area
	elseif R.data == "left" or R.data == "right" or R.data == "back" then
		-- build 3 wall sections in 2 passes
		if R.data == "left" then										-- should be on left corner of existing
			T:go("L1F1 D1") 											-- move left 1 blocks, down 1: <-
			lib.buildWallSection("------c-------", R.useBlockType)		-- front wall (14 blocks) c = network cable <-
			T:go("R1F1")
			lib.buildWallSection("--------------", R.useBlockType)		-- left wall (14 blocks) ^
			T:go("R1F1")
			lib.buildWallSection("-------------", R.useBlockType)		-- back wall (13 blocks) ->
			T:go("U1R2")												-- turn round ready to add next layer <-
			lib.buildWallSection("--------------", R.useBlockType)		-- back wall top (14 blocks) <-
			T:go("L1F1")
			lib.buildWallSection("--------------", R.useBlockType)		-- left wall top (14 blocks) v
			T:go("L1F1")
			lib.buildWallSection("-----bm", R.useBlockType)				-- front wall (7 blocks) barrel/modem ->
			network.attachModem()
			T:forward(1)
			lib.buildWallSection("l-----", R.useBlockType)				-- front wall (5 blocks) log ->
			T:go("R2F12 R1F1 D2") 										-- over 13 x 13 internal area lower left side
		elseif R.data == "right" then									-- should be on right corner of existing
			T:go("R1F1 D1") 											-- move right, forward, down 1
			lib.buildWallSection("------c-------", R.useBlockType)		-- front wall (14 blocks) c = network cable
			T:go("L1F1")
			lib.buildWallSection("--------------", R.useBlockType)		-- right wall (14 blocks)
			T:go("L1F1")
			lib.buildWallSection("-------------", R.useBlockType)		-- back wall (13 blocks)
			T:go("U1R2")												-- turn round ready to add next layer
			lib.buildWallSection("--------------", R.useBlockType)		-- back wall top (14 blocks)
			T:go("R1F1")
			lib.buildWallSection("--------------", R.useBlockType)		-- left wall top (14 blocks)
			T:go("R1F1")
			lib.buildWallSection("-----lmb", R.useBlockType)
			utils.goBack(1)
			network.attachModem()
			T:forward(2)
			lib.buildWallSection("-----", R.useBlockType)	
			T:go("R1F1 D2") 											-- over 13 x 13 internal area
		elseif R.data == "back" then									-- should be on left front corner of existing
			T:go("R2F1 D4R2 F1") 										-- move forward 14 blocks, down 1
			for i = 1, 15 do
				T:place("cable", "up")
				T:forward(1)
			end
			T:up(1)
			if T:getBlockType("up") == R.useBlockType then				-- already a farm on left side
				T:go("U2C2 U1C2 F13R1 F1D1", false, 0, false, R.useBlockType)
				lib.buildWallSection("--------------", R.useBlockType)	-- back wall (14 blocks)
				T:go("R1F1")
			else
				T:up(2)
				lib.buildWallSection("--------------", R.useBlockType)	-- left wall (14 blocks)
				T:go("R1F1")
				lib.buildWallSection("--------------", R.useBlockType)	-- back wall (14 blocks)
				T:go("R1F1")
			end

			lib.buildWallSection("-------------", R.useBlockType)		--right wall (13 blocks) no special blocks
			T:go("U1R2")	-- turn round ready to add next layer
			for i = 1, 2 do
				lib.buildWallSection("--------------", R.useBlockType)	--right wall top (14 blocks) no special blocks
				T:go("L1F1")
			end
			lib.buildWallSection("-------------", R.useBlockType)		-- left wall top (13 blocks) no special blocks
			T:go("F1L1 F7x2")
			T:go("D1x2")
			T:place("cable", "down")
			T:up(1)
			T:place("modem", "down")
			T:go("F1R2x2")
			T:place("log", "down")
			T:go("F2x2")
			T:place("barrel", "down")
			utils.goBack(1)
			network.attachModem()
			T:go("F6R1 F1D2")
		end
	else -- convertStorage or convert
		-- legacy farm had polished block on positions 4 / (10) from left corner
		 local message = lib.findLegacyStart()
		 if message ~= "" then
			return {message}
		 end
		 -- now on top of polished block, 4 from left corner, facing Centre
		 T:forward(2)
		 T:place("barrel", "down")
		 T:go("F1D1")
		 T:place("cable", "down")
		 T:up(1)
		 T:place("modem", "down")
		 network.attachModem()
		 T:forward(1)
		 T:place("log", "down")
		 T:go("R1F1 R1F1 D5R1 F1L1 F7R1")-- left corner, facing back ready to clear basement
	end
	if (R.data):find("convert") == nil then
		lib.floodFarm(R)
	end
	lib.clearBasement() -- area has been cleared. ends right side facing right, just below ceiling

	if R.data == "back" then
		T:go("R2F6 R1D1")
	else
		T:go("R2F6 L1F1 U4D5 R2F1") -- make exit for player. end mid floor/ceiling height, facing back, in centre
	end
	if R.data == "new" or R.data == "convertStorage" then	-- put storage in this farm
		for i = 1, 3 do
			T:place("cable", "up")
			T:forward(1)
		end
		T:place("cable", "up")
		--T:down(1)
		utils.createStorage()	-- creates on ground, 1 below current
		T:go("F1R2")
		T:place("cable", "forward")
		T:go("R2")
		for i = 1, 2 do
			T:place("cable", "up")
			T:forward(1)
		end
	else
		for i = 1, 6 do
			T:place("cable", "up")
			T:forward(1)
		end
	end
	T:place("modem", "up")
	T:go("F1R2U2")
	T:place("barrel", "down")
	T:drop("down", "dirt", 64)-- override 'slot' with item string
	T:up(1)
	T:place("hopper", "down")
	T:go("F1D1")
	network.attachModem()
	T:go("U1C2 U2F6 R2")
	--network.attachModem()

	return {"Tree farm ready for planting"}
end

local function createWallOrFence(R)
	local lib = {}
	
	function lib.placeBarrel(R)
		if R.data == "barrel" then
			utils.goBack(1)
			T:go("L1F1")
			T:place("barrel", "down", false)
			utils.goBack(1)
			T:go("R1")
			T:forward(1)
		end
	end
	
	function lib.placeTorch(R)
		T:up(1)
		local up = 1
		local blockType = T:getBlockType("forward")
		while blockType:find(R.useBlockType) ~= nil and blockType ~= "" do -- prevent continuous upward travel
			T:up(1)
			up = up + 1
			blockType = T:getBlockType("forward")
		end
		T:place("torch", "forward", true)
		T:down(up)
	end
	
	function lib.buildWall(R, length)
		-- T:place(blockType, direction, leaveExisting, signText)
		local blockType = ""
		local blocks = 0
		lib.placeBarrel(R)
		while blocks < length do
			if turtle.back() then
				T:place(R.useBlockType, "forward", true)
				if R.torchInterval > 0 then
					if blocks == 0 or blocks % R.torchInterval == 0 then
						lib.placeTorch(R)
					end
				end
				blocks = blocks + 1 -- still facing start position
				while turtle.down() do
					T:place(R.useBlockType, "up", true)
				end
			else -- obstruction
				T:turnRight(2) -- facing away from start
				blockType = T:getBlockType("forward")
				if blockType:find("torch") ~= nil then
					T:go("F1R2")
					T:place(R.useBlockType, "forward")
					blocks = blocks + 1 -- facing start
				elseif blockType:find("log") ~= nil then
					T:harvestTree()
					T:turnRight(2)
					T:place(R.useBlockType, "forward")
					blocks = blocks + 1 -- facing start
				elseif T:isVegetation(blockType) then
					T:go("F1R2")
					T:place(R.useBlockType, "forward")
					blocks = blocks + 1 -- facing start
				else -- cant go forward, go up instead
					while turtle.detect() and blockType:find("torch") == nil and blockType:find("log") == nil and not T:isVegetation(blockType) do -- block ahead, but not torch or tree
						while turtle.detectUp() do -- will only run if block above
							utils.goBack(1)
							blocks = blocks - 1
						end
						turtle.up()
						T:place(R.useBlockType, "down", true)
						blockType = T:getBlockType("forward")
					end
					T:turnRight(2) -- facing start
				end
			end
		end
	end
	
	T:turnRight(2) --facing start position
	if R.width == 0 then -- single fence
		lib.buildWall(R, R.length)
	else	
		lib.buildWall(R, R.length - 1)
		T:go("R1") -- facing start so left turn = turnRight
		lib.buildWall(R, R.width - 1)
		T:go("R1")
		lib.buildWall(R, R.length - 1)
		T:go("R1")
		lib.buildWall(R, R.width - 2)
		T:go("U1")
		T:place(R.useBlockType, "down", true)
	end
	
	return {"Wall or fence completed"}
end

local function createWaterCanal(R) -- 53
	--[[
	designed for 4 turtles, but can be done with 2 as well
	R.data = 1 (2 turtles) or 2 (4 turtles)
	R.height = 0 (in water/ on canal floor) or 1 (at ground level)
	R.side = "R" or "L"
	R.subChoice =
		1 = left side, ground level (on towpath)
		2 = left side above canal water (new canal only)
		3 = right side above canal water (new canal only)
		4 = right side, ground level (on towpath)
		5 = left side in canal water (if present)
		6 = right side in canal water (if present)
	
	if R.height = 0 then already at correct height on canal floor
		check block below, block to left and block above, move forward tunnelling
		if entering water then move up, onto canal wall and continue pathway
		if tunnelling then flood canal
	else R.height = 1 then above water and on path across
		move forward, checking for water below
		if water finishes, move into canal, drop down and continue tunnelling
	]]
	local lib = {}
	
	function lib.newCanalSide(oTurn)
		T:go("C1 U1x1 U1x1 D2"..oTurn.."1", false, 0, false)
	end
	
	function lib.newCanalBase(R)
		local oTurn = "R"								-- assume R.side = "L"
		if R.side == "R" then
			oTurn = "L"
		end
		if not turtle.detectDown() then					-- air / water below: fill floor
			T:go(oTurn.."1D1")							-- *|>| | | to *|V| | | turn towards canal centre, go down ready to repair neighbouring canal base 
			if T:getBlockType("forward"):find("turtle") ~= nil then -- turtle in similar position
				if R.side == "L" then					-- only left side repairs, so wait 1 second
					sleep(1)
					T:go("C1")							-- repair neighbouring canal base
				end
			else
				T:go("C1")								-- repair neighbouring canal base
			end
			T:go(R.side.."1")							-- *|V| | | to *|>| | | turn to face start 
			T:up(1)										-- *|>| | | return to canal floor 
		end
		T:go("C2", false, 0, false)
	end
	
	function lib.newCanal(R)
		--  no source in front as this function called												-- *|<| | |  facing end wall ready for new canal canal base level
		local oTurn = "R"									-- assume R.side = "L"
		if R.side == "R" then
			oTurn = "L"
		end
		lib.newCanalSide(oTurn)								-- *|<| | | wall fixed. to -- *|^| | | 
		lib.newCanalSide(oTurn)								-- *|^| | | wall fixed. to -- *|>| | | 
		lib.newCanalBase(R)									-- *|>| | | base fixed
		T:go("F1"..R.side.."1") 							-- *|>| | | to *| |>| | to *| |^| |
		lib.newCanalSide(oTurn)								-- *| |^| | to *| |>| |
		lib.newCanalBase(R)									-- *| |>| | base fixed
		T:go("F1"..R.side.."1") 							-- *| |>| | to *| | |>| to *| | |^|
		lib.newCanalSide(oTurn)								-- *| | |^| to *| | |>|
		lib.newCanalBase(R)									-- *| | |>| base fixed
		T:go(R.side.."2") 									-- *| | |>| to *| | |<|facing existing / back wall 
		T:forward(1)										-- *| |<| |
		T:placeWater("forward") 							-- *|W|<| | placed against start wall  
		T:go("L2")											-- *|W|>| |
		T:placeWater("forward") 							-- *|W|>|W| placed direction of travel 
		T:go("R2") 											-- *|W|<|W| rotate
		if deletesWater then
			T:up(1)
		else
			sleep(0.2)
		end
		utils.getWater()									-- *|W|<|W| 
		T:go(oTurn.."2F1")									-- *|W|<|W|  to *|W|W|>|  ready to go	
	end
	
	function lib.towpathOnly(R)
		--[[single turtle on towpath only using 4 turtles. Starts at ground level]]
		for i = 1, R.length do
			if turtle.detectDown() then						-- eg dirt, stone
				T:dig("down")								-- remove block below
			end
			local placeOnly = true
			if R.torchInterval > 0 then						-- place torches
				if i == 1 or i % R.torchInterval == 0 then	-- ready to place torch
					T:go("C2U1")							-- place solid block below, up 1
					T:place("torch", "down")				-- place torch, move forward
					T:go("F1D1")							-- move forward, down
					placeOnly = false		
				end
			end
			if placeOnly then
				T:dig("up")									-- clear blocks above
				if not T:place("stone", "down") then		-- place stone below
					break
				end
				if i < R.length then
					T:forward(1)							-- move forward
				end							
			end
		end
	end
	
	function lib.initialiseCanal(R)
		--[[ move turtle to correct position. return moves]]
		local moves = 1
		local oTurn = "R"
		if R.side == "R" then
			oTurn = "L"
		end
		local newCanal, isWater, isSource = false, false, false
		if R.data == 1 then -- use 2 turtles only
			if R.subChoice == 1 or R.subChoice == 4 then 	-- left / right side on towpath- move into canal space
				if deletesWater then
					T:go(oTurn.."1F1")						-- turn to face canal centre, go forward over water
					isWater, isSource = T:isWater("down")
					if isSource then 						-- canal already exists
						T:go(oTurn.."1")					-- stay above water, face existing canal
					else									-- NOT above source
						T:go("D1"..oTurn.."1")				-- go to canal floor, face existing
						newCanal = true						-- flag create 6 water source blocks
					end
				else										-- NOT deletesWater
					T:go(oTurn.."1F1D1"..oTurn.."1") 		-- move into canal, face back along any existing canal
					isWater, isSource = T:isWater("forward")
					if isSource then
						T:go(R.side.."2") 					-- face forward for new canal
					else
						newCanal = true
					end
				end
			elseif R.subChoice == 2 or R.subChoice == 3 then-- left / right side above canal finishing pos if deletesWater
				if deletesWater then
					isWater, isSource = T:isWater("down")
					if isSource then 
						T:go(R.side.."2")					-- face towards existing canal
					else
						T:go("D1"..R.side.."2")				-- go down and face existing canal		 				-- no water ahead
						newCanal = true						-- already in newCanal starting position
					end
				else										-- NOT deletesWater
					T:go("D1"..R.side.."2")					-- facing existing on canal floor
					isWater, isSource = T:isWater("forward")
					if isSource then						-- water ahead
						T:go(R.side.."2")					-- face forward for new canal
					else 									
						newCanal = true
					end
				end
			elseif R.subChoice == 5 or R.subChoice == 6 then -- left / right  side in canal base. Assume NOT deletesWater
				T:go(R.side.."2") 							-- check if water behind	
				isWater, isSource = T:isWater("forward")
				if isSource then
					T:go(oTurn.."2") 	
				else
					newCanal = true
				end
			end
		else	-- use 4 turtles
			if R.subChoice == 1 or R.subChoice == 4 then 	-- left / right side on towpath stays in place for 4 part canal
			
			elseif R.subChoice == 2 or R.subChoice == 3 then-- left / right side above canal finishing pos if deletesWater
			
			elseif R.subChoice == 5 or R.subChoice == 6 then -- left / right  side in canal base. Assume NOT deletesWater
			
			end
		end
		if newCanal then 								-- no water ahead, facing start wall of new canal *|<| | |
			lib.newCanal(R) 							-- start new canal, finish facing new canal 6 block water sources
			moves = 2
		end
		
		return moves 									-- facing forward ready for new canal *|>| | |
	end
	
	function lib.side(R, maxLength)
		-- Already in position facing new canal, 2 water buckets
		local torch = R.length - maxLength					-- start torch count at 1-2 depending on lib.initialise()
		local sourceCount = 0								-- allow for 1 iteration of placing source blocks when changing from solid to water
		local numBlocks = 0									-- distance travelled
		local _, isSource = nil, false						-- initialise variables
		local oTurn = "R"									-- assume R.side == "L" -> oTurn = "R"
		if R.side == "R" then								-- R.side = "R"
			oTurn = "L"										-- oTurn = "L"
		end
		
		while numBlocks < maxLength do						-- loop from here. Facing forwards to extend canal
			torch = torch + 1								-- increase torch spacing interval
			numBlocks = numBlocks + 1						-- inrease block count
			if deletesWater then							-- up to and including mc 1.12.2
				T:forward(1)								-- move forward to extend canal  | |>|
				_, isSource = T:isWater("down")				-- check if source water below
				if isSource then
					sourceCount = sourceCount + 1			-- count source blocks
				else										
					T:down(1)								-- down to canal floor
					sourceCount = 0							-- reset
					T:go("C2", false, 0, false)				-- place block below
					T:up(1)									-- up to water level
				end											-- still facing away from canal
				T:go(R.side.."1F1C2", false, 0, false) 		-- go above towpath, place stone down, facing out
				if turtle.detectUp() then 					-- ? block above
					T:go(R.side.."2U1F1D1"..R.side.."2")	-- rotate to face canal, up 1 forward over canal, back down to water level, face towpath
				else
					utils.goBack(1)							-- face towpath
				end
				-- facing towpath
				if R.torchInterval > 0 then					-- Are torches required?
					if torch == R.torchInterval  or numBlocks == 0 then		-- check if ready to place
						torch = 0							-- reset interval counter
						T:go("U1F1")
						T:place("torch", "down")		-- place torch
						utils.goBack(1)
						T:down(1)
					end
				end											-- facing towpath, above water
				-- facing towpath
				if isSource and scoreCount > 0 then
					T:go(oTurn.."1x0")						-- face new canal direction
				else										-- not source below, or first time found, ensures continous canal
					T:go(R.side.."1x0")						-- face back to existing canal
					T:placeWater("down")					-- place water
					T:forward(1)							-- forward 1
					T:placeWater("down")					-- place water
					utils.getWater() 							-- collects water from below
					utils.goBack(1) 						-- back 1
					T:go(oTurn.."1x0")						-- face new canal
				end
			else
				T:forward(1) 								-- move forward to extend canal
				_, isSource = T:isWater("forward")			-- check if source water ahead
				if isSource then							-- ? source ahead
					sourceCount = sourceCount + 1
				else
					sourceCount = 0
					if not turtle.detectDown() then			-- air / water below, but no source in front, so fill it
						T:go(oTurn.."1D1")					-- ready to repair neighbouring canal base
						if T:getBlockType("forward"):find("turtle") ~= nil then -- turtle in similar position
							if R.side == "L" then			-- only left side repairs, so wait 1 second
								sleep(1)
								T:go("C1")					-- repair neighbouring canal base
							end
							T:go(R.side.."1")				-- face forward
						else
							T:go("C1"..R.side.."1")			-- repair neighbouring canal base if air
						end
						T:up(1)
					end
					T:go("C2", false, 0, false)				-- place block below if not already source
				end
				T:go(R.side.."1C1", false, 0, false) 		-- face canal wall, replace with stone
				
				local placeTorch = false
				if R.torchInterval > 0 then					-- Are torches required?
					if torch == R.torchInterval  or numBlocks == 0 then		-- check if ready to place
						torch = 0							-- reset interval counter
						placeTorch = true
					end
				end
				if (isSource and placeTorch) or not isSource then
					T:go("U1x1 U1x1")						-- up 2 and excavate blocks above tow path
					if placeTorch then						-- torch required
						T:forward(1)						-- move over towpath
						T:place("torch", "down")		-- place torch
						utils.goBack(1)						-- move back
					end
					T:down(2)								-- return to canal base
				end
				if isSource and sourceCount > 1 then 		-- source ahead found at least once
					T:go(oTurn.."1")						-- face newcanal as no water refill required
				else										-- not source in front, or first time found, ensures continous canal
					T:go(oTurn.."1C1") 						-- *| | | |>| face along new canal and block entrance
					utils.goBack(1)							-- *| | |>| | back 1
					T:placeWater("forward")					-- *| | |>|W| place water
					T:go(oTurn.."2") 						-- *| | |<|W| face existing canal 
					_, isSource = T:isWater("forward")		-- *| |?|<|W| check if source water ahead 
					if not isSource then
						if not T:placeWater("forward") then	-- place water again *| |W|<|W|
							while not T:getWater("forward") do -- wait for other turtle
								print("Out of water buckets")
								sleep(1)
							end
							sleep(0.2)
							T:getWater("forward") 
						end
					end
					utils.getWater() 							-- collects water *| |W|<|W|
					T:go(R.side.."2F1") 						-- face along new canal *| |W|>|W| to *| |W|W|>|
				end
			end
		end
	end
		
	function lib.waterOnly(R, maxLength)
		-- Already in position facing new canal, 2 water buckets
		local torch = R.length - maxLength					-- start torch count at 1-2 depending on lib.initialise()
		local sourceCount = 0								-- allow for 1 iteration of placing source blocks when changing from solid to water
		local numBlocks = 0									-- distance travelled
		local _, isSource = nil, false						-- initialise variables
		local oTurn = "R"									-- assume R.side == "L" -> oTurn = "R"
		if R.side == "R" then								-- R.side = "R"
			oTurn = "L"										-- oTurn = "L"
		end
		
		while numBlocks < maxLength do						-- loop from here. Facing forwards to extend canal
			torch = torch + 1								-- increase torch spacing interval
			numBlocks = numBlocks + 1						-- inrease block count
			if deletesWater then							-- up to and including mc 1.12.2
				T:forward(1)								-- move forward to extend canal  | |>|
				_, isSource = T:isWater("down")				-- check if source water below
				if isSource then
					sourceCount = sourceCount + 1			-- count source blocks
				else										
					T:down(1)								-- down to canal floor
					sourceCount = 0							-- reset
					T:go("C2", false, 0, false)				-- place block below
					T:up(1)									-- up to water level
				end											-- still facing away from canal
				if turtle.detectUp() then 					-- ? block above
					T:go("U1x0")							-- break block above
				end
				if not isSource or scoreCount == 0 then		-- not source below, or first time found, ensures continous canal
					T:go(R.side.."2x0")						-- face back to existing canal
					T:placeWater("down")					-- place water
					T:forward(1)							-- forward 1
					T:placeWater("down")					-- place water
					utils.getWater() 						-- collects water from below
					utils.goBack(1) 						-- back 1
					T:go(R.side.."2")						-- face new canal
				end
			else
				T:forward(1) 								-- move forward to extend canal
				_, isSource = T:isWater("forward")			-- check if source water ahead
				if isSource then							-- ? source ahead
					sourceCount = sourceCount + 1
				else
					sourceCount = 0
					if not turtle.detectDown() then			-- air / water below, but no source in front, so fill it
						T:go(oTurn.."1D1")					-- ready to repair neighbouring canal base
						if T:getBlockType("forward"):find("turtle") ~= nil then -- turtle in similar position
							if R.side == "L" then			-- only left side repairs, so wait 1 second
								sleep(1)
								T:go("C1", false, 0, true)	-- repair neighbouring canal base
							end
							T:go(R.side.."1")				-- face forward
						else
							T:go("C1"..R.side.."1",false, 0, true)	-- repair neighbouring canal base if air
						end
						T:up(1)
					end
					T:go("C2", false, 0, false)				-- place block below if not already source
				end
				if not isSource then
					T:go("U1x0D1")							-- up 1 and excavate blocks above canal. return to canal base
				end
				T:go(R.side.."1C1"..oTurn.."1", false, 0, true) -- face canal wall, replace with stone if empty, face forward										
				if not isSource	and sourceCount == 0 then	-- not source in front, or first time found, ensures continous canal					
					T:go("C1", false, 0, true) 				-- *| | | |>| face along new canal and block entrance
					utils.goBack(1)							-- *| | |>| | back 1
					T:placeWater("forward")					-- *| | |>|W| place water
					T:go(oTurn.."2") 						-- *| | |<|W| face existing canal 
					_, isSource = T:isWater("forward")		-- *| |?|<|W| check if source water ahead 
					if not isSource then
						if not T:placeWater("forward") then	-- place water again *| |W|<|W|
							while not T:getWater("forward") do -- wait for other turtle
								print("Out of water buckets")
								sleep(1)
							end
							sleep(0.2)
							T:placeWater("forward") 
						end
					end
					utils.getWater() 							-- collects 2 water *| |W|<|W|
					T:go(R.side.."2F1") 						-- face along new canal *| |W|>|W| to *| |W|W|>|
				end
			end
		end
	end
		
	local maxLength = 512
	if R.length ~= 0 then
		maxLength = R.length
	end
	menu.clear()
	menu.colourWrite("Building canal "..R.side.." side", colors.yellow, nil, nil, false, true)
	local moves = lib.initialiseCanal(R) -- move to correct position and/or start new canal
	if R.data == 1 then -- 2 turtles
		lib.side(R, maxLength - moves)	
	else -- 4 turtles 
		if R.subChoice == 1 or R.subChoice == 4 then -- towpath
			lib.towpathOnly(R)
			--lib.waterCanalTowpath(R, maxLength - moves)
		else -- main canal only
			lib.waterOnly(R, maxLength - moves)
		end
	end
	
	return {}
end

local function createMobGrinder(R)
	-- go down 5 and create a cavity 9 wide, 5 long, 8 high
	-- assume facing out from spawner cube at base of exit (6 blocks above ground
	-- R.subChoice = 1 or 2 (sticky or normal pistons)
	
	local lib = {}
	
	function lib.getInventory(R)
		T:clear()
		menu.colourPrint("All blocks to be ejected. Ready? Enter", colors.red)
		read()
		T:emptyInventory("up")
		T:checkInventoryForItem({"stone"}, {20}, true, "Match existing walls?")
		if R.subChoice == 1 then -- sticky pistons
			T:checkInventoryForItem({"computercraft:computer_normal"}, {1})
			T:checkInventoryForItem({"minecraft:sticky_piston"}, {2})
		else
			T:checkInventoryForItem({"computercraft:computer_normal"}, {2})
			T:checkInventoryForItem({"minecraft:piston"}, {4})
			T:checkInventoryForItem({"computercraft:cable"}, {6})
			T:checkInventoryForItem({"computercraft:wired_modem"}, {2})
		end
		T:checkInventoryForItem({"polished"}, {23}, true, "Any polished block")
		T:checkInventoryForItem({"wall"}, {2}, true, "Any wall block ? match")
		T:checkInventoryForItem({"slab"}, {7}, true, "Any stone slab. ? polished / match")
		T:checkInventoryForItem({"minecraft:glass"}, {2})
		T:checkInventoryForItem({"minecraft:stone_pressure_plate"}, {1})
		T:checkInventoryForItem({"minecraft:dispenser"}, {1})
		T:checkInventoryForItem({"hopper"}, {1})
		T:checkInventoryForItem({"chest"}, {2})
		T:checkInventoryForItem({"minecraft:redstone"}, {9})
		T:checkInventoryForItem({"lava"}, {1})
		R.useBlockType = T:getPolishedItem("")
		if R.useBlockType == "" then
			R.useBlockType = T:getMostItem("", true)
		end
	end
	
	function lib.placeRedstone()
		T:go("D2U2")								-- in left corner facing right 
		T:place("slab", "down")					-- place slab layer 1
		T:up(2)
		T:place("slab", "down")					-- place slab layer 2
		T:up(1)
		T:place("redstone", "down")
		T:go("F1D4 C2L1C1 L1U1", false, 0, false)	-- facing ground level slab
		T:place("redstone", "forward")			-- redstone on ground level slab
		T:up(1)
		T:place("slab", "down")					-- slab on layer 1
		T:up(2)
		T:place("slab", "down")					-- slab on layer 3
		T:up(1)
		T:place("redstone", "down")				-- redstone on layer 3 slab
		utils.goBack(1)
		T:down(3)									-- facing layer 1 slab
		T:place("redstone", "forward")			-- redstone on layer 1 slab
		T:go("D2C2", false, 0, false)				-- under end of chest position
		T:place("redstone", "forward")			-- redstone on level 0 floor
		T:go("R1C1R1", false, 0, false)				-- face right, repair back wall
		T:go("F1C2 L1C1 R1", false, 0, false)		-- under chest start
		T:go("F1C2 L1C1 R1", false, 0, false)		-- under hopper
		T:go("F1C2 L1C1 R1", false, 0, false)		-- under right side wall block
		T:go("U1L2")								-- ready for redstone
		for i = 1, 4 do
			T:place("redstone", "down")			-- redstone under chest etc
			if i < 4 then
				T:forward(1)
			end
		end
		-- finishes facing slab at ground level, redstone below
	end
	
	function lib.placeStorage()
		-- starts facing slab at ground level, redstone below
		T:go("L1F1L2")								-- up and out ready for chest placement
		T:place("chest", "forward")				-- end chest
		T:go("R1F1 L1F1 R1U2")						-- at above start chest position facing right
		T:place("slab", "down")					-- slab above chest
		T:turnLeft(1)
		utils.goBack(1)								
		T:down(2)									-- in front of start chest position
		T:place("chest", "forward")				-- start chest
		T:go("R1F2L2")								-- at pressure plate position facing left
		T:place("wall", "forward")				-- place wall
		T:up(1)
		T:place("pressure", "down")				-- place pressure plate
		T:go("R1F1 L1D1")							-- at second wall position
		T:place("hopper", "forward")				-- place hopper into chest
		utils.goBack(1)
		T:place("wall", "forward")				-- place second wall
		-- finishes on level 1 (ground) facing right side wall block
	end
	
	function lib.placePistons(R)
		-- starts on level 1 (ground) facing right side wall block
		T:go("U1F2 R1")									-- go over wall block, facing back wall layer 2
		T:place(R.useBlockType, "forward", false)	-- replace back wall with polished block layer 2
		T:up(1)											-- layer 3
		T:place(R.useBlockType, "forward", false)	-- replace back wall with polished block layer 3
		T:turnRight(1)									-- face right side
		if R.subChoice == 1 then						-- use sticky pistons x 2
			T:place(R.useBlockType, "forward", false)-- polished block above second wall layer 3
			T:go("R2F1")								-- ready to place lower piston (works ok as slab already in place behind it)
		else
			T:go("F2R2")								-- move forward 2 and face left
			T:place("piston", "forward")				-- lower replacer piston placed
			T:go("U1F2D1F1")							-- go up and over piston forward 1 ready for other piston
		end
		T:place("piston", "forward")					-- lower piston placed
		utils.goBack(1)
		T:go("U1R1")									-- layer 4
		T:place(R.useBlockType, "forward", false)	-- polished block back wall layer 4
		T:go("L1F2R2")									-- head left ready for dispenser
		T:place("dispenser", "forward")				-- dispenser placed
		T:dropItem("lava", "forward")					-- drop lava bucket into dispenser
		T:go("U1F2 D1")									-- up and over dispenser, facing right side
		T:place("slab", "down")						-- lower piston slab placed
		if R.subChoice == 1 then
			T:place(R.useBlockType, "forward", false)-- polished block above second wall layer 4
			T:turnLeft(1)								-- facing back wall
		else
			T:go("F1L1")								-- at second computer position, facing back wall
			utils.goBack(1)								-- ready to place computer
			T:place("computercraft:computer_normal", "forward", false)	-- place computer
			T:go("L1F1R1F1")							-- facing back wall in mob drop, level 4
		end
		T:place(R.useBlockType, "forward", false)	-- polished block back wall layer 4
		T:turnLeft(1)
		T:go("U1F3R2")									-- level 5 ready for upper piston
		T:place("piston", "forward")					-- upper piston placed
		T:go("U1F3D1R2")								-- up and over piston, facing left, level 5
		T:turnRight(1)									-- at mob drop, facing wall, level 5
		T:place(R.useBlockType, "forward", false)	-- polished block back wall layer 5
		T:turnRight(1)									-- facing right side
		if R.subChoice == 1 then
			T:place(R.useBlockType, "forward", false)-- right side polished block layer 5, facing right side, in mob drop 							-- layer 5 facing left side, in mob drop		
		else
			T:go("F1C1")								-- move forward, place temporary block
			utils.goBack(1)
			T:place("piston", "forward")				-- upper replacer piston placed				
		end
		T:turnRight(2)	
		T:place("slab", "forward")					-- upper piston slab placed
		T:turnLeft(1)									-- facing away from back wall
	end
	
	function lib.placeComputer(R)
		-- starts facing away from back wall, layer 5, in mob drop 			
		T:go("F1R1 F2R1 D1")							-- move to left computerposition, facing back wall, layer 4
		T:place("computercraft:computer_normal", "forward", false)		-- place computer in gap, layer 4
	end
	
	function lib.placeColumnSection(direction)
		T:place(R.useBlockType, "forward", false)
		T:go(direction.."1")
		T:place(R.useBlockType, "forward", false)
		T:go(direction.."1")
		T:place(R.useBlockType, "forward", false)	-- facing right
	end
	
	function lib.placeColumns(R)
		-- starts facing left computer, layer 4
		T:go("R1F2 L1")									-- facing mob drop level 4
		T:place("glass", "down", false)
		T:up(1)											-- facing mob drop level 5
		T:place("glass", "down", false)				-- on top of glass facing back wall at dungeon base level 5
		T:up(1)	
		T:place(R.useBlockType, "down", false)		-- level 6 dungeon exit
		T:go("F1L1")
		lib.placeColumnSection("L")						-- facing right
		T:up(1)
		lib.placeColumnSection("R")						-- facing left
		T:up(1)
		lib.placeColumnSection("L")						-- facing right
		T:up(1)
		lib.placeColumnSection("R")						-- facing left
		T:up(1)
		T:place(R.useBlockType, "forward", false)
		T:turnLeft(2)
		T:place(R.useBlockType, "forward", false)	-- facing right
		T:turnLeft(1)									-- at top of column
		T:go("x1D1 x1D1 x1U2")							-- open exit for mobs
		utils.goBack(2)
		T:place(R.useBlockType, "forward", false)
		T:down(9)
	end
	
	function lib.placeNetwork()
		T:go("R1F2L1 F3U3 F1L1F1 L1x1")								-- go behind second computer and remove block
		T:place("computercraft:wired_modem", "forward", false)	-- place modem
		utils.goBack(1)
		T:place("computercraft:cable", "forward", false)			-- place network cable
		T:place("computercraft:cable", "forward", false)			-- place network cable (no need to move)
		T:go("R1F1 x2L1")											-- move forward, face back wall
		T:place("computercraft:cable", "forward", false)
		T:go("R1F1 x2L1")
		T:place("computercraft:cable", "forward", false)
		T:go("R1F1 x2L1F1 x1x2")									-- come behind left computer and expose back
		T:place("computercraft:wired_modem", "forward", false)	-- place modem
		utils.goBack(1)
		T:place("computercraft:cable", "forward", false)
		T:place("computercraft:cable", "forward", false)
		T:go("L1D3 F4R1 F3U4 D4")									-- removes temporary block
	end
	
	local tempSubChoice = R.subChoice	-- store for later use
	R.width = 4							-- settings for createFloorCeiling()
	R.length = 9
	R.height = 0
	R.up = true
	T:turnRight(2)
	local isWater, isSource, isIce, level, isAir = T:isWater("forward")
	if not isWater then
		T:turnRight(2)
		return{"Not in correct position. Must be water behind"}
	end
	--T:go("U1x1 U1L1 F4R2")					-- go up to starting point
	T:go("U2L1 F4R2")					-- go up to starting point
	local data = createFloorCeiling(R)[1] 	-- place ceiling, returns to starting position. if water or lava present is returned as "water or lava found"
	if data == "water or lava found" then
		R.height = 10
		R.silent = true
		T:up(1)
		createSinkingPlatform(R)
		T:go("F4L1 U5x1 U1x1 U3R1 F4C0 R1F3C0 R1F8C0 R1F3C0 R1D9") 			-- re-open exit hole, return to floor level
	else -- no water or lava found so empty out area
		R.height = 10
		R.subChoice = 2
		clearSolid(R) -- 76
		T:down(R.height - 1)
		R.width = 4							-- settings for createFloorCeiling()
		R.length = 9
		R.height = 0
		R.down = true
		R.up = false
		R.subChoice = 1						-- replace existing floor
		createFloorCeiling(R)
	end
	
	R.subChoice = tempSubChoice
	lib.getInventory(R)
	lib.placeRedstone()
	lib.placeStorage()
	lib.placePistons(R)
	lib.placeComputer(R)		-- ends facing computer
	lib.placeColumns(R)
	if R.subChoice == 2 then
		lib.placeNetwork()
	end
	
	return {}
end

local function createTrialCover(R)
	local lib = {}
	
	function lib.isSpawner()
		local blockType = T:getBlockType("down")
		if blockType:find("spawner") ~= nil then
			return true, "top"
		end
		blockType = T:getBlockType("up")
		if blockType:find("spawner") ~= nil then
			return true, "bottom"
		end
		blockType = T:getBlockType("forward")
		if blockType:find("spawner") ~= nil then
			return true, "forward"
		end
		return false, ""
	end
	
	function lib.findSpawner()
		local moves  = 0
		local quit = false
		-- assume turtle placed facing trial spawner
		print("Checking if next to spawner")
		local found, position = lib.isSpawner() -- true/false, top/bottom/nil
		if not found then -- move forward towards spawner
			print("Not close to spawner")
			while turtle.forward() and not quit do
				moves = moves + 1
				if moves > 32 then
					quit = true
				end
			end
			found, position = lib.isSpawner() -- true/false, top/bottom/nil
			if not found then	-- could be behind a wall
				print("Assuming spawner behind a wall")
				T:forward(1)
				moves = moves + 1
				while turtle.forward() and not quit do 
					moves = moves + 1
					if moves > 32 then
						quit = true
					end
				end
				found, position = lib.isSpawner() -- true/false, top/bottom/nil
				if not found then
					T:go("R2F"..moves + 2 .."R2")
				end
			end
		end
		
		return found, position
	end
	
	function lib.attack()
		local totalHitsF = 0
		local totalHitsU = 0
		local totalHitsD = 0
		while true do
			local hitF = false
			local hitU = false
			local hitD = false
			if turtle.attackUp() then
				hitU = true
				totalHitsU = totalHitsU + 1
			end
			if turtle.attackDown() then
				hitD = true
				totalHitsD = totalHitsD + 1
			end
			if turtle.attack() then
				hitF = true
				totalHitsF = totalHitsF + 1
			end
			if hitF or hitU or hitD then
				print("hits forward: "..totalHitsF..", up: "..totalHitsU..", down: "..totalHitsD)
			end
		end
	end
	
	local found, position = lib.findSpawner() -- move forwards until meet Spawner, go through wall if present
	if not found then --outside dungeon
		return {"Trial spawner not found"}
	end 
	if position == "top" then
		T:go("B2D1")
	elseif position == "forward" then
		T:go("B1")
	else
		T:go("B2U1")
	end
	T:go("R1F2R2")	--on lower right corner
	-- starts with wall across spawner
	buildStructure(R)
	T:go("U3F1 R1F1 L1U1 F1")
	R.height = 0
	R.width = 3
	R.length = 3
	R.down = true
	createFloorCeiling(R)
	T:go("F1R1 B1D1 B1D2 F1")
	lib.attack()
	return {}
end

local function sandFillArea(R) -- 81
	--clearRectangle with sand drop
	-- could be 1 wide x xx length (trench) up and return
	-- could be 2+ x 2+
	-- even no of runs return after last run
	-- odd no of runs forward, back, forward, reverse and return
	local success
	local directReturn = true
	if R.width % 2 == 1 then
		directReturn = false
	end
	if R.width == 1 then -- trench ahead, so fill then return
		for i = 1, R.length - 1 do
			success = utils.dropSand()
			T:forward(1, false)
		end
		success = utils.dropSand()
		T:go("R2F"..(R.length - 1).."R2", false, 0, false)
	else --2 or more columns
		if directReturn then -- R.width = 2,4,6,8 etc
			for i = 1, R.width, 2 do -- i = 1,3,5,7 etc
				-- move along R.length, dropping sand
				for j = 1, R.length - 1 do
					success = utils.dropSand()
					T:forward(1, false)
				end
				success = utils.dropSand()
				T:go("R1F1R1") --turn right and return on next column
				for j = 1, R.length - 1 do
					success = utils.dropSand()
					T:forward(1, false)
				end
				success = utils.dropSand()
				if i < R.width - 2 then -- eg R.width = 8, i compares with 6: 1, 3, 5, 7
					T:go("L1F1L1")
				end
			end
			T:go("R1F"..R.width - 1 .."R1") --return home
		else
			for i = 1, R.width, 2 do -- i = 1,3,5,7 etc
				-- move along R.length, dropping sand
				for j = 1, R.length - 1 do
					success = utils.dropSand()
					T:forward(1, false)
				end
				success = utils.dropSand()
				T:go("R1F1R1") --turn right and return on next column
				for j = 1, R.length - 1 do
					success = utils.dropSand()
					T:forward(1, false)
				end
				success = utils.dropSand()
				T:go("L1F1L1")
			end
			-- one more run then return
			for j = 1, R.length - 1 do
				success = utils.dropSand()
				T:forward(1, false)
			end
			success = utils.dropSand()
			T:go("R2F"..R.length.."R1F"..R.width - 1 .."R1")
		end
	end
	return {}
end

local function deactivateDragonTower() -- 45
	-- go up centre of tower to bedrock
	local height = 0
	--numBlocksMoved, errorMsg = clsTurtle.doMoves(self, numBlocksRequested, direction)
	local numBlocks, message = T:doMoves(1, "up")
	while message == nil do
		numBlocks, message = T:doMoves(1, "up")
		height = height + 1
	end
	-- go round bedrock and destroy crystal
	T:go("F1R2U2x1U1x1")
	-- return to start
	T:down(height + 5)
	return {}
end

local function undermineDragonTowers() -- 44
	--[[
	        -13, -40....12, -40						NNW (4)   	NNE (5)
			
	    -34, -25............33, -25				NWW	(2)				NEE (9)
		
	-42, -1....................42, 0		W (1)						E (8)
	
	     -34, 24............33,24				SWW	(3)				SEE (10)
		 
		      -13,39....12, 39						SSW	(7)		SSE (6)
	
	North towers centres 25 blocks apart, 40 blocks north of axis
	Mid-North towers 67 blocks apart, 25 blocks north of axis
	W-E centres 84 blocks apart, on 0 axis
	Mid-south towers 67 blocks apart, 24 blocks south of axis
	South towers centres 25 blocks apart, 39 blocks south of axis
	]]
	
	local lib = {}
	function lib.findNextTower(maxDistance, withMarker)
		local distance = 0
		local blockTypeF = T:getBlockType("forward")
		local blockTypeD = T:getBlockType("down")
		for i = 1, maxDistance do
			if blockTypeF ~= "minecraft:obsidian" and blockTypeD ~= "minecraft:obsidian" then -- not in a tower
				if withMarker and blockTypeD ~= "minecraft:obsidian" then -- used to mark 0 coordinate
					T:place("cobble", "down", false) -- place cobblestone or cobbled deepslate to mark zero coordinate
				end
			else	-- obsidian found, could still be in an earlier tower
				if i > 10 then
					break
				end
			end
			T:go("F1x0")
			distance = distance + 1
			blockTypeF = T:getBlockType("forward")
			blockTypeD = T:getBlockType("down")
		end
		if distance == maxDistance then -- obsidian not found ? wrong place/ direction
			print("Obsidian not found")
			error()
		end
		-- will now be at side of a tower
		lib.findCentre() -- move into tower to find the other side
		return distance
	end
	
	function lib.findCentre()
		local width = 0
		-- while obsidian in front or below (previously entered tower) measure width and return to centre
		local blockTypeF = T:getBlockType("forward")
		local blockTypeD = T:getBlockType("down")
		while blockTypeF == "minecraft:obsidian" or blockTypeD == "minecraft:obsidian" do
			T:go("F1x0")
			width = width + 1
			blockTypeF = T:getBlockType("forward")
			blockTypeD = T:getBlockType("down")
		end
		-- will always go outside the tower 1 block. width of 5 block tower = 6
		T:go("R2F"..math.ceil(width / 2)) --return to centre of tower
		T:turnLeft(1) -- now find another edge of the tower, dig forward until out of obsidian
		for i = 1, math.ceil(width) do  -- give additional loops if missed centre
			blockTypeF = T:getBlockType("forward")
			blockTypeD = T:getBlockType("down")
			if blockTypeF == "minecraft:obsidian" or blockTypeD == "minecraft:obsidian" then
				T:go("F1x0")
			else
				break
			end
		end
		-- now outside different edge of the tower
		-- reverse and move width/2, dig up + 1 to mark centre, face original direction
		T:go("L2F"..math.ceil(width / 2).."R1U2x1")
		T:place("minecraft:end_stone", "forward", false) -- place endstone to mark facing direction
		T:down(2)
	end
	
	function lib.findPath(maxLength)
		local blockTypeD = T:getBlockType("down")
		local distance = 0
		while blockTypeD:find("cobble") == nil and distance < maxLength do
			T:go("F1x0")							-- return to 0 axis, 
			distance = distance + 1
			blockTypeD = T:getBlockType("down")
		end
		return distance
	end
	
	-- start at 0,y,0, facing West
	T:dig("up")									-- in case not already done
	local maxLength = 0
	local blockTypeD
	local distance = lib.findNextTower(45, true)-- find W tower (1) and mark trail with cobble
	T:turnRight(2)						
	for i = 1, 8 do								-- head back East 8 blocks, turn left (facing north)
		T:go("F1x0")							-- this path may be off-axis, so dig double height
	end
	T:turnLeft(1)
	lib.findNextTower(30)						-- find NWW tower (2)
	T:turnRight(2)
	distance = lib.findPath(30)
	distance = distance + lib.findNextTower(30)	-- find SWW tower (3)
	T:turnRight(2)
	distance = lib.findPath(30)
	T:turnRight(1) 								-- should be on cobble path
	for i = 1, 21 do							-- move East 21 blocks, turn left facing North
		T:go("F1x0")
	end
	T:turnLeft(1)
	
	distance = lib.findNextTower(45)		-- find NNW tower (4)
	T:turnRight(1)							
	distance = lib.findNextTower(30)		-- find NNE tower (5)
	T:turnRight(1)
	distance = lib.findNextTower(85)		-- find SSE tower (6)
	T:turnRight(1)

	distance = lib.findNextTower(30)		-- find SSW tower (7)
	T:turnRight(1)
	distance = lib.findPath(40)				-- head North to 0 axis
	T:go("R1F13") 							-- return to 0,0 facing East
	distance = lib.findNextTower(45, true)	-- find E tower (8)
	
	T:turnRight(2)						
	for i = 1, 9 do
		T:go("F1x0")						-- this path may be off-axis, so dig double height
	end
	T:turnRight(1)
	
	distance = lib.findNextTower(30)		-- find NEE tower (9)
	T:turnRight(2)
	distance = lib.findPath(30) -- return to 0 axis
	distance = lib.findNextTower(30)		-- find SEE tower (10)
	T:turnRight(2)
	distance = lib.findPath(30) 			-- return to 0 axis
	T:go("L1F33")							-- return to 0, 0
	
	return {}
end

local function demolishPortal(R) -- 43
	--[[
	R.length = length of portal NOT width default 4
	R.height = height of portal default 5
	R.width = thickness of portal default 1
	R.data = "bury" to embed bottom into ground
	R.subChoice 1 = facing portal, 2 = aligned
	]]
	local data = R.data
	if R.subChoice == 1 then -- facing portal
		T:go("F"..R.width.."R1")
	else
		T:forward(1)
	end
	if R.data == "bury" then
		T:down(1)
	end

	R.data = "up"
	R.silent = true
	if R.width == 1 then
		clearWall(R)
	else
		clearBuilding(R, true, true)
	end
	if data == "bury" then
		T:up(1)
	end
	if R.subChoice == 1 then -- facing portal
		T:go("R1F1L1F1L1")
	end
	
	return {}
end

local function digTrench(R) -- 77
	local blockType
	-- go down R.height, move forward
	if R.length == 0 then
		R.length = 4096 -- will go out of loaded chunks and stop or max 4096 on a server
	end
	for i = 1, R.length do
		local count = 0
		for down = 1, R.height do
			blockType = T:isWaterOrLava("down") 
			-- go down only if no water or lava below
			if blockType:find("water") == nil and blockType:find("lava") == nil then
				T:down(1)
				count = count + 1
			end 
		end
		T:go("C2", false, 0, true)				-- if empty below fill void
		T:go("U"..count)						-- return to surface, continue if block above
		while turtle.detect() do				-- go up while block in front
			blockType = T:getBlockType("forward")
			if T:isVegetation(blockType) then
				T:dig("forward")
				break
			elseif blockType:find("log") ~= nil then
				T:harvestTree("forward", false)
			else
				T:up(1)
			end
		end
		T:forward(1)							-- move forward
		while not turtle.detectDown() do		-- go down until block detected
			blockType = T:isWaterOrLava("down") 
			if blockType:find("water") == nil and blockType:find("lava") == nil then
				T:down(1)
			else
				break
			end
		end
	end
	
	return {}
end

local function harvestTreeFarm(R) -- 24
	local lib = {}
	
	function lib.getLogCount()
		local count = 0
		for i = 1,16 do
			local item, itemCount = T:getSlotContains(i)
			if item:find("log") ~= nil then
				count = count + itemCount
			end
		end
		
		return count
	end
	
	function lib.initialise(R)
		-- assumes legacy tree farm with turtle on polished block 4 blocks from corner
		local message  = ""
		R.treeSize = "single"
		local blockType = T:getBlockType("forward")
		--local logType = ""
		--local startHeight = 0
		local range = 0
		if blockType == "" then
			while turtle.forward() do
				range = range + 1
				if range == 3 then
					break
				end
			end
		end
		blockType = T:getBlockType("forward")
		if blockType:find("dirt") ~= nil then	-- dirt found
			T:go("R1F1L1")
			blockType = T:getBlockType("forward")
			if blockType:find("dirt") ~= nil then
				R.treeSize = "double"
			end
			T:go("L1F1 R1")
		else	-- dirt NOT found where expected
			message = "Unable to determine position"
		end
		T:up(1)
		blockType = T:getBlockType("forward")	-- 1 block above dirt
		if blockType:find("log") ~= nil or blockType:find("sapling") ~= nil or blockType:find("propagule") ~= nil then
			local parts = T:getNames(blockType)
			if parts[2] == "dark" then
				R.logType = "dark_oak"
			else
				R.logType = parts[2]				-- eg "oak"
			end
			if R.logType == "mangrove" then
				R.useBlockType = "mangrove_propagule"
			else
				R.useBlockType = parts[2].."_sapling"	-- eg "oak_sapling"
			end
		end
		T:down(1)	-- facing dirt
		
		return R, message
	end
	
	function lib.waitForGrowth(R)
		local pattern = R.treeSize	--"single","double"
		local elapsed = 0
		local facing = "left"
		local ready = {}
		ready.left = false
		ready.top = false
		ready.right = false
		ready.bottom = false
		if R.logType == "mangrove" then
			pattern = "mangrove"
			local facings = {"left", "top", "right", "bottom"}
			T:up(1)	-- go up from dirt to sapling level
			while not ready.left or not ready.right or not ready.top or not ready.bottom do
				for i = 1, 4 do
					local blockType = T:getBlockType("forward")
					if blockType:find("propagule") ==  nil then	-- either grown or deleted by roots
						ready[facings[i]] = true
					end
					T:turnRight(1)
				end
				if ready.left and ready.right and ready.top and ready.bottom then
					break
				else
					sleep(15)
					elapsed = elapsed + 15
					if  elapsed / 60 > 15 then	-- max 15 mins real time before farm is harvested
						break
					end
				end
				print("Waiting for mangrove growth "..elapsed / 60 .." minutes")
				print("Left = "..tostring(ready.left)..
					  ", top = "..tostring(ready.top)..
					  ", right = "..tostring(ready.right)..
					  ", bottom = "..tostring(ready.bottom))
				
			end
			--T:go("L1D1")
			T:turnLeft(1)	-- face front
		else
			while not ready.left or not ready.right do
				T:up(1)	-- go up from dirt to sapling level
				local blockType = T:getBlockType("forward")
				if blockType:find("log") ~=  nil then
					ready[facing] = true
				end
				if pattern == "single" then
					--alternate between 2 trees, starts facing left
					T:turnRight(2)
					if facing == "left" then
						facing = "right"
					elseif facing == "right" then
						facing = "left"
					end
					blockType = T:getBlockType("forward")
					if blockType:find("log") ~=  nil then
						ready[facing] = true
					end
					T:down(1)	-- drop below sapling to dirt level
				elseif pattern == "double" then
					if ready.left and facing == "left" then-- tree on left now grown. check right
						T:go("R2F2")
						facing = "right"
					end
					blockType = T:getBlockType("forward")
					if blockType:find("log") ~=  nil then
						ready[facing] = true
					end
					T:down(1)	-- drop below sapling to dirt level
				end
				T:clear()
				print("Farm type: "..pattern)
				print("Waiting for tree growth "..elapsed / 60 .." minutes")
				print("Left grown = "..tostring(ready.left)..", right grown = "..tostring(ready.right))
				if not ready.left or not ready.right then
					sleep(15)
					elapsed = elapsed + 15
					if pattern == "single" and elapsed / 60 > 10 then	-- max 10 mins real time before farm is harvested
						break
					elseif pattern == "double" and elapsed / 60 > 15 then	-- max 15 mins real time before farm is harvested
						break
					end
				end
			end
		end
		-- growth complete
		if pattern == "single" then
			if facing == "right" then
				T:turnRight(1)
			else
				T:turnLeft(1)
			end
			--T:go("F1R1 F3R1")			-- facing first dirt
			T:go("F1R1 F1R1")			-- facing first dirt
		elseif pattern == "double" then -- assume on right side
			if facing == "right" then
				T:go("R1F1 R1F4 R1")
			else
				T:go("L1F1 R1F2 R1")
			end
		elseif pattern == "mangrove" then 
			T:go("D2F6 U1F1 R1F6 R1F1 U1")
		end
		-- ends facing dirt at base of first tree
		-- no return needed, function exit so trees are grown
	end
	
	function lib.watchFarm(R)
		-- rotate to check if dirt on both sides
		-- R.subChoice == 1: 16 single trees, 2 = 4 doubles
		if R.logType ~= "mangrove" then
			R.treeSize = "single"
			T:turnRight(2)	-- if no dirt then on 4 x doubles
			if T:getBlockType("forward") == "" then
				R.treeSize = "double"
			end
			T:saveToLog("lib.watchFarm: R.treeSize set to '"..R.treeSize.."'")
			T:turnLeft(2)	-- face lower left double dirt 
		end
		lib.waitForGrowth(R)
		
		return R
	end
	
	function lib.harvestSingle(direction, moves)
		-- if direction == "up": starting inside tree on dirt at dirt level
		T:saveToLog("lib.harvestSingle('"..direction.."', moves = "..moves)
		if direction == "up" then
			while turtle.detectUp() do
				T:up(1)
				moves = moves + 1
			end
		else	-- direction = "down", but could be mid-tree
			local movesUp = 0
			while turtle.detectUp() do
				T:up(1)
				movesUp = movesUp + 1
			end
			T:down(movesUp)
			T:down(moves)
		end
		return moves
	end
	
	function lib.harvestSingleRow()
		-- start next to tree/dirt
		T:go("F1")
		local moves = lib.harvestSingle("up", 0)
		T:go("F2")
		lib.harvestSingle("down", moves)
		T:go("F2")
		moves = lib.harvestSingle("up", 0)
		T:go("F2")
		lib.harvestSingle("down", moves)
	end
	
	function lib.harvestDouble()
		T:forward(1)	-- dig dirt, move into left (S) corner
		local moves = 0
		while turtle.detectUp() do
			turtle.dig()
			turtle.digUp()
			turtle.up()
			moves = moves + 1
		end
		turtle.dig()
		T:go("R1F1L1")	-- move to right corner
		for i = 1, moves do
			turtle.dig()
			turtle.digDown()
			turtle.down()
		end
		turtle.dig()
		T:go("F1L1F1R1") -- move to left corner (N)
	end
		
	--T:setUseLog(true, "treeFarmLog.txt", true)	-- T:setUseLog(use, filename, delete)
	--dbug = true								-- set dbug flag
	
	R.silent = true
	-- if on modem, R.networkFarm has already been set
	T:saveToLog("harvestTreeFarm(R) R.networkFarm = "..tostring(R.networkFarm))

	if R.networkFarm then
		local message = network.loadStorageLists()	-- initialises or creates lists of where an item can be found: GLOBAL LISTS!
		if message ~= nil then return {message} end
		network.emptyInventory(R, {"sapling", "propagule", "dirt"}, {"all"}, true)
	end
	
	if turtle.getFuelLevel() < turtle.getFuelLimit() / 2 then
		local turtleSlot, turtleCount = network.getItemFromNetwork("chest", "log", 16)
		if turtleSlot > 0 then
			if turtle.craft() then
				turtle.refuel()
				T:saveToLog("harvestTreeFarm(R) R.networkFarm = "..tostring(R.networkFarm))
			end
		end
	end
	
	if R.networkFarm then			-- monitor trees for growth
		if R.logType == "mangrove" then
			T:go("F1D1")
			T:place("dirt", "up")
			T:go("F6x2U1L1")	-- move under dirt covering, clear roots from hopper, move level with dirt, face left
		else
			T:go("F4R1")				-- either in between 2 trees or in gap between double trees at dirt level
			if turtle.detect() then		-- single trees, move between 1st and 2nd rows
				T:go("R1F1 R1F2 R1F1 L1")
			else	-- using double trees
				T:go("R2F1")
				if not turtle.detect() then
					return {"Unable to determine position"}
				end
			end
		end
		R = lib.watchFarm(R)	-- wait for trees to grow, then start harvest
	else
		--logType, startHeight, R = lib.initialise(R) -- possible ID tree type + move to correct position 1 above dirt
		R, message = lib.initialise(R) 		-- possible ID tree type + move to correct position next to first dirt
		if message ~= "" then
			return{message}
		end
	end
	T:saveToLog("R.networkFarm = "..tostring(R.networkFarm)..", logType = "..R.logType..", treeSize = "..R.treeSize)
	-- different clearing for different trees:
	-- double spruce and jungle: staight up/down or small
	if R.logType == "mangrove" then
		clearRectangle({width = 13, length = 13, up = true, down = true })
		T:go("U2F2 R1F2L1")
		clearSolid({width = 9, length = 9, height = 18, direction ="up"})
		T:go("D3R1 F4R1 F3R2")
		network.emptyInventory(R, {"sapling", "propagule", "dirt", "crafting"}, {"all"}, true)
	elseif R.logType == "birch" or R.logType == "spruce" or R.logType == "jungle" then	-- use column harvest
		if R.treeSize == "single" then
			lib.harvestSingleRow()
			T:go("F1R1F2R1")
			lib.harvestSingleRow()
			T:go("F1L1F2L1")
			lib.harvestSingleRow()
			T:go("F1R1F2R1")
			lib.harvestSingleRow()
			if R.networkFarm then
				T:go("F1R1 F3L1 F3R2")
				network.emptyInventory(R, {"sapling", "propagule", "dirt", "crafting"}, {"all"}, true)
			else
				T:go("F1R1 F6L1 F3R2")
			end
		else
			lib.harvestDouble()
			T:go("F3")
			lib.harvestDouble()
			T:go("R1F4")
			lib.harvestDouble()
			T:go("R1F4")
			lib.harvestDouble()
			if R.networkFarm then
				T:go("F1R1 F3L1 F3R2")
				network.emptyInventory(R, {"sapling", "propagule", "dirt", "crafting"}, {"all"}, true)
			else
				T:go("F1R1 F6L1 F3R2")
			end
		end
	else	-- use cube harvest, including mangrove
		local size = 10
		local start = "L1F1 L1F1 R2"
		local finish = "R1F1 R1F3 R2"
		if R.logType == "acacia" then
			size = 12
			start = "L1F2 L1F2 R2"
			finish = "R1F2 R1F2 R2"
		elseif R.logType == "cherry" then
			size = 14
			start = "L1F3 L1F3 R2"
			finish = "R1F3 R1F1 R2"
		end
		T:go("U1F1")	-- into first log at base of tree
		clearRectangle({width = 7, length = 7, up = true, down = true})
		--T:go("L1F2 L1F2 R2")	-- rect size 12
		--T:go("L1F1 L1F1 R2")	-- rect size 10
		T:go(start)
		local height = 0
		local pastLogCount = -1
		local currentLogCount = lib.getLogCount()
		--while currentLogCount ~= pastLogCount do
		while currentLogCount - pastLogCount > 5 do	-- ony continue if at least 5 logs harvested last round
			T:up(3)
			height = height + 3
			pastLogCount = currentLogCount -- 0 when loop starts
			--clearRectangle({width = 12, length = 12, up = true, down = true})
			clearRectangle({width = size, length = size, up = true, down = true})
			currentLogCount = lib.getLogCount() -- eg 20 logs from first round
		end	
		T:down(height + 1)
		--T:go("R1F2 R1F2 R2")		-- on polished stone rect size 12
		--T:go("R1F1 R1F3 R2")		-- on polished stone rect size 10
		T:go(finish)
		if R.networkFarm then
			T:go("R1F3 L1")			-- on modem
			network.emptyInventory(R, {"sapling", "propagule", "dirt", "crafting"}, {"all"}, true)
		end
	end
	
	return {}	-- if player initiated, stops here. If R.auto then returns to plantTreeFarm()
end

local function harvestObsidian(R) -- 41
	local lib = {}
	
	function lib.forward(move)
		T:isWaterOrLava("forward")	-- automatically use lava ahead to refuel
		T:isWaterOrLava("down") 	-- automatically use lava down to refuel
		T:go("C2", false, 0, false)	-- place / replace block below
		if move then
			T:forward(1)
		end
	end
	
	function lib.home(outward)
		if outward then
			T:go("L1F"..R.width - 1 .."L1F"..R.length - 1)
		else	
			T:go("R1F"..R.width - 1 .."R1")
		end
	end
	
	function lib.start()
		local lavaSlot = T:getItemSlot("lava")
		if lavaSlot > 0 then
			turtle.select(slot)
			turtle.refuel()
		end
		T:down(1)
	end
	
	local outward = true
	
	lib.start()						-- use lava bucket if placed, move down into block below
	for w = 1, R.width do
		for l = 1, R.length do
			if l < R.length then
				lib.forward(true)
			else
				lib.forward(false)
			end
		end
		if w < R.width then
			if outward then
				T:go("R1F1R1")
			else
				T:go("L1F1L1")
			end
			outward = not outward
		end
	end
	
	lib.home(outward)
	
	return {}
end

local function harvestShulkers(R)
	local lib = {}
	
	function lib.attackAll()
		return turtle.attack(), turtle.attackUp(), turtle.attackDown()
	end

	function lib.attack()
		local forward, up, down = lib.attackAll()
		while forward or up or down do
			forward, up, down = lib.attackAll()
			sleep(0.2)
		end
	end
	
	function lib.approach(direction, limit, dig)
		-- move forward until stopped by shulker
		limit = limit or 64
		dig = dig or false
		local count = 0
		local solidDown = false
		move = turtle.forward
		if direction == "up" then
			move = turtle.up
		elseif direction == "down" then
			move = turtle.down
		end
		local forward, up, down = lib.attackAll()
		if forward or up or down then -- attacks suceeded
			return true, 0, solidDown
		else
			while move() do
				count = count + 1
				if turtle.detectDown() then
					solidDown = true
				end
				if count >= limit then
					return false, count, solidDown
				end
				forward, up, down = lib.attackAll()
				if forward or up or down then
					return true, count, solidDown
				else
					if dig then
						T:dig("forward")
					end
				end
			end
			return false, count, solidDown
		end
	end
	
	function lib.home(direction, moves)
		local move = turtle.back
		if direction == "up" then
			move = turtle.down
		elseif direction == "down" then
			move = turtle.up
		end
		for i = 1, moves do
			move()
		end
	end
	
	function lib.checkPosition()
		if T:detect("forward") then			-- wall in front
			T:turnRight(1)
			if T:detect("forward") then		-- wall to right
				T:turnLeft(1)
				return true					-- position corrected
			else
				T:turnLeft(2)
				if T:detect("forward") then	-- wall in front. position correct
					return true
				end
			end
		end
		return false
	end
	
	function lib.getLength()
		local count = 0
		while turtle.detectDown() do
			count = count + 1
			T:forward(1)
		end
		utils.goBack(1)
		return count
	end
	
	function lib.clearWall()
		local distance = 0
		while distance < 9 do	-- smallest external walls are 8 x 8
			local success, count = lib.approach("forward", 8 - distance)
			if success then
				lib.attack()
			end
			distance = distance + count
		end
		T:turnLeft(1)
		if T:detect("forward") then	-- larger than 8 blocks
			T:turnRight(1)
			while distance < 14 do	-- larger builds are 14 x 14
				local success, count = lib.approach("forward", 13 - distance)
				if success then
					lib.attack()
				end
				distance = distance + count
			end
			T:go("L1x2")
		end
	end
	
	function lib.roof()
		-- check position
		local doContinue = lib.checkPosition()
		
		if doContinue then
			T:go("U2F3 R1F3 R1")
			local length = lib.getLength()
			local width = 1
			local outward = lib.turnRound(true)	
			local success, count, onRoof = false, 0, true	
			while onRoof do
				local distance = 0
				while distance < length - 1 do
					success, count, onRoof = lib.approach("forward", length - 1 - distance)
					if success then
						lib.attack()
					end
					if count == 0 then
						turtle.dig()
					end
					distance = distance + count
				end
				width = width + 1
				outward = lib.turnRound(outward)
			end
			if outward then
				T:go("F".. 3 .."L1F"..width - 3 .."D2L1")
			else
				T:go("F".. length - 3 .."R1F"..width - 3 .."D2L1")
			end
			return {}
		else
			return {"Turtle not in front of a wall"}
		end
	end
	
	function lib.turnRound(outward)
		if outward then
			T:go("R1F1R1")
		else
			T:go("L1F1L1")
		end
		return not outward
	end

	function lib.upAndOver()
		local start, height, forward = 0, 0, 0
		while turtle.detect() do
			turtle.up()
			start = start + 1
		end
		while turtle.forward() do
			forward = forward + 1
		end
		turtle.turnRight()
		while not turtle.detectUp() do
			local success, count = lib.approach("up", 64, true)
			if success then
				lib.attack()
			end
			height = height + count
		end
		T:turnRight(2)
		while not turtle.detectDown() do
			if lib.approach("down", 64, true) then
				lib.attack()
			end
		end
		T:turnLeft(1)
		for i = 1, forward do
			turtle.forward()
		end
		for i = 1, start do
			turtle.down()
		end
		T:turnRight(2)
	end
	
	function lib.walls()
		local doContinue = lib.checkPosition()
		if doContinue then
			T:go("F2R1 F2R2 D1x2")		-- on corner outside middle of wall, facing along its length, dig light rod	
			for i = 1, 4 do
				lib.clearWall()
			end
			T:go("F2L1 U1F2 R2")
		else
			return {"Turtle not in front of a wall"}
		end
	end
		
	local direction = "forward"
	local doContinue = false
	
	if R.subChoice == 1 then		-- Shulker is above
		direction = "up"
		doContinue = true
	elseif R.subChoice == 2 then	-- Shulker is ahead
		doContinue = true
	elseif R.subChoice == 3 then	-- Shulker is below
		direction = "down"
		doContinue = true
	else
		if R.subChoice == 4 then	-- Climb tower wall
			lib.upAndOver()
		elseif R.subChoice == 5 then	-- Clear roof above
			return lib.roof()
		elseif R.subChoice == 6 then	-- Clear outside walls
			lib.walls()
		end
	
	end
	if doContinue then
		local success, moves = lib.approach(direction, 64)
		if success then
			lib.attack()
		end
		lib.home(direction, moves)
	end
	
	return {}
end

local function upgradeFarmland(R)
	local essences = {":inferium", ":prudentium", ":tertium", ":imperium", ":supremium", ":awakened" , ":insanium"}
	
	local lib = {}
	
	function lib.isHigherTeir(essence, farmLand)
		-- eg "ma:prudentium_essence", "mc:farmland"
		local teir = 0
		for index = 1, #essences do
			if farmLand:find(essences[index]) ~= nil then
				teir = index	-- 0 if vanilla, else eg 2 for prudentium
				break
			end 
		end
		for index = 1, #essences do
			if essence:find(essences[index]) ~= nil then
				if index > teir then
					return true
				end
			end 
		end
		return false
	end
	
	function lib.upgrade(essence, slot)
		-- essence is the slot no of any essence
		turtle.select(slot)
		local blockType = T:getBlockType("up")
		if blockType:find("farmland") ~= nil then			-- farmland found (vanilla or modded)
			if lib.isHigherTeir(essence, blockType) then	-- eg "ma:inferium", mc:farmland"
				turtle.placeUp()
			end
		end
	end
	-- check if any essence still onboard
	T:checkInventoryForItem({"essence"}, {95}, false)
	-- return slotData.lastSlot, total, slotData -- integer, integer, table
	local name = ""
	local slot, amount, data = T:getItemSlot("essence")
	name = data.mostName or ""
	local empty = T:getFirstEmptySlot()
	
	if slot > 0 then
		T:go("D2")
		local outward = true
		for w = 1, 10 do
			for i = 1, 9 do
				if turtle.getItemCount(slot) == 0 then
					slot, amount, data = T:getItemSlot("essence")
					name = data.mostName or ""
					if slot == 0 then
						slot = empty
					end
				end
				lib.upgrade(name, slot)
				if w == 1 and i == 1 then
					T:go("F1R2 C1R2")
				elseif w == 10 and i == 1 then
					
				else
					T:forward(1)
				end
			end
			if outward then
				lib.upgrade(name, slot)
				if w == 1 then
					T:go("L1F1 L2C1 R1")
				elseif w == 9 then
					T:go("L1F1 L1F1 L2C1 L2")
				else
					T:go("L1F1L1")
				end
			else
				if w < 10 then
					lib.upgrade(name, slot)
					T:go("R1F1R1")
				else
					T:go("L1F1 L2C1 R2F8 L1U1 C2U2") -- 1 above normal position
				end
			end
			outward = not outward
		end
		-- sometimes original essence pops out of the ground when upgraded, so rescue it
		for w = 1, 10 do
			for i = 1, 9 do
				turtle.suckDown()
				turtle.suck()
				T:forward(1)
			end
			if outward then
				turtle.suckDown()
				turtle.suck()
				T:go("L1F1L1")
			else
				if w < 10 then
					turtle.suckDown()
					turtle.suck()
					T:go("R1F1R1")
				else
					T:go("L1F9 L1D1") -- normal position
				end
			end
			outward = not outward
		end
	end
	return ({"Farmland Upgraded"})
end

local function manageFarm(R)
	local lib = {}
		
	function lib.askPlayerForCrops()
		local seed  = ""
		pp.itemColours = {colors.lightGray, colors.red, colors.orange, colors.brown, colors.magenta, colors.yellow}
		crops = {"minecraft:wheat_seeds", "minecraft:beetroot_seeds", "minecraft:carrots", "minecraft:potatoes", "mysticalagriculture", "none"}
		choices = {"wheat (seeds)", "beetroot (seeds)", "carrot", "potato", "Mystical Agriculture", "Till soil only"}
		choice = menu.menu("Choose preferred crop", choices, pp, "Type number of your choice")
		crop = crops[choice]
		if crop == "none" then
			return "", ""
		elseif crop == "mysticalagriculture" then
			T:checkInventoryForItem({"seeds"}, {95}, true, "Add one type of M. Agriculture seeds")
		else
			T:checkInventoryForItem({crop}, {95}, true, "Do not mix! add as many as you want")
		end
		crop = T:getMostItem("", false)		-- not searching for any specific item, not checking stone only
		-- crop could be wheat/beetroot seeds, carrots, potatoes or mystical agriculture seeds
		seed, crop = lib.getCropSeed(crop)	-- seed type or "", crop type
		return seed, crop	
	end	
		
	function lib.assessPlot(R)
		local crop = T:getBlockType("forward")	-- convert ma:inferium_crop to ma:inferium_seeds
		local seed = lib.getCropSeed(crop)
		turtle.down()									-- into water source
		local soil = T:getBlockType("forward")
		turtle.up()										-- at crop level
		return crop, seed, soil
	end
	
	function lib.checkEquipment(R, itemRequired)
		-- Check if item is equipped and return it to slot
		T:clear()
		print("Checking equipment. Please wait...")
		local equipped, slot = T:getEquipped("right", false)	-- see what is equipped and replace it 
		if equipped == itemRequired then
			equipped, slot = T:getEquipped("right", true)		-- remove item and return slot
			return slot
		end

		return 0	-- not found
	end
		
	function lib.crossFarm(R)
		-- used with goHome to find starting point
		local blockType = ""
		local isReady, cropType, seed, status
		isReady, cropType, seed, status, R = lib.isCropReady(R,"down")
		-- will go forward until chest, barrel, modem or cobble detected below
		-- if detected within 1 move, this is ignored
		local numMoves = 0
		local endOfPath = false
		while not endOfPath do
			blockType = T:getBlockType("down")
			if blockType == "" or cropType ~= "" then --crops or nothing below
				turtle.forward()
			elseif  blockType:find("barrel") ~= nil or
					blockType:find("chest") ~= nil or
					blockType:find("modem") ~= nil or
					blockType:find("cobble") ~= nil then
				endOfPath = true
			end
			numMoves = numMoves + 1
		end
		return R, blockType -- either barrel, chest, modem or cobble
	end
	
	function lib.farmAll(R, isFarmToRight, isFarmToFront)
		local plotCountR = 0		-- plot a1 harvested
		local plotCountF = 0		-- plot a1 harvested
		if isFarmToRight then
			while isFarmToRight do	-- do all plots on this axis
				R, isFarmToRight = lib.farmToRight(R) -- plot harvested and back to plot origin
				plotCountR = plotCountR + 1
			end
			lib.goToLeft(R, plotCountR)
		end
		if isFarmToFront then
			while isFarmToFront do	-- do all plots on this axis
				plotCountR = 0				-- reset
				R, isFarmToRight, isFarmToFront = lib.farmInFront(R)
				if isFarmToRight then
					while isFarmToRight do	-- do all plots on this axis
						R, isFarmToRight = lib.farmToRight(R) -- plot harvested and back to plot origin
						plotCountR = plotCountR + 1
					end
					lib.goToLeft(R, plotCountR)	-- return home and continue with front
				end
				plotCountF = plotCountF + 1
			end
			lib.goToFront(R, plotCountF)
		end
	end
	
	function lib.farmInFront(R)
		--[[ facing crops on first farm. move to next farm in front ]]
		T:go("U1L1 F11D1 R1")						-- on next farm, facing crops
		local seed, crop = lib.manageTree(R)		-- refuel, gather seeds or other crops
		local isFarmToRight = false
		R, isFarmToRight = lib.harvest(R, seed, crop)		-- harvest field, store crops
		return R, isFarmToRight
	end
	
	function lib.farmToRight(R)
		--[[ facing crops on first farm. move to next farm on right side ]]
		T:go("U1F11 D1")								-- on next farm, facing crops
		local seed, crop = lib.manageTree(R)					-- refuel, gather seeds and other crops
		R, isFarmToRight = lib.harvest(R, seed, crop)		-- harvest field, store crops
		-- now at starting position of current plot
		return R, isFarmToRight
	end
	
	function lib.getCropSeed(crop)
		-- change growing crops into equivalent seed names
		-- crop could be seeds, so return equivalent crop
		local start = crop:find("_crop")
		if start ~= nil then	-- only modded seeds have "crop"
			return crop:sub(1, start).."seeds", crop
		end
		if crop:find("seeds") ~= nil then	-- asked to return crop from seed type
			if crop:find("wheat") ~= nil then
				return "minecraft:wheat_seeds", "minecraft:wheat"
			end
			if crop:find("beetroot") ~= nil then
				return "minecraft:beetroot_seeds", "minecraft:beetroot"
			end
		end
		if crop:find("wheat") ~= nil then
			return "minecraft:wheat_seeds", "minecraft:wheat"
		end
		if crop:find("beetroot") ~= nil then
			return "minecraft:beetroot_seeds", "minecraft:beetroot"
		end
		if crop:find("carrot") ~= nil then
			return "", "minecraft:carrot"
		end
		if crop:find("potato") ~= nil then
			return "", "minecraft:potato"
		end
		-- planted crops are plural, harvested singular: carrots / carrot, pototoes/ potato
		return "", crop -- no seed for carrot / potato
	end
	
	function lib.getHoe()
		local message = ""
		if R.networkFarm then	-- get hoe from storage
			hoeSlot = network.getItemFromNetwork("barrel", "minecraft:diamond_hoe", 1)
			if hoeSlot == 0 then
				if T:checkInventoryForItem({"minecraft:diamond_hoe"}, {1}, true, "Diamond Hoe required for planting!") ~= nil then
					hoeSlot = T:getItemSlot("minecraft:diamond_hoe")
				end
			end
		else	-- put crafting table into barrel in floor
			T:go("L1F1")		-- over barrel
			local isStorage, storageType = utils.isStorage("down")
			if not isStorage then
				message =
[["Farm upgrade required:
Previous designs had a crafting table
next to the water source.

 1. Place a barrel or chest under the turtle
	instead.
	
 2. Restart"
]]
				return 0, message
			end
			-- must be storage below to get this far
			T:suck("down")		-- if hoe already in storage get it out
			hoeSlot = T:getItemSlot("minecraft:diamond_hoe")
			if hoeSlot == 0 then
				if T:checkInventoryForItem({"minecraft:diamond_hoe"}, {1}, true, "Diamond Hoe required for planting!") ~= nil then
					hoeSlot = T:getItemSlot("minecraft:diamond_hoe")
				end
			end
		end
		return hoeSlot, ""
	end
				
	function lib.getSaplings(R, direction)
		--[[ get a single sapling from the chest ]]
		if direction == nil then
			direction = "forward"
		end
		if R.networkFarm then
			network.getItemFromNetwork("barrel", "sapling", 1)
			--lib.getItemFromNetworkBarrels(R, "sapling", 1)
		else
			while T:suck(direction, 1) do end -- remove saplings/ seeds
			T:dropItem("sapling", direction, 1) -- drop all but 1 saplings
			if not T:dropItem("seeds", direction, 0) then-- drop all seeds
				T:dropItem("seeds", "up", 0)
			end
		end
		
		return T:getItemSlot("sapling")
	end
	
	function lib.getSeeds(R, direction, seed)
		--[[ 
			seed = name of growing crops seed or ""
			turtle facing crops on networked, else facing storage
			allow for other seeds from mods eg MysticalAgriculture
			get 1 stack of seeds of whatever type is being farmed
		]]
		if seed == "" then
			return "", 0
		end
		local inventorySlot, seedCount = 0, 0
		T:saveToLog("Collecting seeds from storage")
		if R.networkFarm then
			inventorySlot, seedCount = network.getItemFromNetwork("chest", seed, 64)
		else
			while T:suck(direction, 1) do end -- remove saplings/ seeds
			T:dropItem("sapling", direction, 0) -- drop all saplings
			T:dropItem("seeds", direction, 64)	-- drop all but 64 of any seed type
			seedCount = T:getItemCount(seed)	
		end
		if seedCount > 0 then
			T:saveToLog("planting " ..seed)
		end
		return seed, seedCount	-- could be: "", 0 or "minecraft:wheat_seeds", 64
	end
		
	function lib.getVeg(R, direction, crop)
		-- assume only one type of crop per field
		-- local item, itemName, shortName, slot = "", "","", 0
		local inventorySlot, cropCount = 0, 0
		
		if R.networkFarm then
			inventorySlot, cropCount = network.getItemFromNetwork("chest", crop, 64)
		else
			if not R.mysticalAgriculture then
				print("Collecting root crops from storage")
				direction = direction or "forward"
				while T:suck(direction, 1) do end 			-- remove carrots / potatoes / wheat / beetroot / essence
				--item, itemName, shortName, slot = T:getFirstItem()
				local found = false
				if T:getItemSlot("potato") > 0 then
					T:dropItem("potato", direction, 64)		-- drop all but 65 potato
					found = true
					crop = "minecraft:potato"
				end
				if T:getItemSlot("carrot") > 0 then
					T:dropItem("carrot", direction, 64)		-- drop all but 64 carrots
					found = true
					crop = "minecraft:carrot"
				end
				if not found then
					T:dropAll(direction)					-- drop everything back
				end
			end
			cropCount = T:getItemCount(crop)
		end
		
		if cropCount > 0 then
			print("planting " ..crop)
		end
		return crop, cropCount -- could be: "", 0 or "minecraft:potato", 64
	end
	
	function lib.goHome(R)
		-- after a re-boot go to start
		local onTree = false
		-- is tree above or in front
		-- check if log in front
		if T:getBlockType("forward"):find("log") ~= nil then -- about to harvest tree
			lib.harvestTree(R, "forward") 		-- will only harvest if fuel below half of limit
			onTree = true					-- end on dirt
		elseif T:getBlockType("up"):find("log") ~= nil then -- harvesting tree
			lib.harvestTree(R, "up")			-- end on dirt
			onTree = true
		elseif T:getItemSlot("log") > 0 then-- tree just harvested 
			onTree = true
			turtle.up()
			if T:getBlockType("up"):find("log") ~= nil then -- harvesting tree
				lib.harvestTree(R, "up")		-- end on dirt
			else
				while turtle.down() do end	-- end on dirt
			end
		end
		
		if onTree then 
			local success, storage = false, ""
			-- tree harvested, sitting on dirt, but direction unknown
			T:down(1) 				-- dig dirt, go down
			-- if storage type farm chest/barrel will give position
			for turns = 1, 4 do
				T:turnRight(1)
				success, storage = utils.isStorage("forward")
				if success then
					T:go("L2U1")
					T:place("dirt", "down")
					T:go("B1R1 F1D1R1")
					R.ready = true
					return R
				end
			end
			-- if networked will be in air 2 blocks above barrel or stone
			T:down(1)
			T:place("dirt", "up")
			T:down(1)	 --should be on corner
			for turns = 1, 4 do
				T:forward(1)
				success, storage = utils.isStorage("down")
				if storage == "modem" then
					T:go("R1F1D1")
					R.ready = true
					return R
				end
				T:go("B1R1")
			end
		else
			while turtle.down() do end -- no tree around, no logs onboard
		end
			
		return R	-- R.ready == false
	end
	
	function lib.goToLeft(R, plotCountR)
		T:go("U1R2 F"..plotCountR * 11 .."D1R2")	-- return home and continue with front
		if R.config ~= nil then
			local coord = R.config.currentPlot
			for i = 1, plotCountR do
				coord = lib.configUpdateCoords(R, coord, "left")
			end
			R.config.currentPlot = coord
		end
	end
	
	function lib.goToFront(R, plotCountF)
		T:go("U1R1F"..plotCountF * 11 .."D1L1")
		if R.config ~= nil then
			local coord = R.config.currentPlot
			for i = 1, plotCountF do
				coord = lib.configUpdateCoords(R, coord, "back")
			end
			R.config.currentPlot = coord
		end
	end
	
	function lib.gotoTree(R)
		-- assume facing crops
		if not R.networkFarm then
			T:turnRight(1)							-- face storage
		end
		T:saveToLog("Extracting saplings from storage")
		lib.getSaplings(R, "forward") 				-- gets one sapling only (if present)
		T:saveToLog("Moving to tree position")
		if R.networkFarm then
			T:turnRight(1)							-- face wall next to corner barrel
		end
		T:go("U1F1R1")								-- move on top of wall/storage. face tree direction

		-- check if tree or dirt ahead
		if turtle.forward() then 					-- No tree or sapling ahead. assume tree is missing or 2 blocks above
			if T:getBlockType("down") == "minecraft:dirt" then
				turtle.back()						-- older design, return 
			else
				T:up(1)
				if turtle.detectUp() then			-- dirt above = new tree layout
					if T:getBlockType("up") == "minecraft:dirt" then
						T:go("B1U2")				-- check tree in elevated position
					else
						turtle.back()				-- not dirt above ? removed or lost
					end
				end
			end
		end
		lib.harvestTree(R, "forward") 				-- fell tree or plant sapling, ends facing tree / dirt / sapling. sticks already used for fuel. excess saplings placed
		T:go("R1F1D1R1")							-- return to base, facing crops 
		if R.networkFarm then
			network.sendItemToNetworkStorage(R, "barrel", "sapling", 64) --move saplings to any attached barrel
		else
			T:turnRight(1)							-- facing plot storage 
			T:saveToLog("Dropping saplings into storage")
			T:dropItem("sapling", "forward", 0)	-- drop all saplings forward into chest/barrel
			T:turnLeft(1)
		end
		-- ends in field facing crops
	end
	
	function lib.harvest(R, seed, crop)
		--[[
		cover the field in a set pattern.
		harvest crop if ripe
		till soil and plant new ones
		place seeds / harvest in chests
		return farm(s) to right / front
		crop is full name. if mixed seeds only one type returned
		]]
		T:go("U1") --ready to farm field
		local isFarmToRight = false
		local isFarmToFront = false
		local width = 9
		local length = 10
		local toRight = true
		for l = 1, length do
			for w = 1, width do
				lib.replant(R, seed, crop)	-- check and replant crop below
				T:forward(1)
				if l == 1 and w == width then -- last block of first row at front of farm
					T:forward(1)
					if utils.isStorage("down") then	-- chest, barrel or modem
						isFarmToRight = true
					end
					turtle.back()
				end
			end
			-- end of the row: change direction
			if l < length then -- do not turn at final row
				lib.replant(R, seed, crop)	-- check and replant crop below
				if toRight then
					T:go("L1F1L1")
				else
					T:go("R1F1R1")
				end
				lib.replant(R, seed, crop)
			end
			toRight = not toRight
		end
		T:go("R1F1") -- goes over chest/cobble on top wall
		if utils.isStorage("down") then
			isFarmToFront = true
		end
		T:go("R2F"..length.."D1L1") -- go straight across to seed chest 10 blocks, facing crops
		lib.storeCrops(R) -- rotates from start to deposit seeds and crops, ends facing crops
		return R, isFarmToRight, isFarmToFront
	end	
	
	function lib.harvestTree(R, direction)
		--[[
			start in front of / during tree harvest
			Check if sapling present
			Harvest tree if present, replant sapling
			Dispose of apples. Use sticks as fuel
			Return to top of storage
		]]

		direction = direction or "forward"
		local inFront = T:getBlockType("forward")
		print("Checking tree")
		if inFront == "" then -- no tree or sapling
			print("No sapling: planting sapling")
			T:place("sapling", "forward")
		elseif inFront:find("log") ~= nil or direction == "up" then -- tree above or in front
			-- clsTurtle.harvestTree(self, extend, craftChest, direction)
			print("Harvesting tree")
			T:harvestTree(false, false, direction) --do not investigate side branches in case chunk unloaded
			T:back(1) -- face dirt
			-- place(self, blockType, direction, leaveExisting, signText)
			T:place("sapling", "forward")
		end
		print("Disposing of apples")
		T:dropItem("apple", "up", 0) -- drop any apples
		utils.useSticksAsFuel()
		
		while turtle.down() do end	-- ends facing tree, on top of plot storage
	end
	
	function lib.manageTree(R)
		--[[ starting position facing crops ]]
		local isReady, crop, seed, status, R = lib.isCropReady(R, "forward")
		if crop == "" and not R.auto then			-- only ask player if not running via startup
			seed, crop = lib.askPlayerForCrops()	-- "" or  specific seed type,
		end
		local logSlot = T:getItemSlot("stick")
		
		if logSlot > 0 then
			turtle.select(logSlot)
			turtle.refuel()
		end
		logSlot = T:getItemSlot("log")
		local needsFuel = false
	
		if turtle.getFuelLevel() < turtle.getFuelLimit() / 2 then
			needsFuel = true
		end
		if needsFuel then
			T:saveToLog("Running Tree Manager")
			lib.gotoTree(R) 					-- check for sapling or harvest tree, retuns to facing crops
		end
		
		logSlot = T:getItemSlot("log")
		if logSlot > 0 then						--logs onboard, need to equip crafting table
			if R.networkFarm then
				lib.refuelWithLogs(R, logSlot) 	-- use any logs for fuel
			else
				T:go("L1F1") 					-- move to buried storage chest/barrel
				lib.refuelWithLogs(R, logSlot) 	-- use any logs for fuel
				T:go("R2F1")					-- facing seed chest/barrel
			end
		else
			if not R.networkFarm then
				T:turnRight(1)
			end
		end
		-- get seeds or veg based on what is growing
		if seed ~= "" then
			local seedType, seedCount = lib.getSeeds(R, "forward", seed) 	-- table: get 95 of beetroot / wheat / mysticalagriculture seeds
			if seedCount == 0 then
				T:saveToLog("No seeds available.")
			end
		else	-- seed  = ""
			local veg, vegCount = "", 0
			if R.networkFarm then
				veg, vegCount = lib.getVeg(R, "forward", crop)	-- gets any carrots / potatoes
			else
				T:turnRight(1)					-- face crop chests
				veg, vegCount = lib.getVeg(R, "forward", crop)	-- gets any carrots / potatoes
				T:turnRight(2)					-- face crops
			end
			if veg ~= "" then
				crop = veg
			end
		end
		
		return seed, crop	-- name of seed / "",  crop / ""
	end
	
	function lib.isCropReady(R, direction)
		local isReady = false
		local status = ""
		local success = false
		local crop, seed = "", ""
		local data = {}

		direction = direction or "forward"

		if direction == "down" then
			success, data = turtle.inspectDown()
		else
			success, data = turtle.inspect()
		end
		--T:saveToLog("lib.isCropReady(R,".. direction..")")
		if success then			-- inspect() success
			crop = data.name	-- name of growing plant
			if crop:find("flower") ~= nil then
				T:saveToLog("Flower "..crop.." found")
				return true, crop, "open"	-- eg torchflower
			else
				if data.name:find("beetroot") ~= nil then
					status = data.state.age.." / 3"
					if data.state.age == 3 then
						isReady = true
					end
				else			-- all other crops inc Mystical Agriculture
					status = data.state.age.." / 7"
					if data.state.age == 7 then
						isReady = true
					end
				end
			end
			seed, crop = lib.getCropSeed(crop)
		end
		--T:saveToLog("return isReady = "..tostring(isReady)..", crop = "..crop..", seed = "..seed..", status = "..status)
		-- crop: "", "minecraft:carrots", "minecraft:beetroot", "minecraft:potatoes", "minecraft:wheat", "mysticalagriculture:*_crop"
		return isReady, crop, seed, status, R	-- eg true, "minecraft:carrots", "7 / 7" or false, "mysticalagriculture:inferium_crop", "1 / 7"
	end
	
	function lib.locateFarm(R)
		T:saveToLog("? over water = false")
		for i = 1, 4 do
			if turtle.detect() then
				detected = i
			end
			T:turnRight(1)
		end
		T:saveToLog("Neighbouring blocks detected at: "..detected)
		-- check if on corner
		if detected > 0 then
			--assume tree / sapling on corner on older farm type
			T:saveToLog("Assuming next to tree / sapling. Moving..")
			T:go("R"..detected .."F1D1R1")
		else	-- no surrounding blocks
			for i = 1, 4 do
				T:forward(1)
				success, storage = utils.isStorage("down")
				T:saveToLog("i = "..i..",success = "..tostring(success)..". storage = "..storage)
				if success then
					discovered = discovered .. storage
					if storage == "modem" then
						R.networkFarm = true
					end
				else
					if storage == "" then
						discovered = discovered .. "_"
					else
						discovered = discovered .. "wall"
					end
				end
				utils.goBack(1)
				T:turnRight(1)
			end
			T:saveToLog("Neighbouring blocks found:"..discovered)
		end
		-- check discovered for patterns eg {_wall_barrel}
		-- |W|*|B| * = turtle on wall
		-- | | |M|
		if R.networkFarm then
			-- E = wall_barrel_, N = _barrel_wall, W = wall_barrel_, S = _wall_barrel 
			if discovered == "_wall_barrel" then
				T:go("F1D1R1")
			elseif discovered == "barrel_wall_" then
				T:go("R1F1D1R1")
			elseif discovered == "_barrel_wall" then
				T:go("R2F1D1R1")
			elseif discovered == "wall_barrel_" then
				T:go("L1F1D1R1")
			end
		else	-- normal storage farm
			if discovered == "_chest_chest" then
				T:go("F1D1R1")
			elseif discovered == "chest__chest" then
				T:go("R1F1D1R1")
			elseif discovered == "_chest_chest" then
				T:go("R2F1D1R1")
			elseif discovered == "chest_chest_" then
				T:go("L1F1D1R1")
			end
		end
		blockType = T:getBlockType("down")
		if blockType:find("water") ~= nil then
			for i = 1, 4 do
				success, storage = utils.isStorage("forward")	-- true/false, chest, barrel, modem / ""
				if success and storage == "modem" then
					R.networkFarm = true
				end
				T:turnRight(1)
			end
			R.ready = true
		end
	end
	
	function lib.plantCrop(R, seed, crop, direction)
		--turtle.digDown("left") -- harvest existing
		--turtle.digDown("right") -- till soil
		if crop:find("potato") ~= nil then
			T:dropItem("poison", "up", 0)
		end
		--T:saveToLog("lib.plantCrop(R, seed = "..seed..", crop = "..crop)
		local success = false
		-- place(blockType, direction, leaveExisting, signText, doNotAttack)
		if seed == "" then	-- must be a crop
			success = T:place(crop, direction, true, "", true)
			--success = T:place(crop, direction, false, "", true)
			--T:saveToLog("Seed = "..seed..". Placing "..crop..": success = "..tostring(success))
		else
			success = T:place(seed, direction, true, "", true) 	-- eg "mysticalagriculture:air_seeds"
			--success = T:place(seed, direction, false, "", true) 	-- eg "mysticalagriculture:air_seeds"
			--T:saveToLog("Placing "..seed..": success = "..tostring(success))
		end
		if not success then
			success = T:place("seed", direction, true, "", true)			-- failsafe
			--success = T:place("seed", direction, false, "", true)			-- failsafe
			--T:saveToLog("Placing generic 'seeds' : success = "..tostring(success))
		end
		return success
	end
		
	function lib.replant(R, seed, crop)
		-- check crop below. If ripe, dig and replant seed
		local isReady, cropType, seedType, status
		isReady, cropType, seedType, status, R = lib.isCropReady(R, "down")	-- eg true, "minecraft:carrots", "7 / 7" or false, "", ""
		if cropType == "" then					-- no crop below (above water, storage or dirt)
			turtle.digDown("right")				-- use hoe
			lib.plantCrop(R, seed, crop, "down")-- plant crop
		elseif isReady then						-- crop below is ready
			turtle.digDown("left")				-- use pickaxe
			lib.plantCrop(R, seedType, cropType, "down")	-- plant crop
		end

		return R
	end
	
	function lib.refuelWithLogs(R, logSlot)
		-- saplings already dropped, apples dumped, sticks used as fuel
		-- assume positioned in front of crops if networked, or over buried storage
		-- earlier versions used crafting table buried in the ground
		-- newer versions have a barrel or chest embedded in the ground, containing the crafting table
		-- networked version uses remote storage, turtle faces crops and has modem at back
		local slot, count = 0, 0
		T:saveToLog("Sorting Inventory")	-- make sure all items collected together
		T:sortInventory(true)
		T:saveToLog("Logs present: collecting crafting table")
		if R.networkFarm then
			slot, count = network.getItemFromNetwork("barrel", "minecraft:crafting_table", 1)
			--slot = lib.getItemFromNetworkBarrels(R, "minecraft:crafting_table", 1)
		else
			while T:suck("down") do end					-- empty out barrel/chest to find crafting table
		end
		if T:getItemSlot("crafting") == 0 then
			T:checkInventoryForItem({"crafting"}, {1}, true, "Crafting table required for logs->planks")
		end
		if T:equip("right", "minecraft:crafting_table") then -- swap equipment on right side
			if R.networkFarm then
				network.sendItemToNetworkStorage(R, "barrel", "minecraft:diamond_hoe", 1)
			end
			for i = 1, 16 do						-- drop anything except logs down into barrel/chest/pit
				if T:getSlotContains(i):find("log") == nil then
					T:drop("down", i)	-- into water if networked, buried chest otherwise
				else
					logSlot = i
				end
			end
			turtle.select(logSlot)
			turtle.transferTo(1)
			turtle.craft()							-- craft logs to planks
			logSlot = T:getItemSlot("planks")
			while logSlot > 0 and turtle.getFuelLevel() < turtle.getFuelLimit() do
				turtle.select(logSlot)
				turtle.refuel()						-- refuel using planks
				logSlot = T:getItemSlot("planks")				
			end
			while T:suck("down") do end			-- recover items from water / storage below
			--T:unequip("right")
			if R.networkFarm then
				slot = network.getItemFromNetwork("barrel", "minecraft:diamond_hoe", 1)
			end
			if not T:equip("right", "minecraft:diamond_hoe") then		-- re-equip hoe/remove crafting table
				T:equip("right", "minecraft:diamond_pickaxe")			
			end
			if R.networkFarm then
				network.sendItemToNetworkStorage(R, "barrel", "minecraft:crafting_table", 1)
			else
				T:dropItem("minecraft:crafting_table", "down")
			end
		else
			print("Unable to equip crafting table.\n\nCheck turtle inventory and chest or barrel below")
			error()
		end
	end
				
	function lib.storeCrops(R)
		-- place crops and seeds into chests. starts facing crops
		T:dropItem("apple", "up", 0) -- drop all apples
		T:dropItem("poison", "up", 0) -- drop all poison potatoes
		if R.networkFarm then
			network.emptyInventory(R, {"sapling", "diamond_hoe", "crafting"}, {"all"}, true)
		else
			T:turnRight(1)	-- face seed storage
			lib.storeSeeds(R, "forward")
			T:turnRight(1)
			if utils.isStorage(direction) then
				T:dropAll(direction) -- drops everything including essences
			end
			T:turnRight(2) -- facing crops again
		end
	end
		
	function lib.storeSeeds(R, direction)
		direction = direction or "forward"
		if utils.isStorage(direction) then -- chest exists
			if not R.networkFarm then
				if T:getItemSlot("minecraft:wheat_seeds") > 0 then
					if not T:dropItem("minecraft:wheat_seeds", direction, 0) then
						T:dropItem("minecraft:wheat_seeds", "up", 0)
					end -- drop all wheat seeds
				elseif T:getItemSlot("minecraft:beetroot_seeds") > 0 then
					if not T:dropItem("minecraft:beetroot_seeds", direction, 0) then-- drop all beetroot seeds
						T:dropItem("minecraft:beetroot_seeds", "up", 0)
					end
				elseif T:getItemSlot("seeds") > 0 then
					if not T:dropItem("seeds", direction, 0) then	-- drop all other seeds as chest is full
						T:dropItem("seeds", "up", 0)
						-- or could print a message and wait for player to empty storage
					end
				end
			end
		end
	end
	
	function lib.watchFarm(R)
		--[[
		check status of crops in front of turtle.
		call lib.harvest when ripe
		return farm(s) found in front or to the right
		]]
		local isReady, crop, seed, status	-- bool, string, string, integer
		isReady, crop, seed, status, R = lib.isCropReady(R, "forward")		-- eg true, "minecraft:carrots", "7 / 7" or false, "", ""
		-- check state of crop in front. Harvest if ripe		
		repeat
			if not isReady then
				if crop == "" then
					print("No crops found in front")
					print("Plant seeds, carrots, potatoes")
					error()
				else
					print("Waiting for "..crop.." status: "..status)
					if crop:find("mysticalagriculture") ~= nil then
						R.mysticalAgriculture = true
					end
				end
				sleep(60)
				isReady, crop, seed, status, R = lib.isCropReady(R, "forward")			-- eg true, "minecraft:carrots", "7 / 7" or false, "", ""
			end
		until isReady
		T:saveToLog("Local crops ripe", true)
		seed, crop = lib.manageTree(R) -- "", "" or name of seed, crop
		return seed, crop
	end
	
	--[[
		ENTRY POINT**********************************************
		called from args on start, or from user choice
		farm already built, needs planting and/or harvesting
		needs both pickaxe and hoe
		may start in any position if chunk unloaded while running
	]]
	
	
	--T:setUseLog(true, "farmLog.txt", true)	-- T:setUseLog(use, filename, delete)
	--dbug = true								-- set dbug flag
	--if not R.auto then						-- not running from startup.lua
		--utils.waitForInput("Logging and debugging enabled")	--utils.waitForInput(message)
	--end
	
	R = utils.checkFarmPosition(R)	-- should be facing crops, placed above water source. R.ready, R.networkFarm is true/false
	if R.networkFarm then
		local message = network.loadStorageLists()	-- initialises or creates lists of where an item can be found: GLOBAL LISTS!
		if message ~= nil then return {message} end
	end
	if not R.ready then		-- not in correct starting place
		R = lib.goHome(R)
		if not R.ready then -- try to find home
			return
			{
				"Unable to determine my position.\n",
				"Place me in the lower left corner",
				"over water, facing the crops with",
				"barrel or chest to my right and behind",
				"(or modem behind if networked farm)"
			}
		end
	end
	if not T:isEmpty() then		-- items in turtle inventory
		local logSlot = T:getItemSlot("log")
		if logSlot > 0 then
			if R.networkFarm then
				lib.refuelWithLogs(R, logSlot) 	-- use any logs for fuel
			else
				T:go("L1F1") 					-- move to buried storage chest/barrel
				lib.refuelWithLogs(R, logSlot) 	-- use any logs for fuel
				T:go("R2F1")					-- facing seed chest/barrel
			end
		end
		if not T:isEmpty() then					-- still items in turtle inventory
			lib.storeCrops(R)
		end
	end
	-- in correct position. Check equipment first, harvest tree, re-equip then harvest crops
	local hoeSlot = lib.checkEquipment(R, "minecraft:diamond_hoe")	-- returns slot  or 0
	
	if hoeSlot == 0 then		-- hoe not in inventory
		local message
		hoeSlot, message = lib.getHoe()
		if message ~= "" then
			return {message}
		end
	end
	-- hoe present or user cancelled request for hoe. Turtle is ready to exchange items
	if hoeSlot > 0 then
		T:equip("right", "minecraft:diamond_hoe", 0) -- equip hoe and put crafting chest into barrel
		if R.networkFarm then	-- drop crafting table into storage
			network.sendItemToNetworkStorage(R, "barrel", "minecraft:crafting_table", 1)
		else	-- put crafting table into barrel in floor
			T:dropItem("crafting", "down")
			T:go("B1R1")
		end
	else	-- hoe not present: return to start and exit
		if not R.networkFarm then
			T:go("B1R1")
		end
		return {"Unable to equip hoe."}
	end
	-- check if crops already planted
	
	local isFarmToRight, isFarmToFront = false, false
	local isReady, crop, seed, status
	isReady, crop, seed, status, R = lib.isCropReady(R, "forward")
	local watch = true	-- assume watching farm already planted
	local init = false
	if crop == "" then	-- nothing has been planted
		seed, crop = lib.askPlayerForCrops()
		if crop ~= "" or seed  ~= "" then	-- something has been chosen
			T:saveToLog("Initial planting of "..crop, true)
			R, isFarmToRight, isFarmToFront = lib.harvest(R, seed, crop)	-- harvest plot a1 plots to right / front recorded	
			init = true
		else
			watch = false	-- not watching, continue with planting
		end
	end
	while true do -- start infinite loop of watching crops, farming all modules
		if watch and not init then -- init true when farm first planted
			seed, crop = lib.watchFarm(R) -- waits if required, returns seed / crop
			init = false
		end
		T:saveToLog("Beginning "..crop.. " management", true)
		R, isFarmToRight, isFarmToFront = lib.harvest(R, seed, crop)	-- harvest plot a1 plots to right / front recorded
		lib.farmAll(R, isFarmToRight, isFarmToFront)
		if not R.auto then -- not started from startup.lua
			if R.networkFarm then
				T:unequip("right")	-- unequip hoe
				network.getItemFromNetwork("barrel", "minecraft:crafting_table", 1)
				network.sendItemToNetworkStorage(R, "barrel", "minecraft:diamond_hoe", 1)
				T:equip("right", "minecraft:crafting_table", 0) -- equip crafting_table
			else
				T:go("L1F1")
				while T:suck("down") do end						-- recover items from storagebelow
				T:equip("right", "minecraft:crafting_table", 0) -- equip crafting_table 
				T:dropItem("minecraft:diamond_hoe", "down") 				-- drop hoe into storage
				T:dropItem("crafting", "down") 					-- in case spare one picked by mistake
				utils.goBack(1)
				T:turnRight(1)
			end
			return {"Crop management of all modules completed"}
		end
	end
	return {}
end

local function manageFarmSetup(R) -- 33
	local lib = {}
	
	function lib.disableAutostart()
		if fs.exists("start.txt") then
			fs.delete("start.txt")
		end
		if fs.exists("startup.lua") then
			fs.delete("startup.lua")
		end
	end
	
	function lib.enableAutostart()
		if not fs.exists("startup.lua") then
			local h = fs.open("startup.lua", "w")
			h.writeLine('function main()')
			h.writeLine('	if fs.exists("start.txt") then')
			h.writeLine('		local handle = fs.open("start.txt", "r")')
			h.writeLine('		local cmd = handle.readLine()')
			h.writeLine('		handle.close()')
			h.writeLine('		shell.run("tk.lua "..cmd)')
			h.writeLine('	end')
			h.writeLine('end')
			h.writeLine('main()')
			h.close()
		end
		local h = fs.open("start.txt", "w")
		if R.data == "farm" then
			h.writeLine('farm')
		end
		h.close()
		print("Startup files written")
	end
	
	T:clear()
	--local pp = utils.getPrettyPrint()	
	local choices = {"Plant or harvest this farm complex"}	-- 1.
	local isManaged = fs.exists("start.txt")

	if isManaged then
		table.insert(choices, "Disable automatic farm management") -- 2.
	else
		table.insert(choices, "Enable automatic farm management") -- 2.
	end
	pp.itemColours = {colors.lime, colors.lightGray}
	if not R.networkFarm then
		table.insert(choices, "Convert to Network Storage")		-- 3.
		table.insert(pp.itemColours, colors.magenta)
	end
	if R.mysticalAgriculture then
		--table.insert(choices, "Convert to Mystical Agriculture")
		table.insert(choices, "Upgrade Mystical Agriculture soil")	--3/4
		table.insert(pp.itemColours, colors.green)
	end
	
	local userChoice, modifier = menu.menu("Choose your option", choices, pp) -- 1 to 2
	if modifier == "q" then -- quit chosen
		return {"Player has quit"}
	end
	R.subChoice = userChoice
	if R.subChoice == 1 then -- harvest now
		R.silent = false
		R.data = "farm"
		R.auto = false
		return manageFarm(R)
	elseif R.subChoice == 2 then -- enable/disable auto farm
		local line = menu.clear()
		if isManaged then
			local message = ( "This turtle has been configured to"..
							  "start automatically and run the farm"..
							  "management program.\n")
			line = menu.colourText(line, message, true, true)
			if menu.getBoolean("Do you want to disable this? (y/n)", line, colors.yellow, colors.black) then
				lib.disableAutostart()
			end
			return {"Autostart disabled. Reboot to activate"}
		else -- not managed
			local message = ( "~yellow~This turtle can be configured to be\n"..
							  "a dedicated farm manager.\n\n"..
							  "~lightGray~It will then start automatically and\n"..
							  "monitor the farm complex:\n\n"..
							  "~green~harvesting~yellow~ and ~lime~replanting ~yellow~continuously.\n")
			line = menu.colourText(line, message, true, true)
			if menu.getBoolean("Do you want to enable this? (y/n)", line + 2, colors.orange, colors.black) then
				lib.enableAutostart()
			else
				return {"Player cancelled operation"}
			end
			return {"Autostart enabled. Reboot to activate"}
		end
	--elseif R.subChoice == 3 and #choices == 4 then -- convert normal farm to network storage
	elseif R.subChoice == 3 then -- convert normal farm to network storage
		local isMain = false
		local line = menu.clear()
		local message = ("~yellow~You have chosen to convert this farm "..
						 "to ~magenta~network storage ~yellow~with modems."..
						 "All ~brown~chests and barrels ~red~will be removed.\n")
		line = menu.colourText(line, message, true, true)
		if menu.getBoolean("Is this the main or only plot? (y/n)", line + 3, colors.orange, colors.black) then
			isMain = true
		end
		T:checkInventoryForItem({"stone"}, {16})
		T:checkInventoryForItem({"dirt"}, {2})
		T:checkInventoryForItem({"sapling"}, {1})
		T:checkInventoryForItem({"barrel"}, {1})
		T:checkInventoryForItem({"ladder"}, {5})
		if isMain then
			T:checkInventoryForItem({"chest"}, {8})
			T:checkInventoryForItem({"wired_modem_full"}, {3})
			T:checkInventoryForItem({"computercraft:cable"}, {70})
			return createFarm(R, "convertWithStorage")
		else
			T:checkInventoryForItem({"wired_modem_full"}, {2})
			T:checkInventoryForItem({"computercraft:cable"}, {57})
			return createFarm(R, "convert")
		end
	--elseif R.subChoice == 3 and #choices == 3 then -- upgrade farmland with essence (network opt not present)
	--elseif R.subChoice == 3 and #choices == 3 then -- upgrade farmland with essence (network opt not present)
		--return upgradeFarmland(R)
	elseif R.subChoice == 4 then -- upgrade farmland with essence
		return upgradeFarmland(R)
	end
	
	return {}
end

local function measure(R) -- 101
	-- measure height/ depth / length
	local lib = {}
	
	function lib.checkBlocks(R, blocks)
		local dimension = "height"
		local message = ""
		local measure = ""
		local doContinue = true
		if R.choice == 102 then
			dimension = "depth"
		elseif R.choice == 103 then
			dimension = "length"
		end
		blocks = blocks + 1
		if blocks > R.size then
			message = "Max "..dimension.." of "..R.size.." stopped measurement"
			measure = ""
			doContinue = false
		else
			measure = dimension.." measured: "..blocks.." blocks"
		end
		return doContinue, blocks, measure, message
	end
	
	local blocks = 1
	local method = ""
	local measure = ""
	local message = ""
	local doContinue = true
	if R.choice == 101 then				-- height
		if R.subChoice == 1 then		-- obstruction above
			method = "Method: Until obstruction above"
			while turtle.up() and doContinue do
				doContinue, blocks, measure, message = lib.checkBlocks(R, blocks)
			end
		elseif R.subChoice == 2 then	-- end of blocks in front of turtle eg cliff, wall
			method = "Method: Until no block detected in front"
			while turtle.detect() and doContinue do
				if turtle.up() then
					doContinue, blocks, measure, message = lib.checkBlocks(R, blocks)
				else
					message = "Obstruction above stopped measurement"
					measure = ""
					doContinue = false
				end
			end
		elseif R.subChoice == 3 then	-- search for specific block min 3 characters
			method = "Method:Until search: '"..R.data.."' met"
			while turtle.detect() and doContinue do
				if turtle.up() then
					doContinue, blocks, measure, message = lib.checkBlocks(R, blocks)
					if doContinue then
						local blockType = T:getBlockType("forward")
						if blockType:find(R.data) ~= nil then
							measure = "Height measured: "..blocks.." blocks"
							message = "Found "..blockType
							doContinue = false
						end
					end
				else
					message = "Obstruction above stopped measurement"
					measure = ""
					doContinue = false
				end
			end
		elseif R.subChoice == 4 then	-- When block above changes eg dragon tower height
			local blockType = T:getBlockType("up")
			local compare = blockType
			method = "Method: Until "..blockType.." changes"
			while blockType == compare and doContinue do
				T:up(1)
				doContinue, blocks, measure, message = lib.checkBlocks(R, blocks)
				if doContinue then
					blockType = T:getBlockType("up")
				end
			end
			measure = "Height measured: "..blocks.." blocks"
			message = "Found "..blockType
		end
		
		for i = 1, blocks do
			turtle.down()
		end
	elseif R.choice == 102 then	-- depth
		T:go("F1R2D1") -- go off the edge and face cliff/pit wall
		blocks = blocks + 1
		if R.subChoice == 1 then		-- obstruction water / lava below
			local move = true
			while move do
				local blockType = T:getBlockType("down")
				if blockType:find("water") ~= nil or blockType:find("lava") ~= nil then
					message1 = blockType.." found at "..blocks
					move = false
				else
					move = turtle.down()
					if move then
						blocks = blocks + 1
					else
						measure = "Depth measured: "..blocks.." blocks"
					end
				end
			end
			method = "Method: Until obstruction below"
		elseif R.subChoice == 2 then	-- end of wall in front`
			while turtle.detect() do
				if turtle.down() then
					blocks = blocks + 1
					measure = "Depth measured: "..blocks.." blocks"
				else
					message1 = "Obstruction below stopped measurement"
					break
				end
			end
			method = "Method: Until no block detected ahead"
		elseif R.subChoice == 3 then	-- specific block detected ahead
			method = "Method:Until search: '"..R.data.."' met"
			while turtle.detect() do
				if turtle.down() then
					blocks = blocks + 1
					local blockType = T:getBlockType("forward")
					if blockType:find(R.data) ~= nil then
						measure = "Depth measured: "..blocks.." blocks"
						message = "Found "..blockType
						break
					end
				else
					message = "Obstruction below stopped measurement"
					break
				end
			end
		end
		for i = 1, blocks do
			turtle.up()
		end
		T:go("F1R2")
	elseif R.choice == 103 then	-- length
		if R.subChoice == 1 then		-- obstruction ahead
			method = "Method: Until obstruction ahead"
			while turtle.forward() and doContinue  do
				doContinue, blocks, measure, message = lib.checkBlocks(R, blocks)
			end
		elseif R.subChoice == 2 then	-- end of ceiling above
			method = "Method: Until no block detected above"
			while turtle.detectUp() and doContinue do
				if turtle.forward() then
					doContinue, blocks, measure, message = lib.checkBlocks(R, blocks)
				else
					message = "Obstruction ahead stopped measurement"
					measure = ""
					doContinue = false
				end
			end
		elseif R.subChoice == 3 then	-- end of floor below
			method = "Method: Until no block detected below"
			while turtle.detectDown() and doContinue do
				if turtle.forward() then
					doContinue, blocks, measure, message = lib.checkBlocks(R, blocks)
				else
					message = "Obstruction ahead stopped measurement"
					measure = ""
					doContinue = false
				end
			end
		elseif R.subChoice == 4 then	-- search for specific block up min 3 characters
			method = "Method:Until search: '"..R.data.."' above met"
			while turtle.detectUp() and doContinue do
				if turtle.forward() then
					doContinue, blocks, measure, message = lib.checkBlocks(R, blocks)
					if doContinue then
						local blockType = T:getBlockType("up")
						if blockType:find(R.data) ~= nil then
							message = "Found "..blockType
							measure = "Length measured: "..blocks.." blocks"
							doContinue = false
						end
					end
				else
					message = "Obstruction ahead stopped measurement"
					measure = ""
					doContinue = false
				end
			end
		elseif R.subChoice == 5 then	-- search for specific block down min 3 characters
			method = "Method:Until search: '"..R.data.."' below met"
			--while turtle.detectDown() and doContinue do
			while doContinue do
				if turtle.forward() then
					doContinue, blocks, measure, message = lib.checkBlocks(R, blocks)
					if doContinue then
						local blockType = T:getBlockType("down")
						if blockType:find(R.data) ~= nil then
							message = "Found "..blockType
							measure = "Length measured: "..blocks.." blocks"
							doContinue = false
						end
					end
				else
					message = "Obstruction ahead stopped measurement"
					measure = ""
					doContinue = false
				end
			end
		end
		T:turnRight(2)	-- head home
		for i = 1, blocks do
			turtle.forward()
		end
		T:turnRight(2)
	elseif R.choice == 104 then	-- depth of stretch of water
		--R.length = 0 to auto calculate
		R.width = 1
		R.silent = true
		R.useBlockType = ""
		R.data = "clearWaterPlants"
		local data = clearWaterPlants(R)
		R.height = data[1]
		local length = data[2]
		T:go ("R2F"..length - 1 .."R2U1")
		return {"Greatest depth measured: ".. R.height,"Width of water: "..R.length}
	end
	if message == "" then
		return{method, measure}
	else
		return{method, measure, message}
	end
end

local function mineBedrockArea(R) -- 19
	--[[ 
	Assume on level 5 or -59
	for 1, width do
		for 1, length do
			go down until bedrock, digging/replacing all directions
			return to 5 / -59
			move forward 1 blocks
		end
		turn right/ forward 2 turn right
	end
	]]	
	local lib = {}
	
	function lib.clearColumn(R)
		local level = 0
		--T:go("L1x1R2x1L1")
		local success = T:down(1)
		while success do
			level = level + 1
			if R.data == "leaveExposed" then
				T:go("R1x1R1x1R1x1R1x1", false, 0, true)
			else
				T:go("R1C1R1C1R1C1R1C1", false, 0, true)
			end
			success = T:down(1)
		end
		if R.data == "leaveExposed" then
			T:go("U"..level)
		else
			T:go("U"..level.."C2")
		end
	end
	
	local goRight = true
	for i = 1, R.width do
		for j = 1, R.length do
			lib.clearColumn(R)
			T:forward(1)
		end
		if goRight then
			T:go("R1F1R1")
		else
			T:go("L1F1L1")
		end
		goRight = not goRight
	end
	return {}
end

local function oceanMonumentColumns(R)
	-- utility to find corners and build columns to surface
	local lib = {}
	
	function lib.buildColumn()
		local depth = 0
		while T:isWater("forward") do
			T:go("U1C2")
			depth = depth + 1
		end
		return depth
	end
	
	function lib.buildTower()
		T:go("F1C2 F1C2 F1C2")
		T:go("L1F1 L1C2 F1C2 F1C2 F1C2")
		T:go("R1F1 R1C2 F1C2 F1C2 F1C2")
		T:go("L1F1 L1C2 F1C2 F1C2 F1C2")
		
		T:go("R2")
		for i = 1, 4 do
			T:go("U1C2")
			for j = 1, 4 do
				T:go("F1C2 F1C2 F1C2 R1")
			end
		end
	end
	
	R.silent = true
	local blockType = T:getBlockType("down")
	while blockType:find("water") == nil do
		T:down(1) -- if on a platform will break through
		blockType = T:getBlockType("down")
	end
	--R.useBlockType = "prismarine", R.data = "oceanMonumentColumns" from getTask
	--local tempData = R.data
	--R.data = "clearWaterPlants"
	local result = clearWaterPlants(R)[1]
	if result ~= "" then
		return {result}
	else
		--on corner of monument, facing out to ocean
		local depth = lib.buildColumn()
		-- now above surface, block below at surface level
		for i = 1, 4 do
			T:turnRight(1)
			R.length = 57
			utils.createPath(R) -- roughly at next corner
			if i < 4 then
				T:down(depth-2) -- roughly at correct depth
				local waterBelow = utils.clearVegetation("down")
				while waterBelow do
					T:down(1)
					waterBelow = utils.clearVegetation("down")
				end
				blockType = T:getBlockType("down")
				while blockType:find("prismarine") ~= nil do
					T:forward(1)
					blockType = T:getBlockType("down")
				end
				turtle.back()
				depth = lib.buildColumn()
			end
		end
		-- completed retaining paths. Build small tower for easy access
		lib.buildTower()
	end
	
	return {}
end

local function placeRedstoneTorch(R) -- 91, 92
	local moves = 2
	local blockType = T:getBlockType("down")
	if R.data == "level" then
		T:turnLeft(1)
		utils.goBack(1)
		if blockType:find("rail") ~= nil then
			 moves = 3
		end
		T:down(moves)
		T:go("F1R1")
		--clsTurtle.place(self, blockType, damageNo, direction, leaveExisting)
		T:place(R.useBlockType, "forward", false)
		utils.goBack(1)
		T:place("minecraft:redstone_torch", "forward", true)
		T:turnLeft(1)
		utils.goBack(1)
		T:up(moves)
		T:go("F1R1F1")
	elseif R.data == "up" then -- sloping rail up/down is relative to dirtection facing
		moves = 3
		T:turnLeft(1)
		utils.goBack(1)
		if blockType:find("rail") ~= nil then
			 moves = 4
		end
		T:down(moves)
		T:go("F1L1")
		T:place("minecraft:redstone_torch", "up", false)
		
		T:turnRight(1)
		utils.goBack(1)
		T:up(moves)
		T:go("F1R1")
	end
	return {}
end

local function plantTreefarm(R) -- 23
	-- already known R.networkFarm, R.subChoice (1 = singe, 2 = double, 3 = mangrove)
	--T:place(blockType, damageNo, leaveExisting, signText)
	local lib = {}
	
	function lib.checkSaplings(firstChoice, secondChoice)
		local saplingSlot, sapling, count = T:getSaplingSlot(firstChoice)
		if count < 4  and secondChoice ~= "" then
			saplingSlot, sapling, count = T:getSaplingSlot(secondChoice)
		end
		if count == 0 then
			sapling = ""
		end
		
		return sapling, count
	end
	
	function lib.emptyInventory(R)
		if not T:isEmpty() then
			utils.useSticksAsFuel()
			network.sendItemToNetworkStorage(R, "barrel", "sapling", 64)
			network.sendItemToNetworkStorage(R, "barrel", "propagule", 64)
			network.sendItemToNetworkStorage(R, "barrel", "apple", 64)
			network.sendItemToNetworkStorage(R, "barrel", "dirt", 64)
			network.sendItemToNetworkStorage(R, "chest", "all", 0)
		end
	end
	
	function lib.getSaplingInventory(R)
		local saplings = {}
		saplings.oak_sapling = 0
		saplings.spruce_sapling = 0
		saplings.birch_sapling = 0
		saplings.jungle_sapling = 0
		saplings.acacia_sapling = 0
		saplings.dark_oak_sapling = 0
		saplings.cherry_sapling = 0
		saplings.mangrove_propagule = 0

		local firstChoice = ""
		local firstCount = 0
		local secondChoice  = ""
		local secondCount = 0
		if T:getItemSlot("sapling") > 0 then
			for i = 1, 16 do
				if turtle.getItemCount(i) > 0 then
					local data = turtle.getItemDetail(i)
					if data.name:find("sapling") ~= nil then
						local name = data.name:sub(11) -- removes "minecraft:"
						saplings[name] = saplings[name] + data.count
					end
				end
			end
		elseif T:getItemSlot("propagule") > 0 then
			saplings.mangrove_propagule = turtle.getItemCount(T:getItemSlot("propagule"))
		else	-- no saplings onBoard: ? automated networked farm
			if R.networkFarm then
				-- networked farms use 1 type of sapling indicated by log embedded to right of modem
				-- discovered from utils.assessTreeFarm() on manual Startup
				if R.auto then	-- called here as NOT manual startup
					R = utils.assessTreeFarm(R)
					if R.message ~= "" then
						return {R.message}	-- location of turtle error
					end
				end
				local turtleSlot, turtleCount = network.getItemFromNetwork("barrel", R.useBlockType, 16)
				if turtleCount == 0 then	-- ask player for saplings
					T:checkInventoryForItem({R.useBlockType}, {16}, true, "Saplings required for tree farm")
				end
				saplings[R.useBlockType] = saplings[R.useBlockType] + turtleCount
				turtleSlot, turtleCount = network.getItemFromNetwork("barrel", "minecraft:dirt", 16)
				if turtleCount == 0 then
					turtleSlot, turtleCount = network.getItemFromNetwork("chest", "minecraft:dirt", 16)
				end
				if turtleCount == 0 then	-- ask player
					T:checkInventoryForItem({"minecraft:dirt"}, {16}, true, "Dirt required for tree farm")
				end
				return saplings, R.useBlockType, R.useBlockType
			end
		end
		for sapling, count in pairs(saplings) do
			if count > firstCount then
				firstCount = count
				firstChoice = sapling
			else
				if count > secondCount then
					secondCount = count
					secondChoice = sapling
				end
			end
		end
		return saplings, firstChoice, secondChoice -- table, "oak_sapling", "dark_oak_sapling"
	end
	
	function lib.createIsland(sapling, count, exit)
		-- place 4 dirt with saplings on all 4 unless jungle
		-- sapling count/type already checked
		T:forward(2) -- assume starting outside planting area
		for i = 1, 4 do
			T:go("R1F1")
			T:place("dirt", "down", false, "", true)
		end
		T:up(1)
		if count >= 4 then
			for i = 1, 4 do
				T:go("R1F1")
				T:place(sapling, "down", false, "", true)
			end
		else
			if sapling:find("dark") == nil and sapling ~= "" then
				T:place(sapling, "down", false, "", true)
			end
		end
		if exit == "forward" then
			T:go("F1D1")
		elseif exit == "right" then
			T:go("R1F2D1")
		elseif exit == "left" then
			T:go("L1F1D1")
		elseif exit == "back" then
			T:go("R2F2D1")
		end
	end
	
	function lib.createSingle(sapling, exit)
		-- place single dirt with sapling on top
		-- sapling count/type already checked
		T:place("dirt", "down", false, "", true)
		T:up(1)
		if not T:place(sapling, "down", false, "", true) then -- try specific sapling
			T:place("sapling", "down", false, "", true)		-- any available sapling
		end
		if exit == "forward" then
			T:go("F1D1")
		elseif exit == "right" then
			T:go("R1F1D1")
		elseif exit == "left" then
			T:go("L1F1D1")
		elseif exit == "back" then
			T:go("R2F1D1")
		end
	end
	
	function lib.getMangroveSupplies()
		local turtleSlot, turtleCount = network.getItemFromNetwork("barrel", "minecraft:dirt", 169)
		if turtleCount < 169 then
			turtleSlot, turtleCount = network.getItemFromNetwork("chest", "minecraft:dirt", 169 - turtleCount)
			if turtleCount < 169 then	-- ask player for saplings
				T:checkInventoryForItem({"dirt"}, {169 - turtleCount})
			end
		end
		turtleSlot, turtleCount = network.getItemFromNetwork("barrel", "minecraft:mangrove_propagule", 25)
		if turtleCount == 0 then	-- ask player for saplings
			T:checkInventoryForItem({"mangrove_propagule"}, {25}, true, "Mangrove propagules required")
		end
	end
	
	function lib.plantMangrove()
		T:go("L1F6 R1F1 U1")
		createFloorCeiling({width = 13, length = 13, up = false, down = true,
							height = 0, subChoice = 0, useBlockType = "minecraft:dirt",
							inventory = T:getInventory()})
		
		--T:go("U1F5 R1F5 L1")			-- lower left of planting area, facing Back
		T:go("U1F4 R1F4 L1")			-- lower left of planting area, facing Back
		for x = 1, 5 do
			for i = 1, 5 do
				T:place("propagule", "down")	-- left 1
				if i < 5 then
					T:forward(1)
				end
			end
			if x % 2 == 1 then
				if x < 5 then
					T:go("R1F1R1")
				end
			else
				T:go("L1F1L1")
			end
		end
		T:go("L1F2 L1F2 D2U2 F7R2 D2")
		--[[
		T:place("propagule", "down")	-- left 1
		T:forward(1)
		T:place("propagule", "down")	-- left 2
		T:forward(1)
		T:place("propagule", "down")	-- left 3/top 1

		T:go("R1F1")
		T:place("propagule", "down")	-- top 2
		T:forward(1)
		T:place("propagule", "down")	-- top 3/right 1
		T:go("R1F1")
		
		T:place("propagule", "down")	-- right 2
		T:forward(1)
		T:place("propagule", "down")	-- right 3/bottom 1
		T:go("R1F1")
		T:place("propagule", "down")	-- bottom 2]]
		
		--T:go("R1F1R2 D2U2 F7R2 D2")
	end
	
	function lib.plantSingle(R)
		local sapling, count = lib.checkSaplings(firstChoice, secondChoice)
		if count >= 1 then
			if R.networkFarm then
				T:go("U1L1 F3R1 F4") -- outside first area
			else
				T:go("U1F4") -- outside first area
			end
			for i = 1, 3 do	-- column 1/4
				lib.createSingle(sapling, "forward")
				T:forward(1)
			end
			for i = 1, 2 do
				lib.createSingle(sapling, "right") -- place 4th dirt/saling and exit to right
				T:forward(1)
			end
			for i = 1, 2 do -- column 2/4
				lib.createSingle(sapling, "forward")
				T:forward(1)
			end
			for i = 1, 2 do
				lib.createSingle(sapling, "left") -- place 4th dirt/saling and exit to right
				T:forward(1)
			end
			for i = 1, 2 do -- column 3/4
				lib.createSingle(sapling, "forward")
				T:forward(1)
			end
			for i = 1, 2 do
				lib.createSingle(sapling, "right") -- place 4th dirt/saling and exit to right
				T:forward(1)
			end
			for i = 1, 3 do -- column 4/4
				lib.createSingle(sapling, "forward")
				T:forward(1)
			end
			if R.networkFarm then
				T:go("R1F3 R1F2L1") -- in-between 2 trees
				if R.auto then
					harvestTreeFarm(R)
				else
					T:go("L1F4R2D1")
				end
			else
				T:go("R1F6 L1F2 R2D1")
			end
		else
			return "No saplings to plant"
		end
		
		return ""
	end
	
	function lib.plantDouble(R)
		-- assume placed 4 blocks from start
		local sapling, count = lib.checkSaplings(saplings, firstChoice, secondChoice)
		
		if count >= 4 then
			if R.networkFarm then
				T:go("U1L1 F3R1 F3") -- outside first area
			else
				T:go("U1F3") -- outside first area
			end
			lib.createIsland(sapling, count, "forward")
			sapling, count = lib.checkSaplings(firstChoice, secondChoice)
			T:go("F2")
			lib.createIsland(sapling, count, "right")
			sapling, count = lib.checkSaplings(firstChoice, secondChoice)
			T:go("F2")
			lib.createIsland(sapling, count,  "right")
			sapling, count = lib.checkSaplings(firstChoice, secondChoice)
			T:go("F2")
			lib.createIsland(sapling, count, "forward")
			
			if R.networkFarm then
				T:go("R1F4 R1F1 L1") 			-- on left side of double tree
				if R.auto then
					harvestTreeFarm(R)
				else
					T:go("L1F4 L1F1 L1D1")	-- back to start
				end
			else
				T:go("R1D1 F6L1 F3R2") -- outside first area
			end
		else
			return "Insufficient saplings to plant"
		end
		return ""
	end
	
	if R.networkFarm then
		local message = network.loadStorageLists()	-- initialises or creates lists of where an item can be found: GLOBAL LISTS!
		if message ~= nil then return {message} end
		lib.emptyInventory(R)
	end
	if R.subChoice == 3 then	-- mangrove, R.networkFarm only 
		lib.getMangroveSupplies()
		lib.plantMangrove()
	else
		local saplings, firstChoice, secondChoice = lib.getSaplingInventory(R)
		if firstChoice ~= "" then
			print("first sapling: "..firstChoice .. " ("..saplings[firstChoice]..")")
		end
		if secondChoice ~= "" then
			print("second sapling: "..secondChoice .. " ("..saplings[secondChoice]..")")
		end
	
		-- check type/size of farm
		local message = ""
		if R.subChoice == 1 then 			-- 16 single trees
			message = lib.plantSingle(R)	-- always ""
		elseif R.subChoice == 2 then 		-- 4 double trees (4 saplings)
			message = lib.plantDouble(R)	-- "" or error about numbers 
		end
	end
	if R.networkFarm then
		lib.emptyInventory(R)
	end
	return {message}
end

local function quickMine(R) -- 17
	--[[
	mine valuable blocks from specified area
	if R.up set or lava/water found, ceiling is formed
	if R.down is set, or lava/water found layer is kept 1 block high
	R.subChoice
	1 At mine area start, on the floor
	2 At mine area start, on the ceiling
	3 On floor, start 1 block ahead
	4 On ceiling, start 1 block ahead
	5 On floor diagonally to left"
	]]
	local lib = {}
	
	function lib.refuel(direction)
		if T:getWater(direction)  then
			T:refuel(1000, false)
		end
	end
	
	function lib.mine(R)
		-- starts on ceiling
		local isValuable, blockType
		for i = 1, R.length do
			local fillUp = R.up
			local fillDown = R.down
			isValuable, blockType = T:isValuable("down")
			if isValuable then
				T:dig("down")
			elseif blockType:find("water") ~= nil then
				fillDown = true
			elseif blockType:find("lava") ~= nil then
				lib.refuel("down")
				fillDown = true
			end
			isValuable, blockType = T:isValuable("up")
			if isValuable then
				T:dig("up")
			elseif blockType:find("water") ~= nil then
				fillUp = true
			elseif blockType:find("lava") ~= nil then
				lib.refuel("up")
				fillUp = true
			end
			--if not turtle.detectUp() and fillUp then
			if fillUp then
				T:fillVoid("up")
			end
			--if not turtle.detectDown() and fillDown then
			if fillDown then
				T:fillVoid("down")
			end
			if i < R.length then 
				T:forward(1)
			end
		end
	end
	
	local outbound = true
	
	if R.subChoice == 1 then
		T:up(1)
	elseif R.subChoice == 3 then
		T:go("U1F1")
	elseif R.subChoice == 4 then
		T:go("F1")
	elseif R.subChoice == 5 then
		T:go("U1R1 F1L1 F1")
	end
	
	for w = 1, R.width do
		lib.mine(R)
		if w < R.width then
			if outbound then
				T:go("R1F1R1")
			else
				T:go("L1F1L1")
			end
			outbound = not outbound
		end
		if T:getFirstEmptySlot() == 0 then
			T:dumpRefuse("forward", 1)
		end
	end
	if outbound then
		T:go("L1F"..R.width - 1 .."L1F"..R.length - 1)
	else
		T:go("R1F"..R.width - 1 .."R1")
	end
	
	return {}
end

local function quickMineCorridor(R) -- 16
	--[[
	R.subChoice
	1: At corridor start, on the floor
	2: At corridor start, on the ceiling
	3: On floor, start 1 block ahead
	4: On ceiling, start 1 block ahead
	]]
	if R.subChoice == 2 then
		T:down(1)
	elseif R.subChoice == 3 then
		T:forward(1)
	elseif R.subChoice == 4 then
		T:go("D1F1")
	end
	local width = R.width - 1
	local length = R.length - 1
	R.silent = true
	R.length = length
	createCorridor(R, true) -- put floor and ceiling for R.length, place torch at start
	T:turnRight(1)
	R.length = width
	createCorridor(R, true)
	T:turnRight(1)
	R.length = length
	createCorridor(R, true)
	T:turnRight(1)
	R.length = width
	createCorridor(R, true)
	T:turnRight(1)
	
	return {}
end

local function repairWall(startAt, height, width, replaceWith)
	-- go up to startAt
	
	-- if width = 1
	
		-- for h = startAt, height, 1 do
		
			-- replace block with replaceWith ("" = any)
			
			-- move up
			
		--end
		
		-- move back to beginning
		
	-- else
	
		-- remain = height % 2
		
		-- for w = 1, width - remain do
		
			-- for h = startAt, height, 1 do
			
				-- replace block with replaceWith ("" = any)
				
				-- move up
				
			--end
			
			-- move to the right 1 block
			
			-- for i = height, startAt, -1 do
			
				-- replace block with replaceWith ("" = any)
				
				-- move down
				
			--end
			
		-- end
		
	-- end
	
end

local function getTaskItemsList()
	-- list of items required for each task
	local text = {}
	--MINING
	text[11] = {"1 ladder for each level","levels / 4 torch (optional)","levels * 4 stone"}				-- ladder to bedrock
	text[12] = {"2 stairs for each level", "6 * levels stone", "1 chest"} 								-- stairs up/down
	text[13] = {"24 torch (optional)", "1 bucket (optional)", "64 stone", "1 chest"} 					-- mine at this level
	text[14] = {"levels * 4 stone","water_bucket"} 														-- safe drop to water block
	text[15] = {"1 soul sand", "3 water bucket", "levels * 4 stone", "1-9 buckets (optional)",
				"2 signs if no ladder present"} 														-- single column bubble lift
	text[16] = {"1 bucket (optional)", "64 stone"} 														-- quick corridor
	text[17] = {"1 bucket (optional)", "64 stone"}														-- quick mine
	text[18] = {"1 bucket (optional)"}																	-- mine to bedrock
	text[19] = {"1 UNUSED diamond sword (optional)"}													-- rob mineshaft

	-- FORESTRY
	text[21] = {"1 chest (optional)"}																	-- Fell Tree
	text[22] = {"320 stone", "4 polished stone"} 														-- Create treefarm
	text[23] = {"min 4 saplings", "16 dirt"} 															-- plant treefarm
	text[24] = {"No items required"} 																	-- Harvest treefarm
	text[25] = {"width * length * 2 walls or fences", "torches (optional)", "4 barrels (optional)"}		-- fence or wall a forest
	text[26] = {"1 chest", " any saplings"} 															-- harvest and replant walled rectangle of natural forest
				
	-- FARMING			
	text[31] = {"64 stone","128 dirt (optional)", "4 water buckets","4 chests / barrels","1 sapling"}	-- Create modular crop farm
	text[32] = {"64 stone","128 dirt (optional)", "4 water buckets","5 chests/ barrels","1 sapling"}	-- extend modular farm
	text[33] = {"No items required"} 																	-- Manual harvest and auto setup
	text[34] = {"Walls or Fences", "Torches (optional)"}												-- Build a wall or fence
	text[35] = text[34]																					-- Wall or fence enclosed area

	-- OBSIDIAN
	text[41] = {"stone to cover area of obsidian"}														-- Harvest obsidian
	text[42] = {"2 x height + width obsidian", "4 stone"} 												-- build Nether portal
	text[43] = {"No items required"}																	-- demolish Nether portal
	text[44] = {"length * 4 stone/netherrack, bucket"} 													-- Netherite stripping
	text[45] = {"84 stone"} 																			-- undermine dragon towers
	text[46] = {"No items required"} 																	-- deactivate dragon tower
	text[47] = {"448 stone, 145 ladders, 1 obsidian, 1 water bucket"} 									-- dragon water trap
	text[48] = {"height * 4 stone","height * ladders", "1 trapdoor"}									-- build end portal platform
				
	--CANALS BRIDGES WALKWAYS
	text[51] = {"dirt or stone * length","torch (optional)"} 											-- single path
	text[52] = {"dirt or stone 2 * length","torch (optional)"} 											-- covered path / tunnel
	text[53] = {"2 * length stone or dirt","2 water buckets","torches (optional)"} 						-- water canal
	text[54] = {"0.5 * length Packed or blue ice","length * slabs","stone","torches (optional)"} 		-- Ice canal
	text[55] = {"width * length stone"} 																-- platform
	text[56] = {"width + 1 * length + 1 stone"} 														-- sinking platform
	text[57] = {"height * 10 stone","height * 4 + 2 soul sand, 2 water buckets"} 						-- Boat bubble lift
	
	-- MOB FARM
	text[61] = {"512 stone","1 slab"} 																	-- 9x9 cube round spawner
	text[62] = {"640 stone","37 slab","8 powered rail","64 rail","2 redstone torch",
				"1 hopper minecart","1 stone button"} 													-- 9x9 cube round blaze spawner
	text[63] = {"2 water buckets","If using bubble lift","2 fence","2 signs","1 slab",
				"1 soul sand (or dirt as placeholder)"} 												-- flood spawner chamber	
	text[64] = {"128 stone","2 water buckets","1 soul sand"} 											--Build bubble tower kill zone
	text[65] = {"1-2 computer","2 sticky or 4 normal pistons","6 network cable + 2 wired modems",
				"23 polished stone + 7 slabs","2 glass","1 stone pressure plate","1 dispenser",
				"1 hopper + 2 chest", "9 redstone", "1 lava bucket"} 									--Computercraft mob grinder
	text[66] = {"1856 stone, diorite etc (inc polished)","1 chest","10 empty buckets",
				"2 water buckets","192 fence","8 signs","3 ladder","2 soul sand"}						-- build endermen observation tower
	text[67] = {"24 blocks of any type"}																-- Cover Trial spawners to prevent mobs escaping
	
	-- AREA CARVING
	text[71] = {"width * length dirt"} 																	-- Clear field
	text[72] = {"No items required"} 																	-- Clear rectangle width, length
	text[73] = {"No items required"} 																	-- Clear wall height, length
	text[74] = {"No items required"} 																	-- Clear rectangle perimeter only width, length
	text[75] = {"No items required"}																	-- Clear structure floor/walls/ceiling
	text[76] = {"No items required"}																	-- clear solid
	text[77] = {"No items required"} 																	-- Dig a trench
	text[78] = {"No items required"} 																	-- carve mountain
	text[79] = {"width * height Any material floor / ceiling"} 											-- floor or ceiling
	text[710] =	{"Blocks to add 'floor as you go'"} 													-- Direct control of movement
				
	-- LAVA WATER
	text[81] = {"Enough sand or gravel to fill volume"} 												-- sand based utilities
	text[82] = {"length * depth stone"} 																-- vertical wall from surface
	text[83] = {"Blocks to add 'floor as you go'"} 														-- player driven path construction
	text[84] = {"width * length + extra stone"} 														-- water clearing by repeated block deletion
	text[85] = text[84] 																				-- sinking platform
	text[86] = {"Full inventories of sand or stone"}													-- Ocean monument utilities
	text[87] = {"ladder to height","stone, dirt netherrack 4 X height"} 								-- ladder to water/lava
	text[88] = {"No items required"} 																	-- clear water plants
	text[89] = {"water buckets / buckets"} 																-- convert flowing water to source
	text[810] = {"6 buckets","slabs to cover area"} 													-- create sloping water
				
	-- BUILDING and MINECART
	text[91] = {"length * height stone"}																-- Build a wall
	text[92] = {"length * height * 4 stone"}															-- build a walled area
	text[93] = {"length * width * height stairs", "length * slabs"}										-- build a gable roof
	text[94] = {"length * width * height stairs", "length * slabs"}										-- Build a pitched roof
	text[95] = {"1 block of choice","1 redstone torch"} 												-- place redstone torch under current block
	text[96] = {"1 block of choice","1 redstone torch"} 												-- place redstone torch on upward slope
	text[97] = {"height x block of choice","height/3 x redstone torch"} 								-- build downward slope
	text[98] = text[97]																					-- build upward slope
	return text
end

local function getTaskHelp(menuLevel, menuItem, noMenu, getInteger)
	-- display help about selected task
	-- terminal size = 39 x 13
--[[This line of text = 39 characters]]
	noMenu = noMenu or false
	getInteger = getInteger or false
	info = {}
	info.main = {}
	info.sub = {}
	table.insert(info.main,
	[[                ~lightGray~MINING:~white~
Can be used in over-world or nether.~brown~
Ladders and ~lightGray~stairs up/down    
Create a pre-formatted 33 x 33 blocks  
mine at chosen level.
~blue~Bubble lift and ~cyan~safe drop to water.~magenta~  
Faster version of ~white~33x33 mine pattern   
using ~magenta~corridor and ~pink~rectangle functions.~brown~
Mine bottom layer to bedrock (not worth
the fuel and time)
~brown~Strip resources from abandoned mines.
]])
	table.insert(info.main,
	[[               ~lime~FORESTRY:~brown~
Fell Tree can be used in Nether as well
for cutting any size tree / branches~lime~
Create a simple 16 single tree farm
or 4 double size (Dark oak or any type)
suitable for turtle harvesting.
~brown~ fence or wall a rectangle keeping
to contours.
~green~Forest can be harvested and replanted.
(Must be walled off)

]])
	table.insert(info.main,
	[[                ~green~FARMING:~yellow~
Farm modules can be built to fixed size
and placed next to each other in linear
or rectangular pattern.~lime~
Whole farm is managed by a dedicated
turtle, which must be equipped with a
diamond hoe as well as pickaxe.
Fuel obtained from a tree placed in the
corner of each module.
Double chests store produce and seeds.
]])
	table.insert(info.main,
	[[               ~red~OBSIDIAN:~lightGray~
The turtle can extract obsidian from
lava areas safely.~pink~
Nether portals can be built or removed
without needing diamond pickaxes.~orange~
End World dragon towers can be
undermined ready for deactivating.
End world towers can have the crystals
destroyed.~red~
Water trapped dragon attacked from above~brown~
Minecart end portal stations built.
]])
	table.insert(info.main,
	[[        ~brown~PATHS, BRIDGES, CANALS:~white~
Can be used in Nether and End.~lightGray~
Build pathways over air, water or lava
Optional roofed pathway for Nether use.
Tunnel through rock and place a floor
at the same time.~blue~
Build a water canal with towpath.~cyan~
Build a super-fast ice canal.~brown~
Platform for use over air, water, lava
Sinking version is removed and replaced
1 block lower each time
]])
	table.insert(info.main,
	[[             ~lightGray~SPAWNER FARMS:~brown~
Tools to create mob farms round
existing spawners. ~red~
Special version for Blaze farms
uses rail collection.~cyan~
Choice of bubble lift mob dropper
or ~brown~simple deep trench.~gray~
Enderman observation tower can be
built >128 above ground: is ~red~expensive.~gray~
Re-spawns new mobs when used.~red~
Suggest build only the base.
]])
	table.insert(info.main,
	[[    ~orange~AREA CLEARING AND REFORMING:~lime~
Tools to clear a field including trees~magenta~
Clear rectangles.~pink~
Clear single walls.~brown~
Clear hollow and~orange~solid structures.~brown~
Dig a trench.~gray~
Carve away side of a mountain.~lightBlue~
Place or replace floors and ceilings



]])
	table.insert(info.main,
	[[      ~blue~WATER AND LAVA TOOLS:~white~
Used to drain ocean monuments and
shipwrecks. Can also be used to make
underwater base. ~blue~Water is cleared using
sand dropping and recycling~cyan~
Destructive draining uses solid block
placing and recycling.~green~
Water plants can be removed without
damaging structures.~lightBlue~
Tools to manipulate water areas:
(convert to source, sloping water)
]])
	table.insert(info.main,
	[[         ~cyan~BUILDING, MINECART TOOLS:~lightGray~
Build simple walls, buildings and ~gray~roofs

~orange~Used to build diagonal uphill slope~brown~
and downhill slope for placing
45 degree rail tracks.~red~
Placing Redstone torches under powered
rails when above ground level (viaduct)



]])
	table.insert(info.main,
	[[           ~yellow~MEASURING TOOLS:
Used to measure
    ~red~Height
    ~purple~Depth
    ~magenta~Length~pink~
	
    Greatest depth of water




]])
	table.insert(info.main,
	[[           ~yellow~NETWORK TOOLS:
Still on ToDo List!



	





]])

	info.sub[11] = 
[[~yellow~Place me on the ground at ~red~^~yellow~
The ~brown~ladder ~yellow~will start at this level
and go up or down.

~lightGray~| | | | | |
~lightGray~| | |*| | | * = Ladder support block
| | |~brown~L~lightGray~| | | ~brown~L = Ladder
~lightGray~| | |~red~^~lightGray~| | | ~red~^ = Turtle
~lightGray~| | | | | |
| | | | | |

]]-- Ladder up/down
	info.sub[12] = 
[[~lightGray~Place me on the ground at ~red~^

~lightGray~| | | | | | | | * = Solid block
~lightGray~| |*|*|*|*|*| | ~cyan~^ = Stairs to back
~lightGray~| |*|-|~cyan~>~lightGray~|-|*| | ~cyan~> = Stairs to right
~lightGray~| |*|~cyan~^|~lightGray~*|~cyan~V~lightGray~|*| | ~cyan~V = Stairs to front
~lightGray~| |*|-|~cyan~<~lightGray~|-|*| | ~cyan~< = Stairs to left
~lightGray~| |*|~red~^~lightGray~|*|*|*| | - = Corner tread
~lightGray~| | | | | | | | ~red~^ = Turtle

~lightGray~Going ~blue~down~lightGray~ -> digs down then stairs up
]] -- Stairs up/down
		info.sub[13] = 
[[~yellow~Press F3 to check Y level.

~lightGray~| |~red~^~lightGray~| | | ~red~^ = Turtle behind ladder
~lightGray~| |~gray~s~lightGray~| | | ~gray~s = 1 block space
~lightGray~| |*| | | * = Ladder support block
~lightGray~| |~brown~L~lightGray~| | | ~brown~L = Ladder
~lightGray~| |~brown~s~lightGray~| | | ~brown~s~gray~ = 2 spaces (inc. ladder)
~lightGray~| |~red~V~lightGray~| | | ~red~V = Turtle ahead of ladder~yellow~

]]
	if bedrock == 0 then	--pre 1.18
		info.sub[13] = info.sub[13].."Place at Y = 5, 8, 11 ~red~(11 nether)" -- Create mine at this level
	else
		info.sub[13] = info.sub[13].."Place at Y = -59, -56, -53 (11 nether)" -- Create mine at this level
	end
	info.sub[14] = 
[[~yellow~Turtle goes ~blue~DOWN ~yellow~to chosen level
enclosing all sides of the column.
Water placed at bottom. Returns here.
If next to a ladder, place as below:

~lightGray~| | | | | |
~lightGray~| | |*| | | * = Ladder support block
| |~red~^~brown~|L|~red~^~lightGray~| | ~brown~L = ladder
~lightGray~| | | | | | ~red~^ = Turtle facing forward
~lightGray~| | | | | |
		   
]] -- safe drop
	info.sub[15] = 
[[~magenta~Direction of travel = UP!
~yellow~Place me on the ground. I will build a
3 x 1 ~blue~water ~yellow~source and a single column
bubble lift to the chosen height.
If near a ladder, place left or right:

~lightGray~| | | | | |
~lightGray~| | |*| | | * = Ladder support block
| |~blue~^~brown~|L|~blue~^~lightGray~| | ~brown~L = ladder
~lightGray~| | | | | | ~blue~^ = Turtle facing forward
~lightGray~| | | | | | ~blue~^ = Bubble column above

]] -- single column bubble lift
	info.sub[16] = 
[[~yellow~Place me as below:
 1. On ~blue~floor   ~yellow~(feet height)
 2. On ~lime~ceiling ~yellow~(eye height)

~lightGray~B|B|B|B|B|B|B    ~yellow~W I D T H
~lightGray~B| | | | | |B               ~orange~L
~lightGray~B| |B|B|B| |B               ~orange~E
~lightGray~B| |B|B|B| |B               ~orange~N
~lightGray~B| |B|B|B| |B               ~orange~G 
~lightGray~B|~red~^~lightGray~| | | | |B  ~red~^~lightGray~ = Turtle   ~orange~T
~lightGray~B|~cyan~P~lightGray~|B|B|B|B|B  ~cyan~P~lightGray~ = Player   ~orange~H
]] -- quick corridor system
	info.sub[17] = 
[[~yellow~~yellow~Place me as below:
 1. On ~blue~floor   ~yellow~(feet height)
 2. On ~lime~ceiling ~yellow~(eye height)
~lightGray~B|B|B|B|B|B|B 
B| | | | | |B
B| |B|B|B| |B
B| |B|B|B| |B
B| |~lime~^~lightGray~|B|B| |B
B|~red~^~lightGray~|~magenta~^~lightGray~| | | |B ~white~^~lightGray~ = turtle
B|~cyan~P~lightGray~|B|B|B|B|B ~cyan~P~lightGray~ = Player
~yellow~Note colour of ~white~^~yellow~ matches next screen->
]] -- quick mine
		info.sub[18] = 
[[~yellow~Place me level -59 / 5 on the floor to
expose bedrock ~red~(slow and inefficient)

~lightGray~| | | |B| |B|     ~yellow~W I D T H
~lightGray~|B| | | | | |B               ~orange~L
~lightGray~| | | |B|B| |                ~orange~E
~lightGray~| | |B| | |B|                ~orange~N
~lightGray~|B| | | |B| |                ~orange~G 
~lightGray~| | | | | | |B               ~orange~T
~lightGray~|~red~^~lightGray~| | | |B| |B  ~red~^~lightGray~ = Turtle   ~orange~H
]] -- mine all blocks to bedrock pre 1.12
		info.sub[19] = 
[[~yellow~Place me on the end wall of a disused
mine in the centre block, 1 block above
the floor.
Provide a ~cyan~diamond ~yellow~sword for
harvesting string from spider webs~lightGray~

~gray~-------   - = Ceiling
~lightGray~| | | |
| |~red~T~lightGray~| |  ~red~T = Turtle (facing wall)
~lightGray~| | | |
~gray~-------  - = Floor
]] -- salvage mineshaft
	info.sub[21] = 
[[~yellow~Place me as below.
~brown~Chest ~yellow~ONLY required if ~blue~0 ~yellow~fuel

Plan view:

~green~   | | | |
~green~   | |~lime~T~green~| |  ~lime~T = Tree
~green~   | |~red~^~green~| |  ~red~^ = Turtle
~green~   | | | |



]] -- Fell Tree
	info.sub[22] = 
[[~yellow~New, extend left/back=~red~^ ~orange~Extend Right=^
~lightGray~|*|~blue~ | | | | | | ~brown~|D| |D| ~blue~| | ~lightGray~|*|
~lightGray~|*|~blue~ | | ~brown~|D|D|~blue~ | | | | | | | ~lightGray~|*|
~lightGray~|*|~blue~ | | ~brown~|D|D|~blue~ | ~brown~|D| |D| ~blue~| | ~lightGray~|*|
~lightGray~|*|~blue~ | | | | | | | | | | | | ~lightGray~|*|
~lightGray~|*|~blue~ | | | | | | | | | | | | ~lightGray~|*|
~lightGray~|*|~blue~ | | | | | | | | | | | | ~lightGray~|*|
~lightGray~|~red~^~lightGray~|*|*|*|*|*|*~magenta~|M|~lightGray~*|*|*|*|*|*|~orange~^|
~lime~4 ~brown~double trees~green~ or 16 ~brown~single trees
~brown~D = Dirt, ~magenta~M = Modem
~red~^~yellow~ = Turtle ~red~(new/left/back) ~orange~^ on right
]] -- Create treefarm
	info.sub[23] = 
[[~yellow~Place me on ground as below ~lightGray~^ ~magenta~^
~lime~|*|~blue~ | | | | | | | ~green~or |*|~blue~ | | ~brown~|D| |D| |
~lime~|*|~blue~ | | ~brown~|D|D|~blue~ | | ~green~or |*|~blue~ | | | | | | |
~lime~|*|~blue~ | | ~brown~|D|D|~blue~ | | ~green~or |*|~blue~ | | ~brown~|D| |D| |
~lime~|*|~blue~ | | | | | | | ~green~or |*|~blue~ | | | | | | |
~lime~|*|~blue~ | | | | | | | ~green~or |*|~blue~ | | | | | | |
~lime~|*|*|*|*|~lightGray~^~lime~|*| ~magenta~|^| ~green~or |*|*|*|*|~lightGray~^~green~|*|*~magenta~|^|
~lime~ 4 ~brown~double trees~green~   or  16 ~brown~single trees
~brown~D = dirt
~lightGray~^ = Turtle on marker (Legacy storage)
~magenta~^ = Turtle on Modem (Network storage)
]] -- Plant treefarm / Harvest treefarm
	info.sub[24] = info.sub[23] 
	info.sub[25] =
[[~yellow~Place me at ~red~^

~lightGray~|F|F|F|F|F|F|F| F = Fence or Wall
~lightGray~|F|~brown~B~lime~| | | |~brown~B~lightGray~|F| ~brown~B = Barrel (corners)
~lightGray~|F|~lime~ | | | | ~lightGray~|F|
~lightGray~|F|~lime~ | | | |~cyan~T~lightGray~|F| ~cyan~T = Tree
~lightGray~|F|~lime~ |~cyan~T~lime~| | | ~lightGray~|F|
~lightGray~|F|~lime~ | | | | ~lightGray~|F|
~lightGray~|F|~brown~B~lime~| |~cyan~T~lime~| |~brown~B~lightGray~|F| 
~lightGray~|~red~^~lightGray~|F|F|F|F|F|F| ~red~^ = Turtle
~yellow~Fence/Wall follows land contours
]] -- 
	info.sub[26] =
[[~yellow~A rectangular walled area of forest:
Place me at ~red~^

~lightGray~|F|F|F|F|F|F|F| F = Fence or wall
~lightGray~|F|~brown~B~lime~| | | |~brown~B~lightGray~|F| ~brown~B = Barrel (corners)
~lightGray~|F|~lime~ | | | | ~lightGray~|F|
~lightGray~|F|~lime~ | | | |~cyan~T~lightGray~|F| ~cyan~T = Tree
~lightGray~|F|~lime~ |~cyan~T~lime~| | | ~lightGray~|F|
~lightGray~|F|~lime~ | | | | ~lightGray~|F|
~lightGray~|F|~red~^~lime~| |~cyan~T~lime~| |~brown~B~lightGray~|F| ~red~^ = Turtle ~brown~(on Barrel)
~lightGray~|F|F|F|F|F|F|F|

]] -- manage walled forest
	info.sub[31] = 
[[~yellow~Place me on the ground as below ~red~^

~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| | ~lightGray~* = Wall
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| |
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| |
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| | 
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| | ~magenta~M = Modem
~brown~|B|B~green~| | |~lightGray~or |*| ~green~| | ~brown~B = Barrel or Chest
~brown~|B|~blue~W~green~| | |~lightGray~or ~magenta~|M|~blue~W~green~| | ~blue~W = Water
~lime~|~red~^~lime~|~brown~B|B|~lightGray~*|or ~brown~|~red~^~brown~|~magenta~M|~lightGray~*| ~red~^ = Turtle
~brown~Legacy   ~lightGray~or ~magenta~Network ~yellow~Size = 12 x 12
]] -- Create modular crop farm
	info.sub[32] = 
[[~yellow~Place on any ~brown~T ~blue~T ~magenta~T~yellow~ facing < > ^ v

~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| | ~lightGray~* = Wall
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| |
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| |
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| | ~magenta~M = Modem
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| | ~brown~B = Barrel or Chest
~brown~|B|B~green~| | |~lightGray~or |*| ~green~| | ~blue~W = Water
~brown~|B~blue~|T| ~green~| |~lightGray~or ~magenta~|M|~blue~T~green~| | ~orange~S = Sapling or Tree
~orange~|S|~brown~T|B|~lightGray~*|or ~brown~|B~magenta~|T|~lightGray~*| ~brown~T ~lightGray~= Turtle (~blue~T ~magenta~T~lightGray~)
~brown~Legacy   ~lightGray~or ~magenta~Network ~yellow~Size = 12 x 12
]] -- Extend farm
	info.sub[33] = 
[[~yellow~Place as below ~blue~T~yellow~ facing < > ^ v

~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| | ~lightGray~* = Wall
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| |
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| |
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| | ~magenta~M = Modem
~lightGray~|*|~green~ | | |   ~lightGray~|*| ~green~| | ~brown~B = Barrel or Chest
~brown~|B|B~green~| | |~lightGray~or |*| ~green~| | C = Crop (first)
~brown~|B|~blue~T~green~|C| |~lightGray~or ~magenta~|M|~blue~T~green~|C| ~orange~S = Sapling or Tree
~orange~|S|~brown~B|B|~lightGray~*|or ~magenta~|M|~brown~B|~lightGray~*| ~blue~T = Turtle on Water
~yellow~Options to harvest or manage to follow.
]] -- Manual harvest and auto setup
	info.sub[34] = 
[[~yellow~Build a ~brown~fence ~yellow~or ~lightGray~wall ~yellow~to chosen length.

Turtle goes ~orange~BACKWARDS ~yellow~when started.

Start: length = 6, Turtle facing right

~lightGray~| |~red~>~lightGray~| | | | | | | ~red~> = Turtle

Finish:

~lightGray~| |F|F|F|F|F|F| | F = Fence or Wall
]] -- build fence or wall
	info.sub[35] = 
[[~yellow~Build a ~brown~fence ~yellow~or ~lightGray~wall ~yellow~
rectangular area.

~lightGray~| | | | | | | | ~brown~F = Fence or Wall
~lightGray~| ~brown~|F|F|F|F|F~lightGray~| |
~lightGray~| ~brown~|F| | | |F~lightGray~| |
~lightGray~| ~brown~|F| | | |F~lightGray~| |
~lightGray~| ~brown~|F| | | |F~lightGray~| |
~lightGray~| |~red~^~brown~|F|F|F|F| | ~red~^ = Turtle
~lightGray~| | | | | | | |

]] -- build rectangular fence or wall
	info.sub[41] = 
[[~yellow~Place me on any block on the left 
side facing the obsidian field.

~gray~|O|O|O|O|O| O = Obsidian
|O|O|O|O|O|
|O|O|O|O|O|
|O|O|O|O|O|
|~red~^~gray~|O|O|O|O| ~red~^ = Turtle
|~red~^~gray~| | | | |

]] -- Harvest obsidian
	info.sub[42] = 
[[~yellow~Place me on the ground as below ~red~> ~pink~^
~yellow~Start ~red~> ~yellow~(facing right) or ~pink~^ ~yellow~ahead
  
~lightGray~| |~red~>~lightGray~|O|O|*| | |    |*|O|O|*| face view             
   ~pink~^~lightGray~               |O|~purple~+ +~lightGray~|O|
                   |O|~purple~+ +~lightGray~|O|
~yellow~Result (plan)      ~lightGray~|O|~purple~+ +~lightGray~|O|
~lightGray~| |O|O|O|O| | |    |*|O|O|*|
                   ~green~--------- ground
~yellow~width=4, ~orange~height=5 ~red~(frame size)
]] -- build Nether portal
	info.sub[43] = info.sub[42] -- Demolish Nether portal
	info.sub[44] = 
[[~yellow~Press F3+G for chunk boundaries
Netherite stripmine plan view
               
~lightGray~|*|*|*~lime~N~lightGray~*|*|*|
~lightGray~|*|*|*~lime~|~lightGray~*|*|*| ~lime~-| = Chunk Boundaries
~lightGray~|*|~red~^~lightGray~|*~lime~|~lightGray~*|~red~^~lightGray~|*|  ~red~^ = Turtle
~lime~W*-*-*~blue~+~lime~*-*-*E  ~blue~+ = Boundaries junction
~lightGray~|*|*|*~lime~|~lightGray~*|*|*|
~lightGray~|*|*|*~lime~|~lightGray~*|*|*|  ~yellow~North of WE
~lightGray~|*|*|*~lime~S~lightGray~*|*|*|  ~yellow~1 block from NS
Most generate close to chunk boundaries
]] -- Netherite stripping
	info.sub[45] = 
[[~yellow~Place me on the ground ~red~<~yellow~ facing ~red~West.

~lime~x
                 ~lightGray~N
~lime~a~lightGray~   -1        | | | |  
~lime~x~lightGray~    0       ~red~W~lightGray~| |~red~<~lightGray~| |E  ~red~< = Turtle
~lime~i~lightGray~    1        | | | |  
~lime~s~lightGray~                S
    ~green~z axis    ~lightGray~-1 0 1
  
Centre of the dragon arena ~lime~X = 0, ~green~Z = 0
~yellow~                           facing ~red~West 
]] -- Find dragon tower centres
	info.sub[46] = 
[[~yellow~Place turtle in ceiling facing endstone

Plan view    Side view
~gray~             |*|*|*|*|*|
    |*|      |*|*|*|*|*|
  |*|*|*|    |*|*|*|*|*|
|*|*|*|*|*|  |*|*|*|*|*|  * ~lightGray~= Obsidian
~gray~|*|*|~yellow~E~gray~|*|*|  |*|*|*|*|*|  ~yellow~E ~lightGray~= Endstone
~gray~  |*|~red~^~gray~|*|    |*|*|~red~T~gray~|*|*|~red~ ^T ~lightGray~= Turtle
~gray~    |*|      |*|*| |*|*|
             |*|*| |*|*|
]] -- deactivate dragon tower
	info.sub[47] = 
[[~yellow~Place turtle on the ground at 100,49,0

|*|*|*|*|*|*|*|*|*|   ~lightGray~= Dragon Island


~yellow~    Facing WEST
~gray~    |*|*|*|*|*|     * ~lightGray~= Obsidian plate
~gray~    |*|*|*|*|*|
~yellow~  S ~gray~|*|*|~red~T~gray~|*|*| ~yellow~N   ~red~T ~lightGray~= Turtle
~gray~    |*|*|*|*|*|
    |*|*|*|*|*|
~yellow~         E]] -- build dragon water trap
	info.sub[48] = 
[[~yellow~Place turtle under end world portal

~gray~        |B|     B ~lightGray~= Bedrock
~gray~      |B|B|B|
        ~purple~|P|     P ~lightGray~= Portal
~gray~      |B|B|B|
        |B|
         ~green~|		
         ~green~|      ~lime~Height measured first		
         ~green~|		
~red~         T	     T ~lightGray~= Turtle	
~yellow~  |*|*|*|*|*|*| ~red~Inventory AFTER height
]] -- build end portal minecart
	
	info.sub[491] = 
[[~yellow~Place turtle <64 blocks from shulker
Directly below or 1 block in front
~lightGray~|*|*|*|*|*|*|*|
     ~gray~> ~lime~S ~gray~<       > T < = kill positions
       ~gray~T



     ~red~> T <       Attacks ahead / above
~lightGray~|*|*|*|*|*|*|*|

~red~> T <~lightGray~ = Turtle   ~lime~S~lightGray~ = Shulker]] -- Shulker is above

	info.sub[492] = 
[[~yellow~Place turtle <64 blocks from shulker
Same level, or 1 block above/below
Plan view:
   ~red~>~lightGray~ | | | | | |~lime~S~lightGray~|
  
~yellow~Side view:
   ~red~T~lightGray~ | | | | | |~gray~T~lightGray~|
   ~red~T~lightGray~ | | | | |~gray~T~lightGray~|~lime~S~lightGray~|   ~gray~T = kill positions
   ~red~T~lightGray~ | | | | | |~gray~T~lightGray~|
   
 ~red~> T~lightGray~ = Turtle   ~lime~S~lightGray~ = Shulker]] -- Shulker is ahead
	
	info.sub[493] = 
[[~yellow~Place turtle <64 blocks from shulker
Directly above or 1 block in front
~lightGray~|*|*|*|*|*|*|*|
     ~red~> T <       Attacks ahead / below



       ~gray~T
     ~gray~> ~lime~S ~gray~<       > T < = kill positions
~lightGray~|*|*|*|*|*|*|*|

~red~> T <~lightGray~ = Turtle   ~lime~S~lightGray~ = Shulker]] -- Shulker is below

	info.sub[494] = 
[[~yellow~Place turtle in entry pit centre wall

~lightGray~|*|~orange~+~lightGray~| | |~red~+~lightGray~| | |~lime~S~lightGray~|*| ~lime~S~lightGray~ = Shulker
~lightGray~|*|~orange~+~lightGray~| |~lime~S|~red~+~lightGray~| | |~blue~+~lightGray~|*| T = turtle places
~lightGray~|*|~orange~+~lightGray~| | |~red~+~lightGray~| | |~blue~+~lightGray~|*|
~lightGray~|*|~orange~+~lightGray~| | |~red~+~lightGray~| | |~blue~+~lightGray~|*|     ~yellow~Plan view
~lightGray~|*|~orange~+|+|+|~red~+|~blue~+|+|+~lightGray~|*|    |*|*|*|*|*|
~lightGray~|*|*|*|~orange~+|~red~+|~blue~+~lightGray~|*|*|*|    |*| |~red~T~lightGray~| |*|
~lightGray~|*|*|*|~orange~T|~red~T|~blue~T~lightGray~|*|*|*|    |*|~orange~T~lightGray~| |~blue~T~lightGray~|*|
~lightGray~|*|*|*| | | |*|*|*|    |*| |~red~T~lightGray~| |*|
                       |*|*|*|*|*|]] -- Climb tower wall

	info.sub[495] = 
[[~yellow~Place turtle in corner against ceiling
Face ~red~direction ~yellow~shown. It will exit up,
clear the roof above and return

~lightGray~|*|*|*|*|*|*|*|*|*|*|  ~yellow~Clears 15x15
~lightGray~|*|~red~<~lightGray~| | | | | | |~red~^~lightGray~|*|  ~yellow~area regardless
~lightGray~|*| | | | | | | | |*|  ~yellow~of actual size

~lightGray~|*| | | | | | | | |*|
~lightGray~|*|~red~V~lightGray~| | | | | | |~red~>~lightGray~|*|
~lightGray~|*|*|*|*|*|*|*|*|*|*|]] -- Clear roof above

	info.sub[496] = 
[[~yellow~Place turtle in corner against ceiling
Face ~red~direction ~yellow~shown. It will exit out,
clear 4 outside walls and return.

~lightGray~|*|*|*|*|*|*|*|*|*|*|  ~yellow~Size calculated
~lightGray~|*|~red~<~lightGray~| | | | | | |~red~^~lightGray~|*|  ~yellow~automatically.
~lightGray~|*| | | | | | | | |*|

~lightGray~|*| | | | | | | | |*|
~lightGray~|*|~red~V~lightGray~| | | | | | |~red~>~lightGray~|*|
~lightGray~|*|*|*|*|*|*|*|*|*|*|]] -- Clear outside wall

	info.sub[51] = 
[[~yellow~Place me on the ground as below ~red~^

~yellow~Start:~blue~  |-|-|-|    - = air/water
~orange~        |-|-|-|    - = lava
~blue~        |-|-|-|
~lightGray~        |*|~red~^~lightGray~|*|    ~red~^ = Turtle

~yellow~Result:~blue~ |-|~lightGray~*|~blue~-|    - = air/water
~orange~        |-|~lightGray~*|~orange~-|    - = lava
~blue~        |-|~lightGray~*|~blue~-|
~lightGray~        |*|*|*|    * = Solid block
]] -- Single path
	info.sub[52] = 
[[~yellow~Place ~red~^ T~yellow~ at start of path or tunnel

~yellow~Plan view    Face view

~lightGray~|*|~green~*~lightGray~|*|      *|*|*|*|*   ~green~* = new block
~lightGray~|*|~green~*~lightGray~|*|      *|*|~green~*~lightGray~|*|*
~lightGray~|*|~green~*~lightGray~|*|      *|*| |*|*
~lightGray~|*|~green~*~lightGray~|*|      *|*|~red~T~lightGray~|*|*   ~red~^ T = Turtle
   ~red~^~lightGray~         ~green~- - * - -   ground

~green~Floor + ceiling ~yellow~placed for your safety!
]] -- Covered walkway / tunnel
	info.sub[53] = 
[[~yellow~plan view

~lightGray~|*|~blue~-|-~lightGray~|*|
~lightGray~|*|~blue~-|-~lightGray~|*|    ~yellow~Cross section view
~lightGray~|*|~blue~-|-~lightGray~|*|     ~lime~1 ~orange~2 ~brown~3 ~green~4  ~lightGray~= on ground
~lightGray~|~lime~^~lightGray~|~blue~^~lightGray~|~cyan~^~lightGray~|~green~^~lightGray~|    |*|~blue~5~lightGray~|~cyan~6~lightGray~|*| ~lightGray~= in water

~yellow~New canal       ~lime~1 ~orange~2 ~brown~3 ~green~4 ~yellow~ground level-63
~yellow~Extend existing ~lime~1     ~green~4 ~yellow~ground level-63
~yellow~Extend existing   ~blue~5 ~cyan~6   ~yellow~water  level-62
]] -- new/existing canal
	info.sub[54] = 
[[~lime~New ~yellow~ice canal or ~lightBlue~convert ~yellow~existing water

~lightGray~ |*| | |*| 	 * = Slab
~lightGray~ |~orange~T~lightGray~|~blue~I~lightGray~| |*| 	 ~blue~I = Ice (packed or blue)
~lightGray~ |*| | |*| 	| | = Air (empty block)
~lightGray~ |*|~blue~I~lightGray~| |~orange~T~lightGray~|   ~orange~T = Torch (optional)
~lime~  1 2 3 4    New ice canal
~lightBlue~  5 6 7 8    Convert water canal

~red~All turtles placed at ground level!
~lime~1-4 ~lightGray~for ~lime~new ~lightGray~canal ~lightBlue~5-8 ~lightGray~to ~lightBlue~convert ~lightGray~water
]] -- ice canal
	info.sub[55] = 
[[~yellow~Place ~red~^~yellow~ any level air, water or lava.~lightGray~

| | | | | | | |
| |*|*|*|*|*| |  * = Block
| |*|*|*|*|*| |
| |*|*|*|*|*| |
| |*|*|*|*|*| |
| |~red~^~lightGray~|*|*|*|*| |  ~red~^ = Turtle~lightGray~
| | | | | | | |

Blocks placed under the turtle
]] -- Platform
	info.sub[56] = 
[[~yellow~Place ~red~^~yellow~ above water.~lightGray~
Existing platform replaced below

| |*|*|*|*|*| |  * = Block
| |*|*|*|*|*| |
| |*|*|*|*|*| |
| |*|*|*|*|*| |
| |~red~^~lightGray~|*|*|*|*| |  ~red~^ = Turtle~lightGray~
| | | | | | | |

Blocks placed under the turtle
]] -- Sinking platform
	info.sub[57] = 
[[~yellow~Boat Lift (Ice or Water)
Place turtle left side. ~blue~Source~yellow~ to right

Start~lightGray~        |*|~blue~ | ~lightGray~|*| ~yellow~Finish
~lightGray~             |*|~blue~ | ~lightGray~|*|
             |*|~cyan~S|S|~lightGray~*| ~cyan~S ~lightGray~= Soul sand
|*|*|*|*|    |*|~brown~S|S~lightGray~|*| ~brown~S = ~lightGray~Sand + gate
|~red~^~lightGray~|~blue~W|W~lightGray~|*|    |*~blue~|W|W|~lightGray~*| ~red~^ ~lightGray~= Turtle
|*|~blue~W|W~lightGray~|*|    |*|~blue~W|W~lightGray~|*|
|*|~blue~ | ~lightGray~|*|    |*|~blue~ | ~lightGray~|*| ~yellow~Ice canal needs
~lightGray~|*|~blue~ | ~lightGray~|*|    |*|~blue~ | ~lightGray~|*| ~yellow~2x2 water source
]] -- boat bubble lift
	info.sub[61] = 
[[~red~NOT ~yellow~for Blaze spawners!
Plan view          Side view~lightGray~
    T       T      T = Outside dungeon
 |*|*|*|*|*|*|*|   |*|~brown~1~lightGray~|*|*|*|~yellow~2~lightGray~|*| Top
T|*| | | | | |*|T  |*| | | | | |*|
 |*| | |~magenta~5~lightGray~| | |*|   |*| | |~magenta~5~lightGray~| | |*|
 |*| |~magenta~5~lightGray~|~orange~S~lightGray~|~magenta~5~lightGray~| |*|   |*|~lime~3~lightGray~|~magenta~5|~orange~S~lightGray~|~magenta~5|~green~4~lightGray~|*| Base
 |*| | |~magenta~5~lightGray~| | |*|
T|*| | | | | |*|T  * = Dungeon Wall
 |*|*|*|*|*|*|*|   ~orange~S = Spawner
~lightGray~    T       T      T = Turtle ~brown~1 ~yellow~2 ~lime~3 ~green~4
~magenta~5~lightGray~ = On top or adjacent (0 chests only)
]] -- 9x9 cube round spawner
	info.sub[62] = 
[[~yellow~Place turtle as indicated:
Plan view          Side view

~lightGray~|*|*|*|*|*|*|*|*|  ~lime~> T = Continue build
~lightGray~|*| | | | | | | |  ~red~< T = New build
~lightGray~|*| | | | | | | |
|*| | | |~purple~S~lightGray~| | | |~lime~>~red~<          T
~lightGray~|*| | | | | | | |   |*| | | |~purple~S~lightGray~| | | |~red~T
~lightGray~|*| | | | | | | |   |*| | | | | | | |
~lightGray~|*| | | | | | | |   |*| | | | | | | |
~lightGray~|*|*|*|*|*|*|*|*|   |*| | | | | | | |~lime~T
                                     ~red~T]] -- 9x9 cube round blaze spawner
	info.sub[63] = 
[[~yellow~ Plan view (truncated)    Side view

~lightGray~ |*| | | | | | | | | |*|  |*| | | | | |
~red~>~lightGray~|*| | | | |~purple~S~lightGray~| | | | |*|~red~<~lightGray~ |*| | | | |~purple~S~lightGray~|
 |*| | | | | | | | | |*|  |*| | | | | |
 |*| | | | | | | | | |*|  |*| | | | | |
 |*| | | | | | | | | |*|  |*| | | | | |
 |*| | | | | | | | | |*|  |*| | | | | |
 |*|*|*|*|*|*|*|*|*|*|*| ~red~T~lightGray~|*|*|*|*|*|*|
            ~red~^
~purple~S ~lightGray~= Spawner ~red~<> ^ T ~lightGray~= Turtle
]] -- Flood spawner chamber
	info.sub[64] = 
[[~yellow~Bubble lift: Plan view at start~lightGray~
 |*| | | | | | | | | |*|
 |*| | | | |~brown~F~lightGray~| | | | |*|
 |*|*|*|*|*|~brown~F~lightGray~|*|*|*|*|*|  ~brown~F ~lightGray~= Fence
           ~brown~|~red~^~brown~|~lightGray~= Turtle on ~brown~Soul Sand
		   
~yellow~Plan view completed~lightGray~		   
 |*| | | | |~brown~F~lightGray~| | | | |*|
 |*|*|*|*|*|~brown~F~lightGray~|*|*|*|*|*|  ~brown~F ~lightGray~= Fence
~yellow~kill zone~lightGray~|*|~blue~S~lightGray~|*|~yellow~kill zone ~lightGray~Left / Right
           ~lightGray~|*|        ~blue~S ~lightGray~= Bubble lift
]] -- Build bubble tower kill zone
	info.sub[65] = 
[[~yellow~Computercraft mob grinder

Plan view~lightGray~ |*~blue~| | | | | | | | | |~lightGray~*|
          |*~blue~| | | | | | | | | |~lightGray~*|
          |*|*|*|*|*~blue~| |~lightGray~*|*|*|*|*| Front
~red~T~yellow~urtle facing out    ~red~V~lightGray~              
                          
~yellow~Side view ~lightGray~|*|*|*|*|*|*|*|*|*|*|*|
          |*|*|*|*|*|*|*|*|*|*|*|
          |*|*|*|*|*|*|*|*|*|*|*|
~red~E~yellow~xit hole ~lightGray~|*|*|*|*|*|~red~T~lightGray~|*|*|*|*|*|
          ~gray~|*|*|*|*|*|*|*|*|*|*|*| Base
]] -- Computercraft mob grinder
	info.sub[66] = 
[[This is a 3 stage process:
1.New tower lower base: place me on
flat ground in open plain.

2.Upper base: place me in front of
the existing chest at tower base.

3.Main tower, only needed to respawn
mobs. Expensive, not recommended.
Place me in front of chest in ground.
]] -- Build endermen observation tower
	info.sub[67] = 
[[Turtle moves toward spawner
Place at spawner level.

Can be behind a wall for protection
of player.

Embeds in wall with attack working

Needs 24 blocks

]] -- Build 3*3*3 wall around trial spawner

	info.sub[71] = 
[[~yellow~Clear field

~lightGray~| | | | | |  Remove ~lime~trees ~lightGray~and ~pink~flowers
~lightGray~| | | | | |  Fill ~gray~holes
~lightGray~| | | | | |  Remove blocks > ground
| | | | | |
| | | | | |
|~red~^~lightGray~| | | | |  ~red~^ ~lightGray~= Turtle position

~yellow~Optional use ~brown~dirt ~yellow~as surface

]] -- Clear field
	info.sub[72] = 
[[~yellow~Clear rectangle

~lightGray~| | | | | |  Remove all blocks
~lightGray~| | | | | |  Optional dig ~lime~up
~lightGray~| | | | | |  Optional dig ~blue~down
~lightGray~| | | | | |
| | | | | |
|~red~^~lightGray~| | | | |  ~red~^ ~lightGray~= Turtle position
 ~red~^

~yellow~Can be used to clear 3 layers at a time

]] -- Clear rectangle

	info.sub[73] = 
[[~yellow~Clear wall
Plan view         Side view
                  ~gray~T ~lightBlue~T
~red~>~lightGray~|~orange~>~lightGray~|*|*|*|*|*|    ~cyan~T~lightGray~|~blue~T~lightGray~|*|*|*|*|*| Top
~lightGray~                   |*|*|*|*|*|*|
                   |*|*|*|*|*|*|
                   |*|*|*|*|*|*|
                   |*|*|*|*|*|*|
                  ~lime~T~lightGray~|~green~T~lightGray~|*|*|*|*|*| Base
				  
T = Turtle top / bottom/ inside / out
~yellow~Bottom to top or top to bottom
]] -- Clear wall
	info.sub[74] = 
[[~yellow~Clear rectangle ~red~perimeter only

~yellow~Plan view
~lightGray~| | | | | |  Remove all blocks
~lightGray~| |*|*|*| |  Optional dig ~lime~up
~lightGray~| |*|*|*| |  Optional dig ~blue~down
~lightGray~| |*|*|*| |
| |*|*|*| |
|~red~^~lightGray~| | | | |  ~red~^ ~lightGray~= Turtle position
~red~ ^
~yellow~Can be used to clear 3 layers at a time

]] -- Clear rectangle (perimeter only) 
	info.sub[75] = 
[[~yellow~Demolish cube structure
Plan view        Side view
               ~gray~T ~lightBlue~T
~lightGray~|*|*|*|*|*|*|  ~cyan~T~lightGray~|~blue~T~lightGray~|*|*|*|*|*|
|*|*|*|*|*|*|   |*|*|*|*|*|*|
|*|*|*|*|*|*|   |*|*|*|*|*|*|
|*|*|*|*|*|*|   |*|*|*|*|*|*|
|*|*|*|*|*|*|   |*|*|*|*|*|*|
|~lime~^~lightGray~|*|*|*|*|*|  ~lime~T~lightGray~|~green~T~lightGray~|*|*|*|*|*|
 ~green~^
~lightGray~^ T = Turtle (top/base in/out)
]] -- Clear structure floor/walls/ceiling hollow and solid
	info.sub[76] = info.sub[75]
	info.sub[77] = 
[[~yellow~Dig a trench (Plan view)

~lightGray~      |~red~>~lightGray~| | | | | | |
  
| |    ~red~>~lightGray~ = Turtle
| |    
| |
| |
| |    
|~red~^~lightGray~|    ~red~^~lightGray~ = Turtle
]] -- Dig a trench
	info.sub[78] = 
[[~yellow~Mountain carving     ~red~T ^ = Turtle
~yellow~Side view            Plan view

~lightGray~        |*|              |*|*|      ~yellow~L
~gray~ 	    |*~lightGray~|*|            ~gray~|*~lightGray~|*|*|*|    ~yellow~E
~gray~      |*~lightGray~|*|*|*|      ~gray~|*|*~lightGray~|*|*|*|*|  ~yellow~N
~gray~      |*~lightGray~|*|*|*|      ~gray~|*|*~lightGray~|*|*|*|*|  ~yellow~G
~gray~      |*~lightGray~|*|*|*|       ~red~^~gray~|*~lightGray~|*|*|*|    ~yellow~T
~gray~    |*|*~lightGray~|*|*|*|*|        |*|*|      ~yellow~H
   ~red~T~gray~|*|*~lightGray~|*|*|*|*|
    ~yellow~<--> no. of rows <-->
]] -- Carve mountain
	info.sub[79] = 
[[~yellow~Place / Replace floor or ceiling

Plan view      Side view
~lightGray~| | | | | |    |*|*|*|*|*|
| | | | | |     T          Ceiling
| | | | | |
| | | | | |
| | | | | |     T          Floor
|~red~^~lightGray~| | | | |    |*|*|*|*|*|

~red~^ ~lightGray~T = Turtle position

]] -- (Re)place floor or ceiling
	info.sub[710] =
[[~yellow~Place me anywhere!
Menu or direct command interface.

~lightGray~Commands:

direction + ~blue~number ~yellow~eg ~white~f2 ~yellow~= forward ~blue~2

~yellow~f = forward  ~orange~b = backward
~lime~l = left     ~red~r = right
~lightGray~u = up       ~cyan~d = down

]] -- Direct control
	info.sub[81] = 
[[~blue~1.Drop sand or gravel wall
  ~yellow~Place me on water/lava surface
  
~lightBlue~2.Fill area with sand
  ~yellow~Place  on left corner of area
 
~yellow~3.Clear ~blue~(1) sand wall
  ~yellow~Place me on the surface of sand.

~yellow~4.Clear ~lightBlue~(2) sand filled area
  ~yellow~Place on left corner of sand field
]] -- Sand based utilities
	info.sub[82] = 
[[~yellow~Turtle position ~red~> T ~gray~(~red~V ~gray~to enclose)
~yellow~Plan view                      ~gray~Start:~red~V
~blue~|~red~>~blue~| | | | | | ~yellow~to ~lightGray~|*|*|*|*|*|~red~V~lightGray~|~gray~ enclose
                            ~gray~*  area
~yellow~Side view
 ~red~T
~blue~| | | | | | | ~yellow~to ~lightGray~|*|*|*|*|*|*|
~blue~| | | | | | |    ~lightGray~|*|*|*|*|*|*|
~blue~| | | | | | |    ~lightGray~|*|*|*|*|*|*|
~yellow~|S|~blue~ | | |~yellow~S|S|    |S|~lightGray~*|*|*|~yellow~S|S|
~yellow~|S|S|S|S|S|S|    |S|S|S|S|S|S|
]] -- build wall from water or lava surface downwards 	
	info.sub[83] = 
[[~yellow~Build a walled rectangle


~yellow~L ~lightGray~|*|*|*|*|*|*|
~yellow~e ~lightGray~|*| | | | |*|
~yellow~n ~lightGray~|*| | | | |*|
~yellow~g ~lightGray~|*| | | | |*|
~yellow~t ~lightGray~|*|*|*|*|*|*|
~yellow~h  ~red~^
~yellow~   W i d t h      ~red~^ ~lightGray~= Turtle


]] -- Create enclosed area
	info.sub[84] = 
[[~yellow~Clear volume of water

Plan view
~lightGray~|*|*|*|*|*|*|*|*|  * = Stone
|*|*~blue~| | |~lightGray~*|*~blue~| |~lightGray~*|  ~blue~| ~lightGray~= Water
|*~blue~| | | | | | |~lightGray~*|
|*~blue~| | | | | | |~lightGray~*|
|*~blue~| | | | | | |~lightGray~*|
|*~blue~| | | | | |~lightGray~*|*|
|*|~red~^~lightGray~|*~blue~| | | | |~lightGray~*|  ~red~^ ~lightGray~= Turtle
|*|*|*|*|*|*|*|*|  ~yellow~Width~blue~: ~yellow~6, ~orange~length~blue~:~orange~ 6

]] -- Clear volume of water
	info.sub[85] = info.sub[56] -- Sinking platform
	info.sub[861] = 
[[~yellow~Turtle placement  ~red~V~lime~ < ^ > ~yellow~over monument

~red~******    ******  * ~lightGray~= Avoid this area
~red~******    ******  V do not face front
******    ******  ~lime~< ^ > ~lightGray~Ideal facing~lightGray~
******    ******
~green~******~lime~++++~green~******  ~lime~+ ~lightGray~= Ideal position~green~
******~lime~++++~green~******  ~green~* ~lightGray~= Good position
~green~****************
****************  Or any corner < 12 
****************  blocks from edge
]]-- Ocean monument 85 subChoice 1: 4 corner pillars

	info.sub[862] = 
[[~yellow~Turtle positions ~red~> ^ < V

~lightGray~|*|~red~>~lightGray~|*|*|*|*|*|~red~<~lightGray~|*|  ~red~NOT ~lightGray~corner blocks!
|~red~V~lightGray~|             |~red~V~lightGray~|
|*|             |*|
|*|             |*|
|*|             |*|
|*|             |*|
|*|             |*|  ~yellow~Fill inventory~lightGray~
|~red~^~lightGray~|             |~red~^~lightGray~|  ~yellow~with stone.~lightGray~
|*|~red~>~lightGray~|*|*|*|*|*|~red~<~lightGray~|*|  ~yellow~Add when asked
]] -- Ocean monument build retaining walls

	info.sub[863] = 
[[~yellow~Turtle ~red~> < ~yellow~on side walls only

~lightGray~|*|*|*|*|*|*|*|*|*|*|
~lightGray~|~red~>~cyan~| *****   ***** |~red~<~lightGray~|
~lightGray~|~red~>~cyan~| *****   ***** |~red~<~lightGray~|
~lightGray~|~red~>~cyan~| *****   ***** |~red~<~lightGray~|
~lightGray~|~red~>~cyan~| *****+++***** |~red~<~lightGray~|
~lightGray~|~red~>~cyan~| *****+++***** |~red~<~lightGray~|
~lightGray~|~red~>~cyan~| ************* |~red~<~lightGray~|
~lightGray~|~red~>~cyan~| ************* |~red~<~lightGray~|
|*|*|*|*|*|*|*|*|*|*|
]] -- clear plants before sand draining
	info.sub[864] = info.sub[863]
	info.sub[865] = info.sub[863]
	info.sub[866] = info.sub[56]
	info.sub[867] = 
[[~yellow~Turtle positions ~red~> ^ < V
~green~|*|*|*|*|*~brown~|*|*|*|~red~V~brown~|*|
~green~|~red~>~green~|- - - - ~brown~- - - -|*|
~green~|*|- - - - ~brown~- - - -|*| ~lightGray~1 Turtle removes
~green~|*|- - - - ~brown~- - - -|*| ~lightGray~1 coloured area
~green~|*|- - - - ~brown~- - - -|*|
~orange~|*|- - - - ~lime~- - - -|*| ~lightGray~6 chests / area
~orange~|*|- - - - ~lime~- - - -|*| ~lightGray~Follow turtle
~orange~|*|- - - - ~lime~- - - -|*|
~orange~|*|- - - - ~lime~- - - -|~red~<~lime~| ~lightGray~30,000 fuel each!
~orange~|*|~red~^~orange~|*|*|*~lime~|*|*|*|*|*| ~lightGray~3,000 stone each!
]] -- Ocean monument drain and remove 1 of 4 quarters
	info.sub[87] = 
[[~yellow~Ladder to water / lava: Plan view

 ~blue~- ~red~- ~blue~- ~red~- ~blue~- ~red~- ~blue~-    ~blue~- ~red~- ~blue~- ~red~- ~blue~- ~red~- ~blue~-
 ~red~- ~blue~- ~red~- ~blue~- ~red~- ~blue~- ~red~-    ~red~- ~blue~- ~red~-~lightGray~|*|- ~blue~- ~red~-
 ~blue~- ~red~- ~blue~- ~red~- ~blue~- ~red~- ~blue~-    ~blue~- ~red~-~lightGray~|*|~brown~L~lightGray~|*|~red~- ~blue~- ~~lightGray~
|*|*|*|~red~^~lightGray~|*|*|*|  |*|*|*|*|*|*|*|
|*|*|*|*|*|*|*|  |*|*|*|*|*|*|*|
|*|*|*|*|*|*|*|  |*|*|*|*|*|*|*|

~red~^ ~lightGray~= Turtle facing water / lava
~brown~L ~lightGray~= Ladder

]] -- Ladder to water/lava	
	info.sub[88] = 
[[~yellow~Place ~red~T~yellow~urtle at water edge.
Returns max ~blue~d~yellow~epth. ~yellow~Water ~green~p~yellow~lants~yellow~ removed

   ~red~T                       T
~lightGray~|*|*| ~blue~| | | | | | | | | | ~lightGray~|*|
|*|*| ~blue~| | | | | | | | | ~lightGray~|*|*|
|*|*| ~blue~| | | | | | | ~lightGray~|*|*|*|*|
|*|*|*| ~blue~| | |~green~p~blue~| | ~lightGray~|*|*|*|*|*|
|*|*|*| ~blue~| | |~green~p~lightGray~|*|*|*|*|*|*|*|
|*|*|*|*~blue~|d~lightGray~|*|*|*|*|*|*|*|*|*|
|*|*|*|*|*|*|*|*|*|*|*|*|*|*|
]] -- Clear water plants from enclosed area
	info.sub[89] = 
[[Place me on the left corner of the top
of retaining wall facing water
]] -- Convert all water to source
	info.sub[810] = 
[[Place me on the left corner of the top
of retaining wall facing water.
The source blocks are placed ahead to
selected length
]] -- Create sloping water

-- Building and railway
	info.sub[91] = 
[[~yellow~Build a wall

Plan view        Side view

~red~>~lightGray~| | | | | | |   |*|*|*|*|*|*|
                 |*|*|*|*|*|*|
                 |*|*|*|*|*|*|
                 |*|*|*|*|*|*|
                ~red~T~lightGray~|~red~T~lightGray~|*|*|*|*|*|

~red~> T~lightGray~ = Turtle
				 
]] -- Build a wall
	info.sub[92] = 
[[~yellow~Build a walled rectangle / house

Plan view         Side view

~yellow~L ~lightGray~|*|*|*|*|*|*|   |*|*|*|*|*|*|
~yellow~e ~lightGray~|*| | | | |*|   |*|*|*|*|*|*|
~yellow~n ~lightGray~|*| | | | |*|   |*|*|*|*|*|*|
~yellow~g ~lightGray~|*| | | | |*|   |*|*|*|*|*|*|
~yellow~t ~lightGray~|~red~^~lightGray~|*|*|*|*|*|  ~red~T~lightGray~|~red~T~lightGray~|*|*|*|*|*|
~yellow~h  ~red~^
~yellow~   W i d t h      ~red~^ T ~lightGray~= Turtle

]] -- Build a rectangular structure
	info.sub[93] = 
[[~yellow~Build a gable roof
Gable built on right side of turtle
Plan view       End view (width)
                     ~gray~+      gable top
~yellow~L ~lightGray~|*|*|*|*|*|      ~gray~+ + +    gable end
~yellow~e ~lightGray~|*| | | |*|    ~red~T~gray~ + + + +  gable end
~yellow~n ~lightGray~|*| | | |*|   |*|*|*|*|*| top of wall
~yellow~g ~lightGray~|*| | | |*|   |*|*|*|*|*|
~yellow~t ~lightGray~|*| | | |*|   |*|*|*|*|*|
~yellow~h ~lightGray~|~red~^~lightGray~|*|*|*|*|   |*|*|*|*|*|
~yellow~  W i d t h     W i d t h   ~red~^T ~lightGray~= Turtle
]] -- Build a gable end roof
	info.sub[94] =
[[~yellow~Build a pitched roof
Width ~red~MUST ~yellow~be ~red~<= ~yellow~Length eg ~red~4~yellow~ x 6
Plan view        End view (width)

                  ~red~T ~lightGray~on top of building
~yellow~L ~lightGray~|*|*|*|*|      |*|*|*|*|
~yellow~e ~lightGray~|*| | |*|      |*|*|*|*|
~yellow~n ~lightGray~|*| | |*|      |*|*|*|*|
~yellow~g ~lightGray~|*| | |*|      |*|*|*|*|
~yellow~t ~lightGray~|*| | |*|
~yellow~h ~lightGray~|~red~^~lightGray~|*|*|*|
~yellow~  W i d t h     ~red~^ T ~lightGray~= Turtle
]]-- Build a pitched roof
	info.sub[95] = 
[[~yellow~Place me on suspended railway stone
Redstone torch will go below me

~lightGray~_____
~lightGray~|*|*|\                           ~red~>~lightGray~|*|
    |*|~red~<                       ~lightGray~/|*|
      ~lightGray~|*|______~red~T~lightGray~_________    /~lightGray~|*|~red~!
       ~red~!~lightGray~|*|*|*|*|*|*|*|*|\ /|*|
               ~red~!        ~lightGray~|*|*|

~red~T < > ~lightGray~= Turtle ~red~! ~lightGray~= Redstone Torch
On block or above rail, face up slope
]] -- Place redstone torch under block
	info.sub[96] = info.sub[95]
	info.sub[97] = 
[[~yellow~Place me on last block before up/down

Build down            Build up~lightGray~

_____~red~T~lightGray~                        ___
|*|*|*|_                     _|*|
      |*|_                 _|*|
        |*|_             _|*|
          |*|__________~red~T~lightGray~|*|
            |*|*|*|*|*|*|		
~red~T~lightGray~ = Turtle on block, not above rail	
]] -- build down
	info.sub[98] =  info.sub[97]

--Measurement tools
	info.sub[101] = 
[[~yellow~Place me on floor.~lightGray~
            Measured Height:
|~lightBlue~*~lightGray~|*|*|*|   ~lightBlue~7. Overhead obstruction
            ~cyan~7. ~red~NOT ~cyan~detect() ~gray~7. Change~lightGray~
  |*|*|*|
  |*|*|*|
  |~lime~S~lightGray~|*|*|   ~lime~4. Specific block found~lightGray~
  |*|*|*|
  |*|*|*|
  |*|*|*|
 ~red~T~lightGray~|*|*|~red~T~lightGray~|   ~red~T~lightGray~ = Turtle
]] -- measure height
	info.sub[102] = 
[[~yellow~Depth measurement
Place me on the floor above pit / edge

    ~red~T~lightGray~
1|*|*|
2|*|*|
3|*|*|
4|*|*|         Measured depth: 
5|*|~lime~S~lightGray~|         ~lime~5. Specific block found
~lightGray~6              ~cyan~6. ~red~NOT ~cyan~turtle.detect()~lightGray~ 
7|*|*|~lightBlue~*~lightGray~|*| |   ~lightBlue~6. Obstruction below
]] -- measure depth
	info.sub[103] = 
[[~yellow~Length measurement

~lightGray~1 2 3 4 ~lime~5~lightGray~ 6 ~lime~7 ~cyan~8 ~lightBlue~9~lightGray~ 10
                      ~cyan~8. No block up
~lightGray~*|*|*|*|*|*|~lime~S~lightGray~| |*|*|  ~lime~7. Search block
~red~T~lightGray~                |*|  ~lightBlue~9. Obstruction
~lightGray~*|*|*|*|~lime~S~lightGray~|*|*| |*|*|  ~lime~5. Search block
                      ~cyan~8. No block down

~red~T ~lightGray~= Turtle

]] -- measure length
	info.sub[104] = info.sub[88] -- measure deepest section of water
	info.sub[105] =
[[~yellow~Place turtle anywhere:

 1. make a ~blue~borehole~yellow~ to chosen level.

 2. Write a report called:

 3. ~lime~borehole~blue~X~lime~.txt ~yellow~( ~blue~X ~yellow~= computer ID )

 4. ~orange~Return home

]] -- Borehole: Analyse blocks below
	info.sub[110] = 
[[~yellow~How many turtles?:

~yellow~1.~lightGray~ Alternative positions for ~lime~2 ~lightGray~turtles
~lightGray~| |~lime~1~lightGray~|~lime~2~lightGray~| |  |~lime~1~lightGray~| | |~lime~2~lightGray~| | | | | | ground 2
~lightGray~|*|~blue~W|W~lightGray~|*|  |*|~blue~W|W~lightGray~|*| |*|~blue~1~lightGray~|~blue~2~lightGray~|*| water  2

~yellow~2.~lightGray~ Alternative positions for ~orange~4 ~lightGray~turtles
~lightGray~|~orange~1~lightGray~|~orange~2~lightGray~|~orange~3~lightGray~|~orange~4~lightGray~|                      ground 4
~lightGray~|*|~blue~W|W~lightGray~|*|                      water  0

~yellow~Enter 1 to use ~lime~2 ~yellow~turtles or 2 to use ~orange~4]]	-- initial menu for water canal
	local line = menu.clear()
	if menuLevel == 1 then -- general help
		line = menu.colourText(line, info.main[menuItem], true, true)
		term.write("Enter to continue ")
		read()
		return ""
	else -- item specific help
		if info.sub[menuItem] ~= nil then -- help file exists
			line = menu.colourText(line, info.sub[menuItem], true, true)
			if noMenu then
				

				if getInteger then
					return line -- ready for further input
				else
					term.setCursorPos(1, 13)
					menu.enterToContinue()
				end
			else
				term.setCursorPos(1, 13)
				term.write("Enter=exit, Any key + Enter=more ")
				return read()
			end
		end
	end
end

local function getTaskOptions()
	local options = {}
	options.main =
	{
		"Mining (includes Nether)",
		"Forestry",
		"Farming",
		"Obsidian, Nether & End",
		"Canal, bridge and walkway",
		"Spawner farm tools",
		"Area shaping and clearing",
		"Lava and Water",
		"Building and minecart",
		"Measuring tools",
		"Network Tools"
	}
	table.insert(options,
	{
		"Ladder up or down",
		"Stairs up or down",
		"Create mine at this level",
		"Safe drop to water block",
		"Single column bubble lift",
		"QuickMine corridor system",
		"QuickMine rectangle",
		"Mine bedrock level",
		"Rob disused mineshaft"
	})
	table.insert(options,
	{
		"Fell Tree",
		"Create extend or convert tree farm",
		"Plant tree farm",
		"Harvest tree farm",
		"Fence or wall a forest",
		"Harvest and replant forest"
	})
	table.insert(options,
	{
		"Create modular crop farm",
		"Extend modular crop farm",
		"Manage farm:plant,harvest,convert",
		"Build a wall or fence",
		"Fence or wall an enclosure"
	})	
	table.insert(options,					
	{
		"Dig obsidian field",
		"Build Nether Portal",
		"Demolish Nether Portal",
		"Stripmine Netherite",
		"Undermine Dragon Towers",
		"Deactivate Dragon Tower",
		"Build dragon water trap",
		"Build portal ladder & platform",
		"Shulker harvester"
	})
	table.insert(options,
	{
		"Simple path on air, water or lava",
		"Covered path or tunnel",
		"Water canal (mulitple options)",
		"Ice canal (multiple options)",
		"Platform",
		"Sinking platform",
		"Boat bubble lift",
	})
	table.insert(options,
	{
		"Cube around spawner (NOT blaze)",
		"Cube around Blaze spawner",
		"Flood mob farm floor",
		"Create mob bubble lift",
		"Computercraft mob grinder",
		"Build Endermen observation tower",
		"Surround trial spawner"
	})
	table.insert(options,
	{
		"Clear field (inc trees)",
		"Clear a rectangle (+ u/d opt)",
		"Clear single wall up/down",
		"Clear rectangular wall section",
		"Clear hollow structure up/down",
		"Clear solid structure up/down",
		"Dig a trench",
		"Carve mountain side",
		"Place a floor or ceiling",
		"Direct control of movement"
	})
	table.insert(options,
	{
		"Sand based utilities",
		"Vertical wall from surface",
		"Create enclosed area",
		"Clear volume of water",
		"Sinking platform",
		"Ocean monument utilities",
		"Ladder down to water/lava",
		"Clear water plants",
		"Convert all water to source",
		"Create sloping water"
	})
	table.insert(options,
	{
		"Build a wall",
		"Build a walled area / house",
		"Build a gable end roof",
		"Build a pitched roof",
		"Place Redstone:torch level track",
		"Place Redstone:torch upward track",
		"Build downward track",
		"Build upward track"
	})
	table.insert(options,
	{
		"Measure height",
		"Measure depth",
		"Measure length",
		"Measure greatest depth",
		"Borehole: Analyse blocks below"
	})
	table.insert(options,
	{
		"Craft an item",
		"Mystical Agriculture Essence tools"
	})
	
	return options
end

local function getTaskColours()
	local options = {}
	options.main =
	{
		colors.lightGray, 	-- Mining (includes Nether)
		colors.lime, 		-- Forestry
		colors.green, 		-- Farming
		colors.red, 		-- Obsidian, Nether & End Portal
		colors.brown, 		-- Canal, bridge and walkway
		colors.lightGray, 	-- Mob farm tools
		colors.orange,		-- Area shaping and clearing
		colors.blue, 		-- Lava and Water
		colors.cyan,		-- Railway
		colors.purple, 		-- Measuring tools
		colors.pink 		-- Network tools
	}
	table.insert(options,
	{
		colors.brown, 		-- Ladder up or down
		colors.lightGray, 	-- Stairs up or down
		colors.lightGray, 	-- Create mine at this level
		colors.blue, 		-- Safe drop to water block
		colors.blue, 		-- Single column bubble lift
		colors.magenta, 	-- QuickMine corridor system
		colors.pink, 		-- QuickMine rectangle
		colors.gray, 		-- Mine bedrock level
		colors.brown 		-- Rob disused mineshaft
	})
	table.insert(options,
	{
		colors.brown, 		-- Fell Tree
		colors.lightGray, 	-- Create tree farm
		colors.lime, 		-- Plant tree farm
		colors.green, 		-- Harvest tree farm
		colors.brown, 		-- Fence or wall an enclosure
		colors.lime 		-- Harvest and replant forest
	})
	table.insert(options,
	{
		colors.yellow, 		-- Create modular crop farm
		colors.green, 		-- Extend modular crop farm
		colors.lime, 		-- Manage modular crop farm
		colors.brown, 		-- Build wall or fence
		colors.brown 		-- Build rectangle wall or fence
	})	
	table.insert(options,					
	{
		colors.lightGray, 	-- Dig obsidian field
		colors.purple, 		-- Build Nether Portal
		colors.gray, 		-- Demolish Nether Portal
		colors.red,			-- Netherite stripping
		colors.orange, 		-- Undermine Dragon Towers
		colors.orange, 		-- Deactivate Dragon Tower
		colors.blue, 		-- Build dragon water trap
		colors.lightGray, 	-- Build portal minecart station
		colors.red			-- Shulker harvesting
	})
	table.insert(options,
	{
		colors.lightGray, 	-- Continuous path
		colors.gray, 		-- Covered walkway / tunnel
		colors.blue, 		-- Water canal
		colors.lightBlue, 	-- Ice canal (4 options)
		colors.brown, 		-- Platform
		colors.blue, 		-- Sinking platform for oceans
		colors.cyan 		-- Boat bubble lift
	})
	table.insert(options,
	{
		colors.brown, 		-- Cube around spawner (NOT blaze)
		colors.red, 		-- Cube around Blaze spawner
		colors.cyan, 		-- Flood mob farm floor
		colors.blue, 		-- Create mob bubble lift
		colors.brown, 		-- Dig mob drop trench
		colors.gray, 		-- Build Endermen observation tower
		colors.orange		-- Surround trial spawner
	})
	table.insert(options,
	{
		colors.lime, 		-- Clear field (inc trees)
		colors.magenta, 	-- Clear a rectangle (+ u/d opt)
		colors.pink, 		-- Clear single wall up/down
		colors.purple, 		-- Clear rectangular wall section
		colors.brown, 		-- Clear hollow structure up/down
		colors.orange, 		-- Clear solid structure up/down
		colors.brown, 		-- Dig a trench
		colors.gray, 		-- Carve mountain side
		colors.lightBlue, 	-- Place a floor or ceiling
		colors.red 			-- Direct control of movement
	})
	table.insert(options,
	{
		colors.yellow, 		-- Sand based utilities
		colors.blue, 		-- Vertical wall from surface
		colors.blue, 		-- Create enclosed area
		colors.cyan, 		-- Clear volume of water
		colors.lightGray,	-- Sinking platform
		colors.orange, 		-- Ocean monument utilities
		colors.brown, 		-- Ladder down to water/lava
		colors.green, 		-- Clear water plants
		colors.lightBlue, 	-- Convert all water to source
		colors.blue 		-- Create sloping water
	})
	table.insert(options,
	{
		colors.yellow,		-- build a wall
		colors.orange,		-- build rectangular structure
		colors.lightGray,	-- gable end roof
		colors.gray,		-- pitched roof
		colors.red, 		-- Place Redstone:torch level track
		colors.red, 		-- Place Redstone:torch upward track
		colors.orange, 		-- Build downward track
		colors.brown 		-- Build upward track
	})
	table.insert(options,
	{
		colors.red, 		-- Measure height
		colors.purple, 		-- Measure depth
		colors.magenta, 	-- Measure length
		colors.pink, 		-- Measure greatest depth
		colors.lightBlue	-- Borehole: Analyse blocks below
	})
	table.insert(options,
	{
		colors.red, 		-- Craft item
		colors.magenta, 	-- MysticalAgriculture 
	})
	return options
end

local function chooseTask(R)
--[[ 
	called from main()
	R = chooseTask(R)
	coloured menu:	
	local pp = 
	{
		prompt = colors.green,
		itemColours = {colors.white, colors.red, ... one for each item},
		menuPrompt = colors.yellow
	}
	choice, modifier = menu.menu or menu.new("Choose your option", options, pp)
	]]
	local lib = {}
	
	function lib.getHelp(choice, itemsRequired, pp)
		local listOfItems = itemsRequired[choice]
		local result = getTaskHelp(2, choice)
		if result ~= "" then -- any key + enter = more
			lib.showItems(listOfItems)
		end
		T:clear()
		pp.itemColours = {colors.green, colors.yellow, colors.orange, colors.red}
		local options ={"Continue with selected task", "return to menu", "Return to main menu","Quit application"}
		local option = menu.menu("Choose your option", options, pp, "Type number + Enter ")
		if option == 2 then
			choice = -2	-- return to subMenu
		elseif option == 3 then
			choice = 0 -- return to main menu
		elseif option == 4 then
			choice = -1 -- quit
		-- else return original value of choice
		end
		
		return choice -- if R.choice reset to 0, then re-starts, -1 == quit
	end
	
	function lib.showItems(listOfItems)
		T:clear()
		if listOfItems ~= nil then
			if next(listOfItems) ~= nil then
				menu.colourPrint("Items required:", colors.lime)
				for k,v in pairs(listOfItems) do
					menu.colourPrint("  "..v, colors.lightGray)
				end
			else
				menu.colourPrint("No items required", colors.lime)
			end
		else
			menu.colourPrint("No items required", colors.lime)
		end
		menu.colourWrite("Enter to continue", colors.yellow, colors.black, nil, true)
		read()
	end
	
	function lib.getItemList(subChoice, itemsRequired)
		local listOfItems = itemsRequired[subChoice]
		lib.showItems(listOfItems)
	end
	
	function lib.getChoice(choice, subChoice)
		if subChoice > 9 then -- need more than 9 sub-options
			choice = subChoice + (choice * 100) -- 10 = 10 + 1000 = 1100
		else -- eg main option 1 (mining), sub-option 1 (create mine) = 1 + 10 = 11
			choice = subChoice + (choice * 10) -- 9 = 9 + 9 * 10 = 99, 1 + 10*10 = 101
		end
		return choice
	end
	
	local modifier = ""
	local subChoice = 0
	local prompt = "Choose an option"
	local mainPrompt = "Choose option (+h = help eg 3h):"
	local subPrompt = "Choose (+h = help +i = items eg 3h):"
	local options = getTaskOptions()
	local menuColours = getTaskColours()
	local itemsRequired = getTaskItemsList()
	local menuState = 0 -- use main menu
	-- local pp = utils.getPrettyPrint(colors.cyan, colors.magenta) -- specify menu title and prompt colours
	--local pp = utils.getPrettyPrint()-- uses default colours
	
	while menuState >= 0 do -- menuState has to be -1 to exit loop
		--[[
		menu returns choice=nil if user enters just q or h
		menu returns choice=2, modifier = "h" if 2h entered
		Mining (includes Nether)		white
		Forestry						lime
		Farming							lime
		Obsidian, Nether & End Portal	brown
		Canal, bridge and walkway		pink	
		Mob farm tools					gray
		Area shaping and clearing		purple	
		Lava and Water					blue
		Railway							magenta
		Measuring tools					cyan		
		]]
		
		if menuState == 0 then
			pp.itemColours = menuColours.main
			local mainChoice, modifier = menu.menu(mainPrompt, options.main, pp) -- open main menu options
			T:saveToLog("chooseTask(): mainChoice = "..tostring(mainChoice)..", modifier = "..tostring(modifier))
			if modifier == "q" then
				R.choice = -1
				return R -- quit application
			elseif modifier == "h" then -- get help on main menu items
				getTaskHelp(1, mainChoice) -- "" or any return string for more
				R.choice = 0
				return R -- quit task system so it re-starts as help menu chosen R.choice = 0
			else
				menuState = 1 -- next level so use sub-menu
				R.choice = mainChoice -- 1-11
			end
		else
			pp.prompt = colors.yellow
			pp.itemColours = menuColours[R.choice]
			subChoice, modifier = menu.menu(subPrompt, options[R.choice], pp, "Back = 'q' or number + Enter: ") -- open submenu options
			T:saveToLog("chooseTask(): subChoice = "..tostring(subChoice)..", modifier = "..tostring(modifier))
			if modifier == "q" then
				R.choice = 0	-- return to root menu. change this to -1 if quit application preferred
				return R -- quit task system so it re-starts first menu
			elseif modifier == "i" then -- get list of items
				local index = lib.getChoice(R.choice, subChoice)
				lib.getItemList(index, itemsRequired) -- list of items shown
				subChoice = nil -- allow menu to continue
			elseif modifier == "h" then -- get help on main menu items
				local index = lib.getChoice(R.choice, subChoice)
				index = lib.getHelp(index, itemsRequired, pp)
				--R = lib.getHelp(R, itemsRequired, pp) -- if R.choice reset to 0 then will continue
				if index == -2 then -- redraw sub-menu
					subChoice = nil -- allow menu to continue
				elseif index == -1 then -- if R.choice reset to 0 then will continue
					R.choice = -1
					return R
				elseif index == 0 then 
					R.choice = 0
					menuState = 0 -- if R.choice reset to 0 then back to main menu
				end
			end
			if subChoice ~= nil then
				R.choice = lib.getChoice(R.choice, subChoice)
				return R -- exit loop
			end
		end
	end
	return R
end

local function getTask(R)
	--[[
	Called from main(): R = getTask(R)
	local R =
		{
			choice = 0,
			subChoice = 0,
			size = 0,
			width = 0,
			length = 0,
			height = 0,
			depth = 0,
			up = false,
			down = false,
			silent = false,
			data = {},
			torchInterval = 0,
			useBlockType = "",
			auto = false,
			side = "",
			direction = "",
			mysticalAgriculture = false
		}
	]]
	local lib = {}
	
	function lib.isAutoHelp(choice, noAutoHelp)
		for _, v in ipairs(noAutoHelp) do
			if choice == v then
				return true
			end
		end
		return false
	end
	
	function lib.isMysticalAgriculture(R)
		if menu.getBoolean("Mystical Agriculture modded? (y/n)", nil, colors.brown) then
			R.mysticalAgriculture = true
		end
		return R
	end
	
	local prompt = "Choose an option"
	local noAutoHelp = {23, 24, 47, 49, 53, 54, 81, 85}
	if not lib.isAutoHelp(R.choice, noAutoHelp) then -- exclude Water canal, ice canal, sand utilities, monument utilities, dragon trap
		getTaskHelp(2, R.choice, true)
		menu.clear()
	end
-- 01. MINING
	if R.choice >= 11 and  R.choice <= 13 then	-- createLadder, createStaircase, createMine)
		--getTaskHelp(2, R.choice, true)
		--menu.clear()
	elseif R.choice == 14 then	-- safe drop to water
		local currentLevel = menu.getInteger("Current level (F3->Y coord)? ", bedrock + 5, ceiling, nil, colors.lightGray)
		local destLevel = menu.getInteger("Go down to level? ("..currentLevel - 2 .." to "..bedrock + 5 ..")", bedrock + 5 , currentLevel - 2, nil, colors.blue, nil, bedrock + 5)
		R.height 	= math.abs(destLevel - currentLevel)
	elseif R.choice == 15 then	-- bubble lift
		R.currentLevel = menu.getInteger("Current level (F3->Y coord)? ", bedrock + 5 , ceiling, nil, colors.blue, nil, bedrock + 5)
		local destLevel = menu.getInteger("Go up to level? ("..R.currentLevel + 2 .." to "..ceiling ..") ", R.currentLevel + 2, ceiling, nil, colors.lightGray)
		--[[if currentLevel <= bedrock + 5 then
			if menu.getBoolean("Confirm close to bedrock (y / n) ", nil, colors.yellow, colors.black) then
				R.data = "bedrock"
			end
		end]]
		R.height 	= math.abs(destLevel - R.currentLevel)
	elseif R.choice == 16 then -- create mining corridor system default: square 17 x 17 
		local choices = {"At corridor start, on the floor",
						 "At corridor start, on the ceiling",
						 "On floor, move forward to start",
						 "On ceiling, move forward to start"}
		pp.itemColours = {colors.lime, colors.green, colors.magenta, colors.pink}
		local userChoice, modifier = menu.menu("Starting position?", choices, pp, "Type number + Enter ") -- 1 to 4
		if modifier == "q" then -- quit chosen
			R.data = "quit"
			return R
		end
		R.width 	= menu.getInteger("Width (2-64 default 17) ", 2, 64, nil, colors.yellow, nil, 17)
		R.length  	= menu.getInteger("Length (2-64 default 17) ", 2, 64, nil, colors.orange, nil, 17)
		R.torchInterval = 9 -- 8 spaces between torches
		if mcMajorVersion >= 1.18 then
			R.torchInterval = 17 -- 16 spaces between torches
		end
		R.subChoice = userChoice
	elseif R.choice == 17 then -- clear a rectangle, fill empty spaces above
		local choices = {"At mine area start, on the floor",
						 "At mine area start, on the ceiling",
						 "On floor, move forward to start",
						 "On ceiling, move forward to start",
						 "On floor diagonally to left"} -- just finished corridor
		pp.itemColours = {colors.lime, colors.green, colors.magenta, colors.pink, colors.red}
		local userChoice, modifier = menu.menu("Starting position?", choices, pp, "Type number + Enter ") -- 1 to 4
		if modifier == "q" then -- quit chosen
			R.data = "quit"
			return R
		end
		R.width 	= menu.getInteger("Width (2-64 default 15) ", 2, 64, nil, colors.yellow, nil, 15)
		R.length  	= menu.getInteger("Length (2-64 default 15) ", 2, 64, nil, colors.orange, nil, 15)
		R.subChoice = userChoice
	elseif R.choice == 18 then -- Mine bedrock area
		--getTaskHelp(2, R.choice, true)
		--menu.clear()
		R.width 	= menu.getInteger("Width (2-64 default 17) ", 2, 64, nil, colors.yellow, nil,  17)
		R.length 	= menu.getInteger("Length (2-64 default 17) ", 2, 64, nil, colors.orange, nil,  17)
		if menu.getBoolean("Leave bedrock exposed? (y/n) ", nil, colors.yellow) then
			R.data = "leaveExposed"
		end
	elseif R.choice == 19 then -- salvage mine shaft
		R.torchInterval = menu.getInteger("Torch spacing? (0-64)", 0, 64, nil, colors.red)
-- 02. FORESTRY
	elseif R.choice == 22 then --Create treefarm
		R.width = 15
		R.length = 15
		pp.itemColours = {colors.lightGray, colors.green, colors.orange, colors.yellow, colors.gray, colors.lightGray}
		choices = {"New tree farm. Starting here", "On left side of existing farm <-",
					"On right side of existing farm ->", "On back left of existing farm ^",
					"Convert legacy with storage", "Convert Legacy without storage"}
		local choice = menu.menu(prompt, choices, pp, "Type number + Enter ")
		if choice == 1 then
			R.data = "new"
		elseif choice == 2 then
			R.data = "left"
		elseif choice == 3 then
			R.data = "right"
		elseif choice == 4 then
			R.data = "back"
		elseif choice == 5 then
			R.data = "convertStorage"
		elseif choice == 6 then
			R.data = "convert"
		end
		R.networkFarm = true
		--R.networkFarm =  menu.getBoolean({"Automate this farm with network","storage and modem? (y/n)"}, nil, {colors.yellow, colors.orange}, colors.black)
		if R.data ~= "convert" and R.data ~= "convertStorage" then
			R.up = menu.getBoolean({"Any blocks/trees above current level","in a 15 x 15 block area (y/n) "}, nil, {colors.yellow, colors.orange}, colors.black)
		end
	elseif R.choice == 23 then -- plant treefarm
		 -- ask the user which layout they want
  	  local sizeOptions = {"Single (4 saplings)","Double (8 saplings)","Mangrove style"}
 	  -- `pp` is your pretty‑print table; if undefined here, just pass `nil` or recreate one:
 	   pp = pp or { prompt = colors.green, itemColours = {colors.white, colors.white, colors.white}, menuPrompt = colors.yellow }
 	   R.subChoice = menu.menu("Tree‑plant layout?", sizeOptions, pp, "1–3 + Enter")
 	   retValue = plantTreefarm(R)
		R = utils.assessTreeFarm(R)	-- sets network and sapling type
		if R.message ~= "" then
			return {R.message}	-- location error
		end
		if R.networkFarm then
			if R.logType == "mangrove" then
				R.subChoice = 3 -- mangrove
			elseif R.logType == "spruce" or R.logType == "dark_oak" then
				R.subChoice = 2	-- double trees
			else
				R.subChoice = 1	-- single trees
			end
		else
			local choices 	= {"16 x oak, birch, acacia, cherry", "4 double spruce, dark oak, jungle"}
			pp.itemColours = {colors.lime, colors.green}
			R.subChoice = menu.menu(prompt, choices, pp, "Type number + Enter ")
		end
	elseif R.choice == 24 then -- Harvest treefarm
		R = utils.assessTreeFarm(R)	-- sets network and sapling type
		if R.message ~= "" then
			return {R.message}	-- location error
		end
	elseif R.choice == 25 then -- Build wall or fence
		R.width 	= menu.getInteger("Width of the area (1-64)", 1, 64, nil, colors.yellow)
		R.length  	= menu.getInteger("Length of the area (1-64)", 1, 64, nil, colors.orange)
		R.torchInterval = menu.getInteger("Torch spacing? (0-64)", 0, 64, nil, colors.red)
		if menu.getBoolean("Storage barrels in corners? (y/n)", nil, colors.brown) then
			R.data = "barrel"
		end
	elseif R.choice == 26 then -- Harvest and replant natural forest

		
-- 03. FARMING
	elseif R.choice == 31 then -- new crop farm
		--R = lib.isMysticalAgriculture(R)
		local choices 	= {"Use local storage", "Use modem network storage"}
		pp.itemColours = {colors.lime, colors.green}
		local choice = menu.menu(prompt, choices, pp, "Type number + Enter ")
		if choice == 2 then 
			R.networkFarm = true
		end
	elseif R.choice == 32 then -- extend crop farm
		R = utils.assessFarm(R)-- sets R.networkFarm and R.mysticalAgriculture
		local choices 	= {"Add a farm at the back", "Add a farm to the right"}
		pp.itemColours = {colors.lime, colors.green}
		R.subChoice = menu.menu(prompt, choices, pp, "Type number + Enter ")
	elseif R.choice == 33 then -- manage crop farm
		R = utils.checkFarmPosition(R)
		--R = utils.assessFarm(R)-- sets R.networkFarm and R.mysticalAgriculture
	elseif R.choice == 34 then -- fence or wall
		R.length  	= menu.getInteger("Length of wall / fence (1-256)", 1, 256, nil, colors.orange)
		R.torchInterval = menu.getInteger("Torch spacing? (0-64)", 0, 64, nil, colors.red)
	elseif R.choice == 35 then -- rectangle fence or wall
		R.width 	= menu.getInteger("Width of the area (1-64)", 1, 64, nil, colors.yellow)
		R.length  	= menu.getInteger("Length of the area (1-64)", 1, 64, nil, colors.orange)
		R.torchInterval = menu.getInteger("Torch spacing? (0-64)", 0, 64, nil, colors.red)
	
-- 04. OBSIDIAN
	elseif R.choice == 41 then	-- Harvest obsidian
		R.width 	= menu.getInteger("Width of the area (1-64) ", 1, 64, nil, colors.yellow)
		R.length  	= menu.getInteger("Length of the area (1-64) ", 1, 64, nil, colors.orange)
	elseif R.choice == 42 or R.choice == 43 then -- build Nether portal / demolish Nether portal
		local choices = {"Facing portal: forward, turn right",
						 "Aligned with portal: start ahead"}
		pp.itemColours = {colors.pink, colors.red}
		local userChoice, modifier = menu.menu("Starting position?", choices, pp, "Type number + Enter ") -- 1 to 2
		R.subChoice = userChoice
		if modifier == "q" then -- quit chosen
			R.data = "quit"
			return R
		end
		R.length 	= menu.getInteger("Portal width", 1, 64, nil, colors.yellow, nil, 4)
		R.height 	= menu.getInteger("Portal height (inc. buried base)", 1, 64, nil, colors.lightGray, nil, 5)
		R.width 	= menu.getInteger("Thickness (Usually 1) Enter = 1)", 1, 64, nil, colors.red, nil, 1)
		if menu.getBoolean("Base below surface (y/n)", nil, colors.orange) then
			R.data = "bury"
		end
	elseif R.choice == 44 then -- Netherite stripping
		R.width  	= 1
		while R.length == 0 or R.length % 16 > 0 do
			R.length = menu.getInteger("Strip length (divisible by 16) ", 16, 512, 1, colors.orange)
			if R.length % 16 > 0 then
				menu.colourText(1, "~red~Must be multiple of 16")
			end
		end
		R.torchInterval = 16
		R.data = "seal"
	elseif R.choice == 45 then -- undermine dragon towers

	elseif R.choice == 46 then -- deactivate dragon tower
	
	elseif R.choice == 47 then -- build dragon water trap
		local text = 
[[~yellow~You ~red~MUST ~yellow~have already constructed a 
bridge / tunnel into the dragon island
to allow for safe construction of the
dragon trap.

If not use toolkit:
  ~brown~5.~gray~2 Covered path or tunnel~yellow~ length 100
  
start centre of obsidian platform:
  100,49,0 facing west]]
		menu.colourText(1, text)
		if menu.getBoolean("Bridge already made? (y/n)", 12, colors.orange) then
			getTaskHelp(2, R.choice, true)
			menu.clear()
		else
			R.data = "quit"
			return R
		end
	elseif R.choice == 48 then -- build end portal minecart station
	elseif R.choice == 49 then -- Shulker harvesting
		local items	= 
		{
			"Shulker is above",
			"Shulker is ahead",
			"Shulker is below",
			"Climb tower wall",
			"Clear roof above",
			"Clear outside walls"
		}
		pp.itemColours = {colors.lightGray, colors.brown, colors.blue, colors.yellow, colors.orange, colors.lightGray}
		R.subChoice = menu.menu("Which utility? ", items, pp)
		getTaskHelp(2, R.choice * 10 + R.subChoice, true)  -- eg 490 + 1 = 491
		menu.clear()	
		
-- 05. CANAL BRIDGE
	elseif R.choice == 51 then	--single path
		if menu.getBoolean("Shorten an existing path? (y/n)", nil, colors.brown) then
			R.data = "reduce"
		end
		if R.data == "reduce" then
			R.length = menu.getInteger("Reduce by? 0 = here to end", 0, 1024, nil, colors.orange, nil, 64)
		else
			R.length = menu.getInteger("Path length? 0 = continuous ", 0, 1024, nil, colors.orange, nil, 64)
			R.torchInterval = menu.getInteger("Torch spacing? (0-64)", 0, 64, line, colors.red, nil, 0)
		end
	elseif R.choice == 52 then	-- 2 block corridor / covered walkway
		R.length 	= menu.getInteger("Corridor length?", 1, 1024, nil, colors.orange, nil, 64)
		R.torchInterval = menu.getInteger("Torch spacing? (0-64)", 0, 64, nil, colors.red)
		if menu.getBoolean("Seal off water or lava? (y/n)", nil, colors.brown) then
			R.data = "seal"
		end
	elseif R.choice == 53 then	--left/right side of new/existing canal
		local line = getTaskHelp(2, 110, true, true) -- request line no of help display if needed for getInteger
		R.data = menu.getInteger("Choose method 1 or 2", 1, 2, line + 1, colors.white)	-- 2 or 4 turtles
		menu.clear()
		line = getTaskHelp(2, R.choice, true, true) -- request line no of help display if needed for getInteger
		R.subChoice = menu.getInteger("Type position of this turtle", 1, 6, line + 1, colors.white)
		local position = "on ground"
		local side = "left"
		local colour = colors.lime
		if R.subChoice == 1 then
			R.side = "L"
			R.height = 1
			position = "on ground"
			colour = colors.lime
		elseif R.subChoice == 2 then
			R.side = "L"
			R.height = 1
			position = "above canal"
			colour = colors.orange
		elseif R.subChoice == 3 then
			R.side = "R"
			side = "right"
			R.height = 1
			position = "above canal"
			colour = colors.brown
		elseif R.subChoice == 4 then
			R.side = "R"
			side = "right"
			R.height = 1
			colour = colors.green
		elseif R.subChoice == 5 then
			R.side = "L"
			R.height = 0
			position = "on canal base"
			colour = colors.blue
		elseif R.subChoice == 6 then
			R.side = "R"
			side = "right"
			R.height = 0
			position = "on canal base"
			colour = colors.cyan
		end
		line = menu.clear()
		if R.data == 1 or (R.data == 2 and (R.subChoice == 1 or R.subChoice == 4)) then
			R.torchInterval = menu.getInteger("Torch spacing? (0-64)", 0, 64, line, colors.red, nil, 0)
		end
		-- menu.colourPrint(text, fg, bg, width)
		-- menu.colourText(row, text, reset)
		menu.colourPrint("Turtle placed "..side.." "..position, colour)
		R.length 	= menu.getInteger("Canal length? 0 = continuous ", 0, 512, line + 2, colors.orange, nil, 64)
	elseif R.choice == 54 then	--ice canal 4 sections: edge+torch, edge, centre+ice, centre no ice
		local line = getTaskHelp(2, R.choice, true, true) -- request line no of help display if needed for getInteger
		R.subChoice = menu.getInteger("Type turtle position", 1, 8, line, colors.white)
		R.side = "L"
		local position = "on towpath"
		local side = "left"
		local colour = colors.lime
		line = menu.clear()
		--[[
			new canal
			1 = left towpath- move to centre left
			2 = centre left ice or hollow
			3 = centre right ice or hollow
			4 = right side - move to centre right
			convert water canal
			5 = left towpath
			6 = centre left ice or air
			7 = centre right ice or air
			8 = right towpath
		]]
		if R.subChoice == 1 or R.subChoice == 4 or R.subChoice == 5 or R.subChoice == 8 then
			-- on towpath r/l
			R.torchInterval = menu.getInteger("Torch spacing? (0-64)", 0, 64, line, colors.red, nil, 0)
			if R.subChoice == 4 or R.subChoice == 8 then
				side = "right"
				R.side = "R"
			end
			if R.subChoice <= 4 then -- 1 or 4 only
				if menu.getBoolean("Place Ice as well? (y/n)", line + 1, colors.blue) then
					R.data = "ice"
				end
			end
		else -- on canal centre r/l
			if R.subChoice == 3 or R.subChoice == 7 then
				side = "right"
				R.side = "R"
			end
			if R.subChoice == 2 or R.subChoice == 3 then -- new canal
				R.torchInterval = menu.getInteger("Torch spacing? (0-64)", 0, 64, line, colors.red, nil, 0)
				position = "above air/ice"
			end
			if menu.getBoolean("Place Ice as well? (y/n)", line + 1, colors.blue) then
				R.data = "ice"
				if R.subChoice == 6 or R.subChoice == 7 then	
					position = "alternate air/ice"
					colour = colors.lightBlue
				end
			else
				if R.subChoice == 6 or R.subChoice == 7 then	
					position = "on air spaces"
					colour = colors.lighGray
					if R.subChoice == 7 then
						side = "right"
						R.side = "R"
					end
				end
			end
		end
		R.length 	= menu.getInteger("Canal length? 0 = continuous ", 0, 1024, line + 2, colors.orange, nil, 64)
		menu.colourPrint("Turtle on "..side.." side "..position, colour)
		sleep(2)
	elseif R.choice == 55 then	--platform
		R.width 	= menu.getInteger("Platform width", 1, 256, 1, colors.yellow)
		R.length 	= menu.getInteger("Platform length", 1, 256, 2, colors.orange)
		if menu.getBoolean("Remove blocks above? (y/n)",3, colours.red) then
			R.up = true
		end
		
	elseif R.choice == 56 then	--sinking platform
		R.width 	= menu.getInteger("Width (excluding retaining wall)? ", 1, 1024, nil, colors.yellow)
		R.length 	= menu.getInteger("Length (excluding retaining wall)? ", 1, 1024 / R.width, nil, colors.orange)
		R.height 	= menu.getInteger("Levels to go down?", 1, 1024 / R.width * R.length, nil, colors.blue)
	elseif R.choice == 57 then	--boat bubble lift
		R.height 	= menu.getInteger("Levels to go up?", 1, ceiling - 2, nil, colors.lightBlue)
		
-- 06. MOB SPAWNER TOOLS
	elseif R.choice == 61 then -- create cube round mob spawner
		local text =
[[~yellow~Turtle placement options:

~lime~1. On top or in front of the spawner
   ~green~(cave spider OR no chests around)
~lightGray~2. Outside the dungeon at floor or
   ceiling level ~red~1 block from corner
~yellow~Make sure you have access to the block
facing the spawner, as any chests
found inside will be placed outside
the new dungeon wall at this height

~white~Enter to continue
]]
		menu.colourText(nil, text, true)
		read()
		menu.clear()
		R.data = "spawner"
		if menu.getBoolean("Any chests around spawner? (y/n)",1, colours.red) then
			R.data = "chest"
		end
		local choices = {"Turtle on spawner (no chests)",
						 "Outside wall: left side, floor",
						 "Outside wall: left side, ceiling",
						 "Outside wall: right side, floor",
						 "Outside wall: right side, ceiling"}
		pp.itemColours = {colors.red, colors.lime, colors.orange, colors.green, colors.yellow}
		local userChoice, modifier = menu.new("Select turtle position", choices, pp) -- 1 to 5
		
		if modifier == "q" then -- quit chosen
			R.data = "quit"
			return R
		end
		R.subChoice 	= userChoice
		if R.subChoice > 1 then -- get dungeon wall dimensions
			R.width 	= menu.getInteger("Dungeon external width ", 0, 11, nil, colors.yellow, nil, 11)
			R.length 	= menu.getInteger("Dungeon external length ", 0, 11, nil, colors.orange, nil, 11)
		end
		
	elseif R.choice == 62 then -- Blaze spawner
		local text =
[[~yellow~Turtle placement options:

~red~1a On top of the spawner

~red~1b ~orange~At the same level in direct line of
spawner.~yellow~ (can be behind a safety wall)

~red~1c~lightGray~ Room below spawner (via stairs)

~lime~2 Finish build: In brick floor outside
  existing cube. (facing player)

~white~Enter to continue]]
		menu.colourText(nil, text, true)
		read()
		pp.itemColours = {colors.red, colors.lime}
		R.subChoice = menu.new("Choose your option", {"New Blaze spawner", "Complete part build (killzone)"}, pp, "Type number + Enter") -- 1 = new, 2= continue
		R.data = "blaze"			-- default
		if R.subChoice == 1 then	-- new blaze spawner
			text =
[[~yellow~Turtle placement options:
~red~1. On top of the spawner
~orange~2. In direct sight (safety wall ok)
~lightGray~3. Room below spawner (via stairs)
   |*|*|*|*|*|   Ceiling
   |*|*|~red~T~lightGray~|*|*|   Turtle under ceiling
   |*|~brown~+~lightGray~|*|~brown~+~lightGray~|*|   Top of fence
   |*|~brown~+~lightGray~|*|~brown~+~lightGray~|*|
   |*|~brown~+~lightGray~|*|~brown~+~lightGray~|*|   Bottom of fence
   |*|*|*|*|*|   Floor level]]
			--R.subChoice = menu.new("Choose your position", {"On top of spawner", "In direct sight (safety wall ok)", "Room below spawner"}, pp, "Type number + Enter")
			--getInteger(prompt, minValue, maxValue, row, fg, bg, default) 
			T:clear()
			menu.colourText(nil, text, true)
			R.subChoice = menu.getInteger("Enter position number", 1, 3, 12, colors.white)
		else
			R.data = "restart"		-- complete part build
		end
	elseif R.choice == 63 then -- flood spawner cube
		local choices = {"Bubble lift", "Computercraft mob softener"}
		pp.itemColours = {colors.lime, colors.orange}
		local userChoice = menu.menu("Flood for Mob grinder type?", choices, pp, "Type number + Enter ")
		R.subChoice = userChoice -- 1 bubble, 2 computercraft
	elseif R.choice == 64 then -- create bubble lift at mob spawner
		local choices = {"Dropzone on left", "Dropzone on right"}
		pp.itemColours = {colors.lime, colors.orange}
		local userChoice = menu.menu("Which side do you want the mobs?", choices, pp, "Type number + Enter")
		R.subChoice = userChoice -- 1 left, 2 right
	elseif R.choice == 65 then -- Computercraft mob grinder
		local choices = {"Use Sticky pistons", "Use non-sticky pistons"}
		pp.itemColours = {colors.lime, colors.orange}
		local userChoice = menu.menu("Which type of pistons?", choices, pp, "Type number + Enter ")
		R.subChoice = userChoice -- 1 sticky, 2 normal
	
-- 07. AREA CARVING
	elseif R.choice == 71 then --Clear field
		R.width 	= menu.getInteger("Width of the area (1-64)", 1, 64, nil, colors.yellow)
		R.length  	= menu.getInteger("Length of the area (1-64)", 1, 64, nil, colors.orange)
		if menu.getBoolean("Dirt on the surface (y/n)", nil, colors.brown) then
			R.useBlockType = "dirt"
		end
	elseif R.choice == 72 then -- Clear solid rectangle R.width, R.length
		R.width 	= menu.getInteger("Rectangle width (1-256)", 1, 256, nil, colors.yellow)
		R.length  	= menu.getInteger("Rectangle length (1-256)", 1, 256, nil, colors.orange)
		R.up 		= menu.getBoolean("Remove blocks above?", nil, colors.yellow)
		R.down 		= menu.getBoolean("Remove blocks below?", nil, colors.orange)
		if menu.getBoolean("Am I outside clearing zone (y/n)?", nil, colors.yellow) then
			T:forward(1)
		end
	elseif R.choice == 73 then -- Clear wall
		R.width 	= 1
		R.length 	= menu.getInteger("Length of wall (1-256) ", 1, 256, nil, colors.orange)
		R.height 	= menu.getInteger("Height of wall (1-50) ", 1, 50, nil, colors.lightGray)
		pp.itemColours = {colors.lime, colors.orange}
		R.subChoice = menu.menu("Which direction?", {"Bottom -> Top", "Top -> Bottom"}, pp, "Type number + Enter ") -- open direction menu options
		if R.subChoice == 1 then
			if menu.getBoolean("Am I outside clearing zone (y/n)?", nil, colors.yellow) then
				T:forward(1)
			end
		else
			pp.itemColours = {colors.lightBlue, colors.cyan, colors.blue, colors.gray}
			local choice = menu.menu("Exact position?", {"On top of clearing zone", "In front of clearing zone", "Inside clearing zone","Above AND outside"}, pp, "Type number + Enter ") 
			if choice == 1 then
				T:down(1)
			elseif choice == 2 then
				T:forward(1)
			elseif choice == 4 then
				T:go("D1F1")
			end
		end
	elseif R.choice == 74 then -- Clear rectangle perimeter only R.width, R.length
		R.width 	= menu.getInteger("Perimeter width (1-256) ", 1, 256, nil, colors.yellow)
		R.length  	= menu.getInteger("Perimeter length (1-256) ", 1, 256, nil, colors.orange)
		R.height 	= 1
		if menu.getBoolean("Remove blocks above? (y/n)", 3, colours.red) then
			R.up = true
		end
		if menu.getBoolean("Remove blocks below? (y/n)", 4, colours.red) then
			R.down = true
		end
		if menu.getBoolean("Am I outside clearing zone (y/n)?", 5, colors.yellow) then
			T:forward(1)
		end
	elseif R.choice == 75 or R.choice == 76 then -- Clear hollow building floor/walls/ceiling OR clear solid object
		R.width 	= menu.getInteger("Structure width (1-256)", 1, 256, nil, colors.yellow)
		R.length  	= menu.getInteger("Structure length (1-256)", 1, 256, nil, colors.orange)
		R.height  	= menu.getInteger("Depth/Height (1-256)", 1, 256, nil, colors.lightGray)
		if R.choice == 75 then -- hollow building so need to check if floors/ceilings to be removed
			R.data = {}
			R.data.ceiling = false
			R.data.floor = false
			if menu.getBoolean("Remove ceiling? (y/n)", nil, colors.yellow, colors.black) then
				R.data.ceiling = true
			end
			if menu.getBoolean("Remove floor? (y/n)", nil, colors.orange, colors.black) then
				R.data.floor = true
			end
		end
		pp.itemColours = {colors.lime, colors.orange}
		local direction = menu.menu("Which direction?", {"Bottom -> Top", "Top -> Bottom"}, pp, "Type number + Enter ") -- open direction menu options
		if direction == 1 then
			R.direction = "up"
			if menu.getBoolean("Am I outside clearing zone (y/n)?", nil, colors.yellow) then
				T:forward(1)
			end
		else
			R.direction = "down"
			pp.itemColours = {colors.lightBlue, colors.cyan, colors.blue, colors.gray}
			local choice = menu.menu("Exact position?", {"On top of clearing zone", "Outside clearing zone", "Inside clearing zone","Above AND outside"}, pp, "Type number + Enter ") 
			if choice == 1 then
				T:down(1)
			elseif choice == 2 then
				T:forward(1)
			elseif choice == 4 then
				T:go("D1F1")
			end
		end
	elseif R.choice == 77 then	-- Dig a trench
		R.height 	= menu.getInteger("Depth of the trench (1-64) ", 1, 64, nil, colors.blue)
		R.length 	= menu.getInteger("Trench length? 0 = continuous ", 0, 1024, nil, colors.orange)
	elseif R.choice == 78 then	-- Carve side of mountain
		pp.itemColours = {colors.lime, colors.orange}
		R.subChoice = menu.menu("Remove blocks on which side?", {"Left", "Right"}, pp, "Type number + Enter ") -- open direction menu options
		R.width 	= menu.getInteger("Remove how many vertical rows? ", 1, 1024, nil, colors.yellow)
		R.length 	= menu.getInteger({"Max length of each row?"," - Prevents cutting too wide","1 to 255 default 64"}, 1, 255, nil, {colors.orange, colors.red, colors.white}, colors.black, 64)
	elseif R.choice == 79 then	-- Place a floor or ceiling
		local items = {	"Replacing current floor",
						"New floor over existing",
						"Replacing current ceiling",
						"New ceiling under existing"}
		pp.itemColours = {colors.lime, colors.orange, colors.green, colors.yellow}
		R.subChoice = menu.menu("Laying what?", items, pp, "Type number + Enter ")
		R.height = menu.getInteger({"Enter 0 for on-site placement",
								    "If in deep water or above reach",
									"Enter approx depth/height"}, 0, 64, nil, {colors.yellow, colors.blue, colors.cyan} )
		if R.subChoice < 3 then
			R.down = true
			R.width 	= menu.getInteger("Width of floor (1-64) ", 1, 64, nil, colors.yellow)
			R.length  	= menu.getInteger("Length of floor (1-64) ", 1, 64, nil, colors.orange)
		else
			R.up = true
			R.width 	= menu.getInteger("Width of ceiling (1-64) ", 1, 64, nil, colors.yellow)
			R.length  	= menu.getInteger("Length of ceiling (1-64) ", 1, 64, nil, colors.orange)
		end
	elseif R.choice == 710 or R.choice == 83 then -- Direct movement
		local choices = {"Simple path", "Covered 2 block high path"}
		pp.itemColours = {colors.lime, colors.orange}
		local userChoice = menu.menu("Choose your path option", choices, pp, "Type number + Enter ")
		R.subChoice	= userChoice -- 1 open, 2 covered
		choices = {"Command driven", "Menu driven"}
		userChoice = menu.menu("Choose your preference", choices, pp, "Type number + Enter ")
		if userChoice == 1 then
			R.data = "cmd"
		else
			R.data = "menu"
		end
		
-- 08. WATER LAVA
	elseif R.choice == 81 then -- Sand based utilities
		local line = getTaskHelp(2, R.choice, true, true) -- request line no of help display if needed for getInteger
		R.subChoice = menu.getInteger("Type number of choice", 1, 4, line, colors.white)
		T:clear()
		if R.subChoice == 1 then -- drop sand into water or lava surface until solid ground reached
			R.width	  = 1
			R.length  = menu.getInteger("Length of sand wall (0=to block) ", 0, 60, nil, colors.orange)
		elseif R.subChoice == 2 then	-- clear rectangle on top of building and fill with sand
			R.width   = menu.getInteger("Width of area (<=30) ", 1, 30, nil, colors.yellow)
			R.length  = menu.getInteger("Length of of area (<=30) ", 1, 30, nil, colors.orange)
		elseif R.subChoice == 3 then	-- clear sand wall or harvest sand
			R.width   = 1
			R.length  = menu.getInteger("Length of sand (0=auto-detect)", 0, 60, nil, colors.orange)
			choices = {"Stay at end of wall", "Return home"}
			pp.itemColours = {colors.lime, colors.orange}
			userChoice = menu.menu("Choose your preference", choices, pp, "Type number + Enter ")
			if userChoice == 2 then
				R.data = "return"
			end
		elseif R.subChoice == 4 then	-- remove sand from cube. start at top
			R.width   = menu.getInteger("Width of sand (<=30) ", 1, 30, nil, colors.yellow)
			R.length  = menu.getInteger("Length of of sand (<=30) ", 1, 30, nil, colors.orange)
			R.height  = 0
			R.data = "down" -- always starts at the top
		end
		if menu.getBoolean("Am I outside the active zone (y/n)?", nil, colors.yellow) then
			T:forward(1)
		end
	elseif R.choice == 82 then -- build wall from water or lava surface downwards
		R.width 	= 1
		if menu.getBoolean("Going 90 deg. from existing? (y/n)", nil, colors.yellow, colors.black) then
			getTaskHelp(2, 852, true)
			menu.clear()	
			R.length = 56
			R.data = "withPath" -- ensures turtle will break through path
			R.length = menu.getInteger({"Wall length minus corners","(Ocean monument default 56)","Number -> Enter or Enter only (56)"},
										1, 64, nil, {colors.yellow, colors.orange, colors.green}, colors.black, 56)
		else
			R.length 	= menu.getInteger("Length of the wall (1-60) ", 1, 60, nil, colors.yellow)
			R.height 	= menu.getInteger("Fixed depth or 0 = to floor ", 0, 60, nil, colors.yellow)
		end
	-- for 83 see 710
	elseif R.choice == 84 then -- Clear area of water bounded by blocks
		R.width 	= menu.getInteger("Width of water (0=autodetect) ", 0, 64, nil, colors.yellow)
		if R.width > 0 then
			R.length = menu.getInteger("Length of water", 1, 64, nil, colors.orange)
		end
		R.height 	= menu.getInteger("Depth of water (0=autodetect)", 0, 64, nil, colors.blue)
	elseif R.choice == 85 then -- Sinking platform
		R.width 	= menu.getInteger("Width (excluding retaining wall)? ", 1, 1024, nil, colors.yellow)
		R.length 	= menu.getInteger("Length (excluding retaining wall)? ", 1, 1024 / R.width, nil, colors.orange)
		R.height 	= menu.getInteger("Levels to go down?", 1, 1024 / R.width * R.length, nil, colors.blue)
	elseif R.choice == 86 then -- ocean monument utilities
		local items	= 
		{
			"Build 4 corner marker columns",
			"Retaining wall beween 2 columns",
			"Clear plants pre sand draining",
			"Drop sand wall",
			"Recover sand wall",
			"Sinking platform",
			"Drain and remove structure"	
		}
		pp.itemColours = {colors.lightGray, colors.brown, colors.blue, colors.yellow, colors.orange, colors.lightGray, colors.gray}
		R.subChoice = menu.menu("Which utility? ", items, pp)
		if R.subChoice ~= nil then
			getTaskHelp(2, R.choice * 10 + R.subChoice, true)
		end
		menu.clear()	
		if R.subChoice == 1 then -- Build 4 corner marker columns			
			R.useBlockType = "prismarine"
			R.data = "oceanMonumentColumns"
		elseif R.subChoice == 2 then -- Retaining wall beween 2 columns
			R.length = 56
			R.data = "withPath" -- ensures turtle will break through path
			T:clear()
			R.length = menu.getInteger({"Wall length minus corners","(Ocean monument default 56)","Number -> Enter or Enter only (56)"},
										 1, 64, nil, {colors.yellow, colors.orange, colors.green}, colors.black, 56)
		elseif R.subChoice == 3 then -- Clear plants pre sand draining
			R.useBlockType = "prismarine"
			R.data = "clearWaterPlants"
			R.silent = true
			R.width 	= menu.getInteger("water width (0=auto detect) ", 0, 64, nil, colors.yellow)
			R.length  	= menu.getInteger("water length (0=auto detect) ", 0, 64, nil, colors.orange)
		elseif R.subChoice == 4 then -- Drain using sand utilities
			R.width	  = 1
			R.length  = 0
		elseif R.subChoice == 5 then -- remove sand wall using sand utilities
			R.width	  = 1
			R.length  = 0
		elseif R.subChoice == 6 then -- sinking platform
			R.width = menu.getInteger("Width (excluding retaining wall)? ", 1, 1024, nil, colors.yellow)
			R.length = menu.getInteger("Length (excluding retaining wall)? ", 1, 1024 / R.width, nil, colors.orange)
			R.height = menu.getInteger("Levels to go down?", 1, 1024 / R.width * R.length, nil, colors.blue)
		elseif R.subChoice == 7 then -- Drain and remove structure
			R.width = 28
			R.length = 28
			R.height = menu.getInteger("Go down how far from current", 1, 64, nil, colors.blue)
		end
	elseif R.choice == 87 then -- Ladder to water/lava	
		R.height 	= menu.getInteger("est. height above (?F3) ", 1, 256, nil, colors.blue)
	elseif R.choice == 88 then -- Clear water plants from enclosed area
		R.data 		= "clearWaterPlants"
		R.width 	= menu.getInteger("water width (0=auto detect) ", 0, 64, nil, colors.yellow)
		R.length  	= menu.getInteger("water length (0=auto detect) ", 0, 64, nil, colors.orange)
	elseif R.choice == 89 then -- convert flowing water to source
		R.width 	= menu.getInteger("water width  (0=auto detect) ", 0, 64, nil, colors.yellow)
		if R.width > 0 then
			R.length = menu.getInteger("water length (0=auto detect) ", 0, 64, nil, colors.orange)
		end
		R.height 	= menu.getInteger("water depth (0=auto detect) ", 0, 64, nil, colors.blue)
	elseif R.choice == 810 then -- create sloping water
		R.width 	= menu.getInteger("water slope width (usually 7/8) ", 1, 8, nil, colors.yellow)
		R.length 	= menu.getInteger("water slope length ", 1, 64, nil, colors.orange)
	
-- 09. BUILDING & RAILWAY
	elseif R.choice == 91 then -- Build wall
		R.width 	= 1
		R.length 	= menu.getInteger("Length of wall (1-256) ", 1, 256, nil, colors.orange)
		R.height 	= menu.getInteger("Height of wall (1-50) ", 1, 50, nil, colors.lightGray)
		pp.itemColours = {colors.lime, colors.magenta}
		R.subChoice = menu.menu("What is my current position?", {"End of wall: Start ahead","Within the wall: start here"}, pp, "Type number + Enter")
	elseif R.choice == 92 then -- Build rectangular structure
		R.width 	= menu.getInteger("Building width (1-256)", 1, 256, nil, colors.yellow)
		R.length 	= menu.getInteger("Building length (1-256) ", 1, 256, nil, colors.orange)
		R.height 	= menu.getInteger("Building Height(1-50) ", 1, 50, nil, colors.lightGray)
		pp.itemColours = {colors.lime, colors.magenta}
		R.subChoice = menu.menu("What is my current position?", {"Outside building: Start ahead","Within the walls: start here"}, pp, "Type number + Enter")
	elseif R.choice == 93 or R.choice == 94 then -- Build gable roof / pitched roof
		R.width 	= menu.getInteger("Building width (1-256)", 1, 256, nil, colors.yellow)
		R.length 	= menu.getInteger("Building length (1-256) ", 1, 256, nil, colors.orange)
	elseif R.choice == 97 then -- build downward slope
	--getInteger(prompt, minValue, maxValue, row, fg, bg, default) 
		R.height  	= menu.getInteger("How many blocks down (0=to ground)?", 0, 256, nil, colors.blue)
		R.depth  	= menu.getInteger("How much headroom (default 2)?", 0, 5, nil, colors.cyan, colors.black, 2)
		R.down = true
	elseif R.choice == 98 then -- build upward slope
		R.height  	= menu.getInteger("Go up by how many blocks?", 1, 256, nil, colors.lightGray)
		R.depth  	= menu.getInteger("How much headroom (default 2)?", 0, 5, nil, colors.cyan, colors.black, 2)
		R.up = true
		
-- 10. MEASURING TOOLS
	elseif R.choice == 101 then -- measure height
		pp.itemColours = {colors.lightBlue, colors.cyan, colors.lime, colors.gray}
		R.subChoice	= menu.menu("Measure using?", {"Obstruction above", "No further blocks in front", "Detect specific block in front", "Until block above changes" }, pp, "Type number + Enter ") -- open direction menu options
		if R.subChoice == 3 then
			R.data = menu.getString({"Search for? eg 'ore', 'obsidian'",">"}, false, 3, 20, nil, {colors.lime, colors.yellow})
		end
		R.size = menu.getInteger("Max distance before abort?", 1, 1024, nil, colors.red, nil, 64)
	elseif R.choice == 102 then -- measure depth
		pp.itemColours = {colors.lime, colors.orange, colors.green}
		R.subChoice	= menu.menu("Measure using?", {"Water/Lava/Obstruction below", "No further blocks ahead", "Detect specific block ahead"}, pp, "Type number + Enter") -- open direction menu options
		if R.subChoice == 3 then
			R.data = menu.getString({"Search for? eg 'ore', 'obsidian'",">"}, false, 3, 20, nil, {colors.lime, colors.yellow})
		end
	elseif R.choice == 103 then -- measure length
		pp.itemColours = {colors.gray, colors.lime, colors.green, colors.blue, colors.cyan}
		R.subChoice	= menu.menu("Measure using?", {"Obstruction ahead",
													"No further blocks above",
													"No further blocks below",
													"Detect specific block above",
													"Detect specific block below"}, pp, "Type number + Enter") -- open direction menu options
		if R.subChoice == 4 or R.subChoice == 5 then
			R.data = menu.getString({"Search for? eg 'ore', 'obsidian'",">"}, false, 3, 20, nil, {colors.lime, colors.yellow})
		end
		R.size = menu.getInteger("Max distance before abort?", 1, 1024, nil, colors.red, nil, 64)
	elseif R.choice == 104 then -- measure greatest depth of water body
		pp.itemColours = {colors.lime, colors.orange}
		R.subChoice	= menu.menu("Measure using?", {"Player entered", "No further water below"}, pp, "Type number + Enter ") -- open direction menu options
		-- 1 = player entry, 2 = water length
		if R.subChoice == 1 then
			R.length = menu.getInteger("water length (0=auto detect) ", 0, 256)
		end
	elseif R.choice == 105 then -- drill borehole and write borhole.txt to file
		R.height = menu.getInteger("Current level (F3->Y coord)? ", bedrock + 5, ceiling, nil, colors.lightGray)
		R.depth = menu.getInteger("Go down to level? ("..R.height - 2 .." to "..bedrock + 5 ..")", bedrock + 5 ,R.height - 2, nil, colors.blue, nil, bedrock + 5)
	
-- 11 Network tools
	elseif R.choice == 111 then -- craft an item
		local modem = peripheral.find("modem")		-- find modem
		if modem == nil then
			menu.colourText(1, "~yellow~I need to be placed close to an\n"..
				  "~red~activated ~brown~computercraft:modem_full~yellow~ to use "..
				  "~magenta~networked resources ~yellow~for crafting"..
				  "\n\n~blue~(Right-click modem to activate)\n")
				error()
		end
	elseif R.choice == 112 then -- mystical Agriculture essence tools
		if T:getBlockType("forward") ~= "minecraft:crafter" then
			menu.colourText(1, "~yellow~I need to be placed in front of a\n"..
				  "~red~minecraft:crafter ~yellow~(mc 1.21.1) as \n"..
				  "currently turtle.craft() with a\n"..
				  "~lime~mystical agriculture crystal\n~red~destroys the crystal!\n")
				error()
		end
		pp.itemColours = {colors.green, colors.lime, colors.orange, colors.blue, colors.red}
		R.subChoice	= menu.menu("Process Essences:", {"Inferium to Prudentium",
													"Prudentium to Tertium",
													"Tertium to Imperium",
													"Imperium to Supremium",
													"Supremium to Insanium"}, pp, "Type number + Enter") -- open essence menu options
		R.size = menu.getInteger("Quantity? 0 = all)", 0, 1024, nil, colors.orange, nil, 64)
	end

	return R
end

local function getTaskInventoryTo30(R)
	local retValue = {}
	local thanks = "Thank you.\n\nPress the ESC key\n\nStand Back..\n"
	--local pp = utils.getPrettyPrint()
	
	if R.choice == 0 then --Missing pickaxe
		T:checkInventoryForItem({"minecraft:diamond_pickaxe"}, {1})
		print("Diamond Pickaxe being tested...")
		T:setEquipment()
	elseif R.choice == 1 then --Missing crafting table
		T:checkInventoryForItem({"minecraft:crafting_table"}, {1}) -- 0 if not present
		print("Crafting table being tested...")
		T:setEquipment()
	elseif R.choice == 2 then --Missing chest
		T:checkInventoryForItem({"minecraft:chest"}, {1}) -- 0 if not present
		sleep(1.5)
		
	-- MINING
	
	elseif R.choice == 11 or R.choice == 12 then			-- ladder down / up / stairs down / stairs up
		local description = "Creating ladder going down"	-- default action description
		pp.itemColours = {colors.blue, colors.lightGray}
		pp.allowModifier = false -- only allow numbers to be returned
		local inAir = false
		local inNether = menu.getBoolean("Are you in the nether? (y/n) ", nil, colors.yellow, colors.black)
		
		if inNether then
			bedrock = 0 
			inAir = true
		end
		local option = menu.menu("Which direction?", {"Going down","Going up"}, pp) 
		if option == 1 then
			R.down = true
			R.height = menu.getInteger("Current level (F3->Y coord)? ", bedrock + 5, ceiling, nil, colors.lightGray)
			R.depth = menu.getInteger("Go down to level? ("..R.height - 2 .." to "..bedrock + 5 ..") ", bedrock + 5 , R.height - 2, nil, colors.blue)
			if R.choice == 11 then
				if menu.getBoolean("Build a shelter at base? (y/n) ", nil, colors.yellow, colors.black) then
					R.data = "chamber"
				end
			end
			if R.choice == 13 then
				description = "Creating stairs going down"
			end
		else
			R.up = true
			--R.depth = utils.getSize(true,"Current level (F3->Y coord)? ", bedrock + 5, ceiling)
			--R.height = utils.getSize(true, "Go up to level? ("..R.depth + 2 .." to "..ceiling ..")", R.depth + 2, ceiling)
			R.depth = menu.getInteger("Current level (F3->Y coord)? ", bedrock + 5, ceiling, nil, colors.blue)
			R.height = menu.getInteger("Go up to level? ("..R.depth + 2 .." to "..ceiling ..") ", R.depth + 2, ceiling, nil, colors.lightGray)
			if R.choice == 11 then
				description = "Creating ladder going up"
			else
				description = "Creating stairs going up"
			end
		end
		local range = math.abs(R.height - R.depth)
		
		if not inAir then
			inAir = menu.getBoolean("Are you in air (add blocks)? (y/n) ", nil, colors.yellow, colors.black)
		end
		--[[
		range examples
		-50 to -59 = -59 -(-50) = -9   down
		-59 to -50 = -50 -(-59) = 9    up
		 70 to -48 = -48 -   70 = -118 down
		  5 to  64 =  64 -   5  = 59   up
		]]
		T:checkInventoryForItem({"minecraft:bucket"}, {1}, false)
		if R.choice == 11 then -- ladders
			utils.checkFuelNeeded(range * 2)
			T:checkInventoryForItem({"minecraft:ladder"}, {range})
			T:checkInventoryForItem({"minecraft:torch"}, {math.floor(range / 3)}, false)
			if inAir then
				range = range * 4 -- more blocks needed
			end
			T:checkInventoryForItem({"stone"}, {range})
		else -- stairs
			utils.checkFuelNeeded(range * 10) -- stairs: each layer needs 10 moves
			local numStairsNeeded = range
			local data = T:getStock("stairs")
			local numStairs = data.total
			local cobbleNeeded = math.min(range * 6, 256)
			if inAir then
				cobbleNeeded = range * 6 -- 5 blocks / layer unless in water or lava
			end
			if numStairs < numStairsNeeded then
				cobbleNeeded = cobbleNeeded + (math.floor((2 * (numStairsNeeded - numStairs)) / 3))
			end
			T:checkInventoryForItem({"stairs"}, {numStairsNeeded}, false)
			T:checkInventoryForItem({"stone"}, {cobbleNeeded})
			T:checkInventoryForItem({"minecraft:chest"}, {1}) 	-- needed for crafting
		end
		menu.colourPrint(description, colors.lightBlue)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		if R.choice == 11 then
			retValue = createLadder(R) -- "bedrock", 70, -48
		else
			retValue = createStaircase(R)
		end
	elseif R.choice == 13 then --Create Mine at this level
		utils.checkFuelNeeded(960)
		T:checkInventoryForItem({"minecraft:torch"}, {24}, false)
		T:checkInventoryForItem({"minecraft:bucket"}, {1}, false)
		T:checkInventoryForItem({"stone"}, {64})
		T:checkInventoryForItem({"minecraft:chest"}, {1})
		menu.colourPrint("CreateMine starting", colors.lightBlue)
		sleep(2)
		retValue = createMine()
	elseif R.choice == 14 then	-- safe drop to water
		utils.checkFuelNeeded(R.height * 2)
		T:checkInventoryForItem({"minecraft:water_bucket"}, {1})
		T:checkInventoryForItem({"stone"}, {R.height * 2}, false) -- estimate only partial cloaking needed
		menu.colourPrint("Creating safe drop ".. R.height.. " blocks deep", colors.lightBlue)
		menu.colourPrint("Wait for my return!", colors.yellow)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		retValue = createSafeDrop(R)
	elseif R.choice == 15 then	-- single column bubble lift
		local needSigns = true
		utils.checkFuelNeeded(R.height * 6)
		--print(text, fg, bg, width)
		menu.colourPrint("Checking if near ladder", colors.red)
		T:turnRight(1)
		local blockType = T:getBlockType("forward")
		if blockType:find("ladder") == nil then
			T:turnLeft(2)
			blockType = T:getBlockType("forward")
			if blockType:find("ladder") ~= nil then
				needSigns = false
			end
			T:turnRight(1)
		else
			needSigns = false
			T:turnLeft(1)
		end
		sleep(1)
		if needSigns then
			T:checkInventoryForItem({"sign"}, {2}, true, "Ladder not found")
		else
			menu.colourPrint("Ladder found, signs not required", colors.orange)
			sleep(1)
		end
		if T:getBlockType("down"):find("bedrock") == nil then -- NOT bedrock below
			T:checkInventoryForItem({"minecraft:water_bucket"}, {3})
		else
			T:checkInventoryForItem({"minecraft:water_bucket"}, {2})
		end
		T:checkInventoryForItem({"minecraft:soul_sand", "minecraft:dirt"}, {1, 1}, true, "? use dirt as soul sand placeholder")
		T:checkInventoryForItem({"stone"}, {R.height * 4 + 10}, false) -- estimate only partial cloaking needed
		local _, slots = T:getFirstEmptySlot() -- returns first empty slot, no of empty slots
		T:checkInventoryForItem({"minecraft:bucket"}, {slots}, false, "More buckets = faster build!")
		menu.colourPrint("Creating bubble lift ".. R.height.. " blocks high", colors.lime)
		
		if needSigns then -- ladder present as signs not required
			menu.colourPrint("\nSTAND CLEAR!", colors.red)
		else
			menu.colourPrint("Wait at the top via ladder...", colors.orange)
			menu.colourPrint("\nSTAND ON THE LADDER FOR SAFETY!", colors.red)
		end
		menu.colourPrint("\nEnter to continue", colors.yellow)
		read()
		retValue = createBubbleLift(R)
	elseif R.choice == 16 then --QuickMine corridor
		utils.checkFuelNeeded((R.width * 2 + R.length * 2) * 2)
		T:checkInventoryForItem({"stone"}, {R.width * 2 + R.length * 2}, false)
		T:checkInventoryForItem({"minecraft:torch"}, {math.floor((R.width * 2 + R.length * 2) / R.torchInterval)}, false)
		T:checkInventoryForItem({"minecraft:bucket"}, {1}, false)
		menu.colourPrint("QuickMine corridor: R.subChoice "..R.width.. " x "..R.length, colors.lightBlue)
		retValue = quickMineCorridor(R)
	elseif R.choice == 17 then --QuickMine
		utils.checkFuelNeeded(R.width * R.length)
		T:checkInventoryForItem({"stone"}, {64})
		T:checkInventoryForItem({"minecraft:bucket"}, {1}, false)
		menu.colourPrint("QuickMine rectangle: R.subChoice "..R.width.. " x "..R.length, colors.lightBlue)
		retValue = quickMine(R)
	elseif R.choice == 18 then --Mine bedrock area
		utils.checkFuelNeeded(R.width * R.length)
		T:checkInventoryForItem({"stone"}, {64})
		T:checkInventoryForItem({"minecraft:bucket"}, {1}, false)
		retValue = mineBedrockArea(R) -- R.data = "leaveExposed" or ""
	elseif R.choice == 19 then	-- salvage mineshaft
		local equippedRight, equippedLeft, inInventory = T:setEquipment() -- check for crafting table, sword, pickaxe, Put sword in spare slot
		if equippedLeft ~= "minecraft:diamond_pickaxe" and equippedRight ~= "minecraft:diamond_pickaxe" then
			T:checkInventoryForItem({"minecraft:diamond_pickaxe"}, {1}, true)
			equippedRight, equippedLeft, inInventory = T:setEquipment() -- check for crafting table, sword, pickaxe, Put sword in spare slot
		end
		if inInventory ~= "minecraft:diamond_sword" then
			T:checkInventoryForItem({"minecraft:diamond_sword"}, {1}, false, "To harvest spider webs\nyou need a diamond sword.") --checkInventoryForItem(self, items, quantities, required, message, name)
		end
		if T:getItemSlot("minecraft:diamond_sword") > 0 then
			inInventory = "minecraft:diamond_sword"
		end
		T:checkInventoryForItem({"minecraft:torch"}, {R.torchInterval}, false)
		if inInventory == "minecraft:diamond_sword" then
			menu.colourPrint("Clearing Mineshaft and cobwebs", colors.orange)
		else
			menu.colourPrint("Clearing Mineshaft", colors.yellow)
		end
		retValue = clearMineshaft(R, equippedRight, equippedLeft, inInventory) -- pass whether the sword is present
		
	-- FORESTRY
	elseif R.choice == 21 then	-- Fell tree
		if T:isLog("forward") then
			if turtle.getFuelLevel() < 30 then
				T:checkInventoryForItem({"minecraft:chest"}, {1}, false,"Fuel level critical: "..turtle.getFuelLevel())
				turtle.select(1)
				T:dig("forward")
				T:craft("planks", 4)
				T:refuel()
				T:forward(1)
				T:up(2)
				T:craft("chest", 1)
			else
				T:forward(1)
			end
			menu.colourPrint("Felling tree", colors.lime)
			os.sleep(2)    -- pause for 2 secs to allow time to press esc
			T:harvestWholeTree("up")
			while turtle.down() do end
			retValue = {"Tree Harvested"}
		else
			retValue =
			{
				"No log in front..",
				"Move me in front of a tree!"
			}
		end
	elseif R.choice == 22 then --Create treefarm
		utils.checkFuelNeeded(900)
		if R.data == "convertStorage" or R.data == "convert" then
			T:checkInventoryForItem({"log"}, {1}, true, "Use log to indicate sapling type")
			T:checkInventoryForItem({"barrel"}, {2})
			T:checkInventoryForItem({"minecraft:hopper"}, {1})
			if R.data == "convertStorage" then
				T:checkInventoryForItem({"chest"}, {8})
				T:checkInventoryForItem({"wired_modem_full"}, {3})
				T:checkInventoryForItem({"computercraft:cable"}, {24})
			else
				T:checkInventoryForItem({"wired_modem_full"}, {2})
				T:checkInventoryForItem({"computercraft:cable"}, {22})
			end
		else
			T:checkInventoryForItem({"stone"}, {320})
			T:checkInventoryForItem({"minecraft:water_bucket"}, {4})
			T:checkInventoryForItem({"minecraft:hopper"}, {1})
			T:checkInventoryForItem({"log"}, {1}, true, "Use log to indicate sapling type")
			R.useBlockType = T:getMostItem("", true)
			T:checkInventoryForItem({"barrel"}, {2})
			if R.data == "new" then
				T:checkInventoryForItem({"chest"}, {8})
				T:checkInventoryForItem({"wired_modem_full"}, {3})
				T:checkInventoryForItem({"computercraft:cable"}, {24})
			else
				T:checkInventoryForItem({"wired_modem_full"}, {2})
				if R.data == "back" then
					T:checkInventoryForItem({"computercraft:cable"}, {34})
				else
					T:checkInventoryForItem({"computercraft:cable"}, {22})
				end
			end
			menu.colourPrint("Creating Tree Farm with "..R.useBlockType, colors.lime)
		end
		retValue = createTreefarm(R)
	elseif R.choice == 23 then -- Plant treefarm
		local sizeOptions = {"Single (4 saplings)","Double (8 saplings)","Mangrove style"}
		R.subChoice = menu.menu("Tree‐plant layout?", sizeOptions, pp, "1–3 + Enter")
		if not R.networkFarm then
			if R.subChoice == 1 then
				utils.checkFuelNeeded(180)
				T:checkInventoryForItem({"dirt"}, {16})
				T:checkInventoryForItem({"sapling"}, {16}, false, "Max 16. NOT dark oak")
			elseif R.subChoice == 2 then
				utils.checkFuelNeeded(180)
				T:checkInventoryForItem({"dirt"}, {16})
				T:checkInventoryForItem({"sapling"}, {16}, false, "Max 16. 4 saplings / tree")
			end
		end
		menu.colourPrint("plantTreefarm starting: size "..R.subChoice, colors.lime)
		retValue = plantTreefarm(R)
	elseif R.choice == 24 then	-- Harvest treefarm
		menu.colourPrint("Harvesting treefarm starting", colors.lime)
		retValue = harvestTreeFarm(R)
	elseif R.choice == 25 then	-- Build wall / fence
		utils.checkFuelNeeded(R.width * R.length * 2)
		local quantity = math.ceil((R.width + R.length) * 2.3)
		T:checkInventoryForItem({"wall", "fence"}, {quantity, quantity})
		if R.torchInterval > 0 then
			T:checkInventoryForItem({"minecraft:torch"}, {math.floor(quantity / R.torchInterval)}, false)
		end
		if R.data == "barrel" then
			T:checkInventoryForItem({"barrel"}, {4}, false)
		end
		R.useBlockType = T:getMostItem("", false) -- no excluded blocks, any block type
		menu.colourPrint("Creating "..R.width.." x "..R.length.." walled enclosure", colors.yellow)
		menu.colourPrint("Using: "..R.useBlockType, colors.orange)
		retValue = createWallOrFence(R)
	elseif R.choice == 26 then	-- clear natural forest
		T:checkInventoryForItem({"minecraft:chest"}, {1})
		T:checkInventoryForItem({"sapling"}, {64}, false)
		menu.colourPrint("Clearing and replanting trees", colors.lime)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		retValue = clearAndReplantTrees()
	end
	return retValue
end

local function getTaskInventoryTo70(R)
	local retValue = {}
	local thanks = "Thank you.\n\nPress the ESC key\n\nStand Back..\n"
	-- FARMING
	if R.choice == 31 then	-- Create modular farm
		utils.checkFuelNeeded(300)
		T:checkInventoryForItem({"stone"}, {64})
		T:checkInventoryForItem({"dirt"}, {128}, false)
		T:checkInventoryForItem({"water_bucket"}, {4})
		if R.networkFarm then	
			T:checkInventoryForItem({"barrel"}, {1})
			T:checkInventoryForItem({"chest",}, {8})
			T:checkInventoryForItem({"ladder",}, {5})
			T:checkInventoryForItem({"wired_modem_full"}, {3})
			T:checkInventoryForItem({"computercraft:cable"}, {70})
		else	-- conventional storage farm
			T:checkInventoryForItem({"chest", "barrel"}, {5,5})
		end
		T:checkInventoryForItem({"sapling"}, {1})
		R.useBlockType = T:getMostItem("dirt", true) -- exclude dirt from count
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		print("Creating modular farm with "..R.useBlockType)
		retValue = createFarm(R, "")
	elseif R.choice == 32 then	-- Extend modular farm
		utils.checkFuelNeeded(300)
		T:checkInventoryForItem({"sapling"}, {1})
		T:checkInventoryForItem({"stone"}, {64})
		T:checkInventoryForItem({"dirt"}, {128}, false)
		T:checkInventoryForItem({"water_bucket"}, {4})
		if R.networkFarm then	
			T:checkInventoryForItem({"barrel"}, {1})
			T:checkInventoryForItem({"ladder",}, {5})
			T:checkInventoryForItem({"wired_modem_full"}, {2})
			T:checkInventoryForItem({"computercraft:cable"}, {57})
		else	-- conventional storage farm
			T:checkInventoryForItem({"chest", "barrel"}, {5,5})
		end
		R.useBlockType = T:getMostItem("dirt", true) -- exclude dirt from count
		menu.colourPrint("Checking position...\n", colors.green)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		retValue = createFarmExtension(R) -- subChoice: 1 = ahead, 2 = to the right
	elseif R.choice == 33 then	-- manage modular farm
		-- inventory checked in function depending on option taken
		R.data = "farm"
		retValue = manageFarmSetup(R)
	elseif R.choice == 34 then	-- build single fence
		utils.checkFuelNeeded(R.length)
		T:checkInventoryForItem({"wall", "fence"}, {R.length, R.length})
		if R.torchInterval > 0 then
			T:checkInventoryForItem({"minecraft:torch"}, {math.ceil(R.length / R.torchInterval)}, false)
		end
		R.useBlockType = T:getMostItem("minecraft:torch") -- exclude torch
		menu.colourPrint("Creating "..R.length.." wall or fence", colors.green)
		menu.colourPrint("Using: "..R.useBlockType, colors.orange)
		retValue = createWallOrFence(R) -- barrels not included in R.data, R.width = 0 so only single length
	elseif R.choice == 35 then	-- build fence
		utils.checkFuelNeeded(R.width * R.length * 2)
		local quantity = math.ceil((R.width + R.length) * 2.3)
		T:checkInventoryForItem({"wall", "fence"}, {quantity, quantity})
		if R.torchInterval > 0 then
			T:checkInventoryForItem({"minecraft:torch"}, {math.floor(quantity / R.torchInterval)}, false)
		end
		R.useBlockType = T:getMostItem("minecraft:torch") -- exclude torch
		menu.colourPrint("Creating "..R.width.." x "..R.length.." walled enclosure", colors.green)
		menu.colourPrint("Using: "..R.useBlockType, colors.orange)
		retValue = createWallOrFence(R) -- barrels not included in R.data
	-- OBSIDIAN
	elseif R.choice == 41 then --harvest obsidian
		utils.checkFuelNeeded(R.width * R.length * 3)
		T:checkInventoryForItem({"stone"}, {R.width * R.length})
		T:checkInventoryForItem({"minecraft:bucket", "minecraft:lava_bucket"}, {1, 1}, false, "Get extra fuel as well!")
		menu.colourPrint("Harvesting obsidian area: size "..R.width.. " x "..R.length, colors.orange)
		sleep(2)
		retValue = harvestObsidian(R)
	elseif R.choice == 42 then --build nether portal
		utils.checkFuelNeeded(R.length * R.height * R.width)	-- length = width when facing standard = 5 high 4 length 1 width
		T:checkInventoryForItem({"minecraft:obsidian"}, {((R.length - 2 + R.height - 2) * R.width * 2)})
		T:checkInventoryForItem({"stone"}, {R.width * 4})
		R.useBlockType = T:getMostItem("obsidian", true) -- exclude obsidian from count
		menu.colourPrint("Building Nether portal", colors.orange)
		sleep(2)
		retValue = createPortal(R)
	elseif R.choice == 43 then --demolish nether portal
		utils.checkFuelNeeded(20)
		print("Demolishing Nether portal")
		retValue = demolishPortal(R)
	elseif R.choice == 44 then -- Strip mine Netherite
		utils.checkFuelNeeded(R.length * 2)
		T:checkInventoryForItem({"stone"}, {R.length * 4})
		R.useBlockType = T:getMostItem("", true) -- exclude none, use stone only/netherrack
		T:checkInventoryForItem({"cobble"}, {math.floor(R.length / 16) * 4}, true, "For marking Chunk boundaries")
		T:checkInventoryForItem({"minecraft:bucket", "minecraft:lava_bucket"}, {1, 1})
		T:checkInventoryForItem({"minecraft:torch"}, {math.floor(R.length / 16)}, false)
		retValue = createStripMine(R)
	elseif R.choice == 45 then --undermine dragon towers
		utils.checkFuelNeeded(500)
		T:checkInventoryForItem({"minecraft:cobblestone", "minecraft:cobbled_deepslate"}, {84, 84})
		print("Undermining dragon towers")
		retValue = undermineDragonTowers()
	elseif R.choice == 46 then --deactivate dragon tower
		utils.checkFuelNeeded(50)
		print("Deactivating dragon tower")
		retValue = deactivateDragonTower()
	elseif R.choice == 47 then --build dragon water trap
		utils.checkFuelNeeded(256)
		T:checkInventoryForItem({"stone"}, {356})
		T:checkInventoryForItem({"minecraft:obsidian"}, {1})
		T:checkInventoryForItem({"minecraft:ladder"}, {145})
		T:checkInventoryForItem({"minecraft:water_bucket"}, {1})
		print("Building dragon water trap")
		retValue = createDragonTrap()
	elseif R.choice == 48 then --build portal minecart station
		utils.checkFuelNeeded(200)
		menu.colourPrint("Inventory after height measurement", colors.red)
		menu.colourPrint("Enter to start measurement.", colors.lime)
		read()
		print("Building portal platform")
		retValue = createPortalPlatform()
	elseif R.choice == 49 then -- shulker harvesting
		retValue = harvestShulkers(R)
		
	-- CANAL BRIDGE
	elseif R.choice == 51 then	-- continuous path over void/water/lava
		utils.checkFuelNeeded(R.length) -- allow for R.length
		if R.data ~= "reduce" then
			T:checkInventoryForItem({"stone"}, {R.length}, false)
			if R.torchInterval > 0 then
				T:checkInventoryForItem({"minecraft:torch"}, {math.floor(R.length/R.torchInterval)}, false)
			end
			print("Building continuous path")
		end
		retValue = utils.createPath(R) -- returns {numBlocks}
	elseif R.choice == 52 then	-- simple 2 block corridor
		utils.checkFuelNeeded(R.length)
		T:checkInventoryForItem({"stone"}, {R.length * 2}, false)
		if R.torchInterval > 0 then
			T:checkInventoryForItem({"minecraft:torch"}, {math.ceil(R.length / R.torchInterval)}, false)
		end
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		print("Building simple corridor")
		retValue = createCorridor(R)
	elseif R.choice == 53 then	-- canal management
		local torches = 0
		local length = R.length
		if length > 0 then
			utils.checkFuelNeeded(length * 4) -- allow for 1024 R.length
			if R.torchInterval > 0 then
				torches = math.floor(length / R.torchInterval)
			end
		else
			utils.checkFuelNeeded(2048) -- allow for 1024 R.length
			length = 256
		end
		T:checkInventoryForItem({"stone"}, {length})
		R.useBlockType = T:getMostItem("", true) 
		if R.data == 1 or (R.data == 2 and (R.subChoice == 2 or R.subChoice == 3 or R.subChoice == 5 or R.subChoice == 6)) then
			T:checkInventoryForItem({"minecraft:water_bucket"}, {2})
		end
		if torches > 0 then
			T:checkInventoryForItem({"minecraft:torch"}, {torches}, false)
		end
		retValue = createWaterCanal(R)
	elseif R.choice == 54 then	-- ice canal
		local default = R.length
		if R.length > 0 then
			utils.checkFuelNeeded(R.length)
		else
			default = 64
			utils.checkFuelNeeded(default * 2) -- allow for 128 min R.length
		end
		--[[
			new canal
			1 = left towpath- move to centre left
			2 = centre left ice or hollow
			3 = centre right ice or hollow
			4 = right side - move to centre right
			convert water canal
			5 = left towpath
			6 = centre left ice or air
			7 = centre right ice or air
			8 = right towpath
		]]
		if R.subChoice <= 5 or R.subChoice == 8 then	-- towpath
			T:checkInventoryForItem({"slab"}, {default}, true, "Add slabs to length required")
		end
		if R.torchInterval > 0 then
			--checkInventoryForItem(items, quantities, required, message)
			T:checkInventoryForItem({"stone"}, {math.ceil(default / R.torchInterval)}, true, "NOT bricks!")
			R.useBlockType = T:getMostItem("", true) 
			T:checkInventoryForItem({"torch"}, {math.ceil(default / R.torchInterval)}, false)
		end
		if R.data == "ice" then	-- ice canal with 2 spaces above
			T:checkInventoryForItem({"minecraft:packed_ice", "minecraft:blue_ice"}, {math.ceil(R.length / 2), math.ceil(R.length / 2)}, false)
		end
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		print("Building ice canal")
		retValue = createIceCanal(R)
	elseif R.choice == 55 then -- platform
		local volume = R.width * R.length
		utils.checkFuelNeeded(volume)
		T:checkInventoryForItem({"stone", "dirt"}, {volume, volume})
		R.useBlockType = T:getMostItem("", true) 
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		print("Building platform")
		retValue = createPlatform(R)
	elseif R.choice == 56 then -- sinking platform
		local volume = (R.width + 1) * (R.length + 1) 
		utils.checkFuelNeeded(volume * (R.height + 1))
		T:checkInventoryForItem({"stone"}, {volume + ((R.length * 2) + (R.width * 2) * R.height) + 1})
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		print("Building sinking platform")
		retValue = createSinkingPlatform(R)
	elseif R.choice == 57 then -- boat bubble lift
		utils.checkFuelNeeded(R.height * 20)
		T:checkInventoryForItem({"minecraft:bucket","minecraft:water_bucket"}, {2, 2})
		T:checkInventoryForItem({"stone"}, {R.height * 10})
		T:checkInventoryForItem({"gate"}, {R.height * 2})
		T:checkInventoryForItem({"minecraft:soul_sand"}, {R.height * 2 + 2})
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		print("Building boat bubble lift")
		retValue = createBoatLift(R)
		--retValue = createBoatLift(R) -- R.subChoice:0=new, R.subChoice:1=extend, R.length:0=left, 1=right
		
	-- MOB SPAWNER
	elseif R.choice == 61 then	--  9x9 hollow cube cobble lined
		utils.checkFuelNeeded(600) -- allow for 600 moves
		T:checkInventoryForItem({"slab","stone"}, {1, 3}, true, "Slab can be crafted from 3 stone")
		if T:getItemSlot("stone") > 0 and T:getItemSlot("slab") == 0 then -- no slabs, but is stone
			local craftOK, message = T:craft("slab")
		end
		if R.data == "chest" then
			menu.colourText(nil, "~yellow~Chest(s) will be emptied first\nWait for me to exit and request\n~orange~around 700 stone!\n\n~lightGray~Enter to continue", true)
			read()
		else
			T:checkInventoryForItem({"stone"}, {512}, false, "Full cube uses ~700 blocks\nEstimate your requirements")
		end
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		retValue = createMobFarmCube(R) -- R.data = "spawner" or "chest": not blaze
	elseif R.choice == 62 then	-- Blaze spawner
		utils.checkFuelNeeded(2500) -- allow for 2500 moves
		if R.data == "blaze" then
			T:checkInventoryForItem({"slab"}, {122}, true)
			T:checkInventoryForItem({"stone"}, {576})
			print("You will be asked for more assets later")
			print("Enter to continue")
			read()
		end	 -- else R.data == "restart"
		retValue = createMobFarmCube(R)	--R.data = "blaze" or R.data = "restart"
	elseif R.choice == 63 then	--  flood mob spawner
		utils.checkFuelNeeded(60) -- allow for 60 moves
		T:checkInventoryForItem({"minecraft:water_bucket"}, {2})
		if R.subChoice == 1 then
			T:checkInventoryForItem({"fence"}, {2})
			T:checkInventoryForItem({"sign"}, {2})
			T:checkInventoryForItem({"slab"}, {1})
			T:checkInventoryForItem({"minecraft:soul_sand", "minecraft:dirt"}, {1, 1}, true)
		end
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		retValue = floodMobFarm(R)
	elseif R.choice == 64 then -- build bubble lift on top of soul sand
		utils.checkFuelNeeded(200) -- allow for 200 moves
		T:checkInventoryForItem({"slab","stone"}, {6, 3}, true, "Slabs can be crafted from 3 stone")
		if T:getItemSlot("stone") > 0 and T:getItemSlot("slab") == 0 then -- no slabs, but is stone
			local craftOK, message = T:craft("slab")
		end
		T:checkInventoryForItem({"minecraft:water_bucket"}, {2})
		T:checkInventoryForItem({"stone"}, {256})
		if T:getBlockType("down") ~= "minecraft:soul_sand" then
			T:checkInventoryForItem({"minecraft:soul_sand"}, {1})
		end
		T:checkInventoryForItem({"hopper"}, {1}, false)
		if T:getItemSlot("hopper") > 0 then
			T:checkInventoryForItem({"chest"}, {2})
		end
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		retValue = createMobBubbleLift(R)
	elseif R.choice == 65 then -- computercraft mob grinder
		utils.checkFuelNeeded(1000) -- allow for 1000 moves
		T:checkInventoryForItem({"stone"}, {256}) -- for ceiling, walls and floor of area
		R.useBlockType = T:getMostItem("", true) -- stone only, no exclusions
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		retValue = createMobGrinder(R)
	elseif R.choice == 66 then -- build endermen tower
		-- build in 3 sections, base, tower, top
		getTaskHelp(2, 66) -- compulsory help display
		read() -- pause until user ready
		local numFuel = 700
		local choices = 
		{
			"New tower lower base",
			"Add tower upper base + killzone",
			"128 block tower to existing base"
		}
		pp.itemColours = {colors.lime, colors.orange, colors.green}
		local option, modifier = menu.menu("Select build stage:", choices, pp)
		if option == 1 then --lower base
			T:checkInventoryForItem({"minecraft:chest"}, {1})
			T:place("chest", "down", false)
			T:emptyInventory("up")
			utils.checkFuelNeeded(320) -- allow for 320 moves
			T:checkInventoryForItem({"stone"}, {144}) -- <3 stacks
			T:checkInventoryForItem({"minecraft:water_bucket"}, {2})
			T:checkInventoryForItem({"fence"}, {4})
			T:checkInventoryForItem({"sign"}, {4})
			T:checkInventoryForItem({"door"}, {2})
			T:checkInventoryForItem({"minecraft:soul_sand"}, {1})
		elseif option == 2 then -- upper base
			utils.checkFuelNeeded(710) -- allow for 703 moves
			T:checkInventoryForItem({"stone"}, {384}) -- 6 stacks
			T:checkInventoryForItem({"minecraft:bucket"}, {4})
			T:checkInventoryForItem({"fence"}, {15})
			T:checkInventoryForItem({"sign"}, {4})
			T:checkInventoryForItem({"ladder"}, {3})
			T:checkInventoryForItem({"minecraft:soul_sand"}, {1})
		else -- main tower
			utils.checkFuelNeeded(3000) -- allow for 3000 moves
			if T:getBlockType("down") ~= "minecraft:chest" then
				T:checkInventoryForItem({"minecraft:chest"}, {1})
				T:place("chest", "down", false)
			end
			T:checkInventoryForItem({"stone"}, {768}) -- 12 stacks
			T:checkInventoryForItem({"minecraft:bucket"}, {10})
			T:checkInventoryForItem({"fence"}, {64})	-- 1 stacks		
		end
		print(thanks)
		os.sleep(2)    -- pause for 2 secs to allow time to press esc
		retValue = createEnderTower(option) -- 1, 2, or 3
	elseif R.choice == 67 then -- surround Trial spawner
		utils.checkFuelNeeded(200) -- allow for 1000 moves
		T:checkInventoryForItem({"stone"}, {57}) -- for covering spawner
		R.useBlockType = T:getMostItem("", false) -- use whatever block type available
		R.height = 3
		R.width = 5
		R.length = 5
		retValue = createTrialCover(R)
	end
	return retValue
end

local function getTaskInventory(R)
	-- run this loop 2x per second to check if player has put anything in the inventory
	-- fuel 1 coal = 60 = 4 planks. 64 planks = 16 coal = 960 units
	local retValue = {}
	local thanks = "Thank you.\n\nPress the ESC key\n\nStand Back..\n"
	
	if R and type(R.choice) == "number" and R.choice < 31 then
		return getTaskInventoryTo30(R) -- Mining, Forestry
	elseif  R and type(R.choice) == "number" and R.choice < 71 then
		return getTaskInventoryTo70(R) -- Farming, Obsidian, Canal / Bridge
	elseif  R and type(R.choice) == "number" and R.choice > 500 and R.choice < 700 then
		return getTaskInventoryTo70(R)
	else -- Area carving, Lava/Water, Railway
		-- AREA CARVING
		if R and type(R.choice) == "number" and R.choice == 71 then --Clear area
			utils.checkFuelNeeded(R.width * R.length * 3)
			if R.useBlockType == "dirt" then
				T:checkInventoryForItem({"minecraft:dirt"}, {R.width * R.length})
			end
			print(thanks)
			sleep(2)
			print("Clearing area: size "..R.width.. " x "..R.length)
			retValue = clearArea(R)
		elseif R.choice == 72 then --Clear rectangle
			-- R.choice, R.width(R.subChoice), R.length(R.width), up(R.length), down(R.height) from getTask()
			utils.checkFuelNeeded(R.width * R.length)
			print("Clearing rectangle: size "..R.width.. " x "..R.length)
			retValue = clearRectangle(R)
		elseif R.choice == 73 then --Clear wall
			utils.checkFuelNeeded(R.length * R.height)
			print("Removing wall "..R.length.." long x "..R.height.." high")
			retValue = clearWall(R)
		elseif R.choice == 74 then --Clear single R.height perimeter wall
			utils.checkFuelNeeded((R.width + R.length) * 2)
			print("Recycling wall section "..R.width.." x "..R.length)
			retValue = clearPerimeter(R)
		elseif R.choice == 75 then --Clear hollow structure
			utils.checkFuelNeeded((R.width * R.length) + ((R.width + R.length) * R.height))
			print("Recycling hollow object "..R.width.." x "..R.length.." height: "..R.height)
			retValue = clearBuilding(R)
		elseif R.choice == 76 then --Clear solid structure / extend water pool
			utils.checkFuelNeeded((R.width * R.length) + ((R.width + R.length) * R.height))
			print("Recycling solid object w:"..R.width..", l:"..R.length..", h:"..R.height)
			retValue = clearSolid(R)
		elseif R.choice == 77 then	-- Dig trench
			utils.checkFuelNeeded(R.height * R.length * 2)
			print(thanks)
			os.sleep(2)    -- pause for 2 secs to allow time to press esc
			if R.length == 0 then
				print("Digging continuous trench "..R.height.." blocks deep")
			else
				print("Digging trench "..R.length.." blocks long, "..R.height.." blocks deep")
			end
			retValue = digTrench(R)
		elseif R.choice == 78 then --Carve mountain
			utils.checkFuelNeeded(R.length * R.width * 10)
			print("Carving mountain side "..R.width.." x "..R.length)
			retValue = clearMountainSide(R)
		elseif R.choice == 79 then -- Place floor or Ceiling
			local blocks = R.width * R.length
			utils.checkFuelNeeded(blocks)
			T:clear()
			local inventory = T:getInventory()
			repeat
				T:clear()
				--colourText(row, text, reset)
				menu.colourText(1, "~yellow~Add floor/ceiling blocks to inventory", false)
				menu.colourText(2, "~orange~Multiple types will allow patterns", false)
				if blocks - inventory.blockCount > 0 then
					menu.colourText(3, "~lime~Add ~red~"..blocks - inventory.blockCount .." ~lime~blocks", false)
				else
					menu.colourText(3, "~lime~Minimum number of blocks recieved ~red~("..blocks..")", false)
					menu.colourText(5, "~yellow~Add more or press ~red~'Enter'~yellow~ to start", true)
				end
				
				inventory = T:updateInventory() -- returns inventory or nil if key pressed
			until inventory == nil
			--T:checkInventoryForItem({"stone", "log", "planks"}, {blocks, blocks, blocks}, false)
			R.inventory = T:getInventory()
			--[[
				{
				inventory["minecraft:cobblestone"] = 128
				inventory["minecraft:stone"] = 64
				inventory.names = {minecraft:cobblestone, minecraft:stone}
				inventory.quantities = {128, 64}
				inventory.blockTypeCount = 2,
				inventory.blockCount = 196,
				inventory.useBlock = "minecraft:cobblestone"
				inventory.mostBlock = "minecraft:cobblestone"
				inventory.mostCount = 128
				}
			]]
			R.useBlockType = R.inventory.useBlock
			-- check if > 1 type of material, then use R.data == "random"
			T:clear()
			if R.inventory.blockTypeCount > 1 then
				local choice, modifier
				local choices = {"Random block placement", "Striped pattern"}
				pp.itemColours = {colors.lime, colors.orange}
				if R.inventory.blockTypeCount == 2 then
					table.insert(choices, "Checkerboard pattern")
					table.insert(pp.itemColours, colors.green)
				end
				choice, modifier = menu.menu("Layout pattern?", choices, pp, "Type number + Enter ")
				if choice == 1 then
					R.data = "random"
				elseif choice == 2 then
					R.data = "striped"
				else
					R.data = "checked"
				end
			end
			retValue = createFloorCeiling(R) -- R.subChoice integer 1 to 4
		elseif R.choice == 710 then -- direct commands
			utils.checkFuelNeeded(200)
			createRectanglePath(R)
			
-- LAVA WATER
		elseif R.choice == 81 then -- Sand based utilities
			if R.subChoice == 1 then	-- Drop sand or gravel wall
				utils.checkFuelNeeded(100)
				T:checkInventoryForItem({"sand", "gravel"}, {1024, 1024}, false)
				if R.length == 0 then
					print("Building sand wall. Auto length: ")
				else
					print("Building sand wall. length: "..R.length)
				end
				retValue = createSandWall(R)
			elseif R.subChoice == 2 then	-- Fill area with sand
				utils.checkFuelNeeded(R.length * R.width)
				T:checkInventoryForItem({"sand"}, {1024}, false)
				print("Filling area with sand. length: "..R.length.." width: "..R.width)
				retValue = sandFillArea(R)
			elseif R.subChoice == 3 then -- Clear sand wall
				utils.checkFuelNeeded(200)
				if R.length == 0 then
					print("Digging sand. Auto length")
				else
					print("Digging sand. length: "..R.length)
				end
				retValue = clearSandWall(R)
			elseif R.subChoice == 4 then	-- Clear sand filled area
				utils.checkFuelNeeded(R.length * R.width * 4)
				print("Removing sand cube. length: "..R.length.." width: "..R.width)
				retValue = clearSandCube(R)
			end
		
		elseif R.choice == 82 then --build containing wall in water or lava
			utils.checkFuelNeeded(R.length * R.length)
			local depth = R.height
			if depth == 0 then
				depth = 20
			end
			T:checkInventoryForItem({"stone"}, {R.length * depth}, false)
			print("Building retaining wall in lava/water. length "..R.length)
			retValue = createRetainingWall(R)			
		elseif R.choice == 83 then -- create a rectangle path in water/lava
			utils.checkFuelNeeded(200)
			createRectanglePath(R)
		elseif  R.choice == 84 then -- Delete water/lava
			if R.width == 0 then
				utils.checkFuelNeeded(2000)
				T:checkInventoryForItem({"stone"}, {256}, false)
				print("Deleting water using auto-detection")
			else
				if R.height == 0 then
					utils.checkFuelNeeded(2000)
					T:checkInventoryForItem({"stone"}, {256}, false)
				else
					utils.checkFuelNeeded(R.width * R.length * R.height)
					T:checkInventoryForItem({"stone"}, {math.max(R.length, R.width) * 2}, false)
				end
				print("Deleting enclosed water "..R.width.." x "..R.length.." x ".. R.height)
			end
			retValue = utils.drainWaterLava(R)
		elseif  R.choice == 85 then -- Sinking platform
			local volume = (R.width + 1) * (R.length + 1) 
			utils.checkFuelNeeded(volume * (R.height + 1))
			T:checkInventoryForItem({"stone"}, {volume + ((R.length * 2) + (R.width * 2) * R.height) + 1})
			print(thanks)
			os.sleep(2)    -- pause for 2 secs to allow time to press esc
			print("Building sinking platform")
			retValue = createSinkingPlatform(R)
		elseif R.choice == 86 then -- ocean monument utilities
			if R.subChoice == 1 then	-- Build 4 corner marker columns
				--R.useBlockType = "prismarine", R.data = "oceanMonumentColumns"
				T:checkInventoryForItem({"stone"}, {448})
				retValue = oceanMonumentColumns(R)
			elseif R.subChoice == 2 then	-- Retaining wall beween 2 columns
				T:checkInventoryForItem({"stone"}, {1024})
				retValue = createRetainingWall(R)
			elseif R.subChoice == 3 then	-- Clear plants pre sand draining
				retValue = clearWaterPlants(R)
			elseif R.subChoice == 4 then	-- Use sand draining
				utils.checkFuelNeeded(100)
				T:checkInventoryForItem({"sand", "gravel"}, {1024, 1024}, false)
				if R.length == 0 then
					print("Building sand wall. Auto length: ")
				else
					print("Building sand wall. length: "..R.length)
				end
				retValue = createSandWall(R)
			elseif R.subChoice == 5 then	-- remove sand wall
				utils.checkFuelNeeded(200)
				print("Digging sand from ocean monument")
				retValue = clearSandWall(R)
			elseif R.subChoice == 6 then	-- Drain and remove structure
				T:checkInventoryForItem({"stone"}, {1024})
				retValue = utils.drainWaterLava(R)
			end
		elseif R.choice == 87 then --ladder to water/lava
			utils.checkFuelNeeded(R.height * 2)
			T:checkInventoryForItem({"minecraft:ladder"}, {R.height}, true, "Add more to be safe!")
			local cobble = R.height * 3 + 10
			T:checkInventoryForItem({"stone"}, {cobble})
			print(thanks)
			os.sleep(2)    -- pause for 2 secs to allow time to press esc
			print("Creating ladder to bedrock")
			retValue = createLadderToWater()
		elseif R.choice == 88 then --remove plants
			utils.checkFuelNeeded(R.length * R.width * 4)
			T:checkInventoryForItem({"sand", "stone"}, {64, 64})
			local width = R.width
			local length = R.length
			if width == 0 then
				width = "auto"
			end
			if length == 0 then
				length = "auto"
			end
			print("Removing water plants. length: "..length.." width: "..width)
			retValue = clearWaterPlants(R)
		elseif R.choice == 89 then -- convert flowing water to source
			--utils.checkFuelNeeded(R.length * R.width * 4) -- unknown as size not calculated
			T:checkInventoryForItem({"water_bucket", "bucket"}, {12, 12})
			T:checkInventoryForItem({"slab"}, {128})
			print("Converting water to source "..R.width.." x "..R.length.." x ".. R.height)
			retValue = convertWater(R)
		elseif R.choice == 810 then -- create sloping water
			utils.checkFuelNeeded(R.length * R.width * 3)
			local buckets = math.floor(R.length / 2) + 1
			T:checkInventoryForItem({"water_bucket", "bucket"}, {buckets, buckets})
			T:checkInventoryForItem({"slab"}, {R.length * R.width})
			print("Creating sloping water field "..R.width.." x "..R.length.." x ".. R.height)
			retValue = createSlopingWater(R)
		-- BUILDING & RAILWAY
		elseif R.choice == 91 then -- Build a wall
			local blocks = R.height * R.length 
			utils.checkFuelNeeded(blocks)
			T:checkInventoryForItem({"stone", "planks", "bricks"}, {blocks, blocks, blocks})
			R.useBlockType = T:getMostItem()
			print("Building a wall using "..R.useBlockType)
			sleep(2)
			retValue = buildWall(R)
		elseif R.choice == 92 then -- Build a rectangular structure
			local blocks = (R.height * R.length * 2) + (R.height * R.width * 2)
			utils.checkFuelNeeded(blocks)
			T:checkInventoryForItem({"stone", "planks", "bricks"}, {blocks, blocks, blocks})
			R.useBlockType = T:getMostItem()
			print("Building a house using "..R.useBlockType)
			sleep(2)
			retValue = buildStructure(R)
		elseif R.choice == 93 or R.choice == 94 then -- Build a gable end roof / pitched roof
			local blocks = ((R.width + 2) * (R.length + 2))
			utils.checkFuelNeeded(blocks)
			if menu.getBoolean("Using stairs / planks for roof (y/n)", nil, colors.yellow) then
				T:checkInventoryForItem({"planks", "stairs"}, {blocks, blocks})
			else
				T:checkInventoryForItem({"stone"}, {blocks})
			end
			
			R.useBlockType = T:getMostItem()
			if R.choice == 93 then 				-- Build a gableroof
				if R.width % 2 == 1 then
					T:checkInventoryForItem({"slab"}, {R.length + 2}, false, "Match slabs with roof blocks")
				end
				blocks = (R.width * 6)
				T:checkInventoryForItem({"stone", "planks", "bricks"}, {blocks, blocks, blocks}, true, "Match gable with existing building")
			else
				local isWidthOdd, isLengthOdd, width, length = false, false, 0, 0
				R, isWidthOdd, isLengthOdd, width, length = utils.getRoofStats(R)
				if isWidthOdd then
					T:checkInventoryForItem({"slab"}, {length - 2}, false, "Match slabs with roof blocks")
				end
			end
			print("Building a roof using "..R.useBlockType)
			sleep(2)
			if R.choice == 93 then 				-- Build a gableroof
				retValue = buildGableRoof(R)
			else								-- Build a pitched roof
				retValue = buildPitchedRoof(R)
			end
		elseif R.choice == 95 or R.choice == 96 then --place redstone torch level or downward slope
			utils.checkFuelNeeded(10)
			if R.choice == 95 then
				R.data = "level"
			else
				R.data = "up"
			end
			T:checkInventoryForItem({"stone"}, {1})
			R.useBlockType = T:getMostItem("", true)
			T:checkInventoryForItem({"minecraft:redstone_torch"}, {1})
			print("Placing redstone torch on ".. R.useBlockType)
			retValue = placeRedstoneTorch(R)
		elseif R.choice == 97 or R.choice == 98 then --build downward/upward slope
			local blocks = R.height * 2
			if R.height == 0 then
				blocks = 64
			end
			utils.checkFuelNeeded(blocks)
			T:checkInventoryForItem({"stone"}, {blocks})
			print("Building slope")
			sleep(2)
			retValue = createRailway(R)
		elseif R.choice == 101 or R.choice == 102 or R.choice == 103 or R.choice == 104 then -- measure height/depth/length
			retValue = measure(R)
		elseif R.choice == 105 then--Borehole
			retValue = createBorehole(R)
		elseif R.choice == 111 then	--craft an item
			retValue = utils.craftItem(R)
		elseif R.choice == 112 then	--MysticalAgriculture essence conversion
			retValue = utils.convertEssence(R)
		end
	end
	return retValue
end

local function test(R)
	-- allows testing any new functions.
	-- use tk test
	T:saveToLog("test() started")
	menu.clear()
	T:emptyTrash("up")
	return {"function 'test' executed successfully"}
end

local function main()
	local lib = {}
	
	function lib.checkLabel()
		if os.getComputerLabel() == nil then
			os.setComputerLabel("toolkit")
			print("Computer label set to "..os.getComputerLabel())
		end
	end
	
	function lib.checkLibs(libDir, filename)
		local fileExists = false
		if fs.exists(libDir) then
			if not fs.isDir(libDir) then
				fs.move(libDir, libDir.."Renamed")
				fs.makeDir(libDir)
			end
		else
			fs.makeDir(libDir)
		end
		if fs.exists(fs.combine(libDir, filename)) or fs.exists(fs.combine(libDir, filename..".lua")) then
			fileExists = true
		end
		return fileExists
	end
	
	local doContinue = true
	lib.checkLabel() -- make sure turtle label is set
	--check if lib folder exists
	if not lib.checkLibs("lib", "clsTurtle") then
		-- use pastebin get to download clsTurtle to libs folder
		print("Missing clsTurtle.lua in libs directory")
		print("Attempting to obtain from Pastebin...")
		if shell.run("pastebin","get","tvfj90gK","lib/clsTurtle.lua") then
			print("clsTurtle.lua installed from Pastebin")
		else
			print("failed to install clsTurtle.lua from Pastebin")
			doContinue = false
		end
	end
	if not lib.checkLibs("lib", "menu") then
		-- use pastebin get to download menu.lua to libs folder
		print("Missing menu.lua in libs directory")
		print("Attempting to obtain from Pastebin...")
		if shell.run("pastebin","get","BhjbYsw4","lib/menu.lua") then
			print("menu.lua installed from Pastebin")
		else
			print("failed to install menu.lua from Pastebin")
			doContinue = false
		end
	end
	if doContinue then
		local result = {}
		local R =
		{
			choice = 0,
			currentLevel = 0,
			subChoice = 0,
			size = 0,
			width = 0,
			length = 0,
			height = 0,
			depth = 0,
			up = false,
			down = false,
			silent = false,
			data = {},
			torchInterval = 0,
			useBlockType = "",
			auto = false,
			side = "",
			direction = "",
			ready = false,
			networkFarm = false,
			mysticalAgriculture = false,
			logType = "",
			treeSize = "",
			message = "",
			inventory = {}
		}
		menu = require("lib.menu")
		--T = require("lib.clsTurtle").new(false) -- true enables logfile to log.txt note dot NOT colon
		T = require("lib.clsTurtle").new(true) -- true enables logfile to log.txt note dot NOT colon
		T:clear()
		doContinue = false	-- reset
		if args[1] ~= nil then
			if args[1]:sub(1,1) == "h" then
				local help =
[[... = any following characters

tk v...     = mc/ccTweaked versions
tk log      = enable logging
tk log d... = enable logging + debug
tk find     = writes locate.txt 
tk test     = runs test(R)
tk farm     = runs manageFarm(R)



Enter to exit]]
				menu.colourPrint(help, colours.yellow)
				read()
			elseif args[1] == "log" then
				if args[2] ~= nil then
					if args[2]:sub(1,1) == "d" then
						dbug = true	-- set dbug flag
						menu.colourPrint("Logging and debugging enabled", colors.lime)
					end
				else
					menu.colourPrint("Logging enabled", colors.lime)
				end
				if T:getLogExists() then
					if menu.getBoolean("Delete existing log file? (y/n)", 3, colors.orange) then
						T:deleteLog()
						menu.colourPrint("Log file deleted", colors.yellow)
					end
				end
				T:setUseLog(true)
				doContinue = true
				utils.waitForInput()
				--if dbug then
					--menu.colourPrint("Enter to continue...", colors.lightBlue)
					--read()
				--end
			elseif args[1] == "farm" then
				R.silent = true
				R.data = "farm"
				R.auto = true
				manageFarm(R)
			--elseif args[1] == "tree" then
				--R.silent = true
				--R.data = "treefarm"
				--R.auto = true
				--manageTreeFarm(R) -- use file to read status
			elseif args[1] == "find" then
				-- missing turtle: player used 'tk find'
				T:setUseLog(true)
				T:setLogFileName("locate.txt")
				T:appendLine("Booting succeeded")
				T:appendLine("Block ahead: "..T:getBlockType("forward"))
				T:appendLine("Block above: "..T:getBlockType("up"))
				T:appendLine("Block below: "..T:getBlockType("down"))
			elseif args[1] == "test" then
				test(R)
			elseif args[1]:find("v") ~= nil then
				print("_HOST:")
				print()
				print(_HOST)
				print()
				print("Minecraft major version: "..mcMajorVersion)
				print("Minecraft minor version: "..mcMinorVersion)
				print("ccTweaked major version: "..ccMajorVersion)
				print("ccTweaked minor version: "..ccMinorVersion)
				print("tk version:              "..tkVersion)
				print("clsTurtle version:       "..version)
				print("\nEnter to exit")
				read()
			end
		else
			doContinue = true
		end
		if doContinue then
			print("Minecraft major version: "..mcMajorVersion)
			print("Bedrock level: "..bedrock)
-- T:setUseLog(use, filename, delete)
--T:setUseLog(true, "log.txt", true)
			if T:getUseLog() then
				if T:saveToLog("Started with logging enabled", true) then
					menu.colourPrint("\nEnter to continue...", colors.lightBlue)
					read()
				end
			else
				print("Logging disabled")
			end	
			sleep(1)
			while R.choice == 0 do
				R = chooseTask(R)
			end
			if R.choice > 0 then
				R = getTask(R)
				if R.data ~= "quit" then
					result = getTaskInventory(R) -- table of comments
				end
			end
		end
		T:clear()
		table.insert(result, "Thank you for using 'survival toolkit'")
		local clr = {colors.yellow, colors.orange, colors.green, colors.lightBlue}
		local count = 1
		for _, value in ipairs(result) do
			--print(value)
			--.print(text, fg, bg, width)
			menu.colourPrint(tostring(value), clr[count])
			count = count + 1
			if count > #clr then
				count = 1
			end
		end
	else
		print("Add missing files and restart")
	end
end

main()
