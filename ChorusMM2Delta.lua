-- Chorus - MM2 | Delta
-- Arquivo monolítico organizado em módulos internos.

--// 0. RESTRIÇÃO À EXPERIÊNCIA DO MM2
local MM2_GAME_ID = 66654135

local function getSharedEnvironment()
	if type(getgenv) == "function" then
		local ok, environment = pcall(getgenv)
		if ok and type(environment) == "table" then
			return environment
		end
	end
	return _G
end

local SharedEnvironment = getSharedEnvironment()
local PreviousRuntime = rawget(SharedEnvironment, "__ChorusMM2DeltaRuntime")
local isMM2 = game.PlaceId == MM2_GAME_ID
if not isMM2 then
	local gameIdOk, gameId = pcall(function()
		return game.GameId
	end)
	isMM2 = gameIdOk and gameId == MM2_GAME_ID
end

if not isMM2 then
	if type(PreviousRuntime) == "table" and type(PreviousRuntime.Shutdown) == "function" then
		pcall(PreviousRuntime.Shutdown, PreviousRuntime)
	end
	return
end

--// 1. CONFIGURAÇÃO E SERVIÇOS
local Config = {
	Name = "Chorus - MM2 | Delta",
	ConfigFolder = "ChorusMM2Delta",
	SaveConfig = true,
	HidePremium = true,
	IntroEnabled = false,
	OrionSource = "https://raw.githubusercontent.com/Qanuir/orion-ui/refs/heads/main/source.lua",
	MapRefreshInterval = 1,
	CoinSearchRadius = 200,
	CoinFilter = "Todos",
}

local Services = {
	Players = game:GetService("Players"),
	RunService = game:GetService("RunService"),
	Workspace = game:GetService("Workspace"),
	TweenService = game:GetService("TweenService"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	CollectionService = game:GetService("CollectionService"),
	CoreGui = game:GetService("CoreGui"),
}

local Player = Services.Players.LocalPlayer
if not Player then
	error("Este arquivo precisa ser executado no cliente do Roblox.")
end

local Runtime = {
	Connections = {},
	Tasks = {},
	ShuttingDown = false,
}
local Farm = nil
local AntiAFK = nil
local AntiFling = nil
local ESP = nil
local FloatingGui = nil
local OrionScreen = nil
local Host = nil

function Runtime:Track(connection)
	table.insert(self.Connections, connection)
	return connection
end

function Runtime:TrackTask(thread)
	if thread then
		table.insert(self.Tasks, thread)
	end
	return thread
end

-- Encerra uma execução anterior deste mesmo arquivo, se existir.
if type(PreviousRuntime) == "table" and type(PreviousRuntime.Shutdown) == "function" then
	pcall(PreviousRuntime.Shutdown, PreviousRuntime)
end

function Runtime:Shutdown()
	if self.ShuttingDown then
		return
	end
	self.ShuttingDown = true
	if Farm then
		pcall(function()
			Farm:Stop()
		end)
	end
	if ESP then
		pcall(function()
			ESP:Stop()
		end)
	end
	if AntiAFK then
		pcall(function()
			AntiAFK:Stop()
		end)
	end
	if AntiFling then
		pcall(function()
			AntiFling:Stop()
		end)
	end
	for _, connection in ipairs(self.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self.Connections)
	for _, thread in ipairs(self.Tasks) do
		pcall(task.cancel, thread)
	end
	table.clear(self.Tasks)
	if FloatingGui and FloatingGui.Parent then
		pcall(function()
			FloatingGui:Destroy()
		end)
	end
	if OrionScreen and OrionScreen.Parent then
		pcall(function()
			OrionScreen:Destroy()
		end)
	elseif Host then
		local partialScreen = Host:FindFirstChild("Orion")
			or Services.CoreGui:FindFirstChild("Orion")
		if partialScreen and partialScreen:IsA("ScreenGui") then
			pcall(function()
				partialScreen:Destroy()
			end)
		end
	end
end

rawset(SharedEnvironment, "__ChorusMM2DeltaRuntime", Runtime)

local OrionOk, OrionLib = pcall(function()
	local source = game:HttpGet(Config.OrionSource)
	return loadstring(source)()
end)
if not OrionOk or type(OrionLib) ~= "table" then
	error("Falha ao carregar a Orion: " .. tostring(OrionLib))
end
if type(OrionLib.MakeWindow) ~= "function" or type(OrionLib.Init) ~= "function" then
	error("A fonte carregada não oferece a API esperada da Orion.")
end

local function initializeComponent(label, callback)
	local ok, result = pcall(callback)
	if not ok then
		Runtime:Shutdown()
		error("Falha ao " .. label .. ": " .. tostring(result), 0)
	end
	return result
end

--// 2. UTILITÁRIOS DE INTERFACE
local function getHost()
	if type(gethui) == "function" then
		local ok, host = pcall(gethui)
		if ok and typeof(host) == "Instance" then
			return host
		end
	end
	return Services.CoreGui
end

Host = getHost()
local function destroyOldFloatingGui(parent)
	local previousGui = parent:FindFirstChild("ChorusMobileControls")
	if previousGui then
		previousGui:Destroy()
	end
end

local function destroyPreviousOrion(parent)
	if type(PreviousRuntime) ~= "table" then
		return
	end
	local previousScreen = parent:FindFirstChild("Orion")
	if previousScreen and previousScreen:IsA("ScreenGui") then
		previousScreen:Destroy()
	end
end

destroyOldFloatingGui(Host)
destroyPreviousOrion(Host)
if Host ~= Services.CoreGui then
	destroyOldFloatingGui(Services.CoreGui)
	destroyPreviousOrion(Services.CoreGui)
end

local function create(className, properties, parent)
	local object = Instance.new(className)
	for property, value in pairs(properties) do
		object[property] = value
	end
	object.Parent = parent
	return object
end

local function formatError(errorMessage)
	local debugLibrary = debug
	if type(debugLibrary) == "table" and type(debugLibrary.traceback) == "function" then
		local ok, trace = pcall(debugLibrary.traceback, tostring(errorMessage), 2)
		if ok then
			return trace
		end
	end
	return tostring(errorMessage)
end

FloatingGui = create("ScreenGui", {
	Name = "ChorusMobileControls",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 10000,
}, Host)

local FloatingButton = create("TextButton", {
	Name = "ReopenHub",
	Size = UDim2.fromOffset(48, 48),
	Position = UDim2.new(0, 14, 1, -70),
	BackgroundColor3 = Color3.fromRGB(112, 82, 245),
	Text = "C",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 18,
	Font = Enum.Font.GothamBold,
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 100,
}, FloatingGui)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, FloatingButton)
create("UIStroke", { Color = Color3.fromRGB(173, 153, 255), Thickness = 1 }, FloatingButton)

