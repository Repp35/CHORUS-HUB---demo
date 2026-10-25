-- [[ gravity ]]

return function(API)
	local Workspace = API.Roblox.Workspace; local Runtime = API.Runtime; local Gravity = { Enabled = false, Value = Workspace.Gravity, DefaultValue = Workspace.Gravity }
	function Gravity:SetValue(value)
		local numericValue = tonumber(value)
		if
			not numericValue
			or numericValue ~= numericValue
			or numericValue == math.huge
			or numericValue == -math.huge
		then
			return false
		end
		self.Value = math.clamp(numericValue, 0, 400)
		if self.Enabled then Workspace.Gravity = self.Value end
		return true
	end
	function Gravity:SetEnabled(enabled)
		self.Enabled = enabled == true; Workspace.Gravity = self.Enabled and self.Value or self.DefaultValue; return self.Enabled
	end
	function Gravity:Destroy()
		self.Enabled = false; Workspace.Gravity = self.DefaultValue
	end
	Runtime:OnShutdown(function() Gravity:Destroy() end)

	return Gravity
end
