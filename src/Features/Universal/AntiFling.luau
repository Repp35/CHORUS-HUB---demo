-- [[ antifling ]]

return function(API)
	local Services = API.Roblox; local Players = Services.Players; local Workspace = Services.Workspace; local Player = API.Player
	local Runtime = API.Runtime; local Fly = API.Features.Fly; local Farm = API.Features.AutoFarm; local Util = API.Util
	local function finiteNumber(value, fallback)
		local number = tonumber(value)
		if not number or number ~= number or number == math.huge or number == -math.huge then return fallback end
		return number
	end
	local AntiFling = {
		Enabled = false,
		PlayerAddedConnection = nil,
		PlayerRemovingConnection = nil,
		CollisionConnection = nil,
		VelocityConnection = nil,
		LocalCharacter = nil,
		LocalRoot = nil,
		BaseWalkSpeed = nil,
		LastPosition = nil,
		LastSampleAt = 0,
		LastAliveState = nil,
		LastSafeCheckAt = 0,
		LastSafeCFrame = nil,
		RecoveryCFrame = nil,
		RecoveryUntil = 0,
		FloorRaycastParams = nil,
		PlayerBindings = {},
		OriginalCanCollide = setmetatable({}, { __mode = "k" }),
		AngularVelocityLimit = 120,
		MovementTolerance = 1.5,
		JumpVelocityLimit = 110,
		SafeFloorCheckDistance = 12,
		FallbackFloorCheckDistance = 10000,
		SafeCheckInterval = 0.1,
		RecoveryDuration = 0.25,
		LastWarningAt = -math.huge,
	}

	-- ConnectionHelpers
	local function disconnect(connection)
		if connection then pcall(function() connection:Disconnect() end) end
	end
	local function safely(label, callback)
		local ok, errorMessage = pcall(callback)
		if not ok then AntiFling:_Warn(label .. tostring(errorMessage)) end
		return ok
	end
	function AntiFling:_Warn(message)
		local now = os.clock()
		if now - self.LastWarningAt < 5 then return end
		self.LastWarningAt = now; warn("[Chorus MM2] " .. message)
	end

	-- CollisionProtection
	function AntiFling:_DisableCollision(part, character)
		if not part:IsA("BasePart") then return end
		local record = self.OriginalCanCollide[part]
		if record and record.Character ~= character then
			if part.Parent then pcall(function() part.CanCollide = record.CanCollide end) end
			self.OriginalCanCollide[part] = nil; record = nil
		end
		if not record then
			local readOk, canCollide = pcall(function() return part.CanCollide end)
			if not readOk then return end
			record = { CanCollide = canCollide, Character = character }; self.OriginalCanCollide[part] = record
		end
		local readOk, canCollide = pcall(function() return part.CanCollide end)
		if readOk and canCollide then
			local writeOk = pcall(function() part.CanCollide = false end)
			if not writeOk then self:_Warn("Anti Fling não conseguiu ajustar a colisão de uma peça.") end
		end
	end
	function AntiFling:_RestoreCharacter(character)
		if not character then return end
		for part, record in pairs(self.OriginalCanCollide) do
			if record.Character == character then
				if part.Parent then pcall(function() part.CanCollide = record.CanCollide end) end
				self.OriginalCanCollide[part] = nil
			end
		end
	end
	function AntiFling:_BindCharacter(player, character)
		local binding = self.PlayerBindings[player]
		if not binding or binding.Character == character then return end
		disconnect(binding.DescendantAddedConnection); binding.DescendantAddedConnection = nil; self:_RestoreCharacter(binding.Character); binding.Character = character
		if not character then return end
		for _, descendant in ipairs(character:GetDescendants()) do
			self:_DisableCollision(descendant, character)
		end
		local connectOk, connection = pcall(function()
			return character.DescendantAdded:Connect(function(descendant)
				if self.Enabled and binding.Character == character then
					safely(
						"Anti Fling não conseguiu proteger uma peça nova: ",
						function() self:_DisableCollision(descendant, character) end
					)
				end
			end)
		end)
		if connectOk then binding.DescendantAddedConnection = connection
		else self:_Warn("Anti Fling não conseguiu acompanhar novas peças de um personagem: " .. tostring(connection)) end
	end
	function AntiFling:_TrackPlayer(player)
		if player == Player or self.PlayerBindings[player] then return end
		local binding = { Character = nil }; self.PlayerBindings[player] = binding
		binding.CharacterAddedConnection = player.CharacterAdded:Connect(function(character)
			if self.Enabled then
				safely(
					"Anti Fling não conseguiu acompanhar um respawn: ",
					function() self:_BindCharacter(player, character) end
				)
			end
		end)
		binding.CharacterRemovingConnection = player.CharacterRemoving:Connect(function(character)
			if binding.Character == character then
				safely(
					"Anti Fling não conseguiu restaurar um personagem removido: ",
					function() self:_BindCharacter(player, nil) end
				)
			end
		end)
		if player.Character then self:_BindCharacter(player, player.Character) end
	end
	function AntiFling:_UntrackPlayer(player)
		local binding = self.PlayerBindings[player]
		if not binding then return end
		disconnect(binding.CharacterAddedConnection); disconnect(binding.CharacterRemovingConnection); disconnect(binding.DescendantAddedConnection); self:_RestoreCharacter(binding.Character)
		self.PlayerBindings[player] = nil
	end
	function AntiFling:_RestoreAllCollisions()
		for part, record in pairs(self.OriginalCanCollide) do
			if part.Parent then pcall(function() part.CanCollide = record.CanCollide end) end
			self.OriginalCanCollide[part] = nil
		end
	end

	-- SafePosition
	function AntiFling:_FindFloor(position, character, distance)
		if not Util.IsFiniteVector3(position) then return nil end
		local params = self.FloorRaycastParams
		if not params then
			params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.IgnoreWater = true
			pcall(function() params.RespectCanCollide = true end)
			self.FloorRaycastParams = params
		end
		local excluded = { character }
		for _, player in ipairs(Players:GetPlayers()) do
			local otherCharacter = player.Character
			if otherCharacter and otherCharacter ~= character then table.insert(excluded, otherCharacter) end
		end
		params.FilterDescendantsInstances = excluded
		local ok, result = pcall(
			function()
				return Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -(distance + 2), 0), params)
			end
		)
		if not ok or not result or result.Normal.Y < 0.55 then return nil end
		if result.Instance:IsA("BasePart") and not result.Instance.CanCollide then return nil end
		return result
	end
	function AntiFling:_UprightCFrame(position, root)
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if not Util.IsFiniteVector3(look) or look.Magnitude <= 0.001 then return CFrame.new(position) end
		return CFrame.lookAt(position, position + look.Unit)
	end
	function AntiFling:_GroundedCFrame(position, root, humanoid, character, checkDistance)
		local floor = self:_FindFloor(position, character, checkDistance or self.SafeFloorCheckDistance)
		if not floor then return nil end
		local height = humanoid.HipHeight + root.Size.Y * 0.5 + 0.25; local groundedPosition = floor.Position + Vector3.new(0, height, 0); return self:_UprightCFrame(groundedPosition, root)
	end
	function AntiFling:_GetSpawnCFrame(root, humanoid, character)
		local candidates = {}; local respawnLocation = Player.RespawnLocation
		if respawnLocation and respawnLocation:IsA("SpawnLocation") then table.insert(candidates, respawnLocation) end
		for _, instance in ipairs(Workspace:GetDescendants()) do
			if instance:IsA("SpawnLocation") and instance ~= respawnLocation then table.insert(candidates, instance) end
		end
		for _, spawn in ipairs(candidates) do
			if spawn.Parent and spawn.CanCollide then
				local height = spawn.Size.Y * 0.5 + humanoid.HipHeight + root.Size.Y * 0.5 + 0.25; local position = spawn.Position + spawn.CFrame.UpVector * height
				if Util.IsFiniteVector3(position) then
					local groundedCFrame = self:_GroundedCFrame(position, root, humanoid, character)
					if groundedCFrame then return groundedCFrame end
				end
			end
		end
		return nil
	end
	function AntiFling:_PrepareLocalCharacter(character, humanoid, root)
		self.LocalCharacter = character; self.LocalRoot = root; self.BaseWalkSpeed = math.max(finiteNumber(humanoid.WalkSpeed, 16), 0); self.LastPosition = nil
		self.LastSampleAt = 0; self.LastSafeCFrame = nil; self.RecoveryCFrame = nil; self.RecoveryUntil = 0
		self.LastSafeCheckAt = 0; self.LastSafeCFrame = self:_GroundedCFrame(root.Position, root, humanoid, character)
			or self:_GroundedCFrame(root.Position, root, humanoid, character, self.FallbackFloorCheckDistance)
			or self:_GetSpawnCFrame(root, humanoid, character)
	end
	function AntiFling:_RememberSafePosition(root, humanoid, character)
		local now = os.clock()
		if now - self.LastSafeCheckAt < self.SafeCheckInterval then return end
		self.LastSafeCheckAt = now
		if humanoid.FloorMaterial == Enum.Material.Air then return end
		self.LastSafeCFrame = self:_GroundedCFrame(root.Position, root, humanoid, character) or self.LastSafeCFrame
	end
	function AntiFling:_GetAllowedSpeed(humanoid)
		local speed = math.max(self.BaseWalkSpeed or 16, finiteNumber(humanoid.WalkSpeed, 16))
		if Farm and Farm.Farming then speed = math.max(speed, finiteNumber(Farm.Speed, 23)) end
		if Fly and Fly.Enabled then
			local flySpeed = type(Fly.GetMovementSpeed) == "function" and Fly:GetMovementSpeed()
				or finiteNumber(Fly.Speed, 1) * 50
			speed = math.max(speed, flySpeed)
		end
		return speed
	end
	function AntiFling:_ApplyRecovery(root, humanoid, now)
		local safeCFrame = self.RecoveryCFrame or self.LastSafeCFrame
		if not safeCFrame and self.LastPosition then
			safeCFrame = self:_GroundedCFrame(
				self.LastPosition,
				root,
				humanoid,
				self.LocalCharacter,
				self.FallbackFloorCheckDistance
			)
		end
		if not safeCFrame then safeCFrame = self:_GetSpawnCFrame(root, humanoid, self.LocalCharacter) end
		if not safeCFrame then
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
			end)
			self:_Warn("Anti Fling detectou um impulso, mas não encontrou uma posição segura com chão."); return false
		end
		if not self.RecoveryCFrame then self.RecoveryUntil = now + self.RecoveryDuration end
		self.RecoveryCFrame = safeCFrame
		if Farm and Farm.Tween then pcall(function() Farm.Tween:Cancel() end) end
		local ok = pcall(function()
			root.CFrame = safeCFrame; root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
		end)
		self.LastPosition = safeCFrame.Position; self.LastSampleAt = now; return ok
	end

	-- MovementGuard
	function AntiFling:_GuardLocalVelocity()
		if not self.Enabled or Runtime.ShuttingDown then return end
		local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then self.LastPosition = nil; self.LastSampleAt = 0; return end
		local ok, errorMessage = pcall(function()
			local isAlive = Player:GetAttribute("Alive") == true
			if self.LastAliveState ~= nil and self.LastAliveState ~= isAlive then
				self.LastAliveState = isAlive; self:_PrepareLocalCharacter(character, humanoid, root); self.LastPosition = root.Position; self.LastSampleAt = os.clock()
				return
			end
			self.LastAliveState = isAlive
			if self.LocalCharacter ~= character or self.LocalRoot ~= root then self:_PrepareLocalCharacter(character, humanoid, root) end
			local now = os.clock(); local position = root.Position
			if self.RecoveryCFrame and now <= self.RecoveryUntil then self:_ApplyRecovery(root, humanoid, now); return
			elseif self.RecoveryCFrame then self.RecoveryCFrame = nil; self.LastPosition = position; self.LastSampleAt = now end
			if not Util.IsFiniteVector3(position) then self:_ApplyRecovery(root, humanoid, now); return end
			if not self.LastPosition or self.LastSampleAt <= 0 then self.LastPosition = position; self.LastSampleAt = now; self:_RememberSafePosition(root, humanoid, character); return end
			local deltaTime = math.max(now - self.LastSampleAt, 1 / 240); local allowedSpeed = self:_GetAllowedSpeed(humanoid); local linear = root.AssemblyLinearVelocity
			local angular = root.AssemblyAngularVelocity
			if not Util.IsFiniteVector3(linear) or not Util.IsFiniteVector3(angular) then self:_ApplyRecovery(root, humanoid, now); return end
			local horizontalSpeed = Vector3.new(linear.X, 0, linear.Z).Magnitude; local hasScriptMovement = (Fly and Fly.Enabled) or (Farm and Farm.Farming)
			local angularLimit = (Fly and Fly.Enabled) and 720 or self.AngularVelocityLimit; local jumpLimit = math.max(self.JumpVelocityLimit, finiteNumber(humanoid.JumpPower, 50) * 2.2)
			local verticalLimit = hasScriptMovement and (allowedSpeed * 1.5 + 20) or jumpLimit; local horizontalLimit = allowedSpeed * 1.5 + 20
			local positionTolerance = self.MovementTolerance + ((Farm and Farm.Farming) and 4 or 0); local positionDelta = position - self.LastPosition
			local horizontalDistance = Vector3.new(positionDelta.X, 0, positionDelta.Z).Magnitude; local verticalDistance = math.abs(positionDelta.Y)
			local verticalMoveSpeed = hasScriptMovement and allowedSpeed or jumpLimit; local maxHorizontalStep = allowedSpeed * deltaTime + positionTolerance
			local maxVerticalStep = verticalMoveSpeed * deltaTime + positionTolerance; local exceededVelocity = horizontalSpeed > horizontalLimit
				or math.abs(linear.Y) > verticalLimit
				or angular.Magnitude > angularLimit
			local exceededDistance = horizontalDistance ~= horizontalDistance
				or verticalDistance ~= verticalDistance
				or horizontalDistance > maxHorizontalStep
				or verticalDistance > maxVerticalStep
			if exceededVelocity or exceededDistance then self:_ApplyRecovery(root, humanoid, now); return end
			self.LastPosition = position; self.LastSampleAt = now; self:_RememberSafePosition(root, humanoid, character)
		end)
		if not ok then self:_Warn("Anti Fling não conseguiu validar o movimento: " .. tostring(errorMessage)) end
	end

	-- Lifecycle
	function AntiFling:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true
		local startOk, startError = pcall(function()
			self.FloorRaycastParams = RaycastParams.new(); self.FloorRaycastParams.FilterType = Enum.RaycastFilterType.Exclude; self.FloorRaycastParams.IgnoreWater = true
			pcall(function() self.FloorRaycastParams.RespectCanCollide = true end)
			self.PlayerAddedConnection = Players.PlayerAdded:Connect(function(player)
				if self.Enabled then
					safely(
						"Anti Fling não conseguiu acompanhar um jogador novo: ",
						function() self:_TrackPlayer(player) end
					)
				end
			end)
			self.PlayerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
				safely(
					"Anti Fling não conseguiu limpar um jogador removido: ",
					function() self:_UntrackPlayer(player) end
				)
			end)
			self.CollisionConnection = Services.RunService.Stepped:Connect(function()
				local stepOk, stepError = pcall(function()
					if not self.Enabled or Runtime.ShuttingDown then return end
					for player, binding in pairs(self.PlayerBindings) do
						if player.Parent ~= Players then self:_UntrackPlayer(player)
						elseif binding.Character ~= player.Character then self:_BindCharacter(player, player.Character) end
					end
					for part, record in pairs(self.OriginalCanCollide) do
						if not part.Parent then self.OriginalCanCollide[part] = nil
						else self:_DisableCollision(part, record.Character) end
					end
				end)
				if not stepOk then self:_Warn("Anti Fling encontrou um erro na proteção de colisão: " .. tostring(stepError)) end
			end)
			self.VelocityConnection = Services.RunService.Heartbeat:Connect(function()
				local guardOk, guardError = pcall(function() self:_GuardLocalVelocity() end)
				if not guardOk then self:_Warn("Anti Fling encontrou um erro ao verificar a velocidade: " .. tostring(guardError)) end
			end)
			for _, player in ipairs(Players:GetPlayers()) do
				self:_TrackPlayer(player)
			end
		end)
		if not startOk then self:Stop(); self:_Warn("Não foi possível iniciar o Anti Fling: " .. tostring(startError)) end
	end
	function AntiFling:Stop()
		self.Enabled = false; disconnect(self.PlayerAddedConnection); self.PlayerAddedConnection = nil; disconnect(self.PlayerRemovingConnection)
		self.PlayerRemovingConnection = nil; disconnect(self.CollisionConnection); self.CollisionConnection = nil; disconnect(self.VelocityConnection)
		self.VelocityConnection = nil
		for player in pairs(self.PlayerBindings) do
			self:_UntrackPlayer(player)
		end
		self:_RestoreAllCollisions(); self.LocalCharacter = nil; self.LocalRoot = nil; self.BaseWalkSpeed = nil
		self.LastPosition = nil; self.LastSampleAt = 0; self.LastAliveState = nil; self.LastSafeCheckAt = 0
		self.LastSafeCFrame = nil; self.RecoveryCFrame = nil; self.RecoveryUntil = 0; self.FloorRaycastParams = nil
	end
	Runtime:OnShutdown(function() AntiFling:Stop() end)

	return AntiFling
end
