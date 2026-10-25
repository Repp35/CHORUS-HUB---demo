-- [[ mapservice ]]

return function(API)
	local Config = API.Config; local Services = API.Roblox; local Runtime = API.Runtime; local CoinService = API.Services.Coin
	local Util = API.Util

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
		if not coin or not coin:IsA("BasePart") then return end
		local ok, position = pcall(function() return coin.Position end)
		if ok and Util.IsFiniteVector3(position) then MapService.CachedCoinPositions[coin] = position end
	end
	local function replaceCoinPositionCache(container)
		if MapService.CachedCoinContainer == container then return MapService.CachedCoinPositions end
		disconnect(MapService.CoinChildAddedConnection); disconnect(MapService.CoinChildRemovedConnection); MapService.CoinChildAddedConnection = nil; MapService.CoinChildRemovedConnection = nil
		MapService.CachedCoinContainer = container; table.clear(MapService.CachedCoinPositions)
		if not container then return MapService.CachedCoinPositions end
		for _, coin in ipairs(container:GetChildren()) do
			cacheCoinPosition(coin)
		end
		MapService.CoinChildAddedConnection = container.ChildAdded:Connect(cacheCoinPosition)
		MapService.CoinChildRemovedConnection = container.ChildRemoved:Connect(
			function(coin) MapService.CachedCoinPositions[coin] = nil end
		)
		return MapService.CachedCoinPositions
	end
	function MapService:GetCoinPositions(container) return replaceCoinPositionCache(container) end
	Runtime:OnShutdown(function()
		disconnect(MapService.CoinChildAddedConnection); disconnect(MapService.CoinChildRemovedConnection)
	end)

	-- ContainerDiscovery
	local function isCoinContainer(instance)
		return instance and instance.Name == "CoinContainer" and (instance:IsA("Folder") or instance:IsA("Model"))
	end
	local function isMapCoinContainer(instance)
		local map = instance and instance.Parent; return isCoinContainer(instance)
			and map
			and map:IsA("Model")
			and map.Parent == Services.Workspace
			and map:GetAttribute("MapID") ~= nil
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
		self.NextScan = now + Config.MapRefreshInterval
		for _, map in ipairs(Services.Workspace:GetChildren()) do
			if map:IsA("Model") and map:GetAttribute("MapID") ~= nil then
				local container = map:FindFirstChild("CoinContainer")
				if isCoinContainer(container) then self.CachedContainer = container; return container end
			end
		end
		return nil
	end

	-- NearestCoin
	function MapService:GetNearestCoin(container, position, retryAfter, passedCoins, filter)
		if not container or not container.Parent then return nil, math.huge end
		if not Util.IsFiniteVector3(position) then return nil, math.huge end
		retryAfter = retryAfter or {}; local nearest, nearestDistance, nearestPosition = nil, math.huge, nil; local now = os.clock()
		for coin, coinPosition in pairs(self:GetCoinPositions(container)) do
			local retryAt = retryAfter[coin] or 0
			if not coin.Parent or not coin:IsDescendantOf(container) then
				self.CachedCoinPositions[coin] = nil
			elseif
				retryAt <= now
				and not (passedCoins and passedCoins[coin])
				and CoinService:IsCollectable(coin, container)
			then
				local ok, currentPosition = pcall(function() return coin.Position end)
				if ok and Util.IsFiniteVector3(currentPosition) then
					if (currentPosition - coinPosition).Magnitude > 0.1 then coinPosition = currentPosition; self.CachedCoinPositions[coin] = currentPosition end
					if filter and not filter(coin, coinPosition) then continue end
					local distance = (position - coinPosition).Magnitude
					if distance == distance and distance < math.huge and distance < nearestDistance then nearest, nearestDistance, nearestPosition = coin, distance, coinPosition end
				else
					self.CachedCoinPositions[coin] = nil
				end
			end
		end
		return nearest, nearestDistance, nearestPosition
	end

	return MapService
end
