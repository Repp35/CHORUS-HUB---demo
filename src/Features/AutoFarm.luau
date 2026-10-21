-- [[ autofarm ]]

return function(API)
	local Services = API.Roblox; local Player = API.Player; local Runtime = API.Runtime; local Util = API.Util
	local CoinService = API.Services.Coin; local MapService = API.Services.Map; local MatchService = API.Services.Match; local Noclip = API.Features.Noclip

	-- State
	local Farm = {
		Enabled = false,
		Farming = false,
		Speed = 23,
		Thread = nil,
		Tween = nil,
		ProximityConnection = nil,
		LastProximitySweepAt = 0,
		BagFull = false,
		MaintenanceConnection = nil,
		NoclipLease = false,
		FarmingCharacter = nil,
		FarmingHumanoid = nil,
		SavedHumanoidState = nil,
		RetryAfter = setmetatable({}, { __mode = "k" }),
		LastErrorAt = 0,
	}

	-- TouchSupport
	local function getTouchFunction()
		local ok, touchFunction = pcall(function() return firetouchinterest end)
		if ok and type(touchFunction) == "function" then return touchFunction end
		return nil
	end

	-- Diagnostics
	function Farm:ReportError(context, errorMessage)
		local now = os.clock()
		if now - self.LastErrorAt < 5 then return end
		self.LastErrorAt = now; warn("[Chorus MM2] Auto Farm recuperando após erro em " .. context .. ": " .. tostring(errorMessage))
	end

	-- Noclip
	function Farm:EnableNoclip()
		if self.NoclipLease then return end
		self.NoclipLease = Noclip:Acquire(self)
	end
	function Farm:DisableNoclip()
		if not self.NoclipLease then return end
		self.NoclipLease = false; Noclip:Release(self)
	end

	-- CoinCollection
	function Farm:TouchOnce(root, coin)
		if not self.Enabled or not root or not root.Parent or not coin or not coin.Parent then return end
		local touchFunction = getTouchFunction()
		if not touchFunction then return end
		pcall(touchFunction, root, coin, 0); pcall(touchFunction, root, coin, 1)
	end

	-- ProximityCollection
	function Farm:StartProximityCollection()
		if self.ProximityConnection then return end
		self.ProximityConnection = Services.RunService.Heartbeat:Connect(function()
			if not self.Enabled or not self.Farming or self.BagFull then return end
			local now = os.clock()
			if now - self.LastProximitySweepAt < 0.1 then return end
			self.LastProximitySweepAt = now
			local ok, errorMessage = xpcall(function()
				local inMatch, _, _, root, container = MatchService:GetContext()
				if not inMatch then return end
				for _, coin in ipairs(CoinService:GetCollectableParts(container)) do
					if (root.Position - coin.Position).Magnitude <= 7.5 then self:TouchOnce(root, coin) end
				end
			end, Util.FormatError)
			if not ok then self:ReportError("coleta por proximidade", errorMessage) end
		end)
	end
	function Farm:StopProximityCollection()
		if self.ProximityConnection then
			pcall(function() self.ProximityConnection:Disconnect() end)
			self.ProximityConnection = nil
		end
	end

	-- FarmMovement
	function Farm:StartFarming(character, humanoid, root)
		if self.Farming and self.FarmingCharacter == character then return true end
		if
			not character
			or not humanoid
			or humanoid.Health <= 0
			or not root
			or Player:GetAttribute("Alive") ~= true
		then
			return false
		end
		self.FarmingCharacter = character; self.FarmingHumanoid = humanoid
		self.SavedHumanoidState = {
			PlatformStand = humanoid.PlatformStand,
			FallingDown = humanoid:GetStateEnabled(Enum.HumanoidStateType.FallingDown),
			Ragdoll = humanoid:GetStateEnabled(Enum.HumanoidStateType.Ragdoll),
		}
		self.Farming = true; local oldGravity = root:FindFirstChild("FarmGravity")
		if oldGravity then oldGravity:Destroy() end
		local gravity = Instance.new("BodyPosition"); gravity.Name = "FarmGravity"; gravity.MaxForce = Vector3.new(0, math.huge, 0); gravity.D = 1000
		gravity.P = 10000; gravity.Position = root.Position; gravity.Parent = root; root.CFrame = root.CFrame - Vector3.new(0, 2.5, 0)
		root.CFrame = root.CFrame * CFrame.Angles(math.rad(90), 0, 0); humanoid.PlatformStand = true; humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false); self:EnableNoclip()
		self.MaintenanceConnection = Services.RunService.Heartbeat:Connect(function()
			if
				not self.Enabled
				or not self.Farming
				or Player.Character ~= character
				or Player:GetAttribute("Alive") ~= true
				or not root.Parent
			then
				self:StopFarming(); return
			end
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero; local activeGravity = root:FindFirstChild("FarmGravity")
				if activeGravity and activeGravity:IsA("BodyPosition") then activeGravity.Position = root.Position end
				if humanoid.Parent then humanoid.PlatformStand = true end
			end)
		end)
		return true
	end

	-- MovementCleanup
	function Farm:StopFarming()
		local wasFarming = self.Farming; local character = self.FarmingCharacter; local humanoid = self.FarmingHumanoid; local savedState = self.SavedHumanoidState
		self.Farming = false
		if self.Tween then
			pcall(function() self.Tween:Cancel() end)
			self.Tween = nil
		end
		if self.MaintenanceConnection then
			pcall(function() self.MaintenanceConnection:Disconnect() end)
			self.MaintenanceConnection = nil
		end
		self:DisableNoclip(); local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local gravity = root:FindFirstChild("FarmGravity")
			if gravity then pcall(function() gravity:Destroy() end) end
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
				if wasFarming then root.CFrame = root.CFrame * CFrame.Angles(math.rad(-90), 0, 0); root.CFrame = root.CFrame + Vector3.new(0, 2.5, 0) end
			end)
		end
		if humanoid and humanoid.Parent and savedState then
			pcall(function()
				humanoid.PlatformStand = savedState.PlatformStand
				humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, savedState.FallingDown); humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, savedState.Ragdoll)
			end)
		end
		self.FarmingCharacter = nil; self.FarmingHumanoid = nil; self.SavedHumanoidState = nil
	end
	function Farm:StopMotion() self:StopFarming() end

	-- CoinCollectionLoop
	function Farm:CollectCoin(coin, character, humanoid, root, distance, container)
		if not self.Enabled or not CoinService:IsCollectable(coin, container) then return end
		local succeeded, errorMessage = xpcall(function()
			if self.Farming and self.FarmingCharacter ~= character then self:StopFarming() end
			if not self.Farming and not self:StartFarming(character, humanoid, root) then return end
			local speed = math.max(tonumber(self.Speed) or 23, 1); local duration = math.max(distance / speed, 0.08); local target = coin.Position - Vector3.new(0, 2.5, 0)
			local targetCFrame = CFrame.new(target) * CFrame.Angles(math.rad(90), 0, 0)
			local tween = Services.TweenService:Create(
				root,
				TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
				{ CFrame = targetCFrame }
			)
			self.Tween = tween; tween:Play(); local deadline = os.clock() + duration + 1.25; local nextPulseAt = 0
			while
				self.Enabled
				and self.Farming
				and Player.Character == character
				and Player:GetAttribute("Alive") == true
				and humanoid.Health > 0
				and root.Parent
				and coin.Parent
				and coin:IsDescendantOf(container)
				and CoinService:IsCollectable(coin, container)
				and os.clock() < deadline
			do
				local inMatch, activeCharacter, activeHumanoid, activeRoot, activeContainer = MatchService:GetContext()
				if
					not inMatch
					or activeCharacter ~= character
					or activeHumanoid ~= humanoid
					or activeRoot ~= root
					or activeContainer ~= container
				then
					break
				end
				local currentDistance = (root.Position - coin.Position).Magnitude
				if currentDistance <= 7.5 and os.clock() >= nextPulseAt then self:TouchOnce(root, coin); nextPulseAt = os.clock() + 0.18 end
				Services.RunService.Heartbeat:Wait()
			end
			if self.Tween == tween then
				pcall(function() tween:Cancel() end)
				self.Tween = nil
			end
			if
				self.Enabled
				and root.Parent
				and coin.Parent
				and coin:IsDescendantOf(container)
				and (root.Position - coin.Position).Magnitude <= 10
			then
				for _ = 1, 4 do
					if not self.Enabled or not coin.Parent or not CoinService:IsCollectable(coin, container) then break end
					self:TouchOnce(root, coin); task.wait(0.06)
				end
			end
		end, Util.FormatError)
		if not succeeded then self:StopFarming(); self:ReportError("coleta", errorMessage) end
		self.RetryAfter[coin] = os.clock() + (succeeded and 0.35 or 0.8)
	end

	-- Lifecycle
	function Farm:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true
		local thread
		thread = task.spawn(function()
			while self.Enabled and not Runtime.ShuttingDown do
				local ok, errorMessage = xpcall(function()
					local inMatch, character, humanoid, root, container = MatchService:GetContext()
					if not inMatch then self:StopFarming(); task.wait(0.3); return end
					if self.BagFull then self:StopFarming(); task.wait(0.3); return end
					local coin, distance = MapService:GetNearestCoin(container, root.Position, self.RetryAfter)
					if coin then self:CollectCoin(coin, character, humanoid, root, distance, container)
					else self:StopFarming(); task.wait(0.25) end
				end, Util.FormatError)
				if not ok then self:StopFarming(); self:ReportError("ciclo", errorMessage); task.wait(0.2) end
			end
			if self.Thread == thread then self.Thread = nil end
			self:StopFarming(); self:StopProximityCollection()
		end)
		self.Thread = thread; self:StartProximityCollection()
	end
	function Farm:Stop()
		self.Enabled = false; local thread = self.Thread; self.Thread = nil
		if thread then pcall(task.cancel, thread) end
		self:StopFarming(); self:StopProximityCollection()
	end
	Runtime:Track(Player.CharacterAdded:Connect(function() Farm:StopMotion() end))

	-- RoundEvents
	local function bindFarmRoundEvents()
		local remotes = Services.ReplicatedStorage:FindFirstChild("Remotes"); local gameplay = remotes and remotes:FindFirstChild("Gameplay")
		if not gameplay then return end
		local coinCollected = gameplay:FindFirstChild("CoinCollected")
		if coinCollected and coinCollected:IsA("RemoteEvent") then
			Runtime:Track(coinCollected.OnClientEvent:Connect(function(_, count, maximum)
				local collected = tonumber(count); local capacity = tonumber(maximum)
				if not collected or not capacity or capacity <= 0 then return end
				Farm.BagFull = collected >= capacity
				if Farm.BagFull then Farm:StopFarming() end
			end))
		end
		for _, eventName in ipairs({ "RoundStart", "RoundEndFade" }) do
			local event = gameplay:FindFirstChild(eventName)
			if event and event:IsA("RemoteEvent") then
				local isRoundEnd = eventName == "RoundEndFade"
				Runtime:Track(event.OnClientEvent:Connect(function()
					Farm.BagFull = false; Farm.RetryAfter = setmetatable({}, { __mode = "k" })
					if isRoundEnd then Farm:StopFarming() end
				end))
			end
		end
	end
	bindFarmRoundEvents()
	Runtime:OnShutdown(function() Farm:Stop() end)

	return Farm
end
