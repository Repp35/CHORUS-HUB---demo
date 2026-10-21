-- [[ antifling ]]

return function(API)
	local Services = API.Roblox; local Runtime = API.Runtime; local MatchService = API.Services.Match

	-- State
	local AntiFling = {
		Enabled = false,
		Connection = nil,
		LinearVelocityLimit = 150,
		AngularVelocityLimit = 120,
		LastWarningAt = 0,
	}

	-- Velocity
	local function velocityMagnitude(vector)
		if typeof(vector) ~= "Vector3" then return 0 end
		local magnitude = vector.Magnitude
		if magnitude ~= magnitude or magnitude == math.huge then return math.huge end
		return magnitude
	end

	-- Activation
	function AntiFling:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true
		local connectionOk, connection = pcall(function()
			return Services.RunService.Heartbeat:Connect(function()
				if not self.Enabled or Runtime.ShuttingDown then return end
				local inMatch, _, _, root = MatchService:GetContext()
				if not inMatch or not root or not root:IsA("BasePart") then return end
				local ok, errorMessage = pcall(function()
					local linear = root.AssemblyLinearVelocity; local angular = root.AssemblyAngularVelocity
					if
						velocityMagnitude(linear) >= self.LinearVelocityLimit
						or velocityMagnitude(angular) >= self.AngularVelocityLimit
					then
						root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
					end
				end)
				if not ok then
					local now = os.clock()
					if now - self.LastWarningAt >= 5 then self.LastWarningAt = now; warn("[Chorus MM2] Anti Fling não conseguiu corrigir a velocidade: " .. tostring(errorMessage)) end
				end
			end)
		end)
		if connectionOk then self.Connection = connection
		else self.Enabled = false; warn("[Chorus MM2] Não foi possível iniciar o Anti Fling: " .. tostring(connection)) end
	end

	-- Cleanup
	function AntiFling:Stop()
		self.Enabled = false
		if self.Connection then
			pcall(function() self.Connection:Disconnect() end)
			self.Connection = nil
		end
	end
	Runtime:OnShutdown(function() AntiFling:Stop() end)

	return AntiFling
end
