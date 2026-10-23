-- [[ mapservice ]]

return function(API)
	local Config = API.Config; local Services = API.Roblox; local Runtime = API.Runtime; local CoinService = API.Services.Coin

	-- Cache
	local MapService = {
		CachedContainer = nil,
		NextScan = 0,
		CachedCoinContainer = nil,
		CachedCoinPositions = {},
		CoinChildAddedConnection = nil,
		CoinChildRemovedConnection = nil,
	}
	local function disconnect(connection)
		if connection then pcall(function() connection:Disconnect() end) end
	end
	local function cacheCoinPosition(coin)
		if coin and coin:IsA("BasePart") then MapService.CachedCoinPositions[coin] = coin.Position end
	end
	local function replaceCoinPositionCache(container)
		if MapService.CachedCoinContainer == container then return MapService.CachedCoinPositions end
		disconnect(MapService.CoinChildAddedConnection); disconnect(MapService.CoinChildRemovedConnection)
		MapService.CoinChildAddedConnection = nil; MapService.CoinChildRemovedConnection = nil
		MapService.CachedCoinContainer = container; table.clear(MapService.CachedCoinPositions)
		if not container then return MapService.CachedCoinPositions end
		for _, coin in ipairs(container:GetChildren()) do cacheCoinPosition(coin) end
		MapService.CoinChildAddedConnection = container.ChildAdded:Connect(cacheCoinPosition)
		MapService.CoinChildRemovedConnection = container.ChildRemoved:Connect(function(coin)
			MapService.CachedCoinPositions[coin] = nil
		end)
		return MapService.CachedCoinPositions
	end
	function MapService:GetCoinPositions(container)
		return replaceCoinPositionCache(container)
	end
	Runtime:OnShutdown(function()
		disconnect(MapService.CoinChildAddedConnection); disconnect(MapService.CoinChildRemovedConnection)
	end)

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
		local nearest, nearestDistance, nearestPosition = nil, math.huge, nil; local now = os.clock()
		for coin, coinPosition in pairs(self:GetCoinPositions(container)) do
			local retryAt = retryAfter[coin] or 0
			if not coin.Parent or not coin:IsDescendantOf(container) then
				self.CachedCoinPositions[coin] = nil
			elseif retryAt <= now and CoinService:IsCollectable(coin, container) then
				local currentPosition = coin.Position
				if (currentPosition - coinPosition).Magnitude > 0.1 then
					coinPosition = currentPosition
					self.CachedCoinPositions[coin] = currentPosition
				end
				local distance = (position - coinPosition).Magnitude
				if distance <= Config.CoinSearchRadius and distance < nearestDistance then
					nearest, nearestDistance, nearestPosition = coin, distance, coinPosition
				end
			end
		end
		return nearest, nearestDistance, nearestPosition
	end

	return MapService
end
