-- [[ mapservice ]]

return function(API)
	local Config = API.Config; local Services = API.Roblox; local Runtime = API.Runtime; local CoinService = API.Services.Coin

	-- Cache
	local MapService = {
		CachedContainer = nil,
		NextScan = 0,
	}

	-- ContainerDiscovery
	local function isCoinContainer(instance)
		return instance and instance.Name == "CoinContainer" and (instance:IsA("Folder") or instance:IsA("Model"))
	end
	local function isMapCoinContainer(instance)
		local map = instance and instance.Parent; return isCoinContainer(instance) and map and map:IsA("Model") and map.Parent == Services.Workspace
	end
	Runtime:Track(Services.Workspace.DescendantAdded:Connect(function(instance)
		if isMapCoinContainer(instance) then MapService.CachedContainer = nil; MapService.NextScan = 0 end
	end))
	Runtime:Track(Services.Workspace.DescendantRemoving:Connect(function(instance)
		local cached = MapService.CachedContainer
		if cached and (cached == instance or cached:IsDescendantOf(instance)) then MapService.CachedContainer = nil; MapService.NextScan = 0 end
	end))

	-- MapScan
	function MapService:GetCoinContainer()
		local now = os.clock()
		if now < self.NextScan and isMapCoinContainer(self.CachedContainer) then return self.CachedContainer end
		self.CachedContainer = nil
		if now < self.NextScan then return nil end
		self.NextScan = now + Config.MapRefreshInterval; local fallback = nil
		for _, map in ipairs(Services.Workspace:GetChildren()) do
			if map:IsA("Model") then
				local container = map:FindFirstChild("CoinContainer")
				if isCoinContainer(container) then
					if map:GetAttribute("MapID") ~= nil then self.CachedContainer = container; return container end
					fallback = fallback or container
				end
			end
		end
		if fallback then self.CachedContainer = fallback; return fallback end
		return nil
	end

	-- NearestCoin
	function MapService:GetNearestCoin(container, position, retryAfter)
		if not container or not container.Parent then return nil, math.huge end
		local nearest, nearestDistance = nil, math.huge; local now = os.clock()
		for _, coin in ipairs(CoinService:GetCollectableParts(container)) do
			local retryAt = retryAfter[coin] or 0
			if coin.Parent and coin:IsDescendantOf(container) and retryAt <= now then
				local distance = (position - coin.Position).Magnitude
				if distance <= Config.CoinSearchRadius and distance < nearestDistance then nearest, nearestDistance = coin, distance end
			end
		end
		return nearest, nearestDistance
	end

	return MapService
end
