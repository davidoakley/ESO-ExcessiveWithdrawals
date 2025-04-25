ExcessiveWithdrawals = {
	db = nil,
	name = "ExcessiveWithdrawals",
	addonName = "Excessive Withdrawals",
	displayName = "|cc40000Excessive Withdrawals|r",
	scanInterval = 600000,
	defaults = {
		building = false,
		warnings = false,
		gUser = "",
		ignoreAmt = "500",
		lastEvent = {},
		userData = {}
	}
}
function ExcessiveWithdrawals:AnalyzeUsers(guildId, guildName)
	local userRanks = self:CheckGuildRank(guildId, self.db.guildRank)
	local ignoreAmt = tonumber(self.db.ignoreAmt)
	if ignoreAmt == nil then ignoreAmt = 0 end
	local dRank, dAmt = nil
	if tonumber(self.db.demoteAmt) ~= nil and tonumber(self.db.demoteRank) ~= nil then
		local _, _, cRank, _, _ = GetGuildMemberInfo(guildId, GetGuildMemberIndexFromDisplayName(guildId, GetDisplayName()))
		if DoesGuildRankHavePermission(guildId, cRank, GUILD_PERMISSION_DEMOTE) == true then
			dAmt = tonumber(self.db.demoteAmt)
			dRank = tonumber(self.db.demoteRank)
			if dRank > GetNumGuildRanks(guildId) then dRank = GetNumGuildRanks(guildId) end
		end
	end

	for user, arr in pairs(self.db.userData[guildName]) do
		if arr.ignore ~= true and userRanks[user] ~= true then
			local balance = arr.goldDeposit - arr.goldWithdraw + arr.itemsDepositVal - arr.itemsWithdrawVal
			if (dAmt ~= nil and (dAmt + balance) < 0) or (ignoreAmt + balance) < 0 then
				if userRanks[user] == nil then
					CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- \n|cFF0000Warning!  Warning!  Warning!|r\n" .. arr.userName .. " exceeded the guild bank allowance and is no longer a member!")
				else
					local uRank
					if dAmt ~= nil and (dAmt + balance) < 0 then
						_, _, uRank, _, _ = GetGuildMemberInfo(guildId, GetGuildMemberIndexFromDisplayName(guildId, arr.userName))
					end
					if dRank ~= nil and uRank ~= nil and dRank > uRank then
						while dRank > uRank do
							zo_callLater(function()
								GuildDemote(guildId, arr.userName)
							end, 1000 * uRank)
							uRank = uRank + 1
						end
						CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- \n|cFF0000Warning: " .. arr.userName .. " has violated the guild bank allowance and has been automatically demoted.")
					else
						CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- \n|cFF0000Warning: " .. arr.userName .. " has exceeded the guild bank allowance.")
					end
				end
			end
		end
	end
end

local function processItems(self, lib, guildID, eventCategory)
	d("process")
	local guildName = self.db.guild
	local processor = lib:CreateGuildHistoryProcessor(guildID, eventCategory, "ExcessiveWithdrawals")
	if not processor then
		-- the processor could not be created
		return
	end

	local now = GetTimeStamp()

	local started = processor:StartIteratingTimeRange(now - 24*60*60, now, function(event)
		self:ProcessEvent(event)
		self.db.lastEvent[guildName][eventCategory] = event:GetEventInfo().eventId
	end, function(reason)
		if (reason == LibHistoire.StopReason.ITERATION_COMPLETED or reason == LibHistoire.StopReason.LAST_CACHED_EVENT_REACHED) then
			-- all events in the time range have been processed
			d("FINISHED")
			self:AnalyzeUsers(guildID, guildName)
		else
			d("Iterator failed to finish, reason "..reason)
			-- the iteration has stopped early for some reason and not all events have been processed
		end
	end)
end

function ExcessiveWithdrawals:MonitorGuild()
	EVENT_MANAGER:UnregisterForUpdate(self.name)
	if self.db.guild == nil or self.db.guild == "-" or self:GetGuild(self.db.guild) == false or self.defaults.building == true then return end
	local guildName = self.db.guild
	local guildId = self:GetGuild(guildName)
	if guildId == false then return end

	if self.db.userData[guildName] == nil then self.db.userData[guildName] = {} end
	if self.db.lastEvent[guildName] == nil then self.db.lastEvent[guildName] = {} end

	--local startTimestamp = self.db.lastEvent[guildName]
	--if startTimestamp == nil then startTimestamp = 1 end
	--local currentTimestamp = GetTimeStamp()

	LibHistoire:OnReady(function(lib)

		processItems(self, lib, guildId, GUILD_HISTORY_EVENT_CATEGORY_BANKED_ITEM)

	end)
end

