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
			{ Name = "DynamicSpeed", Path = "src/Features/DynamicSpeed" },
			{ Name = "Noclip", Path = "src/Features/Noclip" },
			{ Name = "Invisicam", Path = "src/Features/Invisicam" },
			{ Name = "AutoFarm", Path = "src/Features/AutoFarm" },
			{ Name = "AutoGunPickup", Path = "src/Features/AutoGunPickup" },
			{ Name = "InfiniteJump", Path = "src/Features/InfiniteJump" },
			{ Name = "Fly", Path = "src/Features/Fly" },
			{ Name = "AntiAFK", Path = "src/Features/AntiAFK" },
			{ Name = "AntiFling", Path = "src/Features/AntiFling" },
		},

	}
end
