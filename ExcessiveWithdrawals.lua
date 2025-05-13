ExcessiveWithdrawals = {
	db = nil,
	name = "ExcessiveWithdrawals",
	addonName = "Excessive Withdrawals",
	displayName = "|cFF8000Excessive Withdrawals|r",
	defaults = {
		warnings = false,
		gUser = "",
		ignoreAmt = 100000,
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

local function fmtnum(val, showPositive)
	if val < 0 then
		return "-"..zo_strformat("<<1>>", ZO_LocalizeDecimalNumber(math.floor(-val)))
	else
		return (showPositive and "+" or "") .. zo_strformat("<<1>>", ZO_LocalizeDecimalNumber(math.floor(val)))
	end
end
ExcessiveWithdrawals.fmtnum = fmtnum

function getRankIndex(guildId, userName)
	local _, _, rankIndex, _, _ = GetGuildMemberInfo(guildId, GetGuildMemberIndexFromDisplayName(guildId, userName))
	return rankIndex
end

function ExcessiveWithdrawals:UserSummary(guildId, userName, userData)
	local summary = {
		guildId = guildId,
		userName = userName,
		rankIndex = getRankIndex(guildId, userName),
		balance = userData.goldDeposit - userData.goldWithdraw + userData.itemsDepositVal - userData.itemsWithdrawVal
	}

	for key, value in pairs(userData) do
		summary[key] = value
	end

	return summary
end

local function balanceComparison(x,y)
	return x.balance < y.balance
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

	local results = {}
	for user, arr in pairs(self.db.guilds[guildId].users) do
		if arr.ignore ~= true and userRanks[user] ~= true then
			local balance = arr.goldDeposit - arr.goldWithdraw + arr.itemsDepositVal - arr.itemsWithdrawVal
			if (dAmt ~= nil and (dAmt + balance) < 0) or (ignoreAmt + balance) < 0 then
				local summary = self:UserSummary(guildId, arr.userName, arr)
				if userRanks[user] == nil then
					summary.warning = "no longer a member!"
				else
					summary.member = true
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
						summary.warning = "demoted!"
					end
				end
				table.insert(results, summary)
				found = true
			end
		end
	end

	table.sort(results, balanceComparison)

	return results
end

function ExcessiveWithdrawals:ListAnalysis(results)
	CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. " -- |cFF8000Users exceeding guild bank allowance:|r")

	if #results then

		for i = 1, #results do
			local userData = results[i]

			local entries = {}
			if userData.itemsDepositVal > 0 or userData.itemsWithdrawVal > 0 then
				local entry = "items "
				if userData.itemsDepositVal > 0 then entry = entry .. "+" .. fmtnum(userData.itemsDepositVal)  end
				if userData.itemsWithdrawVal > 0 then entry = entry .. "-" .. fmtnum(userData.itemsWithdrawVal) end
				table.insert(entries, entry)
			end
			if userData.goldDeposit > 0 or userData.goldWithdraw > 0 then
				local entry = "gold "
				if userData.goldDeposit > 0 then entry = entry .. "+" .. fmtnum(userData.goldDeposit) end
				if userData.goldWithdraw > 0 then entry = entry .. "-" .. fmtnum(userData.goldWithdraw) end
				table.insert(entries, entry)
			end

			local balance = userData.goldDeposit - userData.goldWithdraw + userData.itemsDepositVal - userData.itemsWithdrawVal
			table.insert(entries, "= -" .. fmtnum(-balance))

			local text =  userData.userName .. " (" .. table.concat(entries, " ") .. ")"
			if userData.warning then
				text = text .. " - " .. userData.warning
			end

			CHAT_SYSTEM:AddMessage(text)
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
		d(self.addonName .. ": Creating user "..string.lower(user))
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
		ZO_Alert(UI_ALERT_CATEGORY_ALERT, SOUNDS.NEGATIVE_CLICK, "No guild is selected")
		return nil
	elseif ExcessiveWithdrawals.db.guilds[self.db.guildId] == nil then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: No data collected for ' .. GetGuildName(self.db.guildId) .. '.')
		ZO_Alert(UI_ALERT_CATEGORY_ALERT, SOUNDS.NEGATIVE_CLICK, 'No data collected for ' .. GetGuildName(self.db.guildId))
		return nil
	elseif user == nil or user == "" then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: You must enter a username.')
		ZO_Alert(UI_ALERT_CATEGORY_ALERT, SOUNDS.NEGATIVE_CLICK, "You must enter a username")
		return nil
	end

	local userObj = ExcessiveWithdrawals.db.guilds[self.db.guildId].users[string.lower(user)]

	if not userObj then
		CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' -- \n|cFF0000ERROR: ' .. user .. ' does not currently have any statistics.')
		ZO_Alert(UI_ALERT_CATEGORY_ALERT, SOUNDS.NEGATIVE_CLICK, user .. ' does not currently have any statistics')
		return nil
	end
	return userObj
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

