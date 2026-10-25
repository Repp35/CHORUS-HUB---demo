-- [[ settings ]]

return function(API)
	local Util = API.Util; local Runtime = API.Runtime; local ControlRegistry = API:Require("src/UI/ControlRegistry"); local WindowContext = API.UI.Window
	local UI = WindowContext.UI; local Tabs = WindowContext.Tabs; local OrionLib = WindowContext.OrionLib; local Config = API.Config
	local Player = API.Player; local Services = API.Roblox; local Farm = API.Features.AutoFarm; local ESP = API.Features.ESP
	local Importance = ControlRegistry.Importance; local AntiAFK = API.Features.AntiAFK; local AntiFling = API.Features.AntiFling; local Noclip = API.Features.Noclip
	local InfiniteJump = API.Features.InfiniteJump; local DynamicSpeed = API.Features.DynamicSpeed; local Fly = API.Features.Fly; local Invisicam = API.Features.Invisicam
	local AutoGunPickup = API.Features.AutoGunPickup; local ShootMurder = API.Features.ShootMurder; local Gravity = API.Features.Gravity; local MapTools = API.Features.MapTools
	local Alerts = API.Features.Alerts; local selectedPlayerName = "None"

	-- ControlGroups
	local Settings = {}
	local ControlGroups = {
		Combat = {
			{ Key = "ShootMurderSection", Type = "Section", Config = { Name = "Shoot Murder" } },
			{
				Key = "ManualShootMurder",
				Flag = "ManualShootMurder",
				SectionKey = "ShootMurderSection",
				Importance = Importance.Normal,
				Type = "Toggle",
				Config = {
					Name = "Manual Shoot Murder",
					Default = false,
					Save = true,
					Callback = function(value) ShootMurder:SetManualEnabled(value) end,
				},
			},
			{
				Key = "ManualShootMurderAccuracy",
				Flag = "ManualShootMurderAccuracy",
				ParentFlag = "ManualShootMurder",
				SectionKey = "ShootMurderSection",
				Type = "Slider",
				Config = {
					Name = "Manual Accuracy",
					Min = 0,
					Max = 100,
					Default = 100,
					Increment = 5,
					ValueName = "%",
					Save = true,
					Callback = function(value) ShootMurder:SetManualAccuracy(value) end,
				},
			},
			{
				Key = "AutoShootMurder",
				Flag = "AutoShootMurder",
				SectionKey = "ShootMurderSection",
				Importance = Importance.High,
				Type = "Toggle",
				Config = {
					Name = "Auto Shoot Murder",
					Default = false,
					Save = true,
					Callback = function(value) ShootMurder:SetAutoEnabled(value) end,
				},
			},
			{
				Key = "AutoShootMurderAccuracy",
				Flag = "AutoShootMurderAccuracy",
				ParentFlag = "AutoShootMurder",
				SectionKey = "ShootMurderSection",
				Type = "Slider",
				Config = {
					Name = "Auto Accuracy",
					Min = 0,
					Max = 100,
					Default = 100,
					Increment = 5,
					ValueName = "%",
					Save = true,
					Callback = function(value) ShootMurder:SetAutoAccuracy(value) end,
				},
			},
			{
				Key = "LegitSheriff",
				Flag = "LegitSheriff",
				SectionKey = "ShootMurderSection",
				Importance = Importance.Normal,
				Type = "Toggle",
				Config = {
					Name = "Legit",
					Description = "Aguarda o assassino sacar a faca.",
					Default = false,
					Save = true,
					Callback = function(value) ShootMurder:SetWaitForKnife(value) end,
				},
			},
			{
				Key = "ShootMurderOffscreen",
				Flag = "ShootMurderOffscreen",
				SectionKey = "ShootMurderSection",
				Importance = Importance.Normal,
				Type = "Toggle",
				Config = {
					Name = "Silent Aim (acerta fora da tela)",
					Default = true,
					Save = true,
					Callback = function(value) ShootMurder:SetAllowOffscreen(value) end,
				},
			},
			{ Key = "GunPickupSection", Type = "Section", Config = { Name = "Coleta de arma" } },
			{
				Key = "AutoGunPickup",
				Importance = Importance.High,
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
					Name = "Murderer Safety (evita coleta sob ameaça do assassino)",
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
				Importance = Importance.High,
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
				Key = "AvoidMurdererCoins",
				SectionKey = "CoinCollectionSection",
				Flag = "AvoidMurdererCoins",
				ParentFlag = "AutoFarm",
				Type = "Toggle",
				Config = {
					Name = "Avoid Coins Near Murderer",
					Default = false,
					Save = true,
					Callback = function(value) Farm.AvoidMurderer = value == true end,
				},
			},
			{
				Key = "ResetWhenBagFull",
				SectionKey = "CoinCollectionSection",
				Flag = "ResetWhenBagFull",
				ParentFlag = "AutoFarm",
				Type = "Toggle",
				Config = {
					Name = "Reset When Bag Is Full (Innocent)",
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
					Max = 100,
					Default = 40,
					Increment = 1,
					ValueName = "studs/s",
					Save = true,
					Callback = function(value) Farm.Speed = tonumber(value) or Farm.Speed end,
				},
			},
		},
		Map = {
			{ Key = "MapTravelSection", Type = "Section", Config = { Name = "Teleporte e jogadores" } },
			{
				Key = "TeleportToMap",
				SectionKey = "MapTravelSection",
				Importance = Importance.High,
				Type = "Button",
				Config = { Name = "Teleport to Map", Callback = function() MapTools:TeleportToMap() end },
			},
			{
				Key = "TeleportToMurderer",
				SectionKey = "MapTravelSection",
				Type = "Button",
				Config = {
					Name = "Teleport to Murderer",
					Callback = function() MapTools:TeleportToRole("Murderer") end,
				},
			},
			{
				Key = "TeleportToGunHolder",
				SectionKey = "MapTravelSection",
				Type = "Button",
				Config = {
					Name = "Teleport to Gun Holder",
					Callback = function() MapTools:TeleportToRole("GunHolder") end,
				},
			},
			{
				Key = "MapTargetPlayer",
				Flag = "MapTargetPlayer",
				SectionKey = "MapTravelSection",
				Type = "Dropdown",
				Config = {
					Name = "Player",
					Options = MapTools:GetPlayerOptions(),
					Default = "None",
					Callback = function(value) selectedPlayerName = value == "Nenhum" and "None" or value end,
				},
			},
			{
				Key = "TeleportToPlayer",
				SectionKey = "MapTravelSection",
				Type = "Button",
				Config = {
					Name = "Teleport to Player",
					Callback = function()
						MapTools:TeleportToPlayer(Services.Players:FindFirstChild(selectedPlayerName))
					end,
				},
			},
			{
				Key = "WalkToPlayer",
				SectionKey = "MapTravelSection",
				Type = "Button",
				Config = {
					Name = "Walk to Player",
					Callback = function() MapTools:WalkToPlayer(Services.Players:FindFirstChild(selectedPlayerName)) end,
				},
			},
			{ Key = "MapVotingSection", Type = "Section", Config = { Name = "Votação de mapas" } },
			{
				Key = "FavoriteMap",
				Flag = "FavoriteMap",
				SectionKey = "MapVotingSection",
				Type = "Dropdown",
				Config = {
					Name = "Favorite Map to Vote",
					Options = MapTools:GetFavoriteMapOptions(),
					Default = "None",
					Save = true,
					Callback = function(value) MapTools:SetFavoriteMaps(value) end,
				},
			},
		},
		Visuals = {
			{ Key = "ESPSection", Type = "Section", Config = { Name = "ESP de jogadores e objetos" } },
			{
				Key = "ESPEnabled",
				Importance = Importance.High,
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
					Name = "Identity (papel/objeto)",
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
					Name = "Username",
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
					Name = "Show Self",
					Default = true,
					Save = true,
					Callback = function(value) ESP:SetShowSelf(value) end,
				},
			},
			{
				Key = "ESPShowDistance",
				Flag = "ESPShowDistance",
				ParentFlag = "ESPEnabled",
				SectionKey = "ESPSection",
				Type = "Toggle",
				Config = {
					Name = "Show Distance",
					Default = true,
					Save = true,
					Callback = function(value) ESP.ShowDistance = value == true end,
				},
			},
		},
		Player = {
			{ Key = "ProtectionSection", Type = "Section", Config = { Name = "Proteção" } },
			{
				Key = "AntiAFK",
				Importance = Importance.High,
				SectionKey = "ProtectionSection",
				Flag = "AntiAFK",
				Type = "Toggle",
				Config = {
					Name = "Anti AFK",
					Default = true,
					Save = true,
					Callback = function(value)
						if value then AntiAFK:Start()
						else AntiAFK:Stop() end
					end,
				},
			},
			{
				Key = "AntiFling",
				Importance = Importance.High,
				SectionKey = "ProtectionSection",
				Flag = "AntiFling",
				Type = "Toggle",
				Config = {
					Name = "Anti Fling",
					Default = true,
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
				Importance = Importance.High,
				SectionKey = "MovementSection",
				Flag = "PlayerInvisicam",
				Type = "Toggle",
				Config = {
					Name = "Invisicam",
					Default = true,
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
					Name = "Dynamic Speed",
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
					Name = "Speed",
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
			{ Key = "GravitySection", Type = "Section", Config = { Name = "Gravidade" } },
			{
				Key = "GravityEnabled",
				Flag = "GravityEnabled",
				SectionKey = "GravitySection",
				Type = "Toggle",
				Config = {
					Name = "Custom Gravity",
					Default = false,
					Save = true,
					Callback = function(value) Gravity:SetEnabled(value) end,
				},
			},
			{
				Key = "GravityValue",
				Flag = "GravityValue",
				ParentFlag = "GravityEnabled",
				SectionKey = "GravitySection",
				Type = "Slider",
				Config = {
					Name = "Gravity",
					Min = 0,
					Max = 400,
					Default = Gravity.DefaultValue,
					Increment = 1,
					ValueName = "studs/s²",
					Save = true,
					Callback = function(value) Gravity:SetValue(value) end,
				},
			},
			{ Key = "ActionsSection", Type = "Section", Config = { Name = "Ações" } },
			{
				Key = "ResetPlayerKill",
				Importance = Importance.Low,
				SectionKey = "ActionsSection",
				Type = "Button",
				Config = {
					Name = "Reset Player (Kill)",
					Callback = function()
						local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid")
						if humanoid and humanoid.Health > 0 then pcall(function() humanoid.Health = 0 end) end
					end,
				},
			},
		},
		Avisos = {
			{ Key = "RoundAlertsSection", Type = "Section", Config = { Name = "Avisos da partida" } },
			{
				Key = "AlertRoleAndMurderer",
				Flag = "AlertRoleAndMurderer",
				SectionKey = "RoundAlertsSection",
				Importance = Importance.High,
				Type = "Toggle",
				Config = {
					Name = "My Role and the Murderer",
					Default = true,
					Save = true,
					Callback = function(value) Alerts:SetRoleAndMurdererEnabled(value) end,
				},
			},
			{
				Key = "AlertGunDropped",
				Flag = "AlertGunDropped",
				SectionKey = "RoundAlertsSection",
				Importance = Importance.High,
				Type = "Toggle",
				Config = {
					Name = "Notify When the Gun Drops",
					Default = true,
					Save = true,
					Callback = function(value) Alerts:SetGunDroppedEnabled(value) end,
				},
			},
		},
		Settings = {
			{ Key = "ScriptInfoSection", Type = "Section", Config = { Name = "Informações do script" } },
			{ Key = "ScriptInfoName", SectionKey = "ScriptInfoSection", Type = "Label", Text = Config.ScriptInfo.Name },
			{
				Key = "ScriptInfoAuthor",
				SectionKey = "ScriptInfoSection",
				Type = "Label",
				Text = "Author: " .. Config.ScriptInfo.Author,
			},
			{ Key = "ConfigurationSection", Type = "Section", Config = { Name = "Configuração" } },
			{
				Key = "ResetSavedConfig",
				SectionKey = "ConfigurationSection",
				Type = "Button",
				Config = {
					Name = "Reset Saved Configuration",
					Callback = function() Settings:ResetSavedConfiguration() end,
				},
			},
		},
	}

	-- ESPOptions
	local ESPOptions = {
		{ Name = "Murderer", Filter = "Murderer", Flag = "ESPMurderer", Default = true },
		{ Name = "Sheriff + Hero", Filter = "Sheriff", Flag = "ESPSheriff", Default = true },
		{ Name = "Innocents", Filter = "Innocent", Flag = "ESPInnocent", Default = true },
		{ Name = "Candy / Coin", Filter = "CandyCoin", Flag = "ESPCandyCoin", Default = false },
		{ Name = "Dropped Gun", Filter = "Gun", Flag = "ESPGun", Default = true },
	}

	for _, option in ipairs(ESPOptions) do
		local currentOption = option
		table.insert(ControlGroups.Visuals, {
			Key = currentOption.Flag,
			Importance = currentOption.Filter == "Murderer" and Importance.High or Importance.Normal,
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
		local fileCleared = clearSavedConfigFile(); local tabOrder = { "Auto Farm", "Combat", "Map", "Visuals", "Player", "Avisos", "Settings" }
		for _, parentPass in ipairs({ false, true }) do
			for _, tabName in ipairs(tabOrder) do
				local registry = self.Registries and self.Registries[tabName]
				for _, node in ipairs(registry and registry.Items or {}) do
					local definition = node.Definition; local control = node.Control; local default = definition.Config and definition.Config.Default
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
		local content = fileCleared and "As opções foram restauradas para os valores padrão."
			or "As opções foram restauradas nesta sessão, mas o executor não permitiu limpar o arquivo salvo."
		if type(OrionLib.MakeNotification) == "function" then pcall(OrionLib.MakeNotification, OrionLib, { Name = "Settings", Content = content, Time = 4 }) end
		return fileCleared
	end

	-- Initialization
	function Settings:Init()
		local registries = {}; local tabOrder = { "Auto Farm", "Combat", "Map", "Visuals", "Player", "Avisos", "Settings" }
		for _, tabName in ipairs(tabOrder) do
			local registry = ControlRegistry.new(Tabs[tabName], function() return UI:GetItemContainer(tabName) end)
			registry:Build(ControlGroups[tabName]); registries[tabName] = registry
		end
		self.Registries = registries; API.UI.Registries = registries
		Util.InitializeComponent("inicializar a Orion", function() return OrionLib:Init() end)
		local function refreshDropdown(tabName, key, options, getCurrent, fallback)
			local registry = registries[tabName]; local node = registry and registry.ByKey[key]; local control = node and node.Control
			if
				not control
				or type(control.Options) ~= "table"
				or type(control.Refresh) ~= "function"
				or type(control.Set) ~= "function"
			then
				return
			end
			local same = #control.Options == #options
			if same then
				for index, option in ipairs(options) do
					if control.Options[index] ~= option then same = false; break end
				end
			end
			if same then return end
			local selected = getCurrent(); control:Refresh(options, true)
			if not table.find(options, selected) then selected = fallback end
			control:Set(selected)
		end
		local function refreshPlayerOptions()
			local options = MapTools:GetPlayerOptions()
			refreshDropdown("Map", "MapTargetPlayer", options, function() return selectedPlayerName end, "None")
		end
		Runtime:Track(Services.Players.PlayerAdded:Connect(refreshPlayerOptions))
		Runtime:Track(Services.Players.PlayerRemoving:Connect(function(target)
			if selectedPlayerName == target.Name then selectedPlayerName = "None" end
			refreshPlayerOptions()
		end))
		local optionsThread
		optionsThread = task.spawn(function()
			while not Runtime.ShuttingDown do
				local options = MapTools:GetFavoriteMapOptions()
				refreshDropdown(
					"Map",
					"FavoriteMap",
					options,
					function() return MapTools.FavoriteMaps[1] or "None" end,
					"None"
				)
				task.wait(3)
			end
		end)
		Runtime:TrackTask(optionsThread)
		for _, parentPass in ipairs({ false, true }) do
			for _, tabName in ipairs(tabOrder) do
				local registry = registries[tabName]
				for _, node in ipairs(registry.Items) do
					local definition = node.Definition; local callback = definition.Config and definition.Config.Callback
					local isStateControl = definition.Type == "Toggle" or definition.Type == "Slider"
					if isStateControl and type(callback) == "function" and (#node.Children > 0) == parentPass then
						local value = node.Control and node.Control.Value; local applied, applyError = pcall(callback, value)
						if not applied then warn("[Chorus MM2] Não foi possível aplicar " .. node.Key .. ": " .. tostring(applyError)) end
					end
				end
			end
		end
		UI:SetOpen(true); return registries
	end

	return Settings
end
