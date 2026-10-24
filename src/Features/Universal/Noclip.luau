-- [[ noclip ]]

return function(API)
	local Services = API.Roblox; local Player = API.Player; local Runtime = API.Runtime
	local Noclip = {
		Enabled = false,
		Owners = {},
		Character = nil,
		SteppedConnection = nil,
		DescendantConnection = nil,
		OriginalCanCollide = {},
		BindGeneration = 0,
		BindThread = nil,
	}

	local function hasOwners() return next(Noclip.Owners) ~= nil end
	local function disconnect(connection)
		if connection then pcall(function() connection:Disconnect() end) end
	end
	local function cancelPendingBind()
		local thread = Noclip.BindThread; Noclip.BindThread = nil
		if thread then pcall(task.cancel, thread) end
	end
	local function disablePart(part)
		if not part:IsA("BasePart") then return end
		local readOk, canCollide = pcall(function() return part.CanCollide end)
		if not readOk then return end
		if Noclip.OriginalCanCollide[part] == nil then Noclip.OriginalCanCollide[part] = canCollide end
		pcall(function() part.CanCollide = false end)
	end
	function Noclip:_RestoreBinding()
		cancelPendingBind(); disconnect(self.SteppedConnection); self.SteppedConnection = nil; disconnect(self.DescendantConnection)
		self.DescendantConnection = nil
		for part, canCollide in pairs(self.OriginalCanCollide) do
			if part.Parent then pcall(function() part.CanCollide = canCollide end) end
		end
		table.clear(self.OriginalCanCollide); self.Character = nil
	end
	function Noclip:_BindCharacter(character)
		self.BindGeneration += 1; local generation = self.BindGeneration
		if character and self.Character == character then return end
		self:_RestoreBinding()
		if not character or not hasOwners() then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			local thread
			thread = task.defer(function()
				local candidate = character:WaitForChild("Humanoid", 10)
				if self.BindThread == thread then self.BindThread = nil end
				if
					candidate
					and candidate:IsA("Humanoid")
					and self.BindGeneration == generation
					and hasOwners()
					and Player.Character == character
				then
					self:_BindCharacter(character)
				end
			end)
			self.BindThread = thread; return
		end
		if humanoid.Health <= 0 then return end
		self.Character = character
		for _, descendant in ipairs(character:GetDescendants()) do
			disablePart(descendant)
		end
		self.DescendantConnection = character.DescendantAdded:Connect(function(descendant)
			if self.Character == character and hasOwners() then disablePart(descendant) end
		end)
		self.SteppedConnection = Services.RunService.Stepped:Connect(function()
			if self.Character ~= character or not hasOwners() then self:_RestoreBinding(); return end
			if Player.Character ~= character then return end
			for part in pairs(self.OriginalCanCollide) do
				if part.Parent then
					pcall(function() part.CanCollide = false end)
				else
					self.OriginalCanCollide[part] = nil
				end
			end
		end)
	end
	function Noclip:Acquire(owner)
		if owner == nil then return false end
		self.Owners[owner] = true; self:_BindCharacter(Player.Character); return true
	end
	function Noclip:Release(owner)
		if owner ~= nil then self.Owners[owner] = nil end
		if not hasOwners() then self:_RestoreBinding()
		elseif not self.Character then self:_BindCharacter(Player.Character) end
	end
	function Noclip:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true; self:Acquire(self)
	end
	function Noclip:Stop()
		self.Enabled = false; self:Release(self)
	end
	Runtime:Track(Player.CharacterAdded:Connect(function(character)
		if hasOwners() then Noclip:_BindCharacter(character) end
	end))
	Runtime:Track(Player.CharacterRemoving:Connect(function(character)
		if Noclip.Character == character or Noclip.BindThread then Noclip:_BindCharacter(nil) end
	end))
	Runtime:OnShutdown(function() Noclip:Stop() end)

	return Noclip
end
