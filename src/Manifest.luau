-- [[ manifest ]]

-- ModuleManifest
return function()

	return {
		Services = {
			{ Name = "Coin", Path = "src/Services/CoinService" },
			{ Name = "Map", Path = "src/Services/MapService" },
			{ Name = "Match", Path = "src/Services/MatchService" },
		},

		Features = {
			{ Name = "ESP", Path = "src/Features/ESP" },
			{ Name = "AutoFarm", Path = "src/Features/AutoFarm" },
			{ Name = "AntiAFK", Path = "src/Features/AntiAFK" },
			{ Name = "AntiFling", Path = "src/Features/AntiFling" },
		},

	}
end
