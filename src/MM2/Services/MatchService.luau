-- [[ matchservice ]]

return function(API)
	local Player = API.Player; local Services = API.Roblox; local MatchService = {}

	-- MatchContext
	function MatchService:GetContext()
		local inRound, _, container = self:GetRoundContext()
		if not inRound or not container or not container.Parent then return false end
		local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or humanoid.Health <= 0 or not root then return false end
		if Player:GetAttribute("Alive") ~= true then return false end
		return true, character, humanoid, root, container
	end
	function MatchService:GetRoundContext()
		for _, map in ipairs(Services.Workspace:GetChildren()) do
			if map:IsA("Model") and map:GetAttribute("MapID") ~= nil then
				local container = map:FindFirstChild("CoinContainer")
				if not container or not (container:IsA("Folder") or container:IsA("Model")) then
					container = nil
				end
				return true, map, container
			end
		end
		return false
	end
	function MatchService:GetPlayerData()
		local remote = Services.ReplicatedStorage:FindFirstChild("GetPlayerData", true)
		if not remote or not remote:IsA("RemoteFunction") then return nil end
		local ok, data = pcall(function() return remote:InvokeServer() end)
		return ok and type(data) == "table" and data or nil
	end
	function MatchService:GetLocalRole()
		local data = self:GetPlayerData()
		if not data then return nil end
		local profile = data[Player.Name]
		return type(profile) == "table" and type(profile.Role) == "string" and profile.Role or nil
	end

	return MatchService
end