local UI = {}

function UI:FindWindow()
	local screen = Host:FindFirstChild("Orion") or Services.CoreGui:FindFirstChild("Orion")
	if not screen or not screen:IsA("ScreenGui") then
		return nil, nil
	end
	OrionScreen = screen

	for _, child in ipairs(screen:GetChildren()) do
		if child:IsA("Frame") and child:FindFirstChild("TopBar") then
			return screen, child
		end
	end
	return screen, nil
end

function UI:SetOpen(open)
	local screen, window = self:FindWindow()
	if screen then
		pcall(function()
			screen.Enabled = open
		end)
	end
	if window then
		pcall(function()
			window.Visible = open
		end)
	end
	if FloatingButton.Parent then
		FloatingButton.Visible = not open or screen == nil
	end
end

Runtime:Track(FloatingButton.Activated:Connect(function()
	UI:SetOpen(true)
end))

--// 3. MÓDULO DE MAPA E MOEDAS
local MapService = {
	CachedContainer = nil,
	NextScan = 0,
}

local function isCoinContainer(instance)
	return instance
		and instance.Name == "CoinContainer"
		and (instance:IsA("Folder") or instance:IsA("Model"))
end

local function isMapCoinContainer(instance)
	local map = instance and instance.Parent
	return isCoinContainer(instance)
		and map
		and map:IsA("Model")
		and map.Parent == Services.Workspace
end

Runtime:Track(Services.Workspace.DescendantAdded:Connect(function(instance)
	if isMapCoinContainer(instance) then
		MapService.CachedContainer = nil
		MapService.NextScan = 0
	end
end))

Runtime:Track(Services.Workspace.DescendantRemoving:Connect(function(instance)
	local cached = MapService.CachedContainer
	if cached and (cached == instance or cached:IsDescendantOf(instance)) then
		MapService.CachedContainer = nil
		MapService.NextScan = 0
	end
end))

local function normalizeCoinKind(value)
	if type(value) ~= "string" then
		return nil
	end

	local normalized = string.lower(value)
	if normalized == "candy" then
		return "candy"
	end
	if normalized == "coin" then
		return "coin"
	end
	return nil
end

local function getCoinKind(part)
	-- NewMM2 identifies Candy directly through CoinID; the standalone
	-- reference accepts regular coins through a valid CoinVisual instead.
	local kind = normalizeCoinKind(part:GetAttribute("CoinID"))
	if kind then
		return kind
	end
	-- The standalone reference accepts valid CoinVisual-based coins even when
	-- they do not expose a CoinID attribute.
	return part:FindFirstChild("CoinVisual") and "coin" or nil
end

local function isCollectableCoin(part, container, respectFarmFilter)
	if not part or not part:IsA("BasePart") or not part.Parent then
		return false
	end
	if not part:IsDescendantOf(container) or part:GetAttribute("Collected") then
		return false
	end
	if not part:FindFirstChild("TouchInterest") then
		return false
	end

	local kind = getCoinKind(part)
	if not kind then
		return false
	end
	if respectFarmFilter ~= false
		and Config.CoinFilter ~= "Todos"
		and kind ~= string.lower(Config.CoinFilter) then
		return false
	end

	local visual = part:FindFirstChild("CoinVisual")
	local isNewMM2Candy = kind == "candy" and part.Transparency == 1
	if visual then
		if visual:GetAttribute("Delete") or visual:GetAttribute("Collected") then
			return false
		end
		local mainCoin = visual:FindFirstChild("MainCoin")
		local visualIsReady = mainCoin and mainCoin:IsA("BasePart") and mainCoin.Transparency < 0.95
		if not visualIsReady and not isNewMM2Candy then
			return false
		end
	elseif not isNewMM2Candy then
		-- NewMM2's candy part is an invisible server-side touch part with
		-- CoinID = Candy. CoinVisual-based coins are handled above.
		return false
	end
	return true
end

local function collectCoinParts(container, respectFarmFilter)
	local parts = {}
	for _, instance in ipairs(container:GetChildren()) do
		if instance:IsA("BasePart") and isCollectableCoin(instance, container, respectFarmFilter) then
			table.insert(parts, instance)
		end
	end
	return parts
end

function MapService:GetCoinContainer()
	local now = os.clock()
	if now < self.NextScan and isMapCoinContainer(self.CachedContainer) then
		return self.CachedContainer
	end
	self.CachedContainer = nil

	if now < self.NextScan then
		return nil
	end
	self.NextScan = now + Config.MapRefreshInterval

	-- Match the references: use the active MapID model first, then the
	-- top-level map model containing CoinContainer as in NewMM2.
	local fallback = nil
	for _, map in ipairs(Services.Workspace:GetChildren()) do
		if map:IsA("Model") then
			local container = map:FindFirstChild("CoinContainer")
			if isCoinContainer(container) then
				if map:GetAttribute("MapID") ~= nil then
					self.CachedContainer = container
					return container
				end
				fallback = fallback or container
			end
		end
	end

	if fallback then
		self.CachedContainer = fallback
		return fallback
	end
	return nil
end

function MapService:GetNearestCoin(container, position, retryAfter)
	if not container or not container.Parent then
		return nil, math.huge
	end

	local nearest, nearestDistance = nil, math.huge
	local now = os.clock()
	for _, coin in ipairs(collectCoinParts(container)) do
		local retryAt = retryAfter[coin] or 0
		if coin.Parent and coin:IsDescendantOf(container) and retryAt <= now then
			local distance = (position - coin.Position).Magnitude
			if distance <= Config.CoinSearchRadius and distance < nearestDistance then
				nearest, nearestDistance = coin, distance
			end
		end
	end
	return nearest, nearestDistance
end

--// 4. MÓDULO DE ESTADO DA PARTIDA
local MatchService = {}

