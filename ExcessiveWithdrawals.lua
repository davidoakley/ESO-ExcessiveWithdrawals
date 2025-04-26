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
		guilds = {}
	},
	processors = {}
}

function ExcessiveWithdrawals:ResetGuild(guildId)
	self.db.guilds[guildId] = {
		lastEvent = {},
		users = {}
	}
end

local function fmtnum(val)
	return zo_strformat("<<1>>", ZO_LocalizeDecimalNumber(math.floor(val)))
end

function ExcessiveWithdrawals:UserSummary(userName, userData)
	local entries = {}
	if userData.itemsDepositVal > 0 or userData.itemsWithdrawVal > 0 then
		local entry = "items "
		if userData.itemsDepositVal > 0 then entry = entry .. "|c00FF00+" .. fmtnum(userData.itemsDepositVal) .. "|r" end
		if userData.itemsWithdrawVal > 0 then entry = entry .. "|cFF8000-" .. fmtnum(userData.itemsWithdrawVal) .. "|r" end
		table.insert(entries, entry)
	end
	if userData.goldDeposit > 0 or userData.goldWithdraw > 0 then
		local entry = "gold "
		if userData.goldDeposit > 0 then entry = entry .. "|c00FF00+" .. fmtnum(userData.goldDeposit) .. "|r" end
		if userData.goldWithdraw > 0 then entry = entry .. "|cFF8000-" .. fmtnum(userData.goldWithdraw) .. "|r" end
		table.insert(entries, entry)
	end

	local balance = userData.goldDeposit - userData.goldWithdraw + userData.itemsDepositVal - userData.itemsWithdrawVal
	table.insert(entries, "= |cFF8000-" .. fmtnum(-balance) .. "|r")

	return userName .. " (" .. table.concat(entries, " ") .. ")"
end

function ExcessiveWithdrawals:AnalyzeUsers(guildId)
	local userRanks = self:CheckGuildRank(guildId, self.db.guildRank)
	local ignoreAmt = tonumber(self.db.ignoreAmt)
	if ignoreAmt == nil then ignoreAmt = 0 end
	local dRank, dAmt
	if tonumber(self.db.demoteAmt) ~= nil and tonumber(self.db.demoteRank) ~= nil then
		local _, _, cRank, _, _ = GetGuildMemberInfo(guildId, GetGuildMemberIndexFromDisplayName(guildId, GetDisplayName()))
		if DoesGuildRankHavePermission(guildId, cRank, GUILD_PERMISSION_DEMOTE) == true then
			dAmt = tonumber(self.db.demoteAmt)
			dRank = tonumber(self.db.demoteRank)
			if dRank > GetNumGuildRanks(guildId) then dRank = GetNumGuildRanks(guildId) end
		end
	end

	CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- |cFF8000Users exceeding guild bank allowance:|r")

	local results = {}
	for user, arr in pairs(self.db.guilds[guildId].users) do
		if arr.ignore ~= true and userRanks[user] ~= true then
			local balance = arr.goldDeposit - arr.goldWithdraw + arr.itemsDepositVal - arr.itemsWithdrawVal
			if (dAmt ~= nil and (dAmt + balance) < 0) or (ignoreAmt + balance) < 0 then
				if userRanks[user] == nil then
					table.insert(results, " - |r" .. self:UserSummary(arr.userName, arr) .. " - |cFF8000no longer a member!|r")
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
						table.insert(results, " - |r" .. self:UserSummary(arr.userName, arr) .. " - |cFF8000demoted!|r")
					else
						table.insert(results, " - |r" .. self:UserSummary(arr.userName, arr))
					end
				end
				found = true
			end
		end
	end
	if #results then
		table.sort(results)
		for i = 1, #results do
			CHAT_SYSTEM:AddMessage(results[i])
		end
	else
		CHAT_SYSTEM:AddMessage(" - none!")
	end
end

function ExcessiveWithdrawals:GetProcessor(lib, guildId, eventCategory)
	if not self.processors[guildId] then self.processors[guildId] = {} end
	if not self.processors[guildId][eventCategory] then
		self.processors[guildId][eventCategory] = lib:CreateGuildHistoryProcessor(guildId, eventCategory, "ExcessiveWithdrawals")
	end
	return self.processors[guildId][eventCategory]
end

local function processItems(self, lib, guildId, eventCategory)
	d("process")
	local processor = self:GetProcessor(lib, guildId, eventCategory) --lib:CreateGuildHistoryProcessor(guildId, eventCategory, "ExcessiveWithdrawals")
	if not processor then
		-- the processor could not be created
		return
	end

	processor:Stop()

	--local now = GetTimeStamp()

	local started = processor:StartStreaming(self.db.guilds[guildId].lastEvent[eventCategory], function(event)
		self:ProcessEvent(event)
		self.db.guilds[guildId].lastEvent[eventCategory] = event:GetEventInfo().eventId
	end)

	if not started then
		d("Failed to start processor for category "..eventCategory)
	end

	--local started = processor:StartIteratingTimeRange(now - 24*60*60, now, function(event)
	--	self:ProcessEvent(event)
	--	self.db.lastEvent[guildName][eventCategory] = event:GetEventInfo().eventId
	--end, function(reason)
	--	if (reason == LibHistoire.StopReason.ITERATION_COMPLETED or reason == LibHistoire.StopReason.LAST_CACHED_EVENT_REACHED) then
	--		-- all events in the time range have been processed
	--		d("FINISHED")
	--		self:AnalyzeUsers(guildID, guildName)
	--	else
	--		d("Iterator failed to finish, reason "..reason)
	--		-- the iteration has stopped early for some reason and not all events have been processed
	--	end
	--end)
