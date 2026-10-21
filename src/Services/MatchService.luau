-- [[ matchservice ]]

return function(API)
	local Player = API.Player; local MapService = API.Services.Map; local MatchService = {}

	-- MatchContext
	function MatchService:GetContext()
		local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or humanoid.Health <= 0 or not root then return false end
		if Player:GetAttribute("Alive") ~= true then return false end
		local container = MapService:GetCoinContainer()
		if not container then return false end
		return true, character, humanoid, root, container
	end

	return MatchService
end
