-- [[ manifest ]]

-- ModuleManifest
return function()

	return {
		GroupOrder = { "MM2", "Universal" },
		Groups = {
			MM2 = {
				Services = {
					{ Name = "Coin", Path = "src/MM2/Services/CoinService" },
					{ Name = "Map", Path = "src/MM2/Services/MapService" },
					{ Name = "Match", Path = "src/MM2/Services/MatchService" },
				},
				Features = {
					{ Name = "ESP", Path = "src/MM2/Features/ESP" },
					{ Name = "AutoFarm", Path = "src/MM2/Features/AutoFarm" },
					{ Name = "AutoGunPickup", Path = "src/MM2/Features/AutoGunPickup" },
				},
			},
			Universal = {
				Features = {
					{ Name = "DynamicSpeed", Path = "src/Universal/Features/DynamicSpeed" },
					{ Name = "Noclip", Path = "src/Universal/Features/Noclip" },
					{ Name = "Invisicam", Path = "src/Universal/Features/Invisicam" },
					{ Name = "InfiniteJump", Path = "src/Universal/Features/InfiniteJump" },
					{ Name = "Fly", Path = "src/Universal/Features/Fly" },
					{ Name = "AntiAFK", Path = "src/Universal/Features/AntiAFK" },
					{ Name = "AntiFling", Path = "src/Universal/Features/AntiFling" },
				},
			},
		},
	}
end
