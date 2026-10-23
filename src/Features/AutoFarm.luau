-- [[ autofarm ]]

return function(API)
	local Services = API.Roblox; local Player = API.Player; local Runtime = API.Runtime; local Util = API.Util
	local CoinService = API.Services.Coin; local MapService = API.Services.Map; local MatchService = API.Services.Match; local Noclip = API.Features.Noclip
	local Invisicam = API.Features.Invisicam
	local TOUCH_DISTANCE = 3.5
	local TOUCH_RETRY_DELAY = 0.75
	local PASS_THROUGH_DISTANCE = 1.5

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
		ResetWhenBagFull = false,
		BagResetTriggered = false,
		BagResetThread = nil,
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
	function Farm:ResetCharacterForFullBag()
		if not self.Enabled or not self.BagFull or not self.ResetWhenBagFull or self.BagResetTriggered or Runtime.ShuttingDown then return false end
		if MatchService:GetLocalRole() ~= "Innocent" then return false end
		local inMatch, character, humanoid = MatchService:GetContext()
		if not inMatch or not character or not humanoid then return false end
		self.BagResetTriggered = true; self:StopFarming()
		local thread
		thread = task.spawn(function()
			task.wait(0.5)
			local canReset = self.Enabled
				and self.BagFull
				and self.ResetWhenBagFull
				and not Runtime.ShuttingDown
				and Player.Character == character
				and humanoid.Parent ~= nil
				and humanoid.Health > 0
				and Player:GetAttribute("Alive") == true
			if canReset and MatchService:GetLocalRole() == "Innocent" then
				local resetOk, resetError = pcall(function() humanoid.Health = 0 end)
				if not resetOk then
					self.BagResetTriggered = false
					self:ReportError("reset da bolsa cheia", resetError)
				end
			else
				self.BagResetTriggered = false
			end
			if self.BagResetThread == thread then self.BagResetThread = nil end
		end)
		self.BagResetThread = thread
		return true
	end
	function Farm:SetResetWhenBagFull(enabled)
		self.ResetWhenBagFull = enabled == true
		if not self.ResetWhenBagFull then
			self:CancelBagReset()
		elseif self.Enabled and self.BagFull then
			self:ResetCharacterForFullBag()
		end
	end
	function Farm:CancelBagReset()
		local thread = self.BagResetThread
		self.BagResetThread = nil
		if thread then
			pcall(task.cancel, thread)
			self.BagResetTriggered = false
		end
	end
	function Farm:ResetBagState()
		self:CancelBagReset()
		self.BagFull = false
		self.BagResetTriggered = false
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
		if not touchFunction then return false end
		local enterOk = pcall(touchFunction, root, coin, 0); local exitOk = pcall(touchFunction, root, coin, 1)
		return enterOk and exitOk
	end
	function Farm:TouchCoinInRange(root, coin, container, coinPosition)
		if
			not self.Enabled
			or not self.Farming
			or not root
			or not root.Parent
			or not CoinService:IsCollectable(coin, container)
		then
			return false
		end
		coinPosition = coinPosition or MapService:GetCoinPositions(container)[coin]
		if not coinPosition or (root.Position - coinPosition).Magnitude > TOUCH_DISTANCE then return false end
		local now = os.clock()
		if (self.RetryAfter[coin] or 0) <= now then
			self:TouchOnce(root, coin)
			self.RetryAfter[coin] = now + TOUCH_RETRY_DELAY
		end
		return true
	end

	-- ProximityCollection
	function Farm:StartProximityCollection()
		if self.ProximityConnection then return end
		self.ProximityConnection = Services.RunService.Heartbeat:Connect(function()
			if not self.Enabled or not self.Farming or self.BagFull then return end
			local now = os.clock()
			if now - self.LastProximitySweepAt < 0.04 then return end
			self.LastProximitySweepAt = now
			local ok, errorMessage = xpcall(function()
				local inMatch, _, _, root, container = MatchService:GetContext()
				if not inMatch then return end
				for coin, coinPosition in pairs(MapService:GetCoinPositions(container)) do
					self:TouchCoinInRange(root, coin, container, coinPosition)
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
	function Farm:CollectCoin(coin, character, humanoid, root, container, coinPosition)
		if not self.Enabled or not CoinService:IsCollectable(coin, container) then return end
		local succeeded, errorMessage = xpcall(function()
			if self.Farming and self.FarmingCharacter ~= character then self:StopFarming() end
			if not self.Farming and not self:StartFarming(character, humanoid, root) then return end
			coinPosition = coinPosition or MapService:GetCoinPositions(container)[coin] or coin.Position
			local speed = math.max(tonumber(self.Speed) or 23, 1); local target = coinPosition - Vector3.new(0, 2.5, 0)
			local approach = target - root.Position; local approachDistance = approach.Magnitude
			if approachDistance > 0.001 then target += approach.Unit * PASS_THROUGH_DISTANCE end
			local duration = math.max((target - root.Position).Magnitude / speed, 1 / 60)
			local targetCFrame = CFrame.new(target) * CFrame.Angles(math.rad(90), 0, 0)
			local tween = Services.TweenService:Create(
				root,
				TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
				{ CFrame = targetCFrame }
			)
			self.Tween = tween; tween:Play(); local deadline = os.clock() + duration + 0.5
			while
				self.Enabled
				and self.Farming
				and Player.Character == character
				and Player:GetAttribute("Alive") == true
				and humanoid.Health > 0
				and root.Parent
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
				self:TouchCoinInRange(root, coin, container, coinPosition)
				if tween.PlaybackState ~= Enum.PlaybackState.Playing then break end
				Services.RunService.Heartbeat:Wait()
			end
			if self.Tween == tween then
				pcall(function() tween:Cancel() end)
				self.Tween = nil
			end
			if
				self.Enabled
				and self.Farming
				and root.Parent
				and coin.Parent
				and coin:IsDescendantOf(container)
				and CoinService:IsCollectable(coin, container)
			then
				if not self:TouchCoinInRange(root, coin, container, coinPosition) then self.RetryAfter[coin] = os.clock() + TOUCH_RETRY_DELAY end
			end
		end, Util.FormatError)
		if not succeeded then
			self:StopFarming(); self.RetryAfter[coin] = os.clock() + 0.8
			self:ReportError("coleta", errorMessage)
		end
	end

	-- Lifecycle
	function Farm:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true; Invisicam:SetSource("AutoFarm", true)
		local thread
		thread = task.spawn(function()
			while self.Enabled and not Runtime.ShuttingDown do
				local ok, errorMessage = xpcall(function()
					local inMatch, character, humanoid, root, container = MatchService:GetContext()
					if not inMatch then self:StopFarming(); task.wait(0.3); return end
					if self.BagFull then self:StopFarming(); task.wait(0.3); return end
					local coin, _, coinPosition = MapService:GetNearestCoin(container, root.Position, self.RetryAfter)
					if coin then self:CollectCoin(coin, character, humanoid, root, container, coinPosition)
					else self:StopFarming(); task.wait(0.05) end
				end, Util.FormatError)
				if not ok then self:StopFarming(); self:ReportError("ciclo", errorMessage); task.wait(0.2) end
			end
			if self.Thread == thread then self.Thread = nil end
			self:StopFarming(); self:StopProximityCollection()
		end)
		self.Thread = thread; self:StartProximityCollection()
		if self.BagFull then self:ResetCharacterForFullBag() end
	end
	function Farm:Stop()
		self.Enabled = false; local thread = self.Thread; self.Thread = nil
		if thread then pcall(task.cancel, thread) end
		self:CancelBagReset(); self:StopFarming(); self:StopProximityCollection(); Invisicam:SetSource("AutoFarm", false)
	end
	Runtime:Track(Player.CharacterAdded:Connect(function() Farm:StopMotion() end))

	-- RoundEvents
	local function bindFarmRoundEvents()
		local remotes = Services.ReplicatedStorage:FindFirstChild("Remotes"); local gameplay = remotes and remotes:FindFirstChild("Gameplay")
		if not gameplay then return end
		local coinCollected = gameplay:FindFirstChild("CoinCollected")
		if coinCollected and coinCollected:IsA("RemoteEvent") then
			Runtime:Track(coinCollected.OnClientEvent:Connect(function(coinType, count, maximum)
				if not CoinService:NormalizeKind(coinType) then return end
				local collected = tonumber(count); local capacity = tonumber(maximum)
				if not collected or not capacity or capacity <= 0 then return end
				if collected >= capacity then
					Farm.BagFull = true
					Farm:StopFarming()
					Farm:ResetCharacterForFullBag()
				end
			end))
		end
		for _, eventName in ipairs({ "RoundStart", "CoinsStarted", "RoundEndFade" }) do
			local event = gameplay:FindFirstChild(eventName)
			if event and event:IsA("RemoteEvent") then
				local isRoundEnd = eventName == "RoundEndFade"
				Runtime:Track(event.OnClientEvent:Connect(function()
					Farm:ResetBagState(); Farm.RetryAfter = setmetatable({}, { __mode = "k" })
					if isRoundEnd then Farm:StopFarming() end
				end))
			end
		end
	end
	bindFarmRoundEvents()
	Runtime:OnShutdown(function() Farm:Stop() end)

	return Farm
end
