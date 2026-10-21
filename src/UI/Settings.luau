-- [[ settings ]]

return function(API)
	local Runtime = API.Runtime; local Util = API.Util; local ControlRegistry = API:Require("src/UI/ControlRegistry"); local WindowContext = API.UI.Window
	local UI = WindowContext.UI; local Tabs = WindowContext.Tabs; local OrionLib = WindowContext.OrionLib; local Farm = API.Features.AutoFarm
	local ESP = API.Features.ESP; local AntiAFK = API.Features.AntiAFK; local AntiFling = API.Features.AntiFling

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
					Save = false,
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
		},
	}

	-- ESPOptions
	local ESPOptions = {
		{ Name = "Assassino", Filter = "Murderer", Flag = "ESPMurderer" },
		{ Name = "Xerife + Hero", Filter = "Sheriff", Flag = "ESPSheriff" },
		{ Name = "Inocentes", Filter = "Innocent", Flag = "ESPInnocent" },
		{ Name = "Candy / Coin", Filter = "CandyCoin", Flag = "ESPCandyCoin" },
		{ Name = "Gun", Filter = "Gun", Flag = "ESPGun" },
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
				Default = true,
				Color = ESP.Colors[currentOption.Filter],
				Save = true,
				Callback = function(value) ESP.Filters[currentOption.Filter] = value == true end,
			},

		})
	end

	-- Initialization
	function Settings:Init()
		local registries = {}
		for _, tabName in ipairs({ "Auto Farm", "Visuals", "Player" }) do
			local registry = ControlRegistry.new(Tabs[tabName], function() return UI:GetItemContainer(tabName) end)
			registry:Build(ControlGroups[tabName]); registries[tabName] = registry
		end
		API.UI.Registries = registries
		Util.InitializeComponent("inicializar a Orion", function() return OrionLib:Init() end)
		UI:SetOpen(true); return registries
	end

	return Settings
end
