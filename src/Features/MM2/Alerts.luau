-- [[ alerts ]]

return function(API)
	local Player = API.Player; local Services = API.Roblox; local Runtime = API.Runtime; local MatchService = API.Services.Match
	local Alerts = {
		RoleAndMurdererEnabled = true,
		GunDroppedEnabled = true,
		Running = false,
		Thread = nil,
		Connections = {},
		ActiveMap = nil,
		LastRoleSignature = nil,
		SeenGuns = setmetatable({}, { __mode = "k" }),
	}

	local function notify(title, content)
		local window = API.UI and API.UI.Window; local library = window and window.OrionLib
		if library and type(library.MakeNotification) == "function" then pcall(library.MakeNotification, library, { Name = title, Content = content, Time = 5 }) end
	end
	local function isAlive(target, profile)
		if
			not target
			or type(profile) ~= "table"
			or profile.Dead == true
			or profile.Killed == true
			or target:GetAttribute("Alive") ~= true
		then
			return false
		end
		local character = target.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); return character ~= nil
			and humanoid ~= nil
			and humanoid.Health > 0
			and character:IsDescendantOf(Services.Workspace)
	end
	function Alerts:RefreshRoles()
		if not self.RoleAndMurdererEnabled then return end
		local inRound, map = MatchService:GetRoundContext()
		if not inRound or not map then self.ActiveMap = nil; self.LastRoleSignature = nil; return end
		if self.ActiveMap ~= map then self.ActiveMap = map; self.LastRoleSignature = nil end
		local data = MatchService:GetPlayerData(); local localProfile = data and data[Player.Name]
		if
			type(localProfile) ~= "table"
			or type(localProfile.Role) ~= "string"
			or localProfile.Role == ""
			or not isAlive(Player, localProfile)
		then
			return
		end
		local murdererName = localProfile.Role == "Murderer" and (Player.DisplayName or Player.Name) or nil
		if not murdererName then
			for playerName, profile in pairs(data) do
				if playerName ~= Player.Name and type(profile) == "table" and profile.Role == "Murderer" then
					local target = Services.Players:FindFirstChild(playerName)
					if isAlive(target, profile) then murdererName = target.DisplayName or target.Name; break end
				end
			end
		end
		if not murdererName then return end
		local signature = tostring(localProfile.Role) .. "|" .. murdererName
		if signature == self.LastRoleSignature then return end
		self.LastRoleSignature = signature; notify("Papéis da rodada", "Seu cargo: " .. localProfile.Role .. " · Assassino: " .. murdererName)
	end
	function Alerts:OnGunDropped(instance)
		if not self.GunDroppedEnabled or self.SeenGuns[instance] then return end
		self.SeenGuns[instance] = true
		task.delay(0.15, function()
			if
				not self.Running
				or not instance
				or not instance.Parent
				or not instance:IsDescendantOf(Services.Workspace)
			then
				return
			end
			local inRound, map = MatchService:GetRoundContext()
			if inRound and map and instance:IsDescendantOf(map) then notify("Arma caiu", "Uma arma foi derrubada no mapa.") end
		end)
	end
	function Alerts:Start()
		if self.Running or Runtime.ShuttingDown then return end
		self.Running = true; table.clear(self.SeenGuns)
		for _, gun in ipairs(Services.CollectionService:GetTagged("GunDrop")) do
			self.SeenGuns[gun] = true
		end
		self.Connections.GunAdded = Runtime:Track(
			Services.CollectionService
				:GetInstanceAddedSignal("GunDrop")
				:Connect(function(instance) self:OnGunDropped(instance) end)
		)
		local thread
		thread = task.spawn(function()
			while self.Running and not Runtime.ShuttingDown do
				local ok, errorMessage = pcall(function() self:RefreshRoles() end)
				if not ok then warn("[Chorus MM2] Avisos recuperando após erro: " .. tostring(errorMessage)) end
				task.wait(1)
			end
			if self.Thread == thread then self.Thread = nil end
		end)
		self.Thread = Runtime:TrackTask(thread)
	end
	function Alerts:Stop()
		self.Running = false; local thread = self.Thread; self.Thread = nil
		if thread then pcall(task.cancel, thread) end
		for key, connection in pairs(self.Connections) do
			if connection then pcall(function() connection:Disconnect() end) end
			self.Connections[key] = nil
		end
		self.ActiveMap = nil; self.LastRoleSignature = nil
	end
	function Alerts:SetRoleAndMurdererEnabled(enabled)
		self.RoleAndMurdererEnabled = enabled == true
		if self.RoleAndMurdererEnabled or self.GunDroppedEnabled then self:Start()
		else self:Stop() end
	end
	function Alerts:SetGunDroppedEnabled(enabled)
		self.GunDroppedEnabled = enabled == true
		if self.RoleAndMurdererEnabled or self.GunDroppedEnabled then self:Start()
		else self:Stop() end
	end
	Runtime:OnShutdown(function() Alerts:Stop() end)

	return Alerts
end
