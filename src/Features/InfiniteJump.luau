-- [[ infinitejump ]]

return function(API)
	local Player = API.Player; local Services = API.Roblox; local Runtime = API.Runtime
	local InfiniteJump = {
		Enabled = false,
		Connection = nil,
		Debouncing = false,
	}

	function InfiniteJump:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true
		local ok, connection = pcall(function()
			return Services.UserInputService.JumpRequest:Connect(function()
				if not self.Enabled or self.Debouncing then return end
				local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not humanoid or humanoid.Health <= 0 or humanoid.Sit then return end
				self.Debouncing = true
				pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
				task.delay(0.05, function() self.Debouncing = false end)
			end)
		end)
		if ok then self.Connection = connection
		else self.Enabled = false; warn("[Chorus MM2] Não foi possível iniciar o Infinite Jump: " .. tostring(connection)) end
	end
	function InfiniteJump:Stop()
		self.Enabled = false; self.Debouncing = false
		if self.Connection then
			pcall(function() self.Connection:Disconnect() end)
			self.Connection = nil
		end
	end
	Runtime:OnShutdown(function() InfiniteJump:Stop() end)

	return InfiniteJump
end