function MatchService:GetContext()
	local character = Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return false
	end

	if Player:GetAttribute("Alive") ~= true then
		return false
	end

	local container = MapService:GetCoinContainer()
	if not container then
		return false
	end
	return true, character, humanoid, root, container
end

--// 5. MÓDULO DE ESP
ESP = {
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

local function destroySafely(instance)
	if instance then
		pcall(function()
			instance:Destroy()
		end)
	end
end

local function getRoleCategory(role)
	if role == "Murderer" then
		return "Murderer"
	end
	if role == "Sheriff" or role == "Hero" then
		return "Sheriff"
	end
	if role == "Innocent" then
		return "Innocent"
	end
	return nil
end

function ESP:ClearMap(map)
	for key, instance in pairs(map) do
		destroySafely(instance)
		map[key] = nil
	end
end

function ESP:ClearAll()
	for _, marker in pairs(self.PlayerMarkers) do
		destroySafely(marker.Gui)
	end
	table.clear(self.PlayerMarkers)
	self:ClearMap(self.CoinMarkers)
	self:ClearMap(self.GunMarkers)
end

function ESP:GetRoleData()
	local now = os.clock()
	if self.RoleData and now - self.RoleDataAt < self.RoleDataRefreshInterval then
		return self.RoleData
	end
	if not self.RoleRemote or not self.RoleRemote.Parent or not self.RoleRemote:IsA("RemoteFunction") then
		self.RoleRemote = Services.ReplicatedStorage:FindFirstChild("GetPlayerData", true)
	end

	local remote = self.RoleRemote
	if remote and remote:IsA("RemoteFunction") then
		local ok, data = pcall(function()
			return remote:InvokeServer()
		end)
		if ok and type(data) == "table" then
			self.RoleData = data
			self.RoleDataAt = os.clock()
			return data
		end
	end

	if self.RoleData and os.clock() - self.RoleDataAt <= self.RoleDataCacheLifetime then
		return self.RoleData
	end
	return nil
end

function ESP:CreatePlayerMarker(target, character, root, color)
	local gui = Instance.new("BillboardGui")
	gui.Name = "ChorusPlayerESP"
	gui.Adornee = root
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 1200
	gui.Size = UDim2.fromOffset(112, 142)
	gui.StudsOffset = Vector3.new(0, 2.25, 0)
	gui.Parent = root

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(0, 0)
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = target.Name
	nameLabel.TextColor3 = color
	nameLabel.TextSize = 13
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.15
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Visible = self.ShowName
	nameLabel.Parent = gui

	local box = Instance.new("Frame")
	box.Name = "PlayerBox"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Position = UDim2.fromOffset(6, 22)
	box.Size = UDim2.new(1, -12, 1, -28)
	box.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Name = "RoleColor"
	stroke.Color = color
	stroke.Thickness = 1.5
	stroke.Transparency = 0
	stroke.Parent = box

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
			local character = target.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local profile = roleData and roleData[target.Name]
			local role = type(profile) == "table" and profile.Role or nil
			local category = getRoleCategory(role)

			if character and character.Parent and humanoid and humanoid.Health > 0
				and root and root:IsA("BasePart") and category and self.Filters[category] then
				keep[target] = true
				local color = self.Colors[category]
				local marker = self.PlayerMarkers[target]
				if not marker or marker.Character ~= character or marker.Root ~= root
					or not marker.Gui.Parent then
					if marker then
						destroySafely(marker.Gui)
					end
					marker = self:CreatePlayerMarker(target, character, root, color)
					self.PlayerMarkers[target] = marker
				end

				marker.NameLabel.Text = target.Name
				marker.NameLabel.TextColor3 = color
				marker.NameLabel.Visible = self.ShowName
				marker.Stroke.Color = color
			end
		end
	end

	for target, marker in pairs(self.PlayerMarkers) do
		if not keep[target] then
			destroySafely(marker.Gui)
			self.PlayerMarkers[target] = nil
		end
	end
end

function ESP:RefreshCoins(container)
	local keep = {}
	for _, part in ipairs(collectCoinParts(container, false)) do
		local kind = getCoinKind(part)
		local category = kind == "candy" and "Candy" or kind == "coin" and "Coin" or nil
		if category and self.Filters[category] then
			keep[part] = true
			local marker = self.CoinMarkers[part]
			if not marker or not marker.Parent then
				marker = Instance.new("SphereHandleAdornment")
				marker.Name = "Chorus" .. category .. "ESP"
				marker.Adornee = part
				marker.Radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 0.5 + 0.3
				marker.AlwaysOnTop = true
				marker.ZIndex = 5
				marker.Transparency = 0.25
				marker.Parent = part
				self.CoinMarkers[part] = marker
			end
			marker.Color3 = self.Colors[category]
		end
	end

	for part, marker in pairs(self.CoinMarkers) do
		if not keep[part] then
			destroySafely(marker)
			self.CoinMarkers[part] = nil
		end
	end
end

function ESP:RefreshGuns()
	local gunParts = {}
	if self.Filters.Gun then
		for _, gun in ipairs(Services.CollectionService:GetTagged("GunDrop")) do
			if gun:IsA("BasePart") and gun:IsDescendantOf(Services.Workspace) then
				gunParts[gun] = true
			end
		end
		for _, target in ipairs(Services.Players:GetPlayers()) do
			if target ~= Player then
				local character = target.Character
				local tool = character and character:FindFirstChild("Gun")
				local handle = tool and tool:FindFirstChild("Handle")
				if handle and handle:IsA("BasePart") and handle:IsDescendantOf(Services.Workspace) then
					gunParts[handle] = true
				end
			end
		end
	end

	for part in pairs(gunParts) do
		local marker = self.GunMarkers[part]
		if not marker or not marker.Parent then
			marker = Instance.new("Highlight")
			marker.Name = "ChorusGunESP"
			marker.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			marker.FillTransparency = 0.35
			marker.OutlineTransparency = 0
			marker.Adornee = part
			marker.Parent = part
			self.GunMarkers[part] = marker
		end
		marker.FillColor = self.Colors.Gun
		marker.OutlineColor = self.Colors.Gun
	end

	for part, marker in pairs(self.GunMarkers) do
		if not gunParts[part] then
			destroySafely(marker)
			self.GunMarkers[part] = nil
		end
	end
end

function ESP:Refresh()
	local inMatch, _, _, _, container = MatchService:GetContext()
	if not inMatch then
		self:ClearAll()
		self.RoleData = nil
		self.RoleDataAt = 0
		return
	end

	local needsRoleData = self.Filters.Murderer or self.Filters.Sheriff or self.Filters.Innocent
	self:RefreshPlayers(needsRoleData and self:GetRoleData() or nil)
	if self.Filters.Candy or self.Filters.Coin then
		self:RefreshCoins(container)
	else
		self:ClearMap(self.CoinMarkers)
	end
	self:RefreshGuns()
end

function ESP:ReportError(context, errorMessage)
	local now = os.clock()
	if now - self.LastErrorAt < 5 then
		return
	end
	self.LastErrorAt = now
	warn("[Chorus MM2] ESP recuperando após erro em " .. context .. ": " .. tostring(errorMessage))
end

function ESP:Start()
	if self.Enabled or Runtime.ShuttingDown then
		return
	end
	self.Enabled = true
	local thread
	thread = task.spawn(function()
		while self.Enabled and not Runtime.ShuttingDown do
			local ok, errorMessage = xpcall(function()
				self:Refresh()
			end, formatError)
			if not ok then
				self:ReportError("atualização", errorMessage)
			end
			task.wait(self.RefreshInterval)
		end

		if self.Thread == thread then
			self.Thread = nil
		end
		self:ClearAll()
	end)
	self.Thread = thread
end

function ESP:Stop()
	self.Enabled = false
	local thread = self.Thread
	self.Thread = nil
	if thread then
		pcall(task.cancel, thread)
	end
	self:ClearAll()
	self.RoleData = nil
	self.RoleDataAt = 0
end

--// 6. MÓDULO DE COLETA
Farm = {
	Enabled = false,
	Farming = false,
	Speed = 23,
	Thread = nil,
	Tween = nil,
	ProximityConnection = nil,
	LastProximitySweepAt = 0,
	BagFull = false,
	MaintenanceConnection = nil,
	NoclipConnection = nil,
	NoclipDescendantConnection = nil,
	OriginalPartProperties = {},
	NoclipCharacter = nil,
	FarmingCharacter = nil,
	FarmingHumanoid = nil,
	SavedHumanoidState = nil,
	RetryAfter = setmetatable({}, { __mode = "k" }),
	LastErrorAt = 0,
}

local function getTouchFunction()
	local ok, touchFunction = pcall(function()
		return firetouchinterest
	end)
	if ok and type(touchFunction) == "function" then
		return touchFunction
	end
	return nil
end

function Farm:ReportError(context, errorMessage)
	local now = os.clock()
	if now - self.LastErrorAt < 5 then
		return
	end
	self.LastErrorAt = now
	warn("[Chorus MM2] Auto Farm recuperando após erro em " .. context .. ": " .. tostring(errorMessage))
end

function Farm:EnableNoclip(character)
	if self.NoclipConnection and self.NoclipCharacter == character then
		return
	end
	self:DisableNoclip()
	self.NoclipCharacter = character

	local function rememberAndDisable(part)
		if not part:IsA("BasePart") then
			return
		end
		if self.OriginalPartProperties[part] == nil then
			self.OriginalPartProperties[part] = {
				CanCollide = part.CanCollide,
				Massless = part.Massless,
			}
		end
		pcall(function()
			part.CanCollide = false
		end)
	end

	for _, part in ipairs(character:GetDescendants()) do
		rememberAndDisable(part)
	end
	self.NoclipDescendantConnection = character.DescendantAdded:Connect(rememberAndDisable)
	self.NoclipConnection = Services.RunService.Stepped:Connect(function()
		if not self.Enabled or not self.Farming or Player.Character ~= character then
			self:DisableNoclip()
			return
		end
		for part in pairs(self.OriginalPartProperties) do
			if part.Parent then
				pcall(function()
					part.CanCollide = false
				end)
			end
		end
	end)
end

function Farm:DisableNoclip()
	if self.NoclipConnection then
		pcall(function()
			self.NoclipConnection:Disconnect()
		end)
		self.NoclipConnection = nil
	end
	if self.NoclipDescendantConnection then
		pcall(function()
			self.NoclipDescendantConnection:Disconnect()
		end)
		self.NoclipDescendantConnection = nil
	end

	for part, properties in pairs(self.OriginalPartProperties) do
		if part.Parent then
			pcall(function()
				part.CanCollide = properties.CanCollide
				part.Massless = properties.Massless
			end)
		end
	end
	self.OriginalPartProperties = {}
	self.NoclipCharacter = nil
end

function Farm:TouchOnce(root, coin)
	if not self.Enabled or not root or not root.Parent or not coin or not coin.Parent then
		return
	end
	local touchFunction = getTouchFunction()
	if not touchFunction then
		return
	end
	pcall(touchFunction, root, coin, 0)
	pcall(touchFunction, root, coin, 1)
end

function Farm:StartProximityCollection()
	if self.ProximityConnection then
		return
	end
	self.ProximityConnection = Services.RunService.Heartbeat:Connect(function()
		if not self.Enabled or not self.Farming or self.BagFull then
			return
		end
		local now = os.clock()
		if now - self.LastProximitySweepAt < 0.1 then
			return
		end
		self.LastProximitySweepAt = now

		local ok, errorMessage = xpcall(function()
			local inMatch, _, _, root, container = MatchService:GetContext()
			if not inMatch then
				return
			end
			for _, coin in ipairs(collectCoinParts(container)) do
				if (root.Position - coin.Position).Magnitude <= 7.5 then
					self:TouchOnce(root, coin)
				end
			end
		end, formatError)
		if not ok then
			self:ReportError("coleta por proximidade", errorMessage)
		end
	end)
end

function Farm:StopProximityCollection()
	if self.ProximityConnection then
		pcall(function()
			self.ProximityConnection:Disconnect()
		end)
		self.ProximityConnection = nil
	end
end

function Farm:StartFarming(character, humanoid, root)
	if self.Farming and self.FarmingCharacter == character then
		return true
	end
	if not character or not humanoid or humanoid.Health <= 0 or not root or Player:GetAttribute("Alive") ~= true then
		return false
	end

	self.FarmingCharacter = character
	self.FarmingHumanoid = humanoid
	self.SavedHumanoidState = {
		PlatformStand = humanoid.PlatformStand,
		FallingDown = humanoid:GetStateEnabled(Enum.HumanoidStateType.FallingDown),
		Ragdoll = humanoid:GetStateEnabled(Enum.HumanoidStateType.Ragdoll),
	}
	self.Farming = true

	local oldGravity = root:FindFirstChild("FarmGravity")
	if oldGravity then
		oldGravity:Destroy()
	end
	local gravity = Instance.new("BodyPosition")
	gravity.Name = "FarmGravity"
	gravity.MaxForce = Vector3.new(0, math.huge, 0)
	gravity.D = 1000
	gravity.P = 10000
	gravity.Position = root.Position
	gravity.Parent = root

	root.CFrame = root.CFrame - Vector3.new(0, 2.5, 0)
	root.CFrame = root.CFrame * CFrame.Angles(math.rad(90), 0, 0)
	humanoid.PlatformStand = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	self:EnableNoclip(character)

	self.MaintenanceConnection = Services.RunService.Heartbeat:Connect(function()
		if not self.Enabled or not self.Farming or Player.Character ~= character
			or Player:GetAttribute("Alive") ~= true or not root.Parent then
			self:StopFarming()
			return
		end
		pcall(function()
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			local activeGravity = root:FindFirstChild("FarmGravity")
			if activeGravity and activeGravity:IsA("BodyPosition") then
				activeGravity.Position = root.Position
			end
			if humanoid.Parent then
				humanoid.PlatformStand = true
			end
		end)
	end)
	return true
end

function Farm:StopFarming()
	local wasFarming = self.Farming
	local character = self.FarmingCharacter
	local humanoid = self.FarmingHumanoid
	local savedState = self.SavedHumanoidState
	self.Farming = false

	if self.Tween then
		pcall(function()
			self.Tween:Cancel()
		end)
		self.Tween = nil
	end
	if self.MaintenanceConnection then
		pcall(function()
			self.MaintenanceConnection:Disconnect()
		end)
		self.MaintenanceConnection = nil
	end
	self:DisableNoclip()

	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local gravity = root:FindFirstChild("FarmGravity")
		if gravity then
			pcall(function()
				gravity:Destroy()
			end)
		end
		pcall(function()
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			if wasFarming then
				root.CFrame = root.CFrame * CFrame.Angles(math.rad(-90), 0, 0)
				root.CFrame = root.CFrame + Vector3.new(0, 2.5, 0)
			end
		end)
	end
	if humanoid and humanoid.Parent and savedState then
		pcall(function()
			humanoid.PlatformStand = savedState.PlatformStand
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, savedState.FallingDown)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, savedState.Ragdoll)
		end)
	end
	self.FarmingCharacter = nil
	self.FarmingHumanoid = nil
	self.SavedHumanoidState = nil
