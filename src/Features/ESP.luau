-- [[ esp ]]

return function(API)
	local Services = API.Roblox; local Player = API.Player; local Runtime = API.Runtime; local Util = API.Util
	local CoinService = API.Services.Coin; local MatchService = API.Services.Match

	-- State
	local ESP = {
		Enabled = false,
		ShowName = true,
		RefreshInterval = 0.75,
		Thread = nil,
		RoleRemote = nil,
		RoleData = nil,
		RoleDataAt = 0,
		RoleDataRefreshInterval = 1.25,
		RoleDataCacheLifetime = 2,
		LastErrorAt = 0,
		PlayerMarkers = {},
		CoinMarkers = {},
		GunMarkers = {},
		Filters = {
			Murderer = true,
			Sheriff = true,
			Innocent = true,
			Candy = true,
			Coin = true,
			Gun = true,
		},
		Colors = {
			Murderer = Color3.fromRGB(255, 65, 65),
			Sheriff = Color3.fromRGB(70, 155, 255),
			Innocent = Color3.fromRGB(70, 220, 120),
			Candy = Color3.fromRGB(255, 90, 175),
			Coin = Color3.fromRGB(255, 210, 65),
			Gun = Color3.fromRGB(70, 225, 255),
		},
	}

	local destroySafely = Util.DestroySafely

	-- RoleCategories
	local function getRoleCategory(role)
		if role == "Murderer" then return "Murderer" end
		if role == "Sheriff" or role == "Hero" then return "Sheriff" end
		if role == "Innocent" then return "Innocent" end
		return nil
	end

	-- MarkerCleanup
	function ESP:ClearMap(map)
		for key, instance in pairs(map) do
			destroySafely(instance); map[key] = nil
		end
	end
	function ESP:ClearAll()
		for _, marker in pairs(self.PlayerMarkers) do
			destroySafely(marker.Gui)
		end
		table.clear(self.PlayerMarkers); self:ClearMap(self.CoinMarkers); self:ClearMap(self.GunMarkers)
	end

	-- RoleData
	function ESP:GetRoleData()
		local now = os.clock()
		if self.RoleData and now - self.RoleDataAt < self.RoleDataRefreshInterval then return self.RoleData end
		if not self.RoleRemote or not self.RoleRemote.Parent or not self.RoleRemote:IsA("RemoteFunction") then self.RoleRemote = Services.ReplicatedStorage:FindFirstChild("GetPlayerData", true) end
		local remote = self.RoleRemote
		if remote and remote:IsA("RemoteFunction") then
			local ok, data = pcall(function() return remote:InvokeServer() end)
			if ok and type(data) == "table" then self.RoleData = data; self.RoleDataAt = os.clock(); return data end
		end
		if self.RoleData and os.clock() - self.RoleDataAt <= self.RoleDataCacheLifetime then return self.RoleData end
		return nil
	end

	-- PlayerMarkers
	function ESP:CreatePlayerMarker(target, character, root, color)
		local gui = Instance.new("BillboardGui"); gui.Name = "ChorusPlayerESP"; gui.Adornee = root; gui.AlwaysOnTop = true
		gui.LightInfluence = 0; gui.MaxDistance = 1200; gui.Size = UDim2.fromOffset(112, 142); gui.StudsOffset = Vector3.new(0, 2.25, 0)
		gui.Parent = root; local nameLabel = Instance.new("TextLabel"); nameLabel.Name = "PlayerName"; nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.fromOffset(0, 0); nameLabel.Size = UDim2.new(1, 0, 0, 20); nameLabel.Font = Enum.Font.GothamBold; nameLabel.Text = target.Name
		nameLabel.TextColor3 = color
		nameLabel.TextSize = 13; nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0); nameLabel.TextStrokeTransparency = 0.15; nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Visible = self.ShowName; nameLabel.Parent = gui; local box = Instance.new("Frame"); box.Name = "PlayerBox"
		box.BackgroundTransparency = 1; box.BorderSizePixel = 0; box.Position = UDim2.fromOffset(6, 22); box.Size = UDim2.new(1, -12, 1, -28)
		box.Parent = gui; local stroke = Instance.new("UIStroke"); stroke.Name = "RoleColor"
		stroke.Color = color
		stroke.Thickness = 1.5; stroke.Transparency = 0; stroke.Parent = box
		return {
			Character = character,
			Root = root,
			Gui = gui,
			NameLabel = nameLabel,
			Stroke = stroke,
		}
	end
	function ESP:RefreshPlayers(roleData)
		local keep = {}
		for _, target in ipairs(Services.Players:GetPlayers()) do
			if target ~= Player and target:GetAttribute("Alive") == true then
				local character = target.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local root = character and character:FindFirstChild("HumanoidRootPart")
				local profile = roleData and roleData[target.Name]; local role = type(profile) == "table" and profile.Role or nil; local category = getRoleCategory(role)
				if
					character
					and character.Parent
					and humanoid
					and humanoid.Health > 0
					and root
					and root:IsA("BasePart")
					and category
					and self.Filters[category]
				then
					keep[target] = true; local color = self.Colors[category]; local marker = self.PlayerMarkers[target]
					if not marker or marker.Character ~= character or marker.Root ~= root or not marker.Gui.Parent then
						if marker then destroySafely(marker.Gui) end
						marker = self:CreatePlayerMarker(target, character, root, color); self.PlayerMarkers[target] = marker
					end
					marker.NameLabel.Text = target.Name
					marker.NameLabel.TextColor3 = color
					marker.NameLabel.Visible = self.ShowName
					marker.Stroke.Color = color
				end
			end
		end
		for target, marker in pairs(self.PlayerMarkers) do
			if not keep[target] then destroySafely(marker.Gui); self.PlayerMarkers[target] = nil end
		end
	end

	-- CoinMarkers
	function ESP:RefreshCoins(container)
		local keep = {}
		for _, part in ipairs(CoinService:GetCollectableParts(container, false)) do
			local kind = CoinService:GetKind(part); local category = kind == "candy" and "Candy" or kind == "coin" and "Coin" or nil
			if category and self.Filters[category] then
				keep[part] = true; local marker = self.CoinMarkers[part]
				if not marker or not marker.Parent then
					marker = Instance.new("SphereHandleAdornment"); marker.Name = "Chorus" .. category .. "ESP"; marker.Adornee = part
					marker.Radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 0.5 + 0.3; marker.AlwaysOnTop = true; marker.ZIndex = 5; marker.Transparency = 0.25
					marker.Parent = part; self.CoinMarkers[part] = marker
				end
				marker.Color3 = self.Colors[category]
			end
		end
		for part, marker in pairs(self.CoinMarkers) do
			if not keep[part] then destroySafely(marker); self.CoinMarkers[part] = nil end
		end
	end

	-- GunMarkers
	function ESP:RefreshGuns()
		local gunParts = {}
		if self.Filters.Gun then
			for _, gun in ipairs(Services.CollectionService:GetTagged("GunDrop")) do
				if gun:IsA("BasePart") and gun:IsDescendantOf(Services.Workspace) then gunParts[gun] = true end
			end
			for _, target in ipairs(Services.Players:GetPlayers()) do
				if target ~= Player then
					local character = target.Character; local tool = character and character:FindFirstChild("Gun"); local handle = tool and tool:FindFirstChild("Handle")
					if handle and handle:IsA("BasePart") and handle:IsDescendantOf(Services.Workspace) then gunParts[handle] = true end
				end
			end
		end
		for part in pairs(gunParts) do
			local marker = self.GunMarkers[part]
			if not marker or not marker.Parent then
				marker = Instance.new("Highlight"); marker.Name = "ChorusGunESP"; marker.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; marker.FillTransparency = 0.35
				marker.OutlineTransparency = 0; marker.Adornee = part; marker.Parent = part; self.GunMarkers[part] = marker
			end
			marker.FillColor = self.Colors.Gun; marker.OutlineColor = self.Colors.Gun
		end
		for part, marker in pairs(self.GunMarkers) do
			if not gunParts[part] then destroySafely(marker); self.GunMarkers[part] = nil end
		end
	end

	-- Refresh
	function ESP:Refresh()
		local inMatch, _, _, _, container = MatchService:GetContext()
		if not inMatch then self:ClearAll(); self.RoleData = nil; self.RoleDataAt = 0; return end
		local needsRoleData = self.Filters.Murderer or self.Filters.Sheriff or self.Filters.Innocent; self:RefreshPlayers(needsRoleData and self:GetRoleData() or nil)
		if self.Filters.Candy or self.Filters.Coin then self:RefreshCoins(container)
		else self:ClearMap(self.CoinMarkers) end
		self:RefreshGuns()
	end
	function ESP:ReportError(context, errorMessage)
		local now = os.clock()
		if now - self.LastErrorAt < 5 then return end
		self.LastErrorAt = now; warn("[Chorus MM2] ESP recuperando após erro em " .. context .. ": " .. tostring(errorMessage))
	end

	-- Lifecycle
	function ESP:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true
		local thread
		thread = task.spawn(function()
			while self.Enabled and not Runtime.ShuttingDown do
				local ok, errorMessage = xpcall(function() self:Refresh() end, Util.FormatError)
				if not ok then self:ReportError("atualização", errorMessage) end
				task.wait(self.RefreshInterval)
			end
			if self.Thread == thread then self.Thread = nil end
			self:ClearAll()
		end)
		self.Thread = thread
	end
	function ESP:Stop()
		self.Enabled = false; local thread = self.Thread; self.Thread = nil
		if thread then pcall(task.cancel, thread) end
		self:ClearAll(); self.RoleData = nil; self.RoleDataAt = 0
	end
	Runtime:OnShutdown(function() ESP:Stop() end)

	return ESP
end
