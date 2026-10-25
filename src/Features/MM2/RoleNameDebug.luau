-- [[ rolenamedebug ]]

return function(API)
	local MatchService = API.Services.Match; local Runtime = API.Runtime; local FILE_PATH = "ChorusMM2Delta-RoleNames.txt"; local POLL_INTERVAL = 1
	local SeenRoles = {}; local LastWarningAt = 0; local Dirty = false
	local function loadExistingRoles()
		if type(readfile) ~= "function" then return end
		local readOk, contents = pcall(readfile, FILE_PATH)
		if not readOk or type(contents) ~= "string" then return end
		for line in contents:gmatch("[^\r\n]+") do
			local role = line
			if line:sub(1, 1) == "{" then
				local decodeOk, record = pcall(function() return API.Roblox.HttpService:JSONDecode(line) end)
				role = decodeOk and type(record) == "table" and record.Role or nil
			end
			if type(role) == "string" and role ~= "" then SeenRoles[role] = true end
		end
	end
	local function saveRoles()
		if type(writefile) ~= "function" then return false end
		local roles = {}
		for role in pairs(SeenRoles) do
			table.insert(roles, role)
		end
		table.sort(roles); local contents = #roles > 0 and (table.concat(roles, "\n") .. "\n") or ""; local writeOk = pcall(writefile, FILE_PATH, contents)
		if writeOk then Dirty = false end
		return writeOk
	end
	local function appendRole(role)
		if type(appendfile) ~= "function" then return false end
		return pcall(appendfile, FILE_PATH, role .. "\n")
	end
	loadExistingRoles()
	if next(SeenRoles) ~= nil then Dirty = not saveRoles() end
	local function logRole(role)
		if type(role) ~= "string" or role == "" or SeenRoles[role] then return end
		SeenRoles[role] = true
		if type(writefile) == "function" then Dirty = not saveRoles()
		elseif appendRole(role) then Dirty = false
		else Dirty = true end
		if Dirty and os.clock() - LastWarningAt >= 10 then
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
				for _, profile in pairs(roleData) do
					if type(profile) == "table" then logRole(profile.Role) end
				end
			end
			if Dirty and type(writefile) == "function" then saveRoles() end
			task.wait(POLL_INTERVAL)
		end
	end))

	return { FilePath = FILE_PATH }
end
