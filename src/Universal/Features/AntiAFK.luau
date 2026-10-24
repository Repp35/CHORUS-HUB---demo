-- [[ antiafk ]]

return function(API)
	local Player = API.Player; local Runtime = API.Runtime
	local AntiAFK = {
		Enabled = false,
		Connection = nil,
		VirtualUser = nil,
		PendingRelease = nil,
		LastInputAt = -math.huge,
		LastWarningAt = -math.huge,
		MinimumInterval = 30,
	}

	-- VirtualInput
	function AntiAFK:_ReleaseVirtualUserButton()
		local pending = self.PendingRelease
		if not pending then return end
		self.PendingRelease = nil
		pcall(function() pending.User:Button2Up(pending.Position, pending.CameraCFrame) end)
	end
	function AntiAFK:_SendVirtualUserInput()
		local virtualUser = self.VirtualUser
		if not virtualUser then error("VirtualUser não está acessível", 0) end
		virtualUser:CaptureController()
		if type(virtualUser.ClickButton2) == "function" then
			local clickOk, clickError = pcall(function() virtualUser:ClickButton2(Vector2.zero) end)
			if clickOk then return end
			if type(virtualUser.Button2Down) ~= "function" or type(virtualUser.Button2Up) ~= "function" then error(tostring(clickError), 0) end
		end
		if type(virtualUser.Button2Down) ~= "function" or type(virtualUser.Button2Up) ~= "function" then error("VirtualUser não oferece um método de clique compatível", 0) end
		local camera = workspace.CurrentCamera
		local pending = {
			User = virtualUser,
			Position = Vector2.zero,
			CameraCFrame = camera and camera.CFrame or CFrame.new(),
		}

		local downOk, downError = pcall(function() virtualUser:Button2Down(pending.Position, pending.CameraCFrame) end)
		if not downOk then error(tostring(downError), 0) end
		self.PendingRelease = pending
		local delayOk, delayError = pcall(task.delay, 0.15, function()
			if self.PendingRelease == pending then self:_ReleaseVirtualUserButton() end
		end)
		if not delayOk then self:_ReleaseVirtualUserButton(); error(tostring(delayError), 0) end
	end
	function AntiAFK:_SendVirtualInputManagerInput()
		local virtualInputManager = game:GetService("VirtualInputManager")
		if type(virtualInputManager.SendMouseButtonEvent) ~= "function" then error("VirtualInputManager não oferece entrada de mouse", 0) end
		local pressOk, pressError = pcall(
			function() virtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0) end
		)
		local releaseOk, releaseError = pcall(
			function() virtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0) end
		)
		if not pressOk then error(tostring(pressError), 0) end
		if not releaseOk then error(tostring(releaseError), 0) end
	end

	-- IdleHandler
	function AntiAFK:_OnIdle()
		if not self.Enabled or Runtime.ShuttingDown then return end
		local now = os.clock()
		if now - self.LastInputAt < self.MinimumInterval then return end
		self.LastInputAt = now
		local virtualUserOk, virtualUserError = pcall(function() self:_SendVirtualUserInput() end)
		if virtualUserOk then return end
		local virtualInputOk, virtualInputError = pcall(function() self:_SendVirtualInputManagerInput() end)
		if virtualInputOk then return end
		if now - self.LastWarningAt >= 5 then
			self.LastWarningAt = now
			warn(
				"[Chorus MM2] Anti AFK não conseguiu enviar entrada virtual. VirtualUser: "
					.. tostring(virtualUserError)
					.. "; VirtualInputManager: "
					.. tostring(virtualInputError)
			)
		end
	end

	-- Lifecycle
	function AntiAFK:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true
		local serviceOk, virtualUser = pcall(function() return game:GetService("VirtualUser") end)
		self.VirtualUser = serviceOk and virtualUser or nil
		local connectionOk, connection = pcall(function()
			return Player.Idled:Connect(function() self:_OnIdle() end)
		end)
		if connectionOk then self.Connection = connection
		else self.Enabled = false; self.VirtualUser = nil; warn("[Chorus MM2] Não foi possível iniciar o Anti AFK: " .. tostring(connection)) end
	end
	function AntiAFK:Stop()
		self.Enabled = false
		if self.Connection then
			pcall(function() self.Connection:Disconnect() end)
			self.Connection = nil
		end
		self:_ReleaseVirtualUserButton(); self.VirtualUser = nil; self.LastInputAt = -math.huge
	end
	Runtime:OnShutdown(function() AntiAFK:Stop() end)

	return AntiAFK
end
