return function(API)
local Player = API.Player
local Runtime = API.Runtime

local AntiAFK = {
	Enabled = false,
	Connection = nil,
	VirtualUser = nil,
	WarnedUnavailable = false,
}

function AntiAFK:Start()
	if self.Enabled or Runtime.ShuttingDown then
		return
	end

	self.Enabled = true
	local serviceOk, virtualUser = pcall(function()
		return game:GetService("VirtualUser")
	end)
	self.VirtualUser = serviceOk and virtualUser or nil

	local connectionOk, connection = pcall(function()
		return Player.Idled:Connect(function()
			if not self.Enabled or Runtime.ShuttingDown then
				return
			end

			if not self.VirtualUser then
				if not self.WarnedUnavailable then
					self.WarnedUnavailable = true
					warn("[Chorus MM2] Anti AFK indisponível: VirtualUser não está acessível neste ambiente.")
				end
				return
			end

			local inputOk = pcall(function()
				self.VirtualUser:CaptureController()
				self.VirtualUser:ClickButton2(Vector2.new(0, 0))
			end)
			if not inputOk and not self.WarnedUnavailable then
				self.WarnedUnavailable = true
				warn("[Chorus MM2] Anti AFK não conseguiu enviar a entrada virtual.")
			end
		end)
	end)

	if connectionOk then
		self.Connection = connection
	else
		self.Enabled = false
		warn("[Chorus MM2] Não foi possível iniciar o Anti AFK: " .. tostring(connection))
	end
end

function AntiAFK:Stop()
	self.Enabled = false
	if self.Connection then
		pcall(function()
			self.Connection:Disconnect()
		end)
		self.Connection = nil
	end
	self.VirtualUser = nil
end
Runtime:OnShutdown(function()
	AntiAFK:Stop()
end)

return AntiAFK
end