end

function Farm:StopMotion()
	self:StopFarming()
end

function Farm:CollectCoin(coin, character, humanoid, root, distance, container)
	if not self.Enabled or not isCollectableCoin(coin, container) then
		return
	end

	local succeeded, errorMessage = xpcall(function()
		if self.Farming and self.FarmingCharacter ~= character then
			self:StopFarming()
		end
		if not self.Farming and not self:StartFarming(character, humanoid, root) then
			return
		end

		local speed = math.max(tonumber(self.Speed) or 23, 1)
		local duration = math.max(distance / speed, 0.08)
		local target = coin.Position - Vector3.new(0, 2.5, 0)
		local targetCFrame = CFrame.new(target) * CFrame.Angles(math.rad(90), 0, 0)
		local tween = Services.TweenService:Create(root, TweenInfo.new(
			duration,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out
		), { CFrame = targetCFrame })
		self.Tween = tween
		tween:Play()

		local deadline = os.clock() + duration + 1.25
		local nextPulseAt = 0
		while self.Enabled and self.Farming and Player.Character == character
			and Player:GetAttribute("Alive") == true and humanoid.Health > 0
			and root.Parent and coin.Parent and coin:IsDescendantOf(container)
			and isCollectableCoin(coin, container) and os.clock() < deadline do

			local inMatch, activeCharacter, activeHumanoid, activeRoot, activeContainer = MatchService:GetContext()
			if not inMatch or activeCharacter ~= character or activeHumanoid ~= humanoid
				or activeRoot ~= root or activeContainer ~= container then
				break
			end

			local currentDistance = (root.Position - coin.Position).Magnitude
			if currentDistance <= 7.5 and os.clock() >= nextPulseAt then
				self:TouchOnce(root, coin)
				nextPulseAt = os.clock() + 0.18
			end
			Services.RunService.Heartbeat:Wait()
		end

		if self.Tween == tween then
			pcall(function()
				tween:Cancel()
			end)
			self.Tween = nil
		end

		if self.Enabled and root.Parent and coin.Parent and coin:IsDescendantOf(container)
			and (root.Position - coin.Position).Magnitude <= 10 then
			for _ = 1, 4 do
				if not self.Enabled or not coin.Parent or not isCollectableCoin(coin, container) then
					break
				end
				self:TouchOnce(root, coin)
				task.wait(0.06)
			end
		end
	end, formatError)

	if not succeeded then
		self:StopFarming()
		self:ReportError("coleta", errorMessage)
	end
	self.RetryAfter[coin] = os.clock() + (succeeded and 0.35 or 0.8)