end

function ExcessiveWithdrawals:MonitorGuild()
	EVENT_MANAGER:UnregisterForUpdate(self.name)
	if self.db.guildId == nil then return end
	local guildId = self.db.guildId --self:GetGuild(guildName)
	if guildId == false or guildId == 0 then return end

	if not self.db.guilds[guildId] then self:ResetGuild(guildId) end

	--local startTimestamp = self.db.lastEvent[guildName]
	--if startTimestamp == nil then startTimestamp = 1 end
	--local currentTimestamp = GetTimeStamp()

	LibHistoire:OnReady(function(lib)
		processItems(self, lib, guildId, GUILD_HISTORY_EVENT_CATEGORY_BANKED_ITEM)
		processItems(self, lib, guildId, GUILD_HISTORY_EVENT_CATEGORY_BANKED_CURRENCY)
	end)
end

function ExcessiveWithdrawals:GetUser(user, timestampS)
	local guildId = self.db.guildId

	if self.db.guilds[guildId].users[string.lower(user)] == nil then
		d("Creating user "..string.lower(user))
		self.db.guilds[guildId].users[string.lower(user)] = {
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

	return self.db.guilds[guildId].users[string.lower(user)]
end

function ExcessiveWithdrawals:ProcessEvent(event)
	local info = event:GetEventInfo()
	local user = "@"..info.displayName
	local userObj = self:GetUser(user, event:GetEventTimestampS())

	if event:GetEventCategory() == GUILD_HISTORY_EVENT_CATEGORY_BANKED_CURRENCY then
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
		if self.db.logging then d(string.format("%s - %s: +%d %s (worth %d)", self.displayName, userObj.userName, qty, info.itemLink, price)) end
	elseif type == GUILD_HISTORY_BANKED_ITEM_EVENT_REMOVED then
		userObj.itemsWithdraw = userObj.itemsWithdraw + qty
		userObj.itemsWithdrawVal = userObj.itemsWithdrawVal + price
		if self.db.logging then d(string.format("%s - %s: -%d %s (worth %d)", self.displayName, userObj.userName, qty, info.itemLink, price)) end
	end

	if info.quantity < 0 then userObj.ignore = false end
end

function ExcessiveWithdrawals:ProcessCashEvent(userObj, event, info)
	local type = event:GetEventType()
	local amount = info.amount

	if amount then
		if type == GUILD_HISTORY_BANKED_CURRENCY_EVENT_DEPOSITED then
			userObj.goldDeposit = userObj.goldDeposit + amount
			if self.db.logging then d(string.format("%s - %s: +%d gold", self.displayName, userObj.userName, amount)) end
		elseif type == GUILD_HISTORY_BANKED_CURRENCY_EVENT_WITHDRAWN then
			userObj.goldWithdraw = userObj.goldWithdraw + amount
			if self.db.logging then d(string.format("%s - %s: -%d gold", self.displayName, userObj.userName, amount)) end
		end
	else
		d("Stored event for nil amount event")
		ExcessiveWithdrawals.event = event
	end
end

function ExcessiveWithdrawals:CheckData(user)
	if ExcessiveWithdrawals.db.guildId == nil or ExcessiveWithdrawals.db.guildId == 0 then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: No guild is selected.|r\nType "/exwithdraw" to configure.')
		return false
	elseif ExcessiveWithdrawals.db.guilds[self.db.guildId] == nil then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: No data collected for ' .. GetGuildName(self.db.guildId) .. '.')
		return false
	elseif user == nil or user == "" then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: You must enter a username.')
		return false
	elseif ExcessiveWithdrawals.db.guilds[self.db.guildId].users[string.lower(user)] == nil then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: ' .. user .. ' does not currently have any statistics.')
		return false
	end
	return true
end

function ExcessiveWithdrawals:ShowDisabled(showHint)
	if self.db.guildId == nil or self.db.guildId == 0 or self.db.guilds == nil or self.db.guilds[self.db.guildId] == nil then
		if self.db.guildId == nil or self.db.guildId == 0 then
			CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: No guild configured.')
		else
			CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: ' .. GetGuildName(self.db.guildId) .. ' does not currently have any data.')
		end
		return
	end
	local n = 0
	CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- \nGuild: " .. GetGuildName(self.db.guildId) .. " \nStart Listing Notifications: Disabled")
	for _, arr in pairs(self.db.guilds[self.db.guildId].users) do
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

function ExcessiveWithdrawals.OnAddOnLoaded(_, addon)
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
	--EVENT_MANAGER:RegisterForUpdate(ExcessiveWithdrawals.name, 30000, function() ExcessiveWithdrawals:MonitorGuild() end)
	if ExcessiveWithdrawals.db.guildId then
		ExcessiveWithdrawals:MonitorGuild()
	end
end

EVENT_MANAGER:RegisterForEvent(ExcessiveWithdrawals.name, EVENT_ADD_ON_LOADED, ExcessiveWithdrawals.OnAddOnLoaded)