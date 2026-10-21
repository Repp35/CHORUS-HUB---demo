-- [[ esp ]]

return function(API)
	local Services = API.Roblox; local Player = API.Player; local Runtime = API.Runtime; local Util = API.Util
	local CoinService = API.Services.Coin; local MatchService = API.Services.Match

	-- State
	local ESP = {
		Enabled = false,
		ShowName = true,
		RefreshInterval = 0.75,
		FillTransparency = 0.82,
		OutlineTransparency = 0,
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
			CandyCoin = true,
			Gun = true,
		},
		Colors = {
			Murderer = Color3.fromRGB(255, 65, 65),
			Sheriff = Color3.fromRGB(70, 155, 255),
			Innocent = Color3.fromRGB(70, 220, 120),
			CandyCoin = Color3.fromRGB(255, 185, 70),
			Gun = Color3.fromRGB(70, 225, 255),
		},
	}

	local destroySafely = Util.DestroySafely
	local function destroyPlayerMarker(marker)
		if not marker then return end
		destroySafely(marker.Gui); destroySafely(marker.Highlight)
	end

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
			destroyPlayerMarker(marker)
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
	local function createHighlight(esp, name, adornee, color)
		local highlight = Instance.new("Highlight"); highlight.Name = name; highlight.Adornee = adornee; highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillColor = color
		highlight.FillTransparency = esp.FillTransparency
		highlight.OutlineColor = color
		highlight.OutlineTransparency = esp.OutlineTransparency; highlight.Parent = adornee; return highlight
	end

	-- PlayerMarkers
	function ESP:CreatePlayerMarker(target, character, root, color)
		local highlight = createHighlight(self, "ChorusPlayerESP", character, color); local head = character:FindFirstChild("Head"); local nameAdornee = head and head:IsA("BasePart") and head or root
		local headHeight = nameAdornee == head and head.Size.Y or root.Size.Y; local gui = Instance.new("BillboardGui"); gui.Name = "ChorusPlayerName"; gui.Adornee = nameAdornee
		gui.AlwaysOnTop = true; gui.LightInfluence = 0; gui.MaxDistance = 1200; gui.Size = UDim2.fromOffset(200, 24)
		gui.StudsOffset = Vector3.new(0, headHeight * 0.5 + 0.55, 0); gui.Parent = root; local nameLabel = Instance.new("TextLabel"); nameLabel.Name = "PlayerName"
		nameLabel.BackgroundTransparency = 1; nameLabel.Size = UDim2.fromScale(1, 1); nameLabel.Font = Enum.Font.GothamBold; nameLabel.Text = target.Name
		nameLabel.TextColor3 = color
		nameLabel.TextSize = 13; nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0); nameLabel.TextStrokeTransparency = 0; nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Visible = self.ShowName; nameLabel.Parent = gui
		return {
			Character = character,
			Root = root,
			Gui = gui,
			NameLabel = nameLabel,
			NameAdornee = nameAdornee,
			Highlight = highlight,
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
					keep[target] = true; local color = self.Colors[category]; local marker = self.PlayerMarkers[target]; local head = character:FindFirstChild("Head")
					local nameAdornee = head and head:IsA("BasePart") and head or root
					if
						not marker
						or marker.Character ~= character
						or marker.Root ~= root
						or marker.NameAdornee ~= nameAdornee
						or not marker.Gui.Parent
						or not marker.Highlight.Parent
					then
						if marker then destroyPlayerMarker(marker) end
						marker = self:CreatePlayerMarker(target, character, root, color); self.PlayerMarkers[target] = marker
					end
					marker.NameLabel.Text = target.Name
					marker.NameLabel.TextColor3 = color
					marker.NameLabel.Visible = self.ShowName
					marker.Highlight.FillColor = color
					marker.Highlight.FillTransparency = self.FillTransparency
					marker.Highlight.OutlineColor = color
					marker.Highlight.OutlineTransparency = self.OutlineTransparency
				end
			end
		end
		for target, marker in pairs(self.PlayerMarkers) do
			if not keep[target] then destroyPlayerMarker(marker); self.PlayerMarkers[target] = nil end
		end
	end

	-- CoinMarkers
	local function getCoinVisualAdornee(part)
		local visual = part:FindFirstChild("CoinVisual")
		if not visual then return part end
		if visual:IsA("Model") or visual:IsA("BasePart") then return visual end
		local model = visual:FindFirstChildWhichIsA("Model", true)
		if model then return model end
		local mainCoin = visual:FindFirstChild("MainCoin", true)
		if mainCoin and mainCoin:IsA("BasePart") then return mainCoin end
		local visualPart = visual:FindFirstChildWhichIsA("BasePart", true); return visualPart or part
	end
	function ESP:RefreshCoins(container)
		local keep = {}
		for _, part in ipairs(CoinService:GetCollectableParts(container)) do
			local kind = CoinService:GetKind(part); local adornee = getCoinVisualAdornee(part)
			if kind and self.Filters.CandyCoin then
				keep[part] = true; local marker = self.CoinMarkers[part]
				if not marker or not marker.Parent or marker.Adornee ~= adornee then
					if marker then destroySafely(marker) end
					marker = createHighlight(self, "ChorusCandyCoinESP", adornee, self.Colors.CandyCoin); self.CoinMarkers[part] = marker
				end
				marker.FillColor = self.Colors.CandyCoin; marker.FillTransparency = self.FillTransparency; marker.OutlineColor = self.Colors.CandyCoin
				marker.OutlineTransparency = self.OutlineTransparency
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
			if not marker or not marker.Parent then marker = createHighlight(self, "ChorusGunESP", part, self.Colors.Gun); self.GunMarkers[part] = marker end
			marker.FillColor = self.Colors.Gun; marker.FillTransparency = self.FillTransparency; marker.OutlineColor = self.Colors.Gun; marker.OutlineTransparency = self.OutlineTransparency
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
		if self.Filters.CandyCoin then self:RefreshCoins(container)
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
