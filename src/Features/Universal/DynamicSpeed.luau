-- [[ dynamicspeed ]]

return function(API)
	local Player = API.Player; local Runtime = API.Runtime; local RunService = API.Roblox.RunService
	local Speed = {
		Enabled = false,
		Value = 16,
		Character = nil,
		Humanoid = nil,
		OriginalWalkSpeed = nil,
		EnforcementConnection = nil,
		BindThread = nil,
		PendingCharacter = nil,
		PendingGeneration = nil,
		Generation = 0,
	}

	local function isFiniteNumber(value)
		return type(value) == "number" and value == value and value > -math.huge and value < math.huge
	end
	local function currentHumanoid()
		local character = Player.Character; return character and character:FindFirstChildOfClass("Humanoid")
	end
	local initialHumanoid = currentHumanoid()
	if initialHumanoid and isFiniteNumber(initialHumanoid.WalkSpeed) then Speed.Value = math.clamp(math.floor(initialHumanoid.WalkSpeed + 0.5), 0, 100) end
	function Speed:GetCurrentSpeed()
		local humanoid = currentHumanoid(); local value = humanoid and humanoid.WalkSpeed or self.Value
		if not isFiniteNumber(value) then value = 16 end
		return math.clamp(math.floor(value + 0.5), 0, 100)
	end
	function Speed:SetSpeed(value)
		local speed = tonumber(value)
		if not isFiniteNumber(speed) then return false end
		self.Value = math.clamp(math.floor(speed + 0.5), 0, 100); local humanoid = self.Humanoid
		if self.Enabled and humanoid and humanoid.Parent and humanoid.Health > 0 then
			pcall(function() humanoid.WalkSpeed = self.Value end)
		end
		return true
	end
	function Speed:_BindCharacter(character, generation)
		if not self.Enabled or generation ~= self.Generation or character ~= Player.Character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if
			not self.Enabled
			or generation ~= self.Generation
			or character ~= Player.Character
			or not humanoid
			or not humanoid:IsA("Humanoid")
		then
			return
		end
		if self.Humanoid ~= humanoid then self.Character = character; self.Humanoid = humanoid; self.OriginalWalkSpeed = humanoid.WalkSpeed end
		if humanoid.Health > 0 then pcall(function() humanoid.WalkSpeed = self.Value end) end
	end
	function Speed:_QueueBind(character, generation)
		if not character or not self.Enabled then return end
		if self.PendingCharacter == character and self.PendingGeneration == generation and self.BindThread then return end
		local previousThread = self.BindThread; self.BindThread = nil; self.PendingCharacter = character; self.PendingGeneration = generation
		if previousThread then pcall(task.cancel, previousThread) end
		local thread
		thread = task.spawn(function()
			self:_BindCharacter(character, generation)
			if self.BindThread == thread then self.BindThread = nil; self.PendingCharacter = nil; self.PendingGeneration = nil end
		end)
		self.BindThread = thread; Runtime:TrackTask(thread)
	end
	function Speed:Start()
		if self.Enabled or Runtime.ShuttingDown then return false end
		self.Enabled = true; self.Generation += 1; local generation = self.Generation; local character = Player.Character
		if character then self:_QueueBind(character, generation) end
		self.EnforcementConnection = Runtime:Track(RunService.Heartbeat:Connect(function()
			if not self.Enabled or Runtime.ShuttingDown then return end
			local character = Player.Character
			if not character then return end
			local humanoid = self.Humanoid
			if self.Character ~= character or not humanoid or not humanoid.Parent then
				self:_QueueBind(character, self.Generation)
			elseif humanoid.Health > 0 and humanoid.WalkSpeed ~= self.Value then
				pcall(function() humanoid.WalkSpeed = self.Value end)
			end
		end))
		return true
	end
	function Speed:Stop()
		if not self.Enabled and not self.EnforcementConnection then return false end
		self.Enabled = false; self.Generation += 1; local bindThread = self.BindThread; self.BindThread = nil
		self.PendingCharacter = nil; self.PendingGeneration = nil
		if bindThread then pcall(task.cancel, bindThread) end
		if self.EnforcementConnection then
			pcall(function() self.EnforcementConnection:Disconnect() end)
			self.EnforcementConnection = nil
		end
		local humanoid = self.Humanoid; local original = self.OriginalWalkSpeed
		if humanoid and humanoid.Parent and isFiniteNumber(original) then
			pcall(function() humanoid.WalkSpeed = original end)
		end
		self.Character = nil; self.Humanoid = nil; self.OriginalWalkSpeed = nil; return true
	end
	Runtime:Track(Player.CharacterAdded:Connect(function(character)
		if self.Enabled then self:_QueueBind(character, self.Generation) end
	end))
	Runtime:Track(Player.CharacterRemoving:Connect(function(character)
		if self.Character == character then self.Character = nil; self.Humanoid = nil; self.OriginalWalkSpeed = nil end
	end))
	Runtime:OnShutdown(function() Speed:Stop() end)

	return Speed
end