function ExcessiveWithdrawals:ShowUserHistory(userName)
	if userName:sub(1, 1) ~= "@" then userName = "@" .. userName end
	if ExcessiveWithdrawals:CheckData(userName) == false then return true end
	local userData = ExcessiveWithdrawals.db.guilds[ExcessiveWithdrawals.db.guildId].users[string.lower(userName)]
	notify = "Enabled"
	if userData.ignore == true then notify = "Disabled" end
	CHAT_SYSTEM:AddMessage(ExcessiveWithdrawals.displayName .. ' --\n  Username: ' .. userData.userName .. '\n |  Items Deposited: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsDeposit) .. '   value: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsDepositVal) .. ' gold\n |  Items Withdrawn: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsWithdraw) .. '   value: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsWithdrawVal) .. ' gold\n |  Gold Deposited: ' .. ExcessiveWithdrawals:CommaValue(userData.goldDeposit) .. '\n |  Gold Withdrawn: ' .. ExcessiveWithdrawals:CommaValue(userData.goldWithdraw) .. '\n |  First Scanned on ' .. GetDateStringFromTimestamp(userData.initialScan) .. '\n |  Notifications: ' .. notify)
	itemTot = userData.itemsDepositVal - userData.itemsWithdrawVal
	goldTot = userData.goldDeposit - userData.goldWithdraw
	grandTot = itemTot + goldTot
	CHAT_SYSTEM:AddMessage("Guild Bank Total Values --\n  Items: " .. ExcessiveWithdrawals:CommaValue(itemTot) .. "\n |  Gold: " .. ExcessiveWithdrawals:CommaValue(goldTot) .. "\n |  Grand Total: " .. ExcessiveWithdrawals:CommaValue(grandTot))
end

function ExcessiveWithdrawals:GetUserHistory(userName)
	if userName:sub(1, 1) ~= "@" then userName = "@" .. userName end
	if ExcessiveWithdrawals:CheckData(userName) == false then return true end
	local userData = ExcessiveWithdrawals.db.guilds[ExcessiveWithdrawals.db.guildId].users[string.lower(userName)]
	local out = ExcessiveWithdrawals.addonName .. ' -- ' .. userData.userName .. '\n |  Items Deposited: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsDeposit) .. '   value: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsDepositVal) .. ' gold\n |  Items Withdrawn: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsWithdraw) .. '   value: ' .. ExcessiveWithdrawals:CommaValue(userData.itemsWithdrawVal) .. ' gold\n |  Gold Deposited: ' .. ExcessiveWithdrawals:CommaValue(userData.goldDeposit) .. '\n |  Gold Withdrawn: ' .. ExcessiveWithdrawals:CommaValue(userData.goldWithdraw) .. '\n |  First Scanned on ' .. GetDateStringFromTimestamp(userData.initialScan) .. "\n"
	itemTot = userData.itemsDepositVal - userData.itemsWithdrawVal
	goldTot = userData.goldDeposit - userData.goldWithdraw
	grandTot = itemTot + goldTot
	out = out .. " Guild Bank Total Values --\n |  Items: " .. ExcessiveWithdrawals:CommaValue(itemTot) .. "\n |  Gold: " .. ExcessiveWithdrawals:CommaValue(goldTot) .. "\n |  Grand Total: " .. ExcessiveWithdrawals:CommaValue(grandTot)
	return out
end

function ExcessiveWithdrawals.AdjustContextMenus()
	local ShowPlayerContextMenu = CHAT_SYSTEM.ShowPlayerContextMenu
	CHAT_SYSTEM.ShowPlayerContextMenu = function(self, displayName, rawName)
		ShowPlayerContextMenu(self, displayName, rawName)
		AddCustomMenuItem("List Excessive Withdrawals", function()
			ExcessiveWithdrawals.userWindow:Open(ExcessiveWithdrawals.db.guildId, displayName)
		end)
		--d("DisplayName: " .. displayName)
		if ZO_Menu_GetNumMenuItems() > 0 then
			ShowMenu()
		end
	end

	local GuildRosterRow_OnMouseUp = GUILD_ROSTER_KEYBOARD.GuildRosterRow_OnMouseUp
	GUILD_ROSTER_KEYBOARD.GuildRosterRow_OnMouseUp = function(self, control, button, upInside)

		local data = ZO_ScrollList_GetData(control)
		GuildRosterRow_OnMouseUp(self, control, button, upInside)

		if (button ~= MOUSE_BUTTON_INDEX_RIGHT --[[and not upInside]]) then
			return
		end

		if data ~= nil then
			--In case someone messed around with the guild roster... >_<
			--data.characterName = string.gsub(data.characterName, "|ceeeeee", "")
			--d(data.displayName)
			AddCustomMenuItem("List Excessive Withdrawals", function()
				ExcessiveWithdrawals.userWindow:Open(ExcessiveWithdrawals.db.guildId, data.displayName)
			end)
			self:ShowMenu(control)
		end
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
	ExcessiveWithdrawals.AdjustContextMenus()

	ExcessiveWithdrawals.window:Init()
	ExcessiveWithdrawals.userWindow:Init()
end

EVENT_MANAGER:RegisterForEvent(ExcessiveWithdrawals.name, EVENT_ADD_ON_LOADED, ExcessiveWithdrawals.OnAddOnLoaded)