end

function Farm:Start()
	if self.Enabled or Runtime.ShuttingDown then
		return
	end
	self.Enabled = true

	local thread
	thread = task.spawn(function()
		while self.Enabled and not Runtime.ShuttingDown do
			local ok, errorMessage = xpcall(function()
				local inMatch, character, humanoid, root, container = MatchService:GetContext()
				if not inMatch then
					self:StopFarming()
					task.wait(0.3)
					return
				end
				if self.BagFull then
					self:StopFarming()
					task.wait(0.3)
					return
				end

				local coin, distance = MapService:GetNearestCoin(container, root.Position, self.RetryAfter)
				if coin then
					self:CollectCoin(coin, character, humanoid, root, distance, container)
				else
					self:StopFarming()
					task.wait(0.25)
				end
			end, formatError)

			if not ok then
				self:StopFarming()
				self:ReportError("ciclo", errorMessage)
				task.wait(0.2)
			end
		end

		if self.Thread == thread then
			self.Thread = nil
		end
		self:StopFarming()
		self:StopProximityCollection()
	end)
	self.Thread = thread
	self:StartProximityCollection()
end

function Farm:Stop()
	self.Enabled = false
	local thread = self.Thread
	self.Thread = nil
	if thread then
		pcall(task.cancel, thread)
	end
	self:StopFarming()
	self:StopProximityCollection()
