-- [[ antifling ]]

return function(API)
	local Services = API.Roblox; local Players = Services.Players; local Player = API.Player; local Runtime = API.Runtime
	local Fly = API.Features.Fly
	local AntiFling = {
		Enabled = false,
		PlayerAddedConnection = nil,
		PlayerRemovingConnection = nil,
		CollisionConnection = nil,
		VelocityConnection = nil,
		PlayerBindings = {},
		OriginalCanCollide = setmetatable({}, { __mode = "k" }),
		LinearVelocityLimit = 150,
		AngularVelocityLimit = 120,
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

	-- VelocityGuard
	function AntiFling:_GuardLocalVelocity()
		if not self.Enabled or Runtime.ShuttingDown then return end
		if Fly and Fly.Enabled then return end
		local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			Player:GetAttribute("Alive") ~= true
			or not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA("BasePart")
		then
			return
		end
		local ok, errorMessage = pcall(function()
			local linear = root.AssemblyLinearVelocity; local angular = root.AssemblyAngularVelocity
			if linear.Magnitude >= self.LinearVelocityLimit or angular.Magnitude >= self.AngularVelocityLimit then
				root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
			end
		end)
		if not ok then self:_Warn("Anti Fling não conseguiu corrigir a velocidade: " .. tostring(errorMessage)) end
	end

	-- Lifecycle
	function AntiFling:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true
		local startOk, startError = pcall(function()
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
		self:_RestoreAllCollisions()
	end
	Runtime:OnShutdown(function() AntiFling:Stop() end)

	return AntiFling
end
