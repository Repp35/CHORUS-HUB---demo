-- [[ esp ]]

return function(API)
	local Services = API.Roblox; local Player = API.Player; local Runtime = API.Runtime; local Util = API.Util
	local CoinService = API.Services.Coin; local MatchService = API.Services.Match; local Workspace = Services.Workspace

	-- State
	local ESP = {
		Enabled = false,
		ShowIdentity = true,
		ShowUsername = false,
		NameTextSizeNear = 12,
		NameTextSizeFar = 17,
		UsernameTextSizeMin = 10,
		NameScaleNearDistance = 24,
		NameScaleFarDistance = 240,
		DirectionalDistanceThreshold = 1000,
		RefreshInterval = 0.75,
		FillTransparency = 0.82,
		OutlineTransparency = 0,
		Thread = nil,
		RenderConnection = nil,
		RoleRemote = nil,
		RoleChangedConnection = nil,
		RoleData = nil,
		RoleDataAt = 0,
		RoleDataRefreshInterval = 1.25,
		RoleDataCacheLifetime = 2,
		LastErrorAt = 0,
		PlayerMarkers = {},
		DirectionalMarkers = {},
		DirectionalGui = nil,
		LastKnownRoles = setmetatable({}, { __mode = "k" }),
		CoinMarkers = {},
		GunMarkers = {},
		Filters = {
			Murderer = true,
			Sheriff = true,
			Innocent = true,
			CandyCoin = false,
			Gun = false,
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
	local function getLabelColor(color) return color:Lerp(Color3.new(1, 1, 1), 0.38) end
	local function getNameTextSize(esp, distance)
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
	local function getCharacterPosition(character, root)
		if root and root:IsA("BasePart") and root:IsDescendantOf(Workspace) then return root.Position, true end
		if character and character:IsA("Model") then
			local ok, pivot = pcall(function() return character:GetPivot() end)
			if ok then return pivot.Position, character:IsDescendantOf(Workspace) end
		end
		if root and root:IsA("BasePart") then return root.Position, false end
		return nil, false
	end
	local function getDirectionalScreenPosition(camera, worldPosition)
		local projected, onScreen = camera:WorldToViewportPoint(worldPosition); local viewport = camera.ViewportSize; local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
		local point = Vector2.new(projected.X, projected.Y); local direction = point - center
		if projected.Z <= 0 then direction = -direction end
		if projected.Z > 0 and onScreen then
			local marginX = math.min(155, center.X); local marginY = math.min(30, center.Y)
			local safePoint = Vector2.new(
				math.clamp(point.X, marginX, math.max(viewport.X - marginX, marginX)),
				math.clamp(point.Y, marginY, math.max(viewport.Y - marginY, marginY))
			)
			local edge = (safePoint - point).Magnitude > 0.5; return safePoint, edge, math.deg(math.atan2(direction.Y, direction.X)) + 90
		end
		if direction.Magnitude < 0.001 then direction = Vector2.new(0, -1)
		else direction = direction.Unit end
		local halfWidth = math.max(center.X - 155, 1); local halfHeight = math.max(center.Y - 30, 1); local horizontalScale = halfWidth / math.max(math.abs(direction.X), 0.001)
		local verticalScale = halfHeight / math.max(math.abs(direction.Y), 0.001); local edgePoint = center + direction * math.min(horizontalScale, verticalScale)
		return edgePoint, true, math.deg(math.atan2(direction.Y, direction.X)) + 90
	end
	function ESP:EnsureDirectionalGui()
		if self.DirectionalGui and self.DirectionalGui.Parent then return self.DirectionalGui end
		local playerGui = Player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then return nil end
		local oldGui = playerGui:FindFirstChild("ChorusESPIndicators")
		if oldGui then destroySafely(oldGui) end
		local gui = Instance.new("ScreenGui"); gui.Name = "ChorusESPIndicators"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
		gui.DisplayOrder = 10000; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = playerGui; self.DirectionalGui = gui
		return gui
	end
	function ESP:CreateDirectionalMarker()
		local parent = self:EnsureDirectionalGui()
		if not parent then return nil end
		local frame = Instance.new("Frame"); frame.Name = "PlayerDirection"; frame.AnchorPoint = Vector2.new(0.5, 0.5); frame.BackgroundColor3 = Color3.fromRGB(8, 11, 18)
		frame.BackgroundTransparency = 0.32; frame.BorderSizePixel = 0; frame.Size = UDim2.fromOffset(300, 30); frame.Visible = false
		frame.ZIndex = 100; frame.Parent = parent; local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 7)
		corner.Parent = frame; local stroke = Instance.new("UIStroke"); stroke.Thickness = 1.25; stroke.Transparency = 0.12
		stroke.Parent = frame; local pointer = createTextLabel("Direction", frame); pointer.Position = UDim2.fromOffset(2, 1); pointer.Size = UDim2.fromOffset(28, 28)
		pointer.Font = Enum.Font.GothamBlack; pointer.Text = "▲"; pointer.TextSize = 19; pointer.ZIndex = 101
		local identityLabel = createTextLabel("Identity", frame); identityLabel.Position = UDim2.fromOffset(34, 1); identityLabel.Size = UDim2.new(1, -40, 0, 22)
		identityLabel.TextXAlignment = Enum.TextXAlignment.Left; identityLabel.ZIndex = 101; local usernameLabel = createTextLabel("Username", frame); usernameLabel.Position = UDim2.fromOffset(34, 1)
		usernameLabel.Size = UDim2.new(1, -40, 0, 18); usernameLabel.TextXAlignment = Enum.TextXAlignment.Left; usernameLabel.ZIndex = 101
		return {
			Frame = frame,
			Stroke = stroke,
			Pointer = pointer,
			IdentityLabel = identityLabel,
			UsernameLabel = usernameLabel,
		}
	end
	function ESP:UpdateDirectionalMarker(target, identity, color, distance, position, camera)
		local marker = self.DirectionalMarkers[target]
		if not marker or not marker.Frame.Parent then
			marker = self:CreateDirectionalMarker()
			if not marker then return false end
			self.DirectionalMarkers[target] = marker
		end
		local point, edge, rotation = getDirectionalScreenPosition(camera, position); local showIdentity = self.ShowIdentity == true; local showUsername = self.ShowUsername == true
		local identitySize = getNameTextSize(self, distance); local usernameSize = math.max(self.UsernameTextSizeMin, identitySize - 3); local labelColor = getLabelColor(color); local y = 4
		marker.Frame.Position = UDim2.fromOffset(point.X, point.Y); marker.Position = position
		marker.Stroke.Color = color
		marker.Pointer.TextColor3 = labelColor
		marker.Pointer.Rotation = rotation; marker.Pointer.Visible = edge; marker.UsernameLabel.Text = target.Name
		marker.UsernameLabel.TextColor3 = labelColor
		marker.UsernameLabel.TextSize = usernameSize; marker.UsernameLabel.Visible = showUsername; marker.IdentityLabel.Text = identity .. string.format(" · %.0f st", distance)
		marker.IdentityLabel.TextColor3 = labelColor
		marker.IdentityLabel.TextSize = identitySize; marker.IdentityLabel.Visible = showIdentity
		if showUsername then marker.UsernameLabel.Position = UDim2.fromOffset(34, y); marker.UsernameLabel.Size = UDim2.new(1, -40, 0, usernameSize + 5); y += usernameSize + 5 end
		if showIdentity then marker.IdentityLabel.Position = UDim2.fromOffset(34, y); marker.IdentityLabel.Size = UDim2.new(1, -40, 0, identitySize + 7); y += identitySize + 7 end
		marker.Frame.Size = UDim2.fromOffset(300, math.max(y + 2, 30)); marker.Frame.Visible = showIdentity or showUsername; return true
	end
	function ESP:UpdateDirectionalMarkerPositions()
		local camera = Workspace.CurrentCamera
		if not camera then
			for _, marker in pairs(self.DirectionalMarkers) do
				marker.Frame.Visible = false
			end
			return
		end
		for target, marker in pairs(self.DirectionalMarkers) do
			local character = target.Character; local root = character and character:FindFirstChild("HumanoidRootPart"); local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local position, isLive = getCharacterPosition(character, root); local profile = self.RoleData and self.RoleData[target.Name]; local isDead = target:GetAttribute("Alive") == false
				or type(profile) == "table" and (profile.Dead == true or profile.Killed == true)
			if not position or not isLive or isDead or humanoid and humanoid.Health <= 0 then marker.Frame.Visible = false; continue end
			marker.Position = position + Vector3.new(0, 2.5, 0); local point, edge, rotation = getDirectionalScreenPosition(camera, marker.Position)
			marker.Frame.Position = UDim2.fromOffset(point.X, point.Y); marker.Pointer.Rotation = rotation; marker.Pointer.Visible = edge; marker.Frame.Visible = self.ShowIdentity or self.ShowUsername
		end
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
		for _, marker in pairs(self.DirectionalMarkers) do
			destroySafely(marker.Frame)
		end
		table.clear(self.PlayerMarkers); table.clear(self.DirectionalMarkers); table.clear(self.LastKnownRoles); self:ClearMap(self.CoinMarkers)
		self:ClearMap(self.GunMarkers)
		if self.DirectionalGui then destroySafely(self.DirectionalGui); self.DirectionalGui = nil end
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
					roleData[playerName] = profile
					if type(profile.Role) == "string" then
						local target = Services.Players:FindFirstChild(playerName)
						if target then self.LastKnownRoles[target] = profile.Role end
					end
				end
			end
			self.RoleData = roleData; self.RoleDataAt = os.clock()
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
		local usernameLabel = createTextLabel("Username", gui)
		return {
			Character = character,
			Root = root,
			Gui = gui,
			IdentityLabel = identityLabel,
			UsernameLabel = usernameLabel,
			NameAdornee = nameAdornee,
			Highlight = highlight,
		}
	end
	function ESP:UpdatePlayerLabels(marker, username, identity, color, distance, worldVisible)
		local showIdentity = self.ShowIdentity == true; local showUsername = self.ShowUsername == true; local identitySize = getNameTextSize(self, distance)
		local usernameSize = math.max(self.UsernameTextSizeMin, identitySize - 3); local identityHeight = identitySize + 8; local usernameHeight = usernameSize + 6; local offsetY = 0
		local labelColor = getLabelColor(color); marker.IdentityLabel.Text = identity
		marker.IdentityLabel.TextColor3 = labelColor
		marker.IdentityLabel.TextSize = identitySize; marker.IdentityLabel.Visible = showIdentity; marker.UsernameLabel.Text = username
		marker.UsernameLabel.TextColor3 = labelColor
		marker.UsernameLabel.TextSize = usernameSize; marker.UsernameLabel.Visible = showUsername
		if showUsername then marker.UsernameLabel.Position = UDim2.fromOffset(0, offsetY); marker.UsernameLabel.Size = UDim2.new(1, 0, 0, usernameHeight); offsetY += usernameHeight end
		if showIdentity then marker.IdentityLabel.Position = UDim2.fromOffset(0, offsetY); marker.IdentityLabel.Size = UDim2.new(1, 0, 0, identityHeight); offsetY += identityHeight end
		marker.Gui.Size = UDim2.fromOffset(260, math.max(offsetY, 1)); marker.Gui.Enabled = worldVisible and offsetY > 0
	end
	function ESP:RefreshPlayers(roleData)
		local keepWorld = {}; local keepDirectional = {}; local localCharacter = Player.Character; local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
		local camera = Workspace.CurrentCamera
		for _, target in ipairs(Services.Players:GetPlayers()) do
			if target == Player then continue end
			local profile = roleData and roleData[target.Name]; local character = target.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart"); local aliveAttribute = target:GetAttribute("Alive")
			local profileSaysDead = type(profile) == "table" and (profile.Dead == true or profile.Killed == true)
			if aliveAttribute == false or profileSaysDead or humanoid and humanoid.Health <= 0 then self.LastKnownRoles[target] = nil; continue end
			local role = type(profile) == "table" and profile.Role or self.LastKnownRoles[target]
			if type(profile) == "table" and type(profile.Role) == "string" then self.LastKnownRoles[target] = profile.Role end
			local position, positionIsLive = getCharacterPosition(character, root)
			if not position or not positionIsLive then continue end
			local category = getRoleCategory(role); local identity = getRoleLabel(role); local markerPosition = position
			if category and identity and self.Filters[category] and markerPosition then
				local color = self.Colors[category]; local origin = localRoot and localRoot:IsA("BasePart") and localRoot.Position
					or (camera and camera.CFrame.Position)
				local distance = origin and (origin - markerPosition).Magnitude or self.NameScaleFarDistance; local worldAvailable = character
					and character:IsDescendantOf(Workspace)
					and humanoid
					and humanoid.Health > 0
					and root
					and root:IsA("BasePart")
				local useWorldMarker = worldAvailable and distance < self.DirectionalDistanceThreshold
				if useWorldMarker then
					keepWorld[target] = true; local marker = self.PlayerMarkers[target]; local head = character:FindFirstChild("Head")
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
					self:UpdatePlayerLabels(marker, target.Name, identity, color, distance, true)
					marker.Highlight.FillColor = color
					marker.Highlight.FillTransparency = self.FillTransparency
					marker.Highlight.OutlineColor = color
					marker.Highlight.OutlineTransparency = self.OutlineTransparency
				else
					local marker = self.PlayerMarkers[target]
					if marker then destroyMarker(marker); self.PlayerMarkers[target] = nil end
				end
				local labelPosition = markerPosition + Vector3.new(0, 2.5, 0)
				local projected, onScreen
				if camera then projected, onScreen = camera:WorldToViewportPoint(labelPosition) end
				local showDirectional = not useWorldMarker or not projected or projected.Z <= 0 or not onScreen
				if showDirectional and camera then
					if self:UpdateDirectionalMarker(target, identity, color, distance, labelPosition, camera) then keepDirectional[target] = true end
				end
			end
		end
		for target, marker in pairs(self.PlayerMarkers) do
			if not keepWorld[target] then destroyMarker(marker); self.PlayerMarkers[target] = nil end
		end
		for target, marker in pairs(self.DirectionalMarkers) do
			if not keepDirectional[target] then destroySafely(marker.Frame); self.DirectionalMarkers[target] = nil end
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
	local function addGunPart(gunParts, instance)
		if instance:IsA("BasePart") and instance:IsDescendantOf(Services.Workspace) then
			gunParts[instance] = true
		elseif instance:IsA("Model") and instance:IsDescendantOf(Services.Workspace) then
			local part = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
			if part then gunParts[part] = true end
		end
	end
	function ESP:RefreshGuns()
		local gunParts = {}
		if self.Filters.Gun then
			for _, gun in ipairs(Services.CollectionService:GetTagged("GunDrop")) do
				addGunPart(gunParts, gun)
			end
			for _, target in ipairs(Services.Players:GetPlayers()) do
				if target ~= Player then
					local character = target.Character; local tool = character and character:FindFirstChild("Gun"); local handle = tool and tool:FindFirstChild("Handle")
					if handle and handle:IsA("BasePart") then addGunPart(gunParts, handle) end
				end
			end
		end
		local localCharacter = Player.Character; local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
		for part in pairs(gunParts) do
			local marker = self.GunMarkers[part]
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
			if not gunParts[part] then destroyMarker(marker); self.GunMarkers[part] = nil end
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
		self.Enabled = true; self:ConnectRoleChanges()
		self.RenderConnection = Services.RunService.RenderStepped:Connect(function()
			if not self.Enabled then return end
			local ok, errorMessage = pcall(function() self:UpdateDirectionalMarkerPositions() end)
			if not ok then self:ReportError("atualização dos indicadores direcionais", errorMessage) end
		end)
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
		if self.RenderConnection then
			pcall(function() self.RenderConnection:Disconnect() end)
			self.RenderConnection = nil
		end
		if self.RoleChangedConnection then
			pcall(function() self.RoleChangedConnection:Disconnect() end)
			self.RoleChangedConnection = nil
		end
		self:ClearAll(); self.RoleData = nil; self.RoleDataAt = 0
	end
	Runtime:OnShutdown(function() ESP:Stop() end)

	return ESP
end