end

Runtime:Track(Player.CharacterAdded:Connect(function()
	Farm:StopMotion()
end))

local function bindFarmRoundEvents()
	local remotes = Services.ReplicatedStorage:FindFirstChild("Remotes")
	local gameplay = remotes and remotes:FindFirstChild("Gameplay")
	if not gameplay then
		return
	end

	local coinCollected = gameplay:FindFirstChild("CoinCollected")
	if coinCollected and coinCollected:IsA("RemoteEvent") then
		Runtime:Track(coinCollected.OnClientEvent:Connect(function(coinType, count, maximum)
			local collected = tonumber(count)
			local capacity = tonumber(maximum)
			if not collected or not capacity or capacity <= 0 then
				return
			end
			local selected = string.lower(Config.CoinFilter)
			local received = type(coinType) == "string" and string.lower(coinType) or ""
			if Config.CoinFilter ~= "Todos" and received ~= selected and received ~= "coin" then
				return
			end
			Farm.BagFull = collected >= capacity
			if Farm.BagFull then
				Farm:StopFarming()
			end
		end))
	end

	for _, eventName in ipairs({ "RoundStart", "RoundEndFade" }) do
		local event = gameplay:FindFirstChild(eventName)
		if event and event:IsA("RemoteEvent") then
			local isRoundEnd = eventName == "RoundEndFade"
			Runtime:Track(event.OnClientEvent:Connect(function()
				Farm.BagFull = false
				Farm.RetryAfter = setmetatable({}, { __mode = "k" })
				if isRoundEnd then
					Farm:StopFarming()
				end
			end))
		end
	end
end

bindFarmRoundEvents()

--// 7. MÓDULOS DE PROTEÇÃO DE SESSÃO E FÍSICA
AntiAFK = {
	Enabled = false,
	Connection = nil,
	VirtualUser = nil,
	WarnedUnavailable = false,
}

function AntiAFK:Start()
	if self.Enabled or Runtime.ShuttingDown then
		return
	end

	self.Enabled = true
	local serviceOk, virtualUser = pcall(function()
		return game:GetService("VirtualUser")
	end)
	self.VirtualUser = serviceOk and virtualUser or nil

	local connectionOk, connection = pcall(function()
		return Player.Idled:Connect(function()
			if not self.Enabled or Runtime.ShuttingDown then
				return
			end

			if not self.VirtualUser then
				if not self.WarnedUnavailable then
					self.WarnedUnavailable = true
					warn("[Chorus MM2] Anti AFK indisponível: VirtualUser não está acessível neste ambiente.")
				end
				return
			end

			local inputOk = pcall(function()
				self.VirtualUser:CaptureController()
				self.VirtualUser:ClickButton2(Vector2.new(0, 0))
			end)
			if not inputOk and not self.WarnedUnavailable then
				self.WarnedUnavailable = true
				warn("[Chorus MM2] Anti AFK não conseguiu enviar a entrada virtual.")
			end
		end)
	end)

	if connectionOk then
		self.Connection = connection
	else
		self.Enabled = false
		warn("[Chorus MM2] Não foi possível iniciar o Anti AFK: " .. tostring(connection))
	end
end

function AntiAFK:Stop()
	self.Enabled = false
	if self.Connection then
		pcall(function()
			self.Connection:Disconnect()
		end)
		self.Connection = nil
	end
	self.VirtualUser = nil
end

AntiFling = {
	Enabled = false,
	Connection = nil,
	LinearVelocityLimit = 150,
	AngularVelocityLimit = 120,
	LastWarningAt = 0,
}

local function velocityMagnitude(vector)
	if typeof(vector) ~= "Vector3" then
		return 0
	end
	local magnitude = vector.Magnitude
	if magnitude ~= magnitude or magnitude == math.huge then
		return math.huge
	end
	return magnitude
end

function AntiFling:Start()
	if self.Enabled or Runtime.ShuttingDown then
		return
	end

	self.Enabled = true
	local connectionOk, connection = pcall(function()
		return Services.RunService.Heartbeat:Connect(function()
			if not self.Enabled or Runtime.ShuttingDown then
				return
			end

			-- Reutiliza o mesmo critério de rodada usado pela coleta.
			local inMatch, _, _, root = MatchService:GetContext()
			if not inMatch or not root or not root:IsA("BasePart") then
				return
			end

			local ok, errorMessage = pcall(function()
				local linear = root.AssemblyLinearVelocity
				local angular = root.AssemblyAngularVelocity
				if velocityMagnitude(linear) >= self.LinearVelocityLimit
					or velocityMagnitude(angular) >= self.AngularVelocityLimit then
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
			end)
			if not ok then
				local now = os.clock()
				if now - self.LastWarningAt >= 5 then
					self.LastWarningAt = now
					warn("[Chorus MM2] Anti Fling não conseguiu corrigir a velocidade: " .. tostring(errorMessage))
				end
			end
		end)
	end)

	if connectionOk then
		self.Connection = connection
	else
		self.Enabled = false
		warn("[Chorus MM2] Não foi possível iniciar o Anti Fling: " .. tostring(connection))
	end
end

function AntiFling:Stop()
	self.Enabled = false
	if self.Connection then
		pcall(function()
			self.Connection:Disconnect()
		end)
		self.Connection = nil
	end
end

--// 8. MÓDULO DE JANELA E ABAS
local Window = initializeComponent("criar a janela", function()
	return OrionLib:MakeWindow({
		Name = Config.Name,
		ConfigFolder = Config.ConfigFolder,
		SaveConfig = Config.SaveConfig,
		HidePremium = Config.HidePremium,
		IntroEnabled = Config.IntroEnabled,
		CloseCallback = function()
			UI:SetOpen(false)
		end,
	})
end)
if not Window or type(Window.MakeTab) ~= "function" then
	Runtime:Shutdown()
	error("A Orion retornou uma janela incompatível.")
end

