-- [[ esp ]]

return function(API)
	local Services = API.Roblox; local Player = API.Player; local Runtime = API.Runtime; local Util = API.Util
	local CoinService = API.Services.Coin; local MatchService = API.Services.Match; local Workspace = Services.Workspace

	-- State
	local ESP = {
		Enabled = false,
		ShowIdentity = true,
		ShowUsername = true,
		ShowSelf = true,
		ShowDistance = true,
		NameTextSizeNear = 12,
		NameTextSizeFar = 17,
		UsernameTextSizeMin = 10,
		NameScaleNearDistance = 24,
		NameScaleFarDistance = 240,
		RefreshInterval = 0.75,
		FillTransparency = 0.82,
		OutlineTransparency = 0,
		Thread = nil,
		RenderConnection = nil,
		RepairScheduled = false,
		RoleRemote = nil,
		RoleChangedConnection = nil,
		RoleData = nil,
		RoleDataAt = 0,
		RoleDataRefreshInterval = 1.25,
		RoleDataCacheLifetime = 2,
		InRound = false,
		LastErrorAt = 0,
		PlayerMarkers = {},
		LastKnownRoles = setmetatable({}, { __mode = "k" }),
		CoinMarkers = {},
		GunMarkers = {},
		Filters = {
			Murderer = true,
			Sheriff = true,
			Innocent = true,
			Player = true,
			Self = true,
			CandyCoin = false,
			Gun = true,
		},
		Colors = {
			Murderer = Color3.fromRGB(255, 65, 65),
			Sheriff = Color3.fromRGB(70, 155, 255),
			Innocent = Color3.fromRGB(70, 220, 120),
			Player = Color3.fromRGB(235, 235, 235),
			Self = Color3.fromRGB(235, 235, 235),
			CandyCoin = Color3.fromRGB(255, 185, 70),
			Gun = Color3.fromRGB(70, 225, 255),
		},
	}

	local STUD_TO_METERS = 0.28; local destroySafely = Util.DestroySafely
	local function getLabelColor(color) return color:Lerp(Color3.new(1, 1, 1), 0.38) end
	local function getNameTextSize(esp, distance)
		distance = tonumber(distance) or esp.NameScaleFarDistance
		local progress = math.clamp(
			(distance - esp.NameScaleNearDistance) / math.max(esp.NameScaleFarDistance - esp.NameScaleNearDistance, 1),
			0,
			1
		)
		return math.floor(esp.NameTextSizeNear + (esp.NameTextSizeFar - esp.NameTextSizeNear) * progress + 0.5)
	end
	local function getDistance(fromPart, toPart, fallback)
		if fromPart and fromPart:IsA("BasePart") and toPart and toPart:IsA("BasePart") then return (fromPart.Position - toPart.Position).Magnitude end
		return fallback
	end
	local function createTextLabel(name, parent)
		local label = Instance.new("TextLabel"); label.Name = name; label.BackgroundTransparency = 1; label.BorderSizePixel = 0
		label.Font = Enum.Font.GothamBold; label.TextColor3 = Color3.new(1, 1, 1); label.TextStrokeColor3 = Color3.new(0, 0, 0); label.TextStrokeTransparency = 0
		label.TextTruncate = Enum.TextTruncate.None; label.TextWrapped = false; label.TextXAlignment = Enum.TextXAlignment.Center; label.TextYAlignment = Enum.TextYAlignment.Center
		label.Parent = parent; return label
	end
	local function createBillboard(name, adornee, parent)
		local gui = Instance.new("BillboardGui"); gui.Name = name; gui.Adornee = adornee; gui.AlwaysOnTop = true
		gui.LightInfluence = 0; gui.MaxDistance = 0; gui.Size = UDim2.fromOffset(260, 24); gui.Parent = parent
		return gui
	end
	local function createHighlight(esp, name, adornee, color)
		local highlight = Instance.new("Highlight"); highlight.Name = name; highlight.Adornee = adornee; highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillColor = color
		highlight.FillTransparency = esp.FillTransparency
		highlight.OutlineColor = color
		highlight.OutlineTransparency = esp.OutlineTransparency; highlight.Parent = adornee; return highlight
	end
	local function destroyMarker(marker)
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
	local function getRoleLabel(role)
		if role == "Murderer" then return "Assassino" end
		if role == "Sheriff" then return "Xerife" end
		if role == "Hero" then return "Herói" end
		if role == "Innocent" then return "Inocente" end
		return nil
	end
	local function getObjectLabelAdornee(adornee, fallback)
		if adornee and adornee:IsA("BasePart") then return adornee end
		if adornee and adornee:IsA("Model") then
			if adornee.PrimaryPart then return adornee.PrimaryPart end
			local part = adornee:FindFirstChildWhichIsA("BasePart", true)
			if part then return part end
		end
		return fallback
	end

	-- MarkerCleanup
	function ESP:ClearMap(map)
		for key, marker in pairs(map) do
			if type(marker) == "table" then destroyMarker(marker)
			else destroySafely(marker) end
			map[key] = nil
		end
	end
	function ESP:ClearAll()
		for _, marker in pairs(self.PlayerMarkers) do
			destroyMarker(marker)
		end
		table.clear(self.PlayerMarkers); table.clear(self.LastKnownRoles); self:ClearMap(self.CoinMarkers); self:ClearMap(self.GunMarkers)
		local playerGui = Player:FindFirstChildOfClass("PlayerGui"); local oldIndicators = playerGui and playerGui:FindFirstChild("ChorusESPIndicators")
		if oldIndicators then destroySafely(oldIndicators) end
	end

	-- RoleData
	function ESP:ConnectRoleChanges()
		if self.RoleChangedConnection then return end
		local remote = Services.ReplicatedStorage:FindFirstChild("PlayerDataChanged", true)
		if not remote or not remote:IsA("RemoteEvent") then return end
		self.RoleChangedConnection = remote.OnClientEvent:Connect(function(changes)
			if type(changes) ~= "table" then return end
			local roleData = self.RoleData or {}
			for playerName, profile in pairs(changes) do
				if type(playerName) == "string" and type(profile) == "table" then
					roleData[playerName] = profile; local target = Services.Players:FindFirstChild(playerName)
					if profile.Dead == true or profile.Killed == true then
						if target then self.LastKnownRoles[target] = nil end
					elseif type(profile.Role) == "string" then
						if target then self.LastKnownRoles[target] = profile.Role end
					end
				end
			end
			self.RoleData = roleData; self.RoleDataAt = os.clock(); self:ScheduleRepair()
		end)
	end
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
		local highlight = createHighlight(self, "ChorusPlayerESP", character, color); local head = character:FindFirstChild("Head"); local nameAdornee = head and head:IsA("BasePart") and head or root
		local gui = createBillboard("ChorusPlayerName", nameAdornee, root); gui.StudsOffset = Vector3.new(0, nameAdornee.Size.Y * 0.5 + 0.55, 0); local identityLabel = createTextLabel("Identity", gui)
		local usernameLabel = createTextLabel("Username", gui); local distanceLabel = createTextLabel("Distance", gui)
		return {
			Character = character,
			Root = root,
			Gui = gui,
			IdentityLabel = identityLabel,
			UsernameLabel = usernameLabel,
			DistanceLabel = distanceLabel,
			NameAdornee = nameAdornee,
			Highlight = highlight,
		}
	end
	function ESP:UpdatePlayerLabels(marker, username, identity, color, distance)
		local categoryEnabled = marker.Category ~= nil and self.Filters[marker.Category] == true; local showIdentity = self.ShowIdentity == true and categoryEnabled
		local showDistance = self.ShowDistance == true and marker.IsSelf ~= true and categoryEnabled; local showUsername = self.ShowUsername == true and categoryEnabled
		local identitySize = getNameTextSize(self, distance); local usernameSize = math.max(self.UsernameTextSizeMin, identitySize - 3); local identityHeight = identitySize + 1
		local usernameHeight = usernameSize + 1; local offsetY = 0; local labelColor = getLabelColor(color); marker.IdentityLabel.Text = identity
		marker.IdentityLabel.TextColor3 = labelColor
		marker.IdentityLabel.TextSize = identitySize; marker.IdentityLabel.Visible = showIdentity; marker.UsernameLabel.Text = username
		marker.UsernameLabel.TextColor3 = labelColor
		marker.UsernameLabel.TextSize = usernameSize; marker.UsernameLabel.Visible = showUsername; local distanceText = type(distance) == "number"
				and distance == distance
				and math.abs(distance) < math.huge
				and (string.format("%.1f", math.max(distance, 0) * STUD_TO_METERS):gsub("%.", ",") .. "m")
			or "-- m"
		marker.DistanceLabel.Text = distanceText
		marker.DistanceLabel.TextColor3 = labelColor
		marker.DistanceLabel.TextSize = math.max(11, showIdentity and identitySize or usernameSize); marker.DistanceLabel.Visible = showDistance
		local primaryLabel, primaryHeight
		if showIdentity then
			if showUsername then
				marker.UsernameLabel.TextXAlignment = Enum.TextXAlignment.Center; marker.UsernameLabel.Position = UDim2.fromOffset(0, offsetY)
				marker.UsernameLabel.Size = UDim2.new(1, 0, 0, usernameHeight); offsetY += usernameHeight
			end
			primaryLabel, primaryHeight = marker.IdentityLabel, identityHeight
		elseif showUsername then
			primaryLabel, primaryHeight = marker.UsernameLabel, usernameHeight
		end
		if primaryLabel then
			primaryLabel.TextXAlignment = Enum.TextXAlignment.Left
			if showDistance then marker.DistanceLabel.Text = " " .. distanceText end
			local primaryWidth = math.max(1, math.ceil(primaryLabel.TextBounds.X)); local distanceWidth = showDistance and math.max(1, math.ceil(marker.DistanceLabel.TextBounds.X)) or 0
			local rowWidth = primaryWidth + distanceWidth; local rowHeight = math.max(primaryHeight, showDistance and (marker.DistanceLabel.TextSize + 1) or 0); local rowX = (260 - rowWidth) * 0.5
			primaryLabel.Position = UDim2.fromOffset(rowX, offsetY); primaryLabel.Size = UDim2.fromOffset(primaryWidth, rowHeight)
			if showDistance then
				marker.DistanceLabel.TextXAlignment = Enum.TextXAlignment.Left; marker.DistanceLabel.Position = UDim2.fromOffset(rowX + primaryWidth, offsetY)
				marker.DistanceLabel.Size = UDim2.fromOffset(distanceWidth, rowHeight)
			end
			offsetY += rowHeight
		elseif showDistance then
			marker.DistanceLabel.TextXAlignment = Enum.TextXAlignment.Center; local distanceWidth = math.ceil(marker.DistanceLabel.TextBounds.X)
			marker.DistanceLabel.Position = UDim2.fromOffset((260 - distanceWidth) * 0.5, offsetY); marker.DistanceLabel.Size = UDim2.fromOffset(distanceWidth, marker.DistanceLabel.TextSize + 2)
			offsetY += marker.DistanceLabel.TextSize + 2
		end
		marker.Gui.Size = UDim2.fromOffset(260, math.max(offsetY, 1)); marker.Gui.Enabled = offsetY > 0
	end
	function ESP:SetFilter(filter, enabled)
		if self.Filters[filter] == nil then return false end
		self.Filters[filter] = enabled == true
		if enabled then return true end
		if filter == "Murderer" or filter == "Sheriff" or filter == "Innocent" then
			for target, marker in pairs(self.PlayerMarkers) do
				if marker.Category == filter then destroyMarker(marker); self.PlayerMarkers[target] = nil end
			end
		elseif filter == "CandyCoin" then
			self:ClearMap(self.CoinMarkers)
		elseif filter == "Gun" then
			self:ClearMap(self.GunMarkers)
		end
		return true
	end
	function ESP:SetShowSelf(enabled)
		self.ShowSelf = enabled == true; self.Filters.Self = self.ShowSelf
		if not self.ShowSelf then
			local marker = self.PlayerMarkers[Player]
			if marker then destroyMarker(marker); self.PlayerMarkers[Player] = nil end
		elseif self.Enabled then
			self:ScheduleRepair()
		end
		return true
	end
	function ESP:RefreshPlayers(roleData, inMatch)
		local keepWorld = {}; local localCharacter = Player.Character; local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
		for _, target in ipairs(Services.Players:GetPlayers()) do
			local isSelf = target == Player
			if isSelf and not self.ShowSelf then continue end
			local profile = roleData and roleData[target.Name]; local character = target.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart"); local aliveAttribute = target:GetAttribute("Alive")
			local profileSaysDead = type(profile) == "table" and (profile.Dead == true or profile.Killed == true); local worldAvailable = character
				and character:IsDescendantOf(Workspace)
				and humanoid
				and humanoid.Health > 0
				and root
				and root:IsA("BasePart")
			if not worldAvailable then self.LastKnownRoles[target] = nil; continue end
			local roleActive = inMatch == true and aliveAttribute == true and not profileSaysDead
			if profileSaysDead then self.LastKnownRoles[target] = nil end
			local role = roleActive and (type(profile) == "table" and profile.Role or self.LastKnownRoles[target])
				or nil
			if roleActive and type(profile) == "table" and type(profile.Role) == "string" then self.LastKnownRoles[target] = profile.Role end
			local roleCategory = getRoleCategory(role); local roleLabel = type(role) == "string" and (getRoleLabel(role) or role) or nil; local category = isSelf and "Self" or roleCategory or "Player"
			local identity = isSelf and (roleLabel and ("Você · " .. roleLabel) or "Você")
				or roleLabel
				or "Sem papel"
			if category and identity and self.Filters[category] == true and worldAvailable then
				keepWorld[target] = true; local colorCategory = isSelf and (roleCategory or "Player") or category; local color = self.Colors[colorCategory]
				local distance = getDistance(localRoot, root); local marker = self.PlayerMarkers[target]; local head = character:FindFirstChild("Head")
				local nameAdornee = head and head:IsA("BasePart") and head or root
				if
					not marker
					or marker.Character ~= character
					or marker.Root ~= root
					or marker.NameAdornee ~= nameAdornee
					or not marker.Gui.Parent
					or not marker.Highlight.Parent
				then
					if marker then destroyMarker(marker) end
					marker = self:CreatePlayerMarker(target, character, root, color); self.PlayerMarkers[target] = marker
				end
				marker.Category = category; marker.ColorCategory = colorCategory; marker.Role = roleCategory and role or nil; marker.IsSelf = isSelf
				self:UpdatePlayerLabels(marker, target.Name, identity, color, distance)
				marker.Highlight.FillColor = color
				marker.Highlight.FillTransparency = self.FillTransparency
				marker.Highlight.OutlineColor = color
				marker.Highlight.OutlineTransparency = self.OutlineTransparency
			end
		end
		for target, marker in pairs(self.PlayerMarkers) do
			if not keepWorld[target] then destroyMarker(marker); self.PlayerMarkers[target] = nil end
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
		return visual:FindFirstChildWhichIsA("BasePart", true) or part
	end
	function ESP:RefreshCoins(container)
		local keep = {}; local localCharacter = Player.Character; local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
		for _, part in ipairs(CoinService:GetCollectableParts(container)) do
			local kind = CoinService:GetKind(part); local adornee = getCoinVisualAdornee(part); local labelAdornee = getObjectLabelAdornee(adornee, part)
			if kind and self.Filters.CandyCoin then
				keep[part] = true; local marker = self.CoinMarkers[part]
				if
					not marker
					or not marker.Gui.Parent
					or not marker.Highlight.Parent
					or marker.Highlight.Adornee ~= adornee
					or marker.Gui.Adornee ~= labelAdornee
				then
					if marker then destroyMarker(marker) end
					marker = {
						Highlight = createHighlight(self, "ChorusCandyCoinESP", adornee, self.Colors.CandyCoin),
						Gui = createBillboard("ChorusCandyCoinName", labelAdornee, labelAdornee),
					}

					marker.Gui.StudsOffset = Vector3.new(0, labelAdornee.Size.Y * 0.5 + 0.45, 0); marker.IdentityLabel = createTextLabel("Identity", marker.Gui); self.CoinMarkers[part] = marker
				end
				local label = kind == "candy" and "Candy" or "Coin"; local distance = getDistance(localRoot, part, self.NameScaleFarDistance); local textSize = getNameTextSize(self, distance)
				marker.IdentityLabel.Text = label; marker.IdentityLabel.TextColor3 = getLabelColor(self.Colors.CandyCoin); marker.IdentityLabel.TextSize = textSize
				marker.IdentityLabel.Size = UDim2.fromScale(1, 1); marker.IdentityLabel.Visible = self.ShowIdentity == true; marker.Gui.Size = UDim2.fromOffset(220, textSize + 8)
				marker.Gui.Enabled = self.ShowIdentity == true; marker.Highlight.FillColor = self.Colors.CandyCoin; marker.Highlight.FillTransparency = self.FillTransparency
				marker.Highlight.OutlineColor = self.Colors.CandyCoin; marker.Highlight.OutlineTransparency = self.OutlineTransparency
			end
		end
		for part, marker in pairs(self.CoinMarkers) do
			if not keep[part] then destroyMarker(marker); self.CoinMarkers[part] = nil end
		end
	end

	-- GunMarkers
	local function addGunPart(gunParts, instance, heldRoots)
		local part
		if instance:IsA("BasePart") and instance:IsDescendantOf(Services.Workspace) then part = instance
		elseif instance:IsA("Model") and instance:IsDescendantOf(Services.Workspace) then part = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
		elseif instance:IsDescendantOf(Workspace) then part = instance:FindFirstChildWhichIsA("BasePart", true) end
		if not part or not part:IsDescendantOf(Workspace) then return end
		local ancestor = part
		while ancestor and ancestor ~= Workspace do
			if ancestor:IsA("Tool") or heldRoots[ancestor] then return end
			ancestor = ancestor.Parent
		end
		gunParts[part] = true
	end
	function ESP:RefreshGuns()
		local gunParts = {}; local visibleGunParts = {}
		if self.Filters.Gun then
			local heldRoots = {}
			for _, target in ipairs(Services.Players:GetPlayers()) do
				if target.Character then heldRoots[target.Character] = true end
				local backpack = target:FindFirstChildOfClass("Backpack")
				if backpack then heldRoots[backpack] = true end
			end
			for _, gun in ipairs(Services.CollectionService:GetTagged("GunDrop")) do
				addGunPart(gunParts, gun, heldRoots)
			end
		end
		local localCharacter = Player.Character; local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
		for part in pairs(gunParts) do
			visibleGunParts[part] = true; local marker = self.GunMarkers[part]
			if not marker or not marker.Gui.Parent or not marker.Highlight.Parent then
				if marker then destroyMarker(marker) end
				local gui = createBillboard("ChorusGunName", part, part); gui.StudsOffset = Vector3.new(0, part.Size.Y * 0.5 + 0.45, 0)
				marker = {
					Highlight = createHighlight(self, "ChorusGunESP", part, self.Colors.Gun),
					Gui = gui,
					IdentityLabel = createTextLabel("Identity", gui),
				}

				self.GunMarkers[part] = marker
			end
			local distance = getDistance(localRoot, part, self.NameScaleFarDistance); local textSize = getNameTextSize(self, distance); marker.IdentityLabel.Text = "Arma"
			marker.IdentityLabel.TextColor3 = getLabelColor(self.Colors.Gun); marker.IdentityLabel.TextSize = textSize; marker.IdentityLabel.Size = UDim2.fromScale(1, 1)
			marker.IdentityLabel.Visible = self.ShowIdentity == true; marker.Gui.Size = UDim2.fromOffset(220, textSize + 8); marker.Gui.Enabled = self.ShowIdentity == true
			marker.Highlight.FillColor = self.Colors.Gun; marker.Highlight.FillTransparency = self.FillTransparency; marker.Highlight.OutlineColor = self.Colors.Gun
			marker.Highlight.OutlineTransparency = self.OutlineTransparency
		end
		for part, marker in pairs(self.GunMarkers) do
			if not visibleGunParts[part] then destroyMarker(marker); self.GunMarkers[part] = nil end
		end
	end

	-- Refresh
	function ESP:Refresh()
		local inMatch, _, container = MatchService:GetRoundContext(); self.InRound = inMatch == true
		if not inMatch then self.RoleData = nil; self.RoleDataAt = 0; table.clear(self.LastKnownRoles) end
		local needsRoleData = inMatch
			and (self.ShowSelf or self.Filters.Murderer or self.Filters.Sheriff or self.Filters.Innocent)
		self:RefreshPlayers(needsRoleData and self:GetRoleData() or nil, inMatch)
		if self.Filters.CandyCoin and container then self:RefreshCoins(container)
		else self:ClearMap(self.CoinMarkers) end
	end
	function ESP:ScheduleRepair()
		if self.RepairScheduled or not self.Enabled or Runtime.ShuttingDown then return end
		self.RepairScheduled = true
		task.defer(function()
			if self.Enabled and not Runtime.ShuttingDown then
				local ok, errorMessage = xpcall(function() self:Refresh() end, Util.FormatError)
				if not ok then self:ReportError("reparação de marcadores", errorMessage) end
			end
			self.RepairScheduled = false
		end)
	end
	local function reapplyLabel(label)
		label.BackgroundTransparency = 1; label.Font = Enum.Font.GothamBold; label.TextTransparency = 0; label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0
	end
	local function markerNeedsRepair(marker, includeUsername)
		if not marker or not marker.Gui or not marker.Highlight then return true end
		if not marker.Gui.Parent or not marker.Highlight.Parent then return true end
		if not marker.IdentityLabel or marker.IdentityLabel.Parent ~= marker.Gui then return true end
		if not includeUsername then return false end
		return not marker.UsernameLabel
			or marker.UsernameLabel.Parent ~= marker.Gui
			or not marker.DistanceLabel
			or marker.DistanceLabel.Parent ~= marker.Gui
	end
	function ESP:ReapplyMarkers()
		if not self.Enabled or Runtime.ShuttingDown then return end
		local needsRepair = false; local localCharacter = Player.Character; local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
		for target, marker in pairs(self.PlayerMarkers) do
			if not marker.Category or self.Filters[marker.Category] ~= true then destroyMarker(marker); self.PlayerMarkers[target] = nil; continue end
			local character = target.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local profile = self.RoleData and self.RoleData[target.Name]
			local profileSaysDead = type(profile) == "table" and (profile.Dead == true or profile.Killed == true)
			if
				not character
				or not character:IsDescendantOf(Workspace)
				or not humanoid
				or humanoid.Health <= 0
				or (marker.Role and (target:GetAttribute("Alive") ~= true or profileSaysDead))
			then
				if profileSaysDead then self.LastKnownRoles[target] = nil end
				destroyMarker(marker); self.PlayerMarkers[target] = nil; self:ScheduleRepair(); continue
			end
			if
				markerNeedsRepair(marker, true)
				or not marker.Character
				or not marker.Character.Parent
				or not marker.Root
				or not marker.Root.Parent
				or not marker.NameAdornee
				or not marker.NameAdornee.Parent
			then
				needsRepair = true; continue
			end
			local color = self.Colors[marker.ColorCategory or marker.Category]
			if not color then needsRepair = true; continue end
			local highlight = marker.Highlight; highlight.Adornee = marker.Character; highlight.Parent = marker.Character; highlight.Enabled = true
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillColor = color
			highlight.FillTransparency = self.FillTransparency
			highlight.OutlineColor = color
			highlight.OutlineTransparency = self.OutlineTransparency; local gui = marker.Gui; gui.Adornee = marker.NameAdornee; gui.Parent = marker.Root
			gui.AlwaysOnTop = true; gui.LightInfluence = 0; gui.MaxDistance = 0; gui.StudsOffset = Vector3.new(0, marker.NameAdornee.Size.Y * 0.5 + 0.55, 0)
			self:UpdatePlayerLabels(
				marker,
				marker.UsernameLabel.Text,
				marker.IdentityLabel.Text,
				color,
				getDistance(localRoot, marker.Root)
			)
			reapplyLabel(marker.IdentityLabel); reapplyLabel(marker.UsernameLabel); reapplyLabel(marker.DistanceLabel)
		end
		for part, marker in pairs(self.CoinMarkers) do
			if markerNeedsRepair(marker, false) or not part.Parent then needsRepair = true; continue end
			local adornee = getCoinVisualAdornee(part); local labelAdornee = getObjectLabelAdornee(adornee, part); local highlight = marker.Highlight; highlight.Adornee = adornee
			highlight.Parent = adornee; highlight.Enabled = true; highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; highlight.FillColor = self.Colors.CandyCoin
			highlight.FillTransparency = self.FillTransparency; highlight.OutlineColor = self.Colors.CandyCoin; highlight.OutlineTransparency = self.OutlineTransparency; local gui = marker.Gui
			gui.Adornee = labelAdornee; gui.Parent = labelAdornee; gui.AlwaysOnTop = true; gui.LightInfluence = 0
			gui.MaxDistance = 0; gui.StudsOffset = Vector3.new(0, labelAdornee.Size.Y * 0.5 + 0.45, 0); marker.IdentityLabel.Visible = self.ShowIdentity == true and self.Filters.CandyCoin == true
			marker.IdentityLabel.TextColor3 = getLabelColor(self.Colors.CandyCoin); marker.IdentityLabel.TextStrokeColor3 = Color3.new(0, 0, 0); marker.IdentityLabel.TextStrokeTransparency = 0
			marker.IdentityLabel.TextTransparency = 0; marker.IdentityLabel.Size = UDim2.fromScale(1, 1); gui.Size = UDim2.fromOffset(220, marker.IdentityLabel.TextSize + 8)
			gui.Enabled = marker.IdentityLabel.Visible; reapplyLabel(marker.IdentityLabel)
		end
		for part, marker in pairs(self.GunMarkers) do
			if markerNeedsRepair(marker, false) or not part.Parent then needsRepair = true; continue end
			local color = self.Colors.Gun; local highlight = marker.Highlight; highlight.Adornee = part; highlight.Parent = part
			highlight.Enabled = true; highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillColor = color
			highlight.FillTransparency = self.FillTransparency
			highlight.OutlineColor = color
			highlight.OutlineTransparency = self.OutlineTransparency; local gui = marker.Gui; gui.Adornee = part; gui.Parent = part
			gui.AlwaysOnTop = true; gui.LightInfluence = 0; gui.MaxDistance = 0; gui.StudsOffset = Vector3.new(0, part.Size.Y * 0.5 + 0.45, 0)
			marker.IdentityLabel.Visible = self.ShowIdentity == true and self.Filters.Gun == true; marker.IdentityLabel.TextColor3 = getLabelColor(color)
			marker.IdentityLabel.TextStrokeColor3 = Color3.new(0, 0, 0); marker.IdentityLabel.TextStrokeTransparency = 0; marker.IdentityLabel.TextTransparency = 0
			marker.IdentityLabel.Size = UDim2.fromScale(1, 1); gui.Size = UDim2.fromOffset(220, marker.IdentityLabel.TextSize + 8); gui.Enabled = marker.IdentityLabel.Visible
			reapplyLabel(marker.IdentityLabel)
		end
		if needsRepair then self:ScheduleRepair() end
	end
	function ESP:ReportError(context, errorMessage)
		local now = os.clock()
		if now - self.LastErrorAt < 5 then return end
		self.LastErrorAt = now; warn("[Chorus MM2] ESP recuperando após erro em " .. context .. ": " .. tostring(errorMessage))
	end

	-- Lifecycle
	function ESP:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self:ClearAll(); self.Enabled = true; self:ConnectRoleChanges()
		local refreshed, refreshError = xpcall(function() self:Refresh() end, Util.FormatError)
		if not refreshed then self:ReportError("atualização inicial", refreshError) end
		self.RenderConnection = Runtime:Track(Services.RunService.RenderStepped:Connect(function()
			local ok, errorMessage = xpcall(function()
				self:RefreshPlayers(self.RoleData, self.InRound); self:RefreshGuns(); self:ReapplyMarkers()
			end, Util.FormatError)
			if not ok then self:ReportError("reaplicar por frame", errorMessage) end
		end))
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
		if self.RenderConnection then
			pcall(function() self.RenderConnection:Disconnect() end)
			self.RenderConnection = nil
		end
		if thread then pcall(task.cancel, thread) end
		if self.RoleChangedConnection then
			pcall(function() self.RoleChangedConnection:Disconnect() end)
			self.RoleChangedConnection = nil
		end
		self:ClearAll(); self.RoleData = nil; self.RoleDataAt = 0
	end
	Runtime:OnShutdown(function() ESP:Stop() end)

	return ESP
end
