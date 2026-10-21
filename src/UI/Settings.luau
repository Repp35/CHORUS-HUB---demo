-- [[ settings ]]

return function(API)
	local Runtime = API.Runtime; local Util = API.Util; local ControlRegistry = API:Require("src/UI/ControlRegistry"); local ESPOptionsModal = API:Require("src/UI/ESPOptionsModal")
	local WindowContext = API.UI.Window; local UI = WindowContext.UI; local Tabs = WindowContext.Tabs; local OrionLib = WindowContext.OrionLib
	local Farm = API.Features.AutoFarm; local ESP = API.Features.ESP; local AntiAFK = API.Features.AntiAFK; local AntiFling = API.Features.AntiFling
	local openESPOptions
	local updateESPSelectionText

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
				Key = "ESPOptionsButton",
				Flag = "ESPOptionsButton",
				ParentFlag = "ESPEnabled",
				Type = "Button",
				Config = {
					Name = "Selecionar opções do ESP",
					Callback = function()
						if openESPOptions then openESPOptions() end
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
						if updateESPSelectionText then updateESPSelectionText() end
					end,
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
				Callback = function(value)
					ESP.Filters[currentOption.Filter] = value == true
					if updateESPSelectionText then updateESPSelectionText() end
				end,
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
		local visualRegistry = registries.Visuals; local selectionFlags = { "ESPShowName", "ESPMurderer", "ESPSheriff", "ESPInnocent", "ESPCandyCoin", "ESPGun" }; local optionRoots = {}
		for _, flag in ipairs(selectionFlags) do
			local node = visualRegistry.ByFlag[flag]
			if not node then error("O seletor do ESP não encontrou o controle " .. flag .. ".", 2) end
			table.insert(optionRoots, node.LayoutRoot)
		end
		local selector = Util.InitializeComponent(
			"criar o seletor múltiplo do ESP",
			function() return ESPOptionsModal.new(UI, optionRoots) end
		)
		openESPOptions = function() selector:Open() end
		local selectorButton = visualRegistry.ByFlag.ESPOptionsButton.Control
		updateESPSelectionText = function()
			local selected = ESP.ShowName and 1 or 0
			for _, option in ipairs(ESPOptions) do
				if ESP.Filters[option.Filter] then selected += 1 end
			end
			selectorButton:Set(string.format("Selecionar opções do ESP (%d/%d)", selected, #selectionFlags))
		end
		updateESPSelectionText()
		API.UI.ESPOptionsModal = selector
		API.UI.Registries = registries
		Util.InitializeComponent("inicializar a Orion", function() return OrionLib:Init() end)
		UI:SetOpen(true); return registries
	end

	return Settings
end