local function getSettingsIcon()
	local fallback = "rbxassetid://4483345998"
	if type(getcustomasset) ~= "function" or type(writefile) ~= "function" then
		return fallback
	end

	local path = Config.ConfigFolder .. "/settings-emoji.png"
	local fileExists = false
	if type(isfile) == "function" then
		local ok, exists = pcall(isfile, path)
		fileExists = ok and exists == true
	end

	if not fileExists then
		if type(makefolder) == "function" then
			pcall(makefolder, Config.ConfigFolder)
		end
		local downloadOk, imageData = pcall(function()
			return game:HttpGet("https://cdn.jsdelivr.net/gh/twitter/twemoji@latest/assets/72x72/2699.png")
		end)
		if downloadOk and type(imageData) == "string" then
			pcall(writefile, path, imageData)
		end
	end

	if type(isfile) == "function" then
		local existsOk, exists = pcall(isfile, path)
		if existsOk and exists then
			local assetOk, asset = pcall(getcustomasset, path)
			if assetOk and type(asset) == "string" and asset ~= "" then
				return asset
			end
		end
	end
	return fallback
end

local function makeTab(name)
	return initializeComponent("criar a aba " .. name, function()
		return Window:MakeTab({
			Name = name,
			Icon = name == "Settings" and getSettingsIcon() or "rbxassetid://4483345998",
			PremiumOnly = false,
		})
	end)
end

local SettingsTab = makeTab("Settings")
if not SettingsTab
	or type(SettingsTab.AddToggle) ~= "function"
	or type(SettingsTab.AddSlider) ~= "function"
	or type(SettingsTab.AddDropdown) ~= "function"
	or type(SettingsTab.AddLabel) ~= "function" then
	Runtime:Shutdown()
	error("A Orion retornou uma aba incompatível.")
end

-- Registry de controles. ParentFlag define a relação sem depender da ordem
-- em que os controles aparecem na lista de declarações.
local UIControlRegistry = {}
UIControlRegistry.__index = UIControlRegistry

function UIControlRegistry.new(tab)
	return setmetatable({
		Tab = tab,
		Items = {},
		ByFlag = {},
	}, UIControlRegistry)
end

function UIControlRegistry:GetItemContainer()
	local _, window = UI:FindWindow()
	if not window then
		error("A janela da Orion ainda não está disponível.", 2)
	end

	local container = window:FindFirstChild("ItemContainer")
	if not container or not container:IsA("ScrollingFrame") then
		error("Não foi possível localizar o painel da aba Settings.", 2)
	end
	return container
end

function UIControlRegistry:CreateControl(definition, order)
	local container = self:GetItemContainer()
	local existing = {}
	for _, child in ipairs(container:GetChildren()) do
		existing[child] = true
	end

	local methodName = "Add" .. definition.Type
	local addMethod = self.Tab[methodName]
	if type(addMethod) ~= "function" then
		error("A Orion não oferece " .. methodName .. ".", 2)
	end

	local control
	if definition.Type == "Label" then
		control = addMethod(self.Tab, definition.Text)
	else
		local config = table.clone(definition.Config or {})
		if definition.Flag then
			config.Flag = definition.Flag
		end
		control = addMethod(self.Tab, config)
	end

	local root
	for _, child in ipairs(container:GetChildren()) do
		if not existing[child] and child:IsA("GuiObject") then
			if root then
				error("A Orion criou mais de um elemento visual para " .. definition.Key .. ".", 2)
			end
			root = child
		end
	end
	if not root then
		error("A Orion não criou o elemento visual " .. definition.Key .. ".", 2)
	end
	root.LayoutOrder = order

	return {
		Key = definition.Key,
		Flag = definition.Flag,
		ParentFlag = definition.ParentFlag,
		Definition = definition,
		Control = control,
		LayoutRoot = root,
		Children = {},
		Order = order,
	}
end

function UIControlRegistry:WrapWithChildren(parentNode)
	local originalRoot = parentNode.LayoutRoot
	local originalParent = originalRoot.Parent
	if not originalParent then
		error("O controle pai " .. parentNode.Key .. " perdeu seu contêiner.", 2)
	end

	local group = Instance.new("Frame")
	group.Name = "ChorusGroup_" .. parentNode.Key
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.ClipsDescendants = false
	group.Size = UDim2.new(1, 0, 0, 0)
	group.LayoutOrder = originalRoot.LayoutOrder
	group.Parent = originalParent

	local groupLayout = Instance.new("UIListLayout")
	groupLayout.FillDirection = Enum.FillDirection.Vertical
	groupLayout.SortOrder = Enum.SortOrder.LayoutOrder
	groupLayout.Padding = UDim.new(0, 5)
	groupLayout.Parent = group

	originalRoot.Parent = group
	originalRoot.LayoutOrder = 1

	local childHolder = Instance.new("Frame")
	childHolder.Name = "Children"
	childHolder.BackgroundTransparency = 1
	childHolder.BorderSizePixel = 0
	childHolder.Size = UDim2.new(1, 0, 0, 0)
	childHolder.LayoutOrder = 2
	childHolder.Parent = group

	local childPadding = Instance.new("UIPadding")
	childPadding.PaddingLeft = UDim.new(0, 14)
	childPadding.Parent = childHolder

	local childLayout = Instance.new("UIListLayout")
	childLayout.FillDirection = Enum.FillDirection.Vertical
	childLayout.SortOrder = Enum.SortOrder.LayoutOrder
	childLayout.Padding = UDim.new(0, 5)
	childLayout.Parent = childHolder

	for index, childNode in ipairs(parentNode.Children) do
		local childRoot = childNode.LayoutRoot
		local childSize = childRoot.Size
		childRoot.Size = UDim2.new(1, -14, childSize.Y.Scale, childSize.Y.Offset)
		childRoot.LayoutOrder = index
		childRoot.Parent = childHolder
	end

	local function updateGroupSize()
		if not group.Parent then
			return
		end
		childHolder.Size = UDim2.new(1, 0, 0, childLayout.AbsoluteContentSize.Y)
		group.Size = UDim2.new(1, 0, 0, groupLayout.AbsoluteContentSize.Y)
	end

	Runtime:Track(childLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGroupSize))
	Runtime:Track(groupLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGroupSize))
	updateGroupSize()
	parentNode.LayoutRoot = group
end

