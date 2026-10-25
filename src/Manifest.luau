-- [[ manifest ]]

-- ModuleManifest
return function()

	return {
		GroupOrder = { "MM2", "Universal" },
		Groups = {
			MM2 = {
				Services = {
					{ Name = "Coin", Path = "src/Services/MM2/CoinService" },
					{ Name = "Map", Path = "src/Services/MM2/MapService" },
					{ Name = "Match", Path = "src/Services/MM2/MatchService" },
				},
				Features = {
					{ Name = "ESP", Path = "src/Features/MM2/ESP" },
					{ Name = "AutoFarm", Path = "src/Features/MM2/AutoFarm" },
					{ Name = "Alerts", Path = "src/Features/MM2/Alerts" },
					{ Name = "MapTools", Path = "src/Features/MM2/MapTools" },
					{ Name = "AutoGunPickup", Path = "src/Features/MM2/AutoGunPickup" },
					{ Name = "ShootMurder", Path = "src/Features/MM2/ShootMurder" },
					{ Name = "RoleNameDebug", Path = "Testes/RoleNameDebug" },
				},
			},
			Universal = {
				Features = {
					{ Name = "DynamicSpeed", Path = "src/Features/Universal/DynamicSpeed" },
					{ Name = "Gravity", Path = "src/Features/Universal/Gravity" },
					{ Name = "Noclip", Path = "src/Features/Universal/Noclip" },
					{ Name = "Invisicam", Path = "src/Features/Universal/Invisicam" },
					{ Name = "InfiniteJump", Path = "src/Features/Universal/InfiniteJump" },
					{ Name = "Fly", Path = "src/Features/Universal/Fly" },
					{ Name = "AntiAFK", Path = "src/Features/Universal/AntiAFK" },
					{ Name = "AntiFling", Path = "src/Features/Universal/AntiFling" },
				},
			},
		},

	}
end