function ExcessiveWithdrawals:GetUser(user, timestampS)
	local guildName = self.db.guild

	if self.db.userData[guildName][string.lower(user)] == nil then
		d("Creating user "..string.lower(user))
		self.db.userData[guildName][string.lower(user)] = {
			userName = user,
			initialScan = timestampS,
			itemsDeposit = 0,
			itemsWithdraw = 0,
			itemsDepositVal = 0,
			itemsWithdrawVal = 0,
			goldDeposit = 0,
			goldWithdraw = 0,
			ignore = false
		}
	end

	return self.db.userData[guildName][string.lower(user)]
end

function ExcessiveWithdrawals:ProcessEvent(event)
	local info = event:GetEventInfo()
	local user = "@"..info.displayName
	local userObj = self:GetUser(user, event:GetEventTimestampS())
	d("Event for user "..string.lower(user))


	if info.displayName ~= nil then
		--self:AddEventToTransactions(transactions, type, "@"..info.displayName, info.quantity, info.itemLink)
	end

	if eventType == GUILD_EVENT_BANKGOLD_ADDED or eventType == GUILD_EVENT_BANKGOLD_REMOVED then
		self:ProcessCashEvent(userObj, event, info)
	else
		self:ProcessItemEvent(userObj, event, info)
	end
end

function ExcessiveWithdrawals:ProcessItemEvent(userObj, event, info)
	--local eventTime = event:GetEventTimestampS()
	--local category = event:GetEventCategory()
	local type = event:GetEventType()
	local qty = info.quantity

	if qty < 0 then qty = qty * -1 end
	local price = (info.quantity ~= 0) and self:GetPrice(info.itemLink) * qty or 0

	if type == GUILD_HISTORY_BANKED_ITEM_EVENT_ADDED then
		userObj.itemsDeposit = userObj.itemsDeposit + qty
		userObj.itemsDepositVal = userObj.itemsDepositVal + price
	else
		userObj.itemsWithdraw = userObj.itemsWithdraw + qty
		userObj.itemsWithdrawVal = userObj.itemsWithdrawVal + price
	end

	if info.quantity < 0 then userObj.ignore = false end
end

function ExcessiveWithdrawals:CheckData(user)
	if ExcessiveWithdrawals.db.guild == nil then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: No guild is selected.|r\nType "/exwithdraw" to configure.')
		return false
	elseif ExcessiveWithdrawals.db.userData[self.db.guild] == nil then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: No data collected for ' .. self.db.guild .. '.')
		return false
	elseif user == nil or user == "" then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: You must enter a username.')
		return false
	elseif ExcessiveWithdrawals.db.userData[self.db.guild][string.lower(user)] == nil then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: ' .. user .. ' does not currently have any statistics.')
		return false
	end
	return true
end

function ExcessiveWithdrawals:CommaValue(amount)
	amount = zo_round(amount)
	local formatted = amount
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then break end
	end
	return formatted
end

function ExcessiveWithdrawals:ShowDisabled(showHint)
	if self.db.guild == nil or self.db.userData == nil or self.db.userData[self.db.guild] == nil then
		if self.db.guild == nil then
			CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: No guild configured.')
		else
			CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: ' .. self.db.guild .. ' does not currently have any data.')
		end
		return
	end
	local n = 0
	CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- \nGuild: " .. self.db.guild .. " \nStart Listing Notifications: Disabled")
	for user,arr in pairs(self.db.userData[self.db.guild]) do
		if arr.ignore == true then
			grandTot = arr.goldDeposit - arr.goldWithdraw + arr.itemsDepositVal - arr.itemsWithdrawVal
			CHAT_SYSTEM:AddMessage("Username: " .. arr.userName .. "\n |  Guild Bank Total Value: " .. ExcessiveWithdrawals:CommaValue(grandTot))
			n = n + 1
		end
	end
	if n == 0 or showHint == false then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- \nFinished Listing Notifications: Disabled")
	else
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- \nFinished Listing Notifications: Disabled \nView details, type: /excessive history @USERNAME")
	end
end