function UIControlRegistry:Build(definitions)
	for index, definition in ipairs(definitions) do
		if type(definition.Key) ~= "string" or definition.Key == "" then
			error("Todo controle da Orion precisa de uma Key única.", 2)
		end
		if self.ByFlag[definition.Key] then
			error("Key duplicada no registro de interface: " .. definition.Key, 2)
		end
		if definition.Flag and self.ByFlag[definition.Flag] then
			error("Flag duplicada no registro de interface: " .. definition.Flag, 2)
		end

		local node = self:CreateControl(definition, index)
		self.ByFlag[definition.Key] = node
		if definition.Flag then
			self.ByFlag[definition.Flag] = node
		end
		table.insert(self.Items, node)
	end

	for _, node in ipairs(self.Items) do
		if node.ParentFlag then
			local parentNode = self.ByFlag[node.ParentFlag]
			if not parentNode then
				error("ParentFlag sem controle correspondente: " .. node.ParentFlag, 2)
			end
			node.Parent = parentNode
			table.insert(parentNode.Children, node)
		end
	end

	local function getDepth(node, visiting, memo)
		if memo[node] then
			return memo[node]
		end
		if visiting[node] then
			error("Foi encontrada uma relação de filho circular na interface.", 2)
		end
		visiting[node] = true
		local depth = node.Parent and (getDepth(node.Parent, visiting, memo) + 1) or 0
		visiting[node] = nil
		memo[node] = depth
		return depth
	end

	local memo = {}
	local groupedNodes = {}
	for _, node in ipairs(self.Items) do
		getDepth(node, {}, memo)
		if #node.Children > 0 then
			table.insert(groupedNodes, node)
		end
	end
	table.sort(groupedNodes, function(left, right)
		return memo[left] > memo[right]
	end)
	for _, node in ipairs(groupedNodes) do
		self:WrapWithChildren(node)
	end
end

local ESPOptions = {
	{ Name = "Assassino", Filter = "Murderer", Flag = "ESPMurderer" },
	{ Name = "Xerife + Hero", Filter = "Sheriff", Flag = "ESPSheriff" },
	{ Name = "Inocentes", Filter = "Innocent", Flag = "ESPInnocent" },
	{ Name = "Candy", Filter = "Candy", Flag = "ESPCandy" },
	{ Name = "Coin", Filter = "Coin", Flag = "ESPCoin" },
	{ Name = "Gun", Filter = "Gun", Flag = "ESPGun" },
}

local ControlDefinitions = {
	{
		Key = "AutoFarm",
		Flag = "AutoFarm",
		Type = "Toggle",
		Config = {
			Name = "Auto Farm",
			Default = false,
			Save = true,
			Callback = function(value)
				if value then
					Farm:Start()
				else
					Farm:Stop()
				end
			end,
		},
	},
	{
		Key = "FarmSpeed",
		Flag = "FarmSpeed",
		ParentFlag = "AutoFarm",
		Type = "Slider",
		Config = {
			Name = "Auto Farm Speed",
			Min = 5,
			Max = 40,
			Default = 23,
			Increment = 1,
			ValueName = "studs/s",
			Save = false,
			Callback = function(value)
				Farm.Speed = tonumber(value) or Farm.Speed
			end,
		},
	},
	{
		Key = "CoinFilter",
		Flag = "CoinFilter",
		ParentFlag = "AutoFarm",
		Type = "Dropdown",
		Config = {
			Name = "Tipo de moeda",
			Default = "Todos",
			Options = { "Todos", "Candy", "Coin" },
			Save = true,
			Callback = function(value)
				if value ~= "Todos" and value ~= "Candy" and value ~= "Coin" then
					return
				end
				if Config.CoinFilter == value then
					return
				end

				local restartFarm = Farm.Enabled
				Farm:Stop()
				Config.CoinFilter = value
				Farm.RetryAfter = setmetatable({}, { __mode = "k" })
				if restartFarm then
					Farm:Start()
				end
			end,
		},
	},
	{
		Key = "ESPEnabled",
		Flag = "ESPEnabled",
		Type = "Toggle",
		Config = {
			Name = "ESP",
			Default = false,
			Save = true,
			Callback = function(value)
				if value then
					ESP:Start()
				else
					ESP:Stop()
				end
			end,
		},
	},
	{
		Key = "ESPShowName",
		Flag = "ESPShowName",
		ParentFlag = "ESPEnabled",
		Type = "Toggle",
		Config = {
			Name = "Nome sobre jogadores",
			Default = true,
			Save = true,
			Callback = function(value)
				ESP.ShowName = value == true
			end,
		},
	},
	{
		Key = "ESPFilterNote",
		ParentFlag = "ESPEnabled",
		Type = "Label",
		Text = "Exibir — todos ativos por padrão",
	},
	{
		Key = "AntiAFK",
		Flag = "AntiAFK",
		Type = "Toggle",
		Config = {
			Name = "Anti AFK",
			Default = false,
			Save = true,
			Callback = function(value)
				if value then
					AntiAFK:Start()
				else
					AntiAFK:Stop()
				end
			end,
		},
	},
	{
		Key = "AntiFling",
		Flag = "AntiFling",
		Type = "Toggle",
		Config = {
			Name = "Anti Fling",
			Default = false,
			Save = true,
			Callback = function(value)
				if value then
					AntiFling:Start()
				else
					AntiFling:Stop()
				end
			end,
		},
	},
}

for _, option in ipairs(ESPOptions) do
	local currentOption = option
	table.insert(ControlDefinitions, {
		Key = currentOption.Flag,
		Flag = currentOption.Flag,
		ParentFlag = "ESPEnabled",
		Type = "Toggle",
		Config = {
			Name = currentOption.Name,
			Default = true,
			Color = ESP.Colors[currentOption.Filter],
			Save = true,
			Callback = function(value)
				ESP.Filters[currentOption.Filter] = value == true
			end,
		},
	})
end

initializeComponent("montar os controles e organizar os filhos pelas flags", function()
	local registry = UIControlRegistry.new(SettingsTab)
	registry:Build(ControlDefinitions)
	return registry
end)

initializeComponent("inicializar a Orion", function()
	return OrionLib:Init()
end)
UI:SetOpen(true)

--// 9. O Runtime registra o encerramento no ambiente compartilhado no início,
-- para que uma execução parcial também possa ser limpa ao executar novamente.

