-- [[ autofarm ]]

return function(API)
	local Services = API.Roblox; local Player = API.Player; local Runtime = API.Runtime; local Util = API.Util
	local Workspace = Services.Workspace; local CoinService = API.Services.Coin; local MapService = API.Services.Map; local MatchService = API.Services.Match
	local TOUCH_DISTANCE = 3.5; local PASS_THROUGH_DISTANCE = 1.5; local ROLE_REFRESH_INTERVAL = 0.5; local AVOID_MURDERER_COIN_DISTANCE = 45
	local AVOID_MURDERER_PLAYER_DISTANCE = 40
	local NO_ROLE_VALUES =
		{ unknown = true, none = true, norole = true, sempapel = true, unassigned = true, waiting = true, lobby = true }

	-- State
	local Farm = {
		Enabled = false,
		Farming = false,
		Speed = 40,
		Thread = nil,
		Tween = nil,
		ProximityConnection = nil,
		BagFull = false,
		ResetWhenBagFull = false,
		AvoidMurderer = false,
		BagResetTriggered = false,
		BagResetThread = nil,
		MaintenanceConnection = nil,
		NoclipLease = false,
		FarmingCharacter = nil,
		FarmingHumanoid = nil,
		SavedHumanoidState = nil,
		ActivationCharacter = nil,
		ActivationRoot = nil,
		ActivationCFrame = nil,
		PassedCoins = setmetatable({}, { __mode = "k" }),
		CollectionSerial = 0,
		PassedContainer = nil,
		LastErrorAt = 0,
		RoleData = nil,
		NextRoleRefreshAt = 0,
		ThreatRoot = nil,
		ThreatRefreshAt = 0,
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
	function Farm:GetRoleData(force)
		local now = os.clock()
		if not force and now < self.NextRoleRefreshAt then return self.RoleData end
		self.NextRoleRefreshAt = now + ROLE_REFRESH_INTERVAL; local ok, roleData = pcall(MatchService.GetPlayerData, MatchService); self.RoleData = ok and type(roleData) == "table" and roleData or nil
		return self.RoleData
	end
	function Farm:HasAssignedRole()
		local roleData = self:GetRoleData(); local profile = roleData and roleData[Player.Name]; local role = type(profile) == "table" and profile.Role or nil
		if type(role) ~= "string" or profile.Dead == true or profile.Killed == true then return false end
		local normalizedRole = string.lower(role):gsub("[%s_%-]", ""); return normalizedRole ~= "" and not NO_ROLE_VALUES[normalizedRole]
	end
	function Farm:GetMurdererRoot()
		if not self.AvoidMurderer then return nil end
		local now = os.clock()
		if now < self.ThreatRefreshAt then return self.ThreatRoot and self.ThreatRoot.Parent and self.ThreatRoot or nil end
		self.ThreatRefreshAt = now + 0.2; self.ThreatRoot = nil; local roleData = self:GetRoleData(); local localProfile = roleData and roleData[Player.Name]
		if type(localProfile) == "table" and localProfile.Role == "Murderer" then return nil end
		if type(roleData) ~= "table" then return nil end
		for name, profile in pairs(roleData) do
			if
				name ~= Player.Name
				and type(profile) == "table"
				and profile.Role == "Murderer"
				and profile.Dead ~= true
				and profile.Killed ~= true
			then
				local target = Services.Players:FindFirstChild(name); local character = target and target.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if
					target
					and target:GetAttribute("Alive") == true
					and humanoid
					and humanoid.Health > 0
					and root
					and root:IsA("BasePart")
				then
					self.ThreatRoot = root; return root
				end
			end
		end
		return nil
	end
	function Farm:IsNearMurderer(position, threshold)
		if not self.AvoidMurderer or not Util.IsFiniteVector3(position) then return false end
		local threatRoot = self:GetMurdererRoot(); return threatRoot ~= nil
			and (threatRoot.Position - position).Magnitude < (threshold or AVOID_MURDERER_COIN_DISTANCE)
	end
	function Farm:GetActiveContext()
		if Player:GetAttribute("Alive") ~= true then self.RoleData = nil; self.NextRoleRefreshAt = 0; return false end
		local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			not character
			or not character:IsDescendantOf(Workspace)
			or not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA("BasePart")
			or not self:HasAssignedRole()
		then
			return false
		end
		local container = MapService:GetCoinContainer()
		if not container or not container.Parent then return false end
		return true, character, humanoid, root, container
	end
	function Farm:ResetCharacterForFullBag()
		if
			not self.Enabled
			or not self.BagFull
			or not self.ResetWhenBagFull
			or self.BagResetTriggered
			or Runtime.ShuttingDown
		then
			return false
		end
		if MatchService:GetLocalRole() ~= "Innocent" then return false end
		local inMatch, character, humanoid = MatchService:GetContext()
		if not inMatch or not character or not humanoid then return false end
		self.BagResetTriggered = true; self:StopFarming()
		local thread
		thread = task.spawn(function()
			task.wait(0.5); local canReset = self.Enabled
				and self.BagFull
				and self.ResetWhenBagFull
				and not Runtime.ShuttingDown
				and Player.Character == character
				and humanoid.Parent ~= nil
				and humanoid.Health > 0
				and Player:GetAttribute("Alive") == true
			if canReset and MatchService:GetLocalRole() == "Innocent" then
				local resetOk, resetError = pcall(function() humanoid.Health = 0 end)
				if not resetOk then self.BagResetTriggered = false; self:ReportError("reset da bolsa cheia", resetError) end
			else
				self.BagResetTriggered = false
			end
			if self.BagResetThread == thread then self.BagResetThread = nil end
		end)
		self.BagResetThread = thread; return true
	end
	function Farm:SetResetWhenBagFull(enabled)
		self.ResetWhenBagFull = enabled == true
		if not self.ResetWhenBagFull then self:CancelBagReset()
		elseif self.Enabled and self.BagFull then self:ResetCharacterForFullBag() end
	end
	function Farm:CancelBagReset()
		local thread = self.BagResetThread; self.BagResetThread = nil
		if thread then pcall(task.cancel, thread); self.BagResetTriggered = false end
	end
	function Farm:ResetBagState()
		self:CancelBagReset(); self.BagFull = false; self.BagResetTriggered = false
	end

	-- Noclip
	function Farm:EnableNoclip()
		if self.NoclipLease then return end
		local noclip = API.Features.Noclip
		if noclip and type(noclip.Acquire) == "function" then self.NoclipLease = noclip:Acquire(self) == true end
	end
	function Farm:DisableNoclip()
		if not self.NoclipLease then return end
		self.NoclipLease = false; local noclip = API.Features.Noclip
		if noclip and type(noclip.Release) == "function" then noclip:Release(self) end
	end

	-- CoinCollection
	function Farm:TouchOnce(root, coin)
		if not self.Enabled or not root or not root.Parent or not coin or not coin.Parent then return end
		local touchFunction = getTouchFunction()
		if not touchFunction then return false end
		local enterOk = pcall(touchFunction, root, coin, 0); local exitOk = pcall(touchFunction, root, coin, 1); return enterOk and exitOk
	end
	function Farm:TouchCoinInRange(root, coin, container, coinPosition)
		if
			not self.Enabled
			or not self.Farming
			or not self:HasAssignedRole()
			or Player:GetAttribute("Alive") ~= true
			or not root
			or not root.Parent
			or self:IsNearMurderer(root.Position, AVOID_MURDERER_PLAYER_DISTANCE)
			or self.PassedCoins[coin]
			or not CoinService:IsCollectable(coin, container)
		then
			return false
		end
		coinPosition = coinPosition or MapService:GetCoinPositions(container)[coin]
		if not coinPosition or (root.Position - coinPosition).Magnitude > TOUCH_DISTANCE then return false end
		self:TouchOnce(root, coin); return true
	end

	-- ProximityCollection
	function Farm:StartProximityCollection()
		if self.ProximityConnection then return end
		self.ProximityConnection = Services.RunService.Heartbeat:Connect(function()
			if not self.Enabled or not self.Farming or self.BagFull then return end
			local ok, errorMessage = xpcall(function()
				local inMatch, _, _, root, container = self:GetActiveContext()
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
			or not Util.IsFiniteVector3(root.Position)
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
	function Farm:RestoreActivationPosition()
		local character = self.ActivationCharacter; local savedRoot = self.ActivationRoot; local savedCFrame = self.ActivationCFrame; self.ActivationCharacter = nil
		self.ActivationRoot = nil; self.ActivationCFrame = nil
		if not character or Player.Character ~= character or not savedRoot or not savedCFrame then return false end
		local humanoid = character:FindFirstChildOfClass("Humanoid"); local root = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or root ~= savedRoot or not root:IsA("BasePart") then return false end
		local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.IgnoreWater = true; local excluded = {}
		for _, target in ipairs(Services.Players:GetPlayers()) do
			if target.Character then table.insert(excluded, target.Character) end
		end
		params.FilterDescendantsInstances = excluded
		pcall(function() params.RespectCanCollide = true end)
		local savedPosition = savedCFrame.Position; local floor = Workspace:Raycast(savedPosition + Vector3.new(0, 0.5, 0), Vector3.new(0, -8.5, 0), params)
		if not floor or savedPosition.Y - floor.Position.Y > 8 or floor.Position.Y > savedPosition.Y + 0.5 then return false end
		local restored = pcall(function()
			local antiFling = API.Features.AntiFling
			if antiFling and type(antiFling.AllowTeleport) == "function" then antiFling:AllowTeleport(0.35) end
			root.CFrame = savedCFrame; root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
		end)
		return restored
	end

	-- CoinCollectionLoop
	function Farm:CollectCoin(coin, character, humanoid, root, container, coinPosition)
		if
			not self.Enabled
			or not self:HasAssignedRole()
			or Player:GetAttribute("Alive") ~= true
			or not CoinService:IsCollectable(coin, container)
		then
			return
		end
		local succeeded, errorMessage = xpcall(function()
			local collectionSerial = self.CollectionSerial
			if self.Farming and self.FarmingCharacter ~= character then self:StopFarming() end
			if not self.Farming and not self:StartFarming(character, humanoid, root) then return end
			coinPosition = coinPosition or MapService:GetCoinPositions(container)[coin] or coin.Position
			if not Util.IsFiniteVector3(coinPosition) or not Util.IsFiniteVector3(root.Position) then return end
			local speed = tonumber(self.Speed)
			if not speed or speed ~= speed or speed == math.huge then speed = 40 end
			speed = math.max(speed, 1); local target = coinPosition - Vector3.new(0, 2.5, 0); local approach = target - root.Position; local approachDistance = approach.Magnitude
			if approachDistance ~= approachDistance or approachDistance == math.huge then return end
			if approachDistance > 0.001 then target += approach.Unit * PASS_THROUGH_DISTANCE end
			if not Util.IsFiniteVector3(target) then return end
			local duration = math.max((target - root.Position).Magnitude / speed, 1 / 60); local targetCFrame = CFrame.new(target) * CFrame.Angles(math.rad(90), 0, 0)
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
				if
					self:IsNearMurderer(root.Position, AVOID_MURDERER_PLAYER_DISTANCE)
					or self:IsNearMurderer(coinPosition, AVOID_MURDERER_COIN_DISTANCE)
				then
					pcall(function() tween:Cancel() end)
					if self.Tween == tween then self.Tween = nil end
					return
				end
				local inMatch, activeCharacter, activeHumanoid, activeRoot, activeContainer = self:GetActiveContext()
				if
					not inMatch
					or activeCharacter ~= character
					or activeHumanoid ~= humanoid
					or activeRoot ~= root
					or activeContainer ~= container
					or not self:HasAssignedRole()
					or not coin.Parent
					or not coin:IsDescendantOf(container)
					or not CoinService:IsCollectable(coin, container)
				then
					break
				end
				self:TouchCoinInRange(root, coin, container, coinPosition)
				if self.CollectionSerial ~= collectionSerial or not CoinService:IsCollectable(coin, container) then break end
				if tween.PlaybackState ~= Enum.PlaybackState.Playing then break end
				Services.RunService.Heartbeat:Wait()
			end
			local routeCompleted = tween.PlaybackState == Enum.PlaybackState.Completed
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
				self:TouchCoinInRange(root, coin, container, coinPosition)
			end
			if
				routeCompleted
				and coin.Parent
				and coin:IsDescendantOf(container)
				and CoinService:IsCollectable(coin, container)
			then
				self.PassedCoins[coin] = true
			end
		end, Util.FormatError)
		if not succeeded then self:ReportError("coleta", errorMessage) end
	end

	-- Lifecycle
	function Farm:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		local character = Player.Character; local root = character and character:FindFirstChild("HumanoidRootPart"); self.ActivationCharacter = character; self.ActivationRoot = root
		self.ActivationCFrame = root and root:IsA("BasePart") and root.CFrame or nil; self.Enabled = true; self.RoleData = nil; self.NextRoleRefreshAt = 0
		self.ThreatRoot = nil; self.ThreatRefreshAt = 0; table.clear(self.PassedCoins); self.PassedContainer = nil
		local invisicam = API.Features.Invisicam
		if invisicam and type(invisicam.SetSource) == "function" then pcall(invisicam.SetSource, invisicam, "AutoFarm", true) end
		local thread
		thread = task.spawn(function()
			while self.Enabled and not Runtime.ShuttingDown do
				local ok, errorMessage = xpcall(function()
					local inMatch, character, humanoid, root, container = self:GetActiveContext()
					if not inMatch then self:StopFarming(); Services.RunService.Heartbeat:Wait(); return end
					if self.BagFull then self:StopFarming(); Services.RunService.Heartbeat:Wait(); return end
					if self:IsNearMurderer(root.Position, AVOID_MURDERER_PLAYER_DISTANCE) then self:StopFarming(); Services.RunService.Heartbeat:Wait(); return end
					if self.PassedContainer ~= container then table.clear(self.PassedCoins); self.PassedContainer = container end
					local coin, _, coinPosition = MapService:GetNearestCoin(
						container,
						root.Position,
						nil,
						self.PassedCoins,
						function(_, position) return not self:IsNearMurderer(position, AVOID_MURDERER_COIN_DISTANCE) end
					)
					if coin then self:CollectCoin(coin, character, humanoid, root, container, coinPosition)
					else Services.RunService.Heartbeat:Wait() end
				end, Util.FormatError)
				if not ok then self:ReportError("ciclo", errorMessage); Services.RunService.Heartbeat:Wait() end
			end
			if self.Thread == thread then self.Thread = nil end
			self:StopFarming(); self:StopProximityCollection()
		end)
		self.Thread = thread; self:StartProximityCollection()
		if self.BagFull then self:ResetCharacterForFullBag() end
	end
	function Farm:Stop(restoreActivationPosition)
		self.Enabled = false; local thread = self.Thread; self.Thread = nil
		if thread then pcall(task.cancel, thread) end
		self:CancelBagReset(); self:StopFarming(); self:StopProximityCollection(); local invisicam = API.Features.Invisicam
		if invisicam and type(invisicam.SetSource) == "function" then pcall(invisicam.SetSource, invisicam, "AutoFarm", false) end
		if restoreActivationPosition == true then self:RestoreActivationPosition()
		else self.ActivationCharacter = nil; self.ActivationRoot = nil; self.ActivationCFrame = nil end
	end
	function Farm:DisableAfterDeath()
		if not self.Enabled then return end
		local registries = API.UI and API.UI.Registries; local registry = registries and registries["Auto Farm"]; local node = registry and registry.ByFlag and registry.ByFlag.AutoFarm
		local toggle = node and node.Control
		if toggle and toggle.Value == true and type(toggle.Set) == "function" then pcall(toggle.Set, toggle, false)
		else self:Stop(false) end
	end
	Runtime:Track(Player.CharacterAdded:Connect(function() Farm:StopMotion() end))
	Runtime:Track(Player:GetAttributeChangedSignal("Alive"):Connect(function()
		if Player:GetAttribute("Alive") == false then Farm:DisableAfterDeath() end
	end))

	-- RoundEvents
	local function bindFarmRoundEvents()
		local remotes = Services.ReplicatedStorage:FindFirstChild("Remotes"); local gameplay = remotes and remotes:FindFirstChild("Gameplay")
		if not gameplay then return end
		local coinCollected = gameplay:FindFirstChild("CoinCollected")
		if coinCollected and coinCollected:IsA("RemoteEvent") then
			Runtime:Track(coinCollected.OnClientEvent:Connect(function(coinType, count, maximum)
				if not CoinService:NormalizeKind(coinType) then return end
				Farm.CollectionSerial += 1; local collected = tonumber(count); local capacity = tonumber(maximum)
				if not collected or not capacity or capacity <= 0 then return end
				if collected >= capacity then Farm.BagFull = true; Farm:StopFarming(); Farm:ResetCharacterForFullBag() end
			end))
		end
		for _, eventName in ipairs({ "RoundStart", "CoinsStarted", "RoundEndFade" }) do
			local event = gameplay:FindFirstChild(eventName)
			if event and event:IsA("RemoteEvent") then
				local isRoundEnd = eventName == "RoundEndFade"
				Runtime:Track(event.OnClientEvent:Connect(function()
					Farm:ResetBagState(); Farm.PassedCoins = setmetatable({}, { __mode = "k" }); Farm.PassedContainer = nil
					if isRoundEnd then Farm:StopFarming() end
				end))
			end
		end
	end
	bindFarmRoundEvents()
	Runtime:OnShutdown(function() Farm:Stop(false) end)

	return Farm
end
