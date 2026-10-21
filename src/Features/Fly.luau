-- [[ fly ]]

return function(API)
	local Services = API.Roblox
	local Player = API.Player
	local Runtime = API.Runtime
	local Fly = {
		Enabled = false,
		Speed = 1,
		Controls = { Forward = 0, Backward = 0, Left = 0, Right = 0, Up = 0, Down = 0 },
		InputConnections = {},
		CharacterConnection = nil,
		CharacterRemovingConnection = nil,
		UpdateConnection = nil,
		Character = nil,
		Humanoid = nil,
		Root = nil,
		Velocity = nil,
		Gyro = nil,
		SavedHumanoidState = nil,
		ControlModule = nil,
		AttachGeneration = 0,
		AttachThread = nil,
		LastErrorAt = 0,
	}

	local SPEED_SCALE = 50
	local KEY_BINDINGS = {
		[Enum.KeyCode.W] = { "Forward", 1 },
		[Enum.KeyCode.S] = { "Backward", -1 },
		[Enum.KeyCode.A] = { "Left", -1 },
		[Enum.KeyCode.D] = { "Right", 1 },
		[Enum.KeyCode.E] = { "Up", 1 },
		[Enum.KeyCode.Q] = { "Down", -1 },
	}

	local function clearControls(controls)
		for key in pairs(controls) do
			controls[key] = 0
		end
	end
	local function disconnect(connection)
		if connection then
			pcall(function()
				connection:Disconnect()
			end)
		end
	end
	local function destroy(instance)
		if instance then
			pcall(function()
				instance:Destroy()
			end)
		end
	end
	local function cancelAttach()
		local thread = Fly.AttachThread
		Fly.AttachThread = nil
		if thread then
			pcall(task.cancel, thread)
		end
	end
	function Fly:SetSpeed(value)
		local speed = tonumber(value)
		if not speed or speed ~= speed then
			return false
		end
		self.Speed = math.clamp(math.floor(speed + 0.5), 1, 200)
		return true
	end
	function Fly:LoadControlModule()
		if self.ControlModule then
			return self.ControlModule
		end
		local playerScripts = Player:FindFirstChild("PlayerScripts")
		local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		local controlModule = playerModule and playerModule:FindFirstChild("ControlModule")
		if not controlModule or not controlModule:IsA("ModuleScript") then
			return nil
		end
		local ok, result = pcall(require, controlModule)
		if ok and type(result) == "table" and type(result.GetMoveVector) == "function" then
			self.ControlModule = result
		end
		return self.ControlModule
	end
	function Fly:GetDirection(camera)
		if Services.UserInputService.TouchEnabled then
			local controlModule = self:LoadControlModule()
			if controlModule then
				local ok, move = pcall(function()
					return controlModule:GetMoveVector()
				end)
				if ok and typeof(move) == "Vector3" then
					return camera.CFrame.RightVector * move.X - camera.CFrame.LookVector * move.Z
				end
			end
			local moveDirection = self.Humanoid and self.Humanoid.MoveDirection
			if moveDirection and moveDirection.Magnitude > 0 then
				return moveDirection
			end
		end
		local forward = self.Controls.Forward + self.Controls.Backward
		local lateral = self.Controls.Left + self.Controls.Right
		local vertical = self.Controls.Up + self.Controls.Down
		return camera.CFrame.LookVector * forward + camera.CFrame.RightVector * lateral + Vector3.new(0, vertical, 0)
	end
	function Fly:DetachCharacter()
		disconnect(self.UpdateConnection)
		self.UpdateConnection = nil
		local humanoid = self.Humanoid
		local root = self.Root
		local saved = self.SavedHumanoidState
		destroy(self.Velocity)
		destroy(self.Gyro)
		if root and root.Parent then
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end)
		end
		if humanoid and humanoid.Parent and saved then
			pcall(function()
				humanoid.PlatformStand = saved.PlatformStand
				humanoid.AutoRotate = saved.AutoRotate
			end)
		end
		self.Character = nil
		self.Humanoid = nil
		self.Root = nil
		self.Velocity = nil
		self.Gyro = nil
		self.SavedHumanoidState = nil
		clearControls(self.Controls)
	end
	function Fly:AttachCharacter(character, humanoid, root)
		if
			not self.Enabled
			or not character
			or not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA("BasePart")
		then
			return false
		end
		self:DetachCharacter()
		self.Character = character
		self.Humanoid = humanoid
		self.Root = root
		self.SavedHumanoidState = { PlatformStand = humanoid.PlatformStand, AutoRotate = humanoid.AutoRotate }
		local oldVelocity = root:FindFirstChild("ChorusFlyVelocity")
		local oldGyro = root:FindFirstChild("ChorusFlyGyro")
		destroy(oldVelocity)
		destroy(oldGyro)
		local velocity = Instance.new("BodyVelocity")
		self.Velocity = velocity
		velocity.Name = "ChorusFlyVelocity"
		velocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
		velocity.P = 9e4
		velocity.Velocity = Vector3.zero
		velocity.Parent = root
		local gyro = Instance.new("BodyGyro")
		self.Gyro = gyro
		gyro.Name = "ChorusFlyGyro"
		gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
		gyro.P = 9e4
		gyro.D = 1000
		gyro.CFrame = root.CFrame
		gyro.Parent = root
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
		self.UpdateConnection = Services.RunService.RenderStepped:Connect(function()
			local updateOk, updateError = pcall(function()
				if not self.Enabled or self.Character ~= character or not root.Parent or humanoid.Health <= 0 then
					self:DetachCharacter()
					return
				end
				local camera = Services.Workspace.CurrentCamera
				if not velocity.Parent or not gyro.Parent then
					self:DetachCharacter()
					return
				end
				if not camera then
					velocity.Velocity = Vector3.zero
					return
				end
				local direction = self:GetDirection(camera)
				if direction.Magnitude > 1 then
					direction = direction.Unit
				end
				velocity.Velocity = direction * (self.Speed * SPEED_SCALE)
				gyro.CFrame = camera.CFrame
				if not humanoid.PlatformStand then
					humanoid.PlatformStand = true
				end
				if humanoid.AutoRotate then
					humanoid.AutoRotate = false
				end
			end)
			if not updateOk then
				self:DetachCharacter()
				local now = os.clock()
				if now - self.LastErrorAt >= 5 then
					self.LastErrorAt = now
					warn("[Chorus MM2] Fly recuperou após erro de atualização: " .. tostring(updateError))
				end
			end
		end)
		return true
	end
	function Fly:QueueAttach(character)
		if not character or not self.Enabled then
			return
		end
		self.AttachGeneration += 1
		local generation = self.AttachGeneration
		cancelAttach()
		local thread
		thread = task.defer(function()
			local root = character:WaitForChild("HumanoidRootPart", 10)
			local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
			if self.AttachThread == thread then
				self.AttachThread = nil
			end
			if
				self.Enabled
				and generation == self.AttachGeneration
				and Player.Character == character
				and root
				and root:IsA("BasePart")
				and humanoid
				and humanoid:IsA("Humanoid")
			then
				local ok, errorMessage = pcall(function()
					self:AttachCharacter(character, humanoid, root)
				end)
				if not ok then
					self:DetachCharacter()
					local now = os.clock()
					if now - self.LastErrorAt >= 5 then
						self.LastErrorAt = now
						warn("[Chorus MM2] Fly não conseguiu anexar ao personagem: " .. tostring(errorMessage))
					end
				end
			end
		end)
		self.AttachThread = thread
	end
	function Fly:BindInputs()
		local inputService = Services.UserInputService
		table.insert(
			self.InputConnections,
			inputService.InputBegan:Connect(function(input, processed)
				if processed then
					return
				end
				local binding = KEY_BINDINGS[input.KeyCode]
				if binding then
					self.Controls[binding[1]] = binding[2]
				end
			end)
		)
		table.insert(
			self.InputConnections,
			inputService.InputEnded:Connect(function(input)
				local binding = KEY_BINDINGS[input.KeyCode]
				if binding then
					self.Controls[binding[1]] = 0
				end
			end)
		)
		table.insert(
			self.InputConnections,
			inputService.WindowFocusReleased:Connect(function()
				clearControls(self.Controls)
			end)
		)
		self.CharacterConnection = Player.CharacterAdded:Connect(function(character)
			self:QueueAttach(character)
		end)
		self.CharacterRemovingConnection = Player.CharacterRemoving:Connect(function(character)
			self.AttachGeneration += 1
			cancelAttach()
			if self.Character == character then
				self:DetachCharacter()
			end
		end)
	end
	function Fly:Start()
		if self.Enabled or Runtime.ShuttingDown then
			return
		end
		self.Enabled = true
		local ok, errorMessage = pcall(function()
			self:BindInputs()
			self:QueueAttach(Player.Character)
		end)
		if not ok then
			self:Stop()
			warn("[Chorus MM2] Não foi possível iniciar o Fly: " .. tostring(errorMessage))
		end
	end
	function Fly:Stop()
		self.Enabled = false
		self.AttachGeneration += 1
		cancelAttach()
		clearControls(self.Controls)
		self:DetachCharacter()
		for _, connection in ipairs(self.InputConnections) do
			disconnect(connection)
		end
		table.clear(self.InputConnections)
		disconnect(self.CharacterConnection)
		self.CharacterConnection = nil
		disconnect(self.CharacterRemovingConnection)
		self.CharacterRemovingConnection = nil
		self.ControlModule = nil
	end
	Runtime:OnShutdown(function()
		Fly:Stop()
	end)

	return Fly
end
