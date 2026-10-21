-- [[ main ]]

return function(API)

	-- Dependencies
	API.Config = API:Require("src/Core/Config"); API.Roblox = API:Require("src/Core/RobloxServices"); API.Player = API.Roblox.Players.LocalPlayer
	if not API.Player then error("Este arquivo precisa ser executado no cliente do Roblox.") end
	API.Runtime = API:Require("src/Core/Runtime"); API.Util = API:Require("src/Core/Util"); API.Services = {}; API.Features = {}
	API.UI = {}

	-- Initialization
	local ok, startupError = xpcall(function()
		local manifest = API:Require("src/Manifest")
		for _, entry in ipairs(manifest.Services) do
			API.Services[entry.Name] = API:Require(entry.Path)
		end
		for _, entry in ipairs(manifest.Features) do
			API.Features[entry.Name] = API:Require(entry.Path)
		end
		API.UI.Window = API:Require("src/UI/Window"); local settings = API:Require("src/UI/Settings"); settings:Init()
	end, API.Util.FormatError)
	if not ok then API.Runtime:Shutdown(); error("[Chorus MM2] Falha na inicialização: " .. tostring(startupError), 0) end

	return API
end
