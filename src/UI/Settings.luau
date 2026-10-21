-- [[ settings ]]

return function(API)
	local Config = API.Config; local Runtime = API.Runtime; local Util = API.Util; local ControlRegistry = API:Require("src/UI/ControlRegistry")
	local Window = API.UI.Window; local UI = Window.UI; local SettingsTab = Window.SettingsTab; local OrionLib = Window.OrionLib
	local Farm = API.Features.AutoFarm; local ESP = API.Features.ESP; local AntiAFK = API.Features.AntiAFK; local AntiFling = API.Features.AntiFling

	-- Definitions
	local Settings = {}

	-- ESPOptions
	local ESPOptions = {
		{ Name = "Assassino", Filter = "Murderer", Flag = "ESPMurderer" },
		{ Name = "Xerife + Hero", Filter = "Sheriff", Flag = "ESPSheriff" },
		{ Name = "Inocentes", Filter = "Innocent", Flag = "ESPInnocent" },
		{ Name = "Candy", Filter = "Candy", Flag = "ESPCandy" },
		{ Name = "Coin", Filter = "Coin", Flag = "ESPCoin" },
		{ Name = "Gun", Filter = "Gun", Flag = "ESPGun" },
	}

	-- ControlDefinitions
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
				Save = false,
				Callback = function(value) Farm.Speed = tonumber(value) or Farm.Speed end,
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
					if value ~= "Todos" and value ~= "Candy" and value ~= "Coin" then return end
					if Config.CoinFilter == value then return end
					local restartFarm = Farm.Enabled; Farm:Stop(); Config.CoinFilter = value; Farm.RetryAfter = setmetatable({}, { __mode = "k" })
					if restartFarm then Farm:Start() end
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
					if value then ESP:Start()
					else ESP:Stop() end
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
				Callback = function(value) ESP.ShowName = value == true end,
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
	}

	-- DynamicESPControls
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
				Callback = function(value) ESP.Filters[currentOption.Filter] = value == true end,
			},

		})
	end

	-- Initialization
	function Settings:Init()
		local registry = ControlRegistry.new(SettingsTab, function() return UI:GetItemContainer("Settings") end)
		registry:Build(ControlDefinitions); API.UI.Registry = registry
		Util.InitializeComponent("inicializar a Orion", function() return OrionLib:Init() end)
		UI:SetOpen(true); return registry
	end

	return Settings
end
