-- [[ rolenamedebug ]]

return function(API)
	local MatchService = API.Services.Match; local Runtime = API.Runtime; local HttpService = API.Roblox.HttpService; local FILE_PATH = "ChorusMM2Delta-RoleNames.txt"
	local POLL_INTERVAL = 1; local SeenRoles = {}; local BufferedLines = {}; local LastWarningAt = 0
	local function appendLine(line)
		if type(appendfile) == "function" then
			local ok = pcall(appendfile, FILE_PATH, line)
			if ok then return true end
		end
		if type(writefile) ~= "function" then return false end
		local existing = ""; local hasReadableFile = false
		if type(readfile) == "function" then
			local readOk, contents = pcall(readfile, FILE_PATH)
			if readOk and type(contents) == "string" then existing = contents; hasReadableFile = true end
		end
		if not hasReadableFile then existing = table.concat(BufferedLines) end
		local writeOk = pcall(writefile, FILE_PATH, existing .. line)
		if writeOk then table.insert(BufferedLines, line) end
		return writeOk
	end
	local function logRole(playerName, role)
		if type(playerName) ~= "string" or type(role) ~= "string" or role == "" or SeenRoles[role] then return end
		local encoded
		local ok = pcall(function() encoded = HttpService:JSONEncode({ Player = playerName, Role = role }) end)
		if not ok or type(encoded) ~= "string" then return end
		if appendLine(encoded .. "\n") then
			SeenRoles[role] = true; print("[Chorus Role Debug] Papel observado: " .. role)
		elseif os.clock() - LastWarningAt >= 10 then
			LastWarningAt = os.clock()
			warn(
				"[Chorus Role Debug] Não foi possível gravar "
					.. FILE_PATH
					.. "; verifique se o executor oferece appendfile ou writefile."
			)
		end
	end
	Runtime:TrackTask(task.spawn(function()
		while not Runtime.ShuttingDown do
			local ok, roleData = pcall(MatchService.GetPlayerData, MatchService)
			if ok and type(roleData) == "table" then
				for playerName, profile in pairs(roleData) do
					if type(profile) == "table" then logRole(playerName, profile.Role) end
				end
			end
			task.wait(POLL_INTERVAL)
		end
	end))

	return { FilePath = FILE_PATH }
end
