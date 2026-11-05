-- [[ hitboxexpander ]]

return function(API)
	local Players = API.Roblox.Players
	local Player, Runtime = API.Player, API.Runtime
	local MatchService = API.Services.Match
	local Workspace = API.Roblox.Workspace

	local Hitbox = {
		ShootPercent = 0,
		MurderPercent = 0,
		Original = setmetatable({}, { __mode = "k" }),
		RoleData = nil,
		RoleDataAt = 0,
		Destroyed = false,
	}

	local function restore(part, saved)
		if part and part.Parent then
			pcall(function()
				part.Size = saved.Size
				part.CanCollide = saved.CanCollide
				part.CanQuery = saved.CanQuery
			end)
		end
	end

	function Hitbox:SetShootPercent(value)
		self.ShootPercent = math.clamp(tonumber(value) or 0, 0, 100)
	end

	function Hitbox:SetMurderPercent(value)
		self.MurderPercent = math.clamp(tonumber(value) or 0, 0, 100)
	end

	function Hitbox:Update()
		local active = MatchService:GetRoundContext()
		local wanted = {}
		if active and Player:GetAttribute("Alive") == true then
			local now = os.clock()
			if now - self.RoleDataAt >= 0.6 then
				self.RoleData = MatchService:GetPlayerData()
				self.RoleDataAt = now
			end
			local profiles = self.RoleData
			local mine = profiles and profiles[Player.Name]
			local role = type(mine) == "table" and mine.Role
			local percent = role == "Murderer" and self.MurderPercent
				or (role == "Sheriff" or role == "Hero") and self.ShootPercent
				or 0
			if percent > 0 then
				for _, target in ipairs(Players:GetPlayers()) do
					if target ~= Player and target:GetAttribute("Alive") == true then
						local profile = profiles[target.Name]
						local targetRole = type(profile) == "table" and profile.Role
						local valid = role == "Murderer" and (targetRole == "Innocent" or targetRole == "Sheriff" or targetRole == "Hero")
							or (role == "Sheriff" or role == "Hero") and targetRole == "Murderer"
						local character = target.Character
						local root = valid and character and character:FindFirstChild("HumanoidRootPart")
						local humanoid = character and character:FindFirstChildOfClass("Humanoid")
						if root and root:IsA("BasePart") and character:IsDescendantOf(Workspace) and humanoid and humanoid.Health > 0 then
							wanted[root] = percent
						end
					end
				end
			end
		end
		for part, previous in pairs(self.Original) do
			if not wanted[part] or not part.Parent then
				restore(part, previous)
				self.Original[part] = nil
			end
		end
		for part, percent in pairs(wanted) do
			local saved = self.Original[part]
			if not saved then
				saved = { Size = part.Size, CanCollide = part.CanCollide, CanQuery = part.CanQuery }
				self.Original[part] = saved
			end
			local factor = 1 + percent / 100
			pcall(function()
				part.CanCollide = false
				part.CanQuery = true
				part.Size = saved.Size * factor
			end)
		end
	end

	function Hitbox:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		for part, saved in pairs(self.Original) do restore(part, saved); self.Original[part] = nil end
	end

	Runtime:Track(API.Roblox.RunService.Heartbeat:Connect(function()
		if Hitbox.Destroyed or Runtime.ShuttingDown then return end
		local ok, err = pcall(function() Hitbox:Update() end)
		if not ok then warn("[Chorus MM2] Hitbox Expander: " .. tostring(err)) end
	end))
	Runtime:OnShutdown(function() Hitbox:Destroy() end)
	return Hitbox
end
