-- [[ murdercombat ]]

return function(API)
	local Services = API.Roblox
	local Players, Workspace = Services.Players, Services.Workspace
	local ReplicatedStorage, RunService = Services.ReplicatedStorage, Services.RunService
	local Player, Runtime, MatchService = API.Player, API.Runtime, API.Services.Match
	local CollectionService = Services.CollectionService

	local MELEE_RANGE = 8
	local MELEE_COOLDOWN = 0.3
	local THROW_COOLDOWN = 1.3
	local THROW_MAX_RANGE = 240
	local UPDATE_INTERVAL = 0.085
	local DEFAULT_KNIFE_SPEED = 96

	local Combat = {
		AutoAttack = false,
		AutoThrow = false,
		AttackTargets = "All",
		ThrowTargets = "Auto",
		LastStab = 0,
		LastThrow = 0,
		RoleData = nil,
		RoleDataAt = 0,
		Motion = setmetatable({}, { __mode = "k" }),
		LastRemoteWarning = 0,
		Destroyed = false,
	}

	local function warnRemote()
		if os.clock() - Combat.LastRemoteWarning > 8 then
			Combat.LastRemoteWarning = os.clock()
			warn("[Chorus MM2] Não encontrei um remote compatível de lançamento de faca.")
		end
	end

	local function getRoleData()
		if os.clock() - Combat.RoleDataAt < 0.55 then return Combat.RoleData end
		Combat.RoleDataAt = os.clock()
		Combat.RoleData = MatchService:GetPlayerData()
		return Combat.RoleData
	end

	local function characterInfo(target, profile)
		if target == Player or type(profile) ~= "table" or profile.Dead or profile.Killed
			or target:GetAttribute("Alive") ~= true then return nil end
		local character = target.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not character:IsDescendantOf(Workspace) or not humanoid
			or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
		return character, humanoid, root
	end

	local function getContext()
		local active, character, humanoid, root = MatchService:GetContext()
		if not active then return nil end
		local profiles = getRoleData()
		local mine = profiles and profiles[Player.Name]
		if type(mine) ~= "table" or mine.Role ~= "Murderer" or mine.Dead or mine.Killed then return nil end
		local knife = character:FindFirstChild("Knife")
		if not knife then
			local backpack = Player:FindFirstChildOfClass("Backpack")
			knife = backpack and backpack:FindFirstChild("Knife")
			if knife and knife:IsA("Tool") then humanoid:EquipTool(knife) end
			return nil
		end
		return character, humanoid, root, knife, profiles
	end

	local function acceptedRole(role, mode)
		if mode == "All" or mode == "Nearest" or mode == "Auto" then
			return role == "Sheriff" or role == "Hero" or role == "Innocent"
		end
		if mode == "Sheriff/Hero" then return role == "Sheriff" or role == "Hero" end
		if mode == "Innocent" then return role == "Innocent" end
		return false
	end

	local function getOrigin(character, root, knife)
		local handle = knife:FindFirstChild("RightHandle") or knife:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then return handle.Position end
		return root.Position + Vector3.new(0, 1.5, 0)
	end

	local function raycast(origin, destination, localCharacter, mapContainer)
		local ignores = { localCharacter }
		if mapContainer then table.insert(ignores, mapContainer) end
		for _, item in ipairs(CollectionService:GetTagged("WeaponPassthrough")) do
			table.insert(ignores, item)
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
		for _ = 1, 12 do
			params.FilterDescendantsInstances = ignores
			local result = Workspace:Raycast(origin, destination - origin, params)
			if not result or result.Instance.Transparency ~= 1
				or (API.Features.HitboxExpander and API.Features.HitboxExpander.Original[result.Instance]) then return result end
			table.insert(ignores, result.Instance)
		end
		return nil
	end

	local function visible(origin, part, targetCharacter, ownCharacter, coinContainer)
		local result = raycast(origin, part.Position, ownCharacter, coinContainer)
		return result == nil or result.Instance:IsDescendantOf(targetCharacter)
	end

	local function getMotion(target, root)
		local now, pos = os.clock(), root.Position
		local raw = root.AssemblyLinearVelocity
		local state = Combat.Motion[target]
		local velocity = raw
		if state and state.Root == root then
			local dt = now - state.At
			if dt > 0.015 and dt < 0.5 then
				local sampled = (pos - state.Position) / dt
				if sampled.Magnitude < 120 then
					velocity = raw * 0.65 + sampled * 0.35
				end
			end
		end
		Combat.Motion[target] = { Root = root, At = now, Position = pos }
		return velocity
	end

	local function getPing()
		local ok, ping = pcall(function()
			return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		return ok and math.clamp(tonumber(ping) or 0, 0, 300) / 2000 or 0
	end

	local function predictPosition(root, humanoid, velocity, origin, speed, ownCharacter, coinContainer)
		local t, ping = 0, getPing()
		local targetPosition = root.Position
		local jumping = humanoid.FloorMaterial == Enum.Material.Air
		local floorY
		if jumping then
			local ground = raycast(root.Position, root.Position - Vector3.new(0, 25, 0), root.Parent, coinContainer)
			if ground and ground.Instance:IsA("BasePart") then
				floorY = ground.Position.Y + math.max(2.0, humanoid.HipHeight + root.Size.Y * 0.5)
			end
		end
		for _ = 1, 4 do
			t = math.clamp((targetPosition - origin).Magnitude / speed + ping, 0, 2.8)
			local y = root.Position.Y
			if jumping then
				y += velocity.Y * t - 0.5 * Workspace.Gravity * t * t
				if floorY then y = math.max(y, floorY) end
			else
				y += math.clamp(velocity.Y, -8, 8) * t
			end
			targetPosition = Vector3.new(root.Position.X + velocity.X * t, y, root.Position.Z + velocity.Z * t)
		end
		return targetPosition, t
	end

	local function getKnifeSpeed(knife)
		local speed = tonumber(knife:GetAttribute("ThrowSpeed"))
		if speed and speed > 0 then return math.clamp(speed, 30, 400) end
		for _, projectile in ipairs(CollectionService:GetTagged("ThrowingKnife")) do
			speed = tonumber(projectile:GetAttribute("ThrowSpeed"))
			if speed and speed > 0 then return math.clamp(speed, 30, 400) end
		end
		return DEFAULT_KNIFE_SPEED
	end

	local function getTargets(root, profiles, mode)
		local list = {}
		for _, target in ipairs(Players:GetPlayers()) do
			local profile = profiles[target.Name]
			if type(profile) == "table" and acceptedRole(profile.Role, mode) then
				local character, humanoid, targetRoot = characterInfo(target, profile)
				if character then
					local distance = (targetRoot.Position - root.Position).Magnitude
					table.insert(list, {
						Player = target, Character = character, Humanoid = humanoid,
						Root = targetRoot, Role = profile.Role, Distance = distance,
					})
				end
			end
		end
		return list
	end

	local function chooseMelee(character, root, knife, profiles)
		local nearest, shortest
		local _, _, coinContainer = MatchService:GetRoundContext()
		local origin = getOrigin(character, root, knife)
		for _, entry in ipairs(getTargets(root, profiles, Combat.AttackTargets)) do
			if entry.Distance <= MELEE_RANGE and (not shortest or entry.Distance < shortest) then
				local part = entry.Character:FindFirstChild("UpperTorso") or entry.Character:FindFirstChild("Torso") or entry.Root
				if visible(origin, part, entry.Character, character, coinContainer) then
					nearest, shortest = entry, entry.Distance
				end
			end
		end
		return nearest
	end

	local function tryStab(knife, target)
		local events = knife:FindFirstChild("Events")
		local stabbed = events and events:FindFirstChild("KnifeStabbed")
		local touched = events and events:FindFirstChild("HandleTouched")
		local hitPart = target.Character:FindFirstChild("UpperTorso") or target.Character:FindFirstChild("Torso")
			or target.Character:FindFirstChild("Head") or target.Root
		if stabbed and stabbed:IsA("RemoteEvent") and touched and touched:IsA("RemoteEvent") then
			stabbed:FireServer()
			touched:FireServer(hitPart)
			return true
		end
		local remote = ReplicatedStorage:FindFirstChild("Stab", true)
		if remote and remote:IsA("RemoteEvent") then remote:FireServer(hitPart); return true end
		return false
	end

	local function chooseThrow(character, root, knife, profiles)
		local mode = Combat.ThrowTargets
		local origin = getOrigin(character, root, knife)
		local _, _, coinContainer = MatchService:GetRoundContext()
		local speed = getKnifeSpeed(knife)
		local preferred, bestScore
		for _, entry in ipairs(getTargets(root, profiles, mode)) do
			if entry.Distance <= THROW_MAX_RANGE
				and (not Combat.AutoAttack or entry.Distance > MELEE_RANGE) then
				local aimPart = entry.Character:FindFirstChild("UpperTorso") or entry.Character:FindFirstChild("Torso") or entry.Root
				if visible(origin, aimPart, entry.Character, character, coinContainer) then
					local velocity = getMotion(entry.Player, entry.Root)
					local aim, flightTime = predictPosition(entry.Root, entry.Humanoid, velocity, origin, speed, character, coinContainer)
					aim += aimPart.Position - entry.Root.Position
					local blocked = raycast(origin, aim, character, coinContainer)
					if not blocked or blocked.Instance:IsDescendantOf(entry.Character) then
						local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
						local score = entry.Distance * 0.045 + moving * 0.55 + math.abs(velocity.Y) * 0.25
						if mode == "Nearest" then score = entry.Distance end
						if mode == "Auto" and (entry.Role == "Sheriff" or entry.Role == "Hero") then score -= 10000 end
						if not bestScore or score < bestScore then
							bestScore = score
							preferred = { Entry = entry, Aim = aim, Origin = origin, Speed = speed, TravelTime = flightTime }
						end
					end
				end
			end
		end
		return preferred
	end

	local function simulateProjectile(origin, direction, speed, character, hitRemote)
		local _, _, coinContainer = MatchService:GetRoundContext()
		local traveled, last = 0, origin
		while traveled < THROW_MAX_RANGE and character.Parent and hitRemote.Parent and not Runtime.ShuttingDown do
			local dt = math.min(RunService.Heartbeat:Wait(), 0.08)
			local nextPosition = last + direction * (dt * speed)
			local hit = raycast(last, nextPosition, character, coinContainer)
			if hit then
				hitRemote:FireServer(hit.Instance, hit.Position)
				return
			end
			traveled += (nextPosition - last).Magnitude
			last = nextPosition
		end
	end

	local function tryThrow(knife, data, character)
		local direction = data.Aim - data.Origin
		if direction.Magnitude < 1 then return false end
		direction = direction.Unit
		local throwStart = ReplicatedStorage:FindFirstChild("ThrowStart", true)
		local throwHit = ReplicatedStorage:FindFirstChild("ThrowHit", true)
		if throwStart and throwStart:IsA("RemoteEvent") and throwHit and throwHit:IsA("RemoteEvent") then
			throwStart:FireServer(data.Origin, direction)
			Runtime:TrackTask(task.spawn(simulateProjectile, data.Origin, direction, data.Speed, character, throwHit))
			return true
		end
		local events = knife:FindFirstChild("Events")
		local legacy = events and events:FindFirstChild("KnifeThrown")
		if legacy and legacy:IsA("RemoteEvent") then
			legacy:FireServer(CFrame.new(data.Origin), CFrame.new(data.Aim))
			return true
		end
		local direct = knife:FindFirstChild("Throw")
		if direct and direct:IsA("RemoteEvent") then
			direct:FireServer(CFrame.new(data.Origin), data.Aim)
			return true
		end
		warnRemote()
		return false
	end

	function Combat:Update()
		if self.Destroyed or not self.AutoAttack and not self.AutoThrow then return end
		local character, _, root, knife, profiles = getContext()
		if not character or not knife or not profiles then return end
		local now = os.clock()
		if self.AutoAttack and now - self.LastStab >= MELEE_COOLDOWN then
			local target = chooseMelee(character, root, knife, profiles)
			if target and tryStab(knife, target) then self.LastStab = now end
		end
		if self.AutoThrow and now - self.LastThrow >= THROW_COOLDOWN then
			local selected = chooseThrow(character, root, knife, profiles)
			if selected and tryThrow(knife, selected, character) then self.LastThrow = now end
		end
	end

	function Combat:SetAutoAttack(value) self.AutoAttack = value == true end
	function Combat:SetAutoThrow(value) self.AutoThrow = value == true end
	function Combat:SetAttackTargets(mode)
		if mode == "All" or mode == "Sheriff/Hero" or mode == "Innocent" then self.AttackTargets = mode end
	end
	function Combat:SetThrowTargets(mode)
		if mode == "Auto" or mode == "Sheriff/Hero" or mode == "Innocent" or mode == "Nearest" then self.ThrowTargets = mode end
	end
	function Combat:Destroy()
		self.Destroyed = true
		self.AutoAttack = false
		self.AutoThrow = false
		self.RoleData = nil
		table.clear(self.Motion)
	end

	Runtime:TrackTask(task.spawn(function()
		while not Combat.Destroyed and not Runtime.ShuttingDown do
			local ok, err = pcall(function() Combat:Update() end)
			if not ok then warn("[Chorus MM2] Murder Combat: " .. tostring(err)) end
			task.wait(UPDATE_INTERVAL)
		end
	end))
	Runtime:OnShutdown(function() Combat:Destroy() end)
	return Combat
end
