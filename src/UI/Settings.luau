-- [[ settings ]]

return function(API)
	local Util = API.Util; local ControlRegistry = API:Require("src/UI/ControlRegistry"); local WindowContext = API.UI.Window; local UI = WindowContext.UI
	local Tabs = WindowContext.Tabs; local OrionLib = WindowContext.OrionLib; local Config = API.Config; local Player = API.Player; local Services = API.Roblox; local MatchService = API.Services.Match; local Farm = API.Features.AutoFarm; local ESP = API.Features.ESP
	local AntiAFK = API.Features.AntiAFK; local AntiFling = API.Features.AntiFling; local Noclip = API.Features.Noclip; local InfiniteJump = API.Features.InfiniteJump; local DynamicSpeed = API.Features.DynamicSpeed
	local Fly = API.Features.Fly; local Invisicam = API.Features.Invisicam; local AutoGunPickup = API.Features.AutoGunPickup

	-- PlayerTeleport
	local function notifyTeleport(content)
		if type(OrionLib.MakeNotification) == "function" then
			pcall(OrionLib.MakeNotification, OrionLib, { Name = "Teleport", Content = content, Time = 4 })
		end
	end
	local function findAliveRoleTarget(roleData, wantedRole, allowHero)
		for playerName, profile in pairs(roleData) do
			local roleMatches = type(profile) == "table"
				and (profile.Role == wantedRole or allowHero and wantedRole == "Sheriff" and profile.Role == "Hero")
			local target = type(playerName) == "string" and Services.Players:FindFirstChild(playerName) or nil
			local character = target and target.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if
				roleMatches
				and target
				and target ~= Player
				and target:GetAttribute("Alive") == true
				and profile.Dead ~= true
				and profile.Killed ~= true
				and humanoid
				and humanoid.Health > 0
				and root
				and root:IsA("BasePart")
				and character:IsDescendantOf(Services.Workspace)
			then
				return target, root
			end
		end
		return nil
	end
	local function teleportToPlayer(target, targetRoot)
		local inRound = MatchService:GetRoundContext()
		local character = Player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			not inRound
			or Player:GetAttribute("Alive") ~= true
			or not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA("BasePart")
			or not character:IsDescendantOf(Services.Workspace)
		then
			notifyTeleport("Entre em uma partida e esteja vivo para usar o teleporte.")
			return false
		end
		if not target or not targetRoot or not targetRoot:IsDescendantOf(Services.Workspace) then
			notifyTeleport("Não existe outro jogador vivo com esse papel para teleportar.")
			return false
		end
		local ok = pcall(function() character:PivotTo(targetRoot.CFrame * CFrame.new(0, 0, 3)) end)
		if not ok then notifyTeleport("Não foi possível teleportar até esse jogador."); return false end
		notifyTeleport("Teleportado até " .. target.DisplayName .. ".")
		return true
	end
	local function teleportToRole(role, allowHero)
		local inRound = MatchService:GetRoundContext()
		if not inRound then notifyTeleport("A partida ainda não começou."); return end
		local roleData = MatchService:GetPlayerData()
		if not roleData then notifyTeleport("Não foi possível consultar os papéis desta partida."); return end
		local target, targetRoot = findAliveRoleTarget(roleData, role, allowHero)
		teleportToPlayer(target, targetRoot)
	end
	local function teleportToFarthestInnocent()
		local inRound = MatchService:GetRoundContext()
		if not inRound then notifyTeleport("A partida ainda não começou."); return end
		local roleData = MatchService:GetPlayerData()
		if not roleData then notifyTeleport("Não foi possível consultar os papéis desta partida."); return end
		local _, murdererRoot = findAliveRoleTarget(roleData, "Murderer")
		if not murdererRoot then notifyTeleport("Não encontrei o Murderer vivo."); return end
		local farthestTarget, farthestRoot, farthestDistance
		for playerName, profile in pairs(roleData) do
			local target = type(playerName) == "string" and Services.Players:FindFirstChild(playerName) or nil
			if target and target ~= Player and type(profile) == "table" and profile.Role == "Innocent" then
				local character = target.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if
					target:GetAttribute("Alive") == true
					and profile.Dead ~= true
					and profile.Killed ~= true
					and humanoid
					and humanoid.Health > 0
					and root
					and root:IsA("BasePart")
					and character:IsDescendantOf(Services.Workspace)
				then
					local distance = (root.Position - murdererRoot.Position).Magnitude
					if not farthestDistance or distance > farthestDistance then
						farthestTarget, farthestRoot, farthestDistance = target, root, distance
					end
				end
			end
		end
		teleportToPlayer(farthestTarget, farthestRoot)
	end

	-- ControlGroups
	local Settings = {}
	local ControlGroups = {
		Combat = {
			{ Key = "GunPickupSection", Type = "Section", Config = { Name = "Coleta de arma" } },
			{
				Key = "AutoGunPickup",
				SectionKey = "GunPickupSection",
				Flag = "AutoGunPickup",
				Type = "Toggle",
				Config = {
					Name = "Auto Pick Up Gun (1 frame)",
					Default = true,
					Save = true,
					Callback = function(value)
						if value then AutoGunPickup:Start()
						else AutoGunPickup:Stop() end
					end,
				},
			},
			{
				Key = "GunPickupSafety",
				SectionKey = "GunPickupSection",
				ParentFlag = "AutoGunPickup",
				Flag = "GunPickupSafety",
				Type = "Toggle",
				Config = {
					Name = "Segurança contra o Murderer",
					Default = false,
					Save = true,
					Callback = function(value) AutoGunPickup:SetSafetyEnabled(value) end,
				},
			},
		},
		["Auto Farm"] = {
			{ Key = "CoinCollectionSection", Type = "Section", Config = { Name = "Coleta de moedas" } },
			{
				Key = "AutoFarm",
				SectionKey = "CoinCollectionSection",
				Flag = "AutoFarm",
				Type = "Toggle",
				Config = {
					Name = "Auto Farm",
					Default = false,
					Save = true,
					Callback = function(value)
						if value then Farm:Start()
						else Farm:Stop(true) end
					end,
				},
			},
			{
				Key = "ResetWhenBagFull",
				SectionKey = "CoinCollectionSection",
				Flag = "ResetWhenBagFull",
				ParentFlag = "AutoFarm",
				Type = "Toggle",
				Config = {
					Name = "Resetar com a bolsa cheia (Inocente)",
					Default = false,
					Save = true,
					Callback = function(value) Farm:SetResetWhenBagFull(value) end,
				},
			},
			{
				Key = "FarmSpeed",
				SectionKey = "CoinCollectionSection",
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
					Save = true,
					Callback = function(value) Farm.Speed = tonumber(value) or Farm.Speed end,
				},
			},
		},
		Visuals = {
			{ Key = "ESPSection", Type = "Section", Config = { Name = "ESP de jogadores e objetos" } },
			{
				Key = "ESPEnabled",
				SectionKey = "ESPSection",
				Flag = "ESPEnabled",
				Type = "Toggle",
				Config = {
					Name = "ESP",
					Default = true,
					Save = true,
					Callback = function(value)
						if value then ESP:Start()
						else ESP:Stop() end
					end,
				},
			},
			{
				Key = "ESPShowIdentity",
				SectionKey = "ESPSection",
				Flag = "ESPShowIdentity",
				ParentFlag = "ESPEnabled",
				Type = "Toggle",
				Config = {
					Name = "Identidades (papel / objeto)",
					Default = true,
					Save = true,
					Callback = function(value) ESP.ShowIdentity = value == true end,
				},
			},
			{
				Key = "ESPShowUsername",
				SectionKey = "ESPSection",
				Flag = "ESPShowUsername",
				ParentFlag = "ESPEnabled",
				Type = "Toggle",
				Config = {
					Name = "Nome de usuário",
					Default = true,
					Save = true,
					Callback = function(value) ESP.ShowUsername = value == true end,
				},
			},
			{
				Key = "ESPShowSelf",
				SectionKey = "ESPSection",
				Flag = "ESPShowSelf",
				ParentFlag = "ESPEnabled",
				Type = "Toggle",
				Config = {
					Name = "Mostrar você",
					Default = true,
					Save = true,
					Callback = function(value) ESP:SetShowSelf(value) end,
				},
			},
		},
		Player = {
			{ Key = "ProtectionSection", Type = "Section", Config = { Name = "Proteção" } },
			{
				Key = "AntiAFK",
				SectionKey = "ProtectionSection",
				Flag = "AntiAFK",
				Type = "Toggle",
				Config = {
					Name = "Anti AFK",
					Default = false,
					Save = true,
					Callback = function(value)
						if value then AntiAFK:Start()
						else AntiAFK:Stop() end
					end,
				},
			},
			{
				Key = "AntiFling",
				SectionKey = "ProtectionSection",
				Flag = "AntiFling",
				Type = "Toggle",
				Config = {
					Name = "Anti Fling",
					Default = false,
					Save = true,
					Callback = function(value)
						if value then AntiFling:Start()
						else AntiFling:Stop() end
					end,
				},
			},
			{ Key = "MovementSection", Type = "Section", Config = { Name = "Movimento" } },
			{
				Key = "PlayerInvisicam",
				SectionKey = "MovementSection",
				Flag = "PlayerInvisicam",
				Type = "Toggle",
				Config = {
					Name = "Invisicam",
					Default = false,
					Save = true,
					Callback = function(value) Invisicam:SetSource("Player", value == true) end,
				},
			},
			{
				Key = "DynamicSpeedEnabled",
				SectionKey = "MovementSection",
				Flag = "DynamicSpeedEnabled",
				Type = "Toggle",
				Config = {
					Name = "Speed dinâmico",
					Default = false,
					Save = true,
					Callback = function(value)
						if value then DynamicSpeed:Start()
						else DynamicSpeed:Stop() end
					end,
				},
			},
			{
				Key = "DynamicSpeedValue",
				SectionKey = "MovementSection",
				Flag = "DynamicSpeedValue",
				ParentFlag = "DynamicSpeedEnabled",
				Type = "Slider",
				Config = {
					Name = "Velocidade",
					Min = 0,
					Max = 100,
					Default = DynamicSpeed:GetCurrentSpeed(),
					Increment = 1,
					ValueName = "WalkSpeed",
					Save = true,
					Callback = function(value) DynamicSpeed:SetSpeed(value) end,
				},
			},
			{
				Key = "Noclip",
				SectionKey = "MovementSection",
				Flag = "Noclip",
				Type = "Toggle",
				Config = {
					Name = "Noclip",
					Default = false,
					Save = true,
					Callback = function(value)
						if value then Noclip:Start()
						else Noclip:Stop() end
					end,
				},
			},
			{
				Key = "InfiniteJump",
				SectionKey = "MovementSection",
				Flag = "InfiniteJump",
				Type = "Toggle",
				Config = {
					Name = "Infinite Jump",
					Default = false,
					Save = true,
					Callback = function(value)
						if value then InfiniteJump:Start()
						else InfiniteJump:Stop() end
					end,
				},
			},
			{
				Key = "Fly",
				SectionKey = "MovementSection",
				Flag = "Fly",
				Type = "Toggle",
				Config = {
					Name = "Fly",
					Default = false,
					Save = true,
					Callback = function(value)
						if value then Fly:Start()
						else Fly:Stop() end
					end,
				},
			},
			{
				Key = "FlySpeed",
				SectionKey = "MovementSection",
				Flag = "FlySpeed",
				ParentFlag = "Fly",
				Type = "Slider",
				Config = {
					Name = "Fly Speed",
					Min = 1,
					Max = 200,
					Default = 1,
					Increment = 1,
					ValueName = "x50",
					Save = true,
					Callback = function(value) Fly:SetSpeed(value) end,
				},
			},
			{ Key = "TeleportSection", Type = "Section", Config = { Name = "Teleport" } },
			{
				Key = "TeleportFarthestInnocent",
				SectionKey = "TeleportSection",
				Type = "Button",
				Config = { Name = "Teleportar no inocente mais longe do Murderer", Callback = teleportToFarthestInnocent },
			},
			{
				Key = "TeleportSheriff",
				SectionKey = "TeleportSection",
				Type = "Button",
				Config = { Name = "Teleportar no Xerife", Callback = function() teleportToRole("Sheriff", true) end },
			},
			{
				Key = "TeleportMurderer",
				SectionKey = "TeleportSection",
				Type = "Button",
				Config = { Name = "Teleportar no Murderer", Callback = function() teleportToRole("Murderer") end },
			},
			{ Key = "ActionsSection", Type = "Section", Config = { Name = "Ações" } },
			{
				Key = "ResetPlayerKill",
				SectionKey = "ActionsSection",
				Type = "Button",
				Config = {
					Name = "Reset Player (Kill)",
					Callback = function()
						local character = Player.Character
						local humanoid = character and character:FindFirstChildOfClass("Humanoid")
						if humanoid and humanoid.Health > 0 then pcall(function() humanoid.Health = 0 end) end
					end,
				},
			},
		},
		Settings = {
			{ Key = "ConfigurationSection", Type = "Section", Config = { Name = "Configuração" } },
			{
				Key = "ResetSavedConfig",
				SectionKey = "ConfigurationSection",
				Type = "Button",
				Config = {
					Name = "Resetar configurações salvas",
					Callback = function() Settings:ResetSavedConfiguration() end,
				},
			},
		},
	}

	-- ESPOptions
	local ESPOptions = {
		{ Name = "Assassino", Filter = "Murderer", Flag = "ESPMurderer", Default = true },
		{ Name = "Xerife + Hero", Filter = "Sheriff", Flag = "ESPSheriff", Default = true },
		{ Name = "Inocentes", Filter = "Innocent", Flag = "ESPInnocent", Default = true },
		{ Name = "Candy / Coin", Filter = "CandyCoin", Flag = "ESPCandyCoin", Default = false },
		{ Name = "Gun", Filter = "Gun", Flag = "ESPGun", Default = false },
	}

	for _, option in ipairs(ESPOptions) do
		local currentOption = option
		table.insert(ControlGroups.Visuals, {
			Key = currentOption.Flag,
			SectionKey = "ESPSection",
			Flag = currentOption.Flag,
			ParentFlag = "ESPEnabled",
			Type = "Toggle",
			Config = {
				Name = currentOption.Name,
				Default = currentOption.Default,
				Color = ESP.Colors[currentOption.Filter],
				Save = true,
				Callback = function(value) ESP:SetFilter(currentOption.Filter, value) end,
			},

		})
	end

	-- ConfigurationReset
	local function clearSavedConfigFile()
		local path = Config.ConfigFolder .. "/" .. tostring(game.GameId) .. ".txt"
		local exists
		if type(isfile) == "function" then
			local checkOk, result = pcall(isfile, path)
			if checkOk then exists = result == true end
		end
		if exists == false then return true end
		if type(delfile) == "function" then
			local deleteOk = pcall(delfile, path)
			if deleteOk then
				if type(isfile) ~= "function" then return true end
				local verifyOk, stillExists = pcall(isfile, path)
				if verifyOk and not stillExists then return true end
			end
		end
		if type(writefile) == "function" then
			local writeOk = pcall(writefile, path, "{}")
			if writeOk then return true end
		end
		return false
	end
	function Settings:ResetSavedConfiguration()
		local fileCleared = clearSavedConfigFile()
		local tabOrder = { "Auto Farm", "Combat", "Visuals", "Player", "Settings" }
		for _, parentPass in ipairs({ false, true }) do
			for _, tabName in ipairs(tabOrder) do
				local registry = self.Registries and self.Registries[tabName]
				for _, node in ipairs(registry and registry.Items or {}) do
					local definition = node.Definition
					local control = node.Control
					local default = definition.Config and definition.Config.Default
					if
						default ~= nil
						and control
						and type(control.Set) == "function"
						and (#node.Children > 0) == parentPass
					then
						pcall(control.Set, control, default)
					end
				end
			end
		end
		local content = fileCleared
			and "As opções foram restauradas para os valores padrão."
			or "As opções foram restauradas nesta sessão, mas o executor não permitiu limpar o arquivo salvo."
		if type(OrionLib.MakeNotification) == "function" then
			pcall(OrionLib.MakeNotification, OrionLib, { Name = "Settings", Content = content, Time = 4 })
		end
		return fileCleared
	end

	-- Initialization
	function Settings:Init()
		local registries = {}
		for _, tabName in ipairs({ "Auto Farm", "Combat", "Visuals", "Player", "Settings" }) do
			local registry = ControlRegistry.new(Tabs[tabName], function() return UI:GetItemContainer(tabName) end)
			registry:Build(ControlGroups[tabName]); registries[tabName] = registry
		end
		self.Registries = registries; API.UI.Registries = registries
		Util.InitializeComponent("inicializar a Orion", function() return OrionLib:Init() end)
		local tabOrder = { "Auto Farm", "Combat", "Visuals", "Player", "Settings" }
		for _, parentPass in ipairs({ false, true }) do
			for _, tabName in ipairs(tabOrder) do
				local registry = registries[tabName]
				for _, node in ipairs(registry.Items) do
					local definition = node.Definition
					local callback = definition.Config and definition.Config.Callback
					local isStateControl = definition.Type == "Toggle" or definition.Type == "Slider"
					if
						isStateControl
						and type(callback) == "function"
						and (#node.Children > 0) == parentPass
					then
						local value = node.Control and node.Control.Value
						local applied, applyError = pcall(callback, value)
						if not applied then warn("[Chorus MM2] Não foi possível aplicar " .. node.Key .. ": " .. tostring(applyError)) end
					end
				end
			end
		end
		UI:SetOpen(true); return registries
	end

	return Settings
end
