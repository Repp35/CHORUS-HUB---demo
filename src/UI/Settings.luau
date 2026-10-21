-- [[ settings ]]

return function(API)
	local Util = API.Util; local ControlRegistry = API:Require("src/UI/ControlRegistry"); local WindowContext = API.UI.Window; local UI = WindowContext.UI
	local Tabs = WindowContext.Tabs; local OrionLib = WindowContext.OrionLib; local Config = API.Config; local Farm = API.Features.AutoFarm; local ESP = API.Features.ESP
	local AntiAFK = API.Features.AntiAFK; local AntiFling = API.Features.AntiFling; local Noclip = API.Features.Noclip; local InfiniteJump = API.Features.InfiniteJump
	local Fly = API.Features.Fly; local Invisicam = API.Features.Invisicam

	-- ControlGroups
	local Settings = {}
	local ControlGroups = {
		["Auto Farm"] = {
			{
				Key = "AutoFarm",
				Flag = "AutoFarm",
				Type = "Toggle",
				Config = {
					Name = "Auto Farm",
					Default = false,
					Save = true,
					Callback = function(value)
						if value then Farm:Start()
						else Farm:Stop() end
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
					Save = true,
					Callback = function(value) Farm.Speed = tonumber(value) or Farm.Speed end,
				},
			},
		},
		Visuals = {
			{
				Key = "ESPEnabled",
				Flag = "ESPEnabled",
				Type = "Toggle",
				Config = {
					Name = "ESP",
					Default = false,
					Save = true,
					Callback = function(value)
						if value then ESP:Start()
						else ESP:Stop() end
					end,
				},
			},
			{
				Key = "ESPShowIdentity",
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
				Flag = "ESPShowUsername",
				ParentFlag = "ESPEnabled",
				Type = "Toggle",
				Config = {
					Name = "Nome de usuário",
					Default = false,
					Save = true,
					Callback = function(value) ESP.ShowUsername = value == true end,
				},
			},
		},
		Player = {
			{
				Key = "AntiAFK",
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
			{
				Key = "PlayerInvisicam",
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
				Key = "Noclip",
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
		},
		Settings = {
			{
				Key = "ResetSavedConfig",
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
		for _, registry in pairs(self.Registries or {}) do
			for _, node in ipairs(registry.Items) do
				local definition = node.Definition
				local control = node.Control
				local default = definition.Config and definition.Config.Default
				if default ~= nil and control and type(control.Set) == "function" then
					pcall(control.Set, control, default)
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
		for _, tabName in ipairs({ "Auto Farm", "Visuals", "Player", "Settings" }) do
			local registry = ControlRegistry.new(Tabs[tabName], function() return UI:GetItemContainer(tabName) end)
			registry:Build(ControlGroups[tabName]); registries[tabName] = registry
		end
		self.Registries = registries; API.UI.Registries = registries
		Util.InitializeComponent("inicializar a Orion", function() return OrionLib:Init() end)
		UI:SetOpen(true); return registries
	end

	return Settings
end