function ExcessiveWithdrawals:Commands(key, val)
	if string.find(key, "his") or string.find(key, "stat") then
		if string.find(val, "@") == nil then
			ExcessiveWithdrawals:ShowDisabled(true)
			return true
		end
		if ExcessiveWithdrawals:CheckData(val) == false then return true end
		local userData = ExcessiveWithdrawals.db.userData[ExcessiveWithdrawals.db.guild][string.lower(val)]
		notify = "Enabled"
		if userData.ignore == true then notify = "Disabled" end
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' --\n  Username: ' .. userData.userName .. '\n |  Items Deposited: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsDeposit) .. '   value: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsDepositVal) .. ' gold\n |  Items Withdrawn: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsWithdraw) .. '   value: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsWithdrawVal) .. ' gold\n |  Gold Deposited: ' .. ExcessiveWithdrawals:CommaValue(userData.goldDeposit) .. '\n |  Gold Withdrawn: ' .. ExcessiveWithdrawals:CommaValue(userData.goldWithdraw) .. '\n |  First Scanned on ' .. GetDateStringFromTimestamp(userData.initialScan) .. '\n |  Notifications: ' .. notify)
		itemTot = userData.itemsDepositVal - userData.itemsWithdrawVal
		goldTot = userData.goldDeposit - userData.goldWithdraw
		grandTot = itemTot + goldTot
		CHAT_SYSTEM:AddMessage("Guild Bank Total Values --\n  Items: " .. ExcessiveWithdrawals:CommaValue(itemTot) .. "\n |  Gold: " .. ExcessiveWithdrawals:CommaValue(goldTot) .. "\n |  Grand Total: " .. ExcessiveWithdrawals:CommaValue(grandTot))
		return true
	end
	if string.find(key, "ign") or string.find(key, "ena") then
		if ExcessiveWithdrawals:CheckData(val) == false then return true end
		if string.find(key, "ign") then
			ExcessiveWithdrawals.db.userData[ExcessiveWithdrawals.db.guild][string.lower(val)].ignore = true
		else
			ExcessiveWithdrawals.db.userData[ExcessiveWithdrawals.db.guild][string.lower(val)].ignore = false
		end
		local userData = ExcessiveWithdrawals.db.userData[ExcessiveWithdrawals.db.guild][string.lower(val)]
		local notify = "Enabled"
		if userData.ignore == true then notify = "Disabled" end
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \nUsername: ' .. userData.userName .. '\nNotifications: ' .. notify)
		return true
	end
	if string.find(key, "remov") then
		if ExcessiveWithdrawals:CheckData(val) == false then return true end
		local userData = ExcessiveWithdrawals.db.userData[ExcessiveWithdrawals.db.guild][string.lower(val)]
		local userName = userData.userName
		ExcessiveWithdrawals.db.userData[ExcessiveWithdrawals.db.guild][string.lower(val)] = nil
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \nGuild bank history for ' .. userData.userName .. ' has been removed/reset.')
		return true
	end
	if string.find(key, "reset") then
		if string.find(val, "hist") then
			ExcessiveWithdrawals.db.userData = {}
			ExcessiveWithdrawals.db.lastEvent = {}
			CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n Successfully reset all guild bank history.')
		else
			local guildName = nil
			if tonumber(val) ~= nil then guildName = GetGuildName(val) end
			if ExcessiveWithdrawals.db.userData ~= nil then
				if guildName == nil or guildName == "" then
					CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- \n |cFF0000ERROR: Guild number doesn't exist.")
					return true
				elseif ExcessiveWithdrawals.db.userData[guildName] == nil then
					CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n |cFF0000ERROR: No data was found for ' .. guildName .. '.')
					return true
				end
				ExcessiveWithdrawals.db.userData[guildName] = nil
				ExcessiveWithdrawals.db.lastEvent[guildName] = {}
			end
			CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n Successfully reset guild bank history for ' .. guildName .. '.')
		end
		return true
	end
	return false
end

function ExcessiveWithdrawals.Cmd(txt)
	if txt == "" then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ': type "/exwithdraw" for a list of commands.')
		return
	end
	local arr = {}
	local i = 1
	for val in string.gmatch(txt,"%w+") do
		arr[i] = val
	    i = i + 1
	end
	if string.find(txt, "@") then arr[2] = "@" .. arr[2] end
	if ExcessiveWithdrawals:Commands(arr[1], arr[2]) == true then return end
	CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n |cFF0000ERROR: Chat command was not found.|r \nFor a list of commands, type: /exwithdraw')
end

function ExcessiveWithdrawals.OnAddOnLoaded(event, addon)
	if addon ~= ExcessiveWithdrawals.name then return end
	ExcessiveWithdrawals.db = ZO_SavedVars:NewAccountWide("ExcessiveWithdrawals_Vars", 1, nil, ExcessiveWithdrawals.defaults)
	ExcessiveWithdrawals:Menu()
	SLASH_COMMANDS["/excessive"] = ExcessiveWithdrawals.Cmd
	if ExcessiveWithdrawals.db.warnings == false then
		if MasterMerchant == nil and TamrielTradeCentrePrice == nil then
			CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- \n|cFF0000ERROR: Master Merchant and Tamriel Trade Centre addons were not found.|r\nDefault system prices will be used instead!")
		elseif MasterMerchant == nil then
			CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- \n|cFF0000Warning: Master Merchant addon was not found.|r\nPrices used for calculations may not reflect your current market value!")
		end
	end
	EVENT_MANAGER:UnregisterForEvent(ExcessiveWithdrawals.name, EVENT_ADD_ON_LOADED)
	EVENT_MANAGER:RegisterForUpdate(ExcessiveWithdrawals.name, 30000, function() ExcessiveWithdrawals:MonitorGuild() end)
end

EVENT_MANAGER:RegisterForEvent(ExcessiveWithdrawals.name, EVENT_ADD_ON_LOADED, ExcessiveWithdrawals.OnAddOnLoaded)