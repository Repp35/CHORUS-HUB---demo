-- [[ autogunpickup ]]

return function(API)
	local Services = API.Roblox; local Player = API.Player; local Runtime = API.Runtime; local Util = API.Util
	local MatchService = API.Services.Match; local Workspace = Services.Workspace; local ReplicatedStorage = Services.ReplicatedStorage; local PathfindingService = Services.PathfindingService
	local GUN_DROP_TAG = "GunDrop"; local SCAN_INTERVAL = 0.12; local ROLE_REFRESH_INTERVAL = 0.75; local RETRY_DELAY = 0.8
	local KNIFE_REACH = 12; local MIN_SAFE_GAP = KNIFE_REACH * 1.6; local RUN_SPEED_FLOOR = 16; local DEFAULT_THROW_REACH = 70

	-- State
	local Pickup = {
		Enabled = false,
		Busy = false,
		SafetyEnabled = false,
		Thread = nil,
		Generation = 0,
		ActiveMap = nil,
		ActiveHumanoid = nil,
		ActiveRoot = nil,
		Touching = false,
		RoleData = nil,
		RoleDataAt = 0,
		NextRoleRefreshAt = 0,
		NextAttemptAt = 0,
		RetryAfter = setmetatable({}, { __mode = "k" }),
		Failures = setmetatable({}, { __mode = "k" }),
		ThreatPathCache = nil,
		HuntRoot = nil,
		HuntGap = nil,
		HuntGapAt = 0,
		HuntUntil = 0,
		ObservedThrowDistance = nil,
		ThrowObservedAt = 0,
		KnifeThrownConnection = nil,
		PlayerDataConnection = nil,
		LastErrorAt = 0,
	}

	-- ExecutorInput
	local function getTouchFunction()
		local ok, touchFunction = pcall(function() return firetouchinterest end)
		if ok and type(touchFunction) == "function" then return touchFunction end
		return nil
	end

	-- Diagnostics
	function Pickup:ReportError(context, errorMessage)
		local now = os.clock()
		if now - self.LastErrorAt < 5 then return end
		self.LastErrorAt = now; warn("[Chorus MM2] Auto Pick Up Gun recuperando após erro em " .. context .. ": " .. tostring(errorMessage))
	end

	-- MapBounds
	local boundsCache = setmetatable({}, { __mode = "k" })
	local function pointInModel(model, position, padding)
		if not model or not model:IsA("Model") or not Util.IsFiniteVector3(position) then return nil end
		local now = os.clock(); local bounds = boundsCache[model]
		if not bounds or now - bounds.At > 3 then
			local ok, cframe, size = pcall(function() return model:GetBoundingBox() end)
			if not ok or not cframe or not size then boundsCache[model] = nil; return nil end
			bounds = { CFrame = cframe, Size = size, At = now }; boundsCache[model] = bounds
		end
		local point = bounds.CFrame:PointToObjectSpace(position); padding = math.max(tonumber(padding) or 0, 0); return math.abs(point.X) <= bounds.Size.X * 0.5 + padding
			and math.abs(point.Y) <= bounds.Size.Y * 0.5 + padding
			and math.abs(point.Z) <= bounds.Size.Z * 0.5 + padding
	end
	local function isInLobby(position)
		local lobby = Workspace:FindFirstChild("RegularLobby")
		if not lobby then return false end
		return pointInModel(lobby, position, 20) ~= false
	end

	-- RoleData
	function Pickup:GetRoleData()
		local now = os.clock()
		if self.RoleData and now < self.NextRoleRefreshAt then return self.RoleData end
		self.NextRoleRefreshAt = now + ROLE_REFRESH_INTERVAL; local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
		if remote and remote:IsA("RemoteFunction") then
			local ok, data = pcall(function() return remote:InvokeServer() end)
			if ok and type(data) == "table" and next(data) ~= nil then self.RoleData = data; self.RoleDataAt = now; return data end
		end
		self.RoleData = nil; self.RoleDataAt = 0; return nil
	end
	local function isProfileDead(profile)
		return type(profile) ~= "table" or profile.Dead == true or profile.Killed == true
	end
	function Pickup:GetActiveContext()
		local active, map, container = MatchService:GetRoundContext()
		local character = Player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not active or not map or not container or not character or not humanoid or humanoid.Health <= 0
			or not root or not root:IsA("BasePart") or not character:IsDescendantOf(Workspace) then return false end
		if Player:GetAttribute("Alive") == false then return false end
		local roleData = self:GetRoleData()
		local profile = roleData and roleData[Player.Name]
		if type(profile) == "table" and (profile.Role == "Murderer" or profile.Dead == true or profile.Killed == true) then return false end
		if self.ActiveMap ~= map then
			self.ActiveMap = map; self.NextAttemptAt = 0
			self.RetryAfter = setmetatable({}, { __mode = "k" })
			self.Failures = setmetatable({}, { __mode = "k" })
		end
		return true, character, humanoid, root, container, map, roleData
	end

	-- Inventory
	function Pickup:HasGun(character)
		if character and character:FindFirstChild("Gun") then return true end
		local backpack = Player:FindFirstChildOfClass("Backpack"); return backpack ~= nil and backpack:FindFirstChild("Gun") ~= nil
	end
	function Pickup:HasKnife(character)
		if character and character:FindFirstChild("Knife") then return true end
		local backpack = Player:FindFirstChildOfClass("Backpack"); return backpack ~= nil and backpack:FindFirstChild("Knife") ~= nil
	end

	-- GunLookup
	local function getGunPart(instance)
		if not instance or not instance.Parent or not instance:IsDescendantOf(Workspace) then return nil end
		if instance:IsA("BasePart") then return instance end
		if instance:IsA("Model") then return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true) end
		return instance:FindFirstChildWhichIsA("BasePart", true)
	end
	local function gunStillThere(gun) return gun ~= nil and gun.Parent ~= nil and gun:IsDescendantOf(Workspace) end
	function Pickup:GetNearestDroppedGun(root)
		local nearest, nearestPart, nearestDistance
		for _, gun in ipairs(Services.CollectionService:GetTagged(GUN_DROP_TAG)) do
			local part = getGunPart(gun)
			if part then
				local distance = (root.Position - part.Position).Magnitude
				if not nearestDistance or distance < nearestDistance then
					nearest, nearestPart, nearestDistance = gun, part, distance
				end
			end
		end
		return nearest, nearestPart, nearestDistance
	end

	-- ThreatGeometry
	local function flatDistance(from, to) return Vector3.new(from.X - to.X, 0, from.Z - to.Z).Magnitude end
	local function makeThreatRayParams(threatRoot)
		local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {
			Player.Character,
			threatRoot and threatRoot.Parent,
		}

		params.RespectCanCollide = true; return params
	end
	function Pickup:GetThreatGap(position, threatRoot)
		if not threatRoot or not threatRoot.Parent or not Util.IsFiniteVector3(position) then return math.huge end
		local delta = threatRoot.Position - position; local flat = flatDistance(position, threatRoot.Position); local vertical = math.abs(delta.Y)
		if vertical < 6 then return flat end
		if threatRoot.Position.Y > position.Y - 2 and vertical < 40 then return flat + vertical * 0.5 end
		local distance = flat + vertical * 3
		if flat < 80 then
			local rayOk, obstruction = pcall(
				function() return Workspace:Raycast(threatRoot.Position, -delta, makeThreatRayParams(threatRoot)) end
			)
			if rayOk and obstruction then distance += 40 end
		end
		return distance
	end
	local function gapToRoute(from, to, threatRoot)
		local a = Vector3.new(from.X, 0, from.Z); local b = Vector3.new(to.X, 0, to.Z); local threat = Vector3.new(threatRoot.Position.X, 0, threatRoot.Position.Z); local segment = b - a
		local length = segment.Magnitude
		local gap
		if length < 0.01 then gap = (threat - a).Magnitude
		else local along = math.clamp((threat - a):Dot(segment) / (length * length), 0, 1); gap = (threat - (a + segment * along)).Magnitude end
		if math.abs(threatRoot.Position.Y - from.Y) >= 6 then gap += 30 end
		return gap
	end
	function Pickup:GetThrowReach()
		if self.ObservedThrowDistance and os.clock() - self.ThrowObservedAt <= 30 then return math.clamp(self.ObservedThrowDistance * 1.15, KNIFE_REACH + 6, 250) end
		return DEFAULT_THROW_REACH
	end
	function Pickup:CanMurdererSee(position, threatRoot)
		if not threatRoot or not threatRoot.Parent then return false end
		local params = makeThreatRayParams(threatRoot)
		for _, lift in ipairs({ 1.5, 0, 3 }) do
			local start = threatRoot.Position + Vector3.new(0, 1.5, 0); local destination = position + Vector3.new(0, lift, 0)
			local ok, obstruction = pcall(function() return Workspace:Raycast(start, destination - start, params) end)
			if ok and not obstruction then return true end
		end
		return false
	end
	function Pickup:IsMurdererDangerous(position, threatRoot)
		local gap = self:GetThreatGap(position, threatRoot)
		if gap < KNIFE_REACH + 8 then return true end
		return gap < self:GetThrowReach() and self:CanMurdererSee(position, threatRoot)
	end

	-- MurdererLookup
	function Pickup:GetMurdererRoot(character, root, map, roleData)
		if self:HasKnife(character) then return nil end
		roleData = roleData or self:GetRoleData()
		if not roleData then return nil end
		for playerName, profile in pairs(roleData) do
			if
				playerName ~= Player.Name
				and type(profile) == "table"
				and profile.Role == "Murderer"
				and not isProfileDead(profile)
			then
				local target = Services.Players:FindFirstChild(playerName); local targetCharacter = target and target.Character
				local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid"); local threatRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
				if
					target
					and target:GetAttribute("Alive") ~= false
					and targetHumanoid
					and targetHumanoid.Health > 0
					and threatRoot
					and threatRoot:IsA("BasePart")
					and threatRoot:IsDescendantOf(Workspace)
					and pointInModel(map, threatRoot.Position, 20) == true
					and not isInLobby(threatRoot.Position)
				then
					if self:HasGun(character) and self:GetThreatGap(root.Position, threatRoot) >= KNIFE_REACH + 6 then return nil end
					return target, threatRoot
				end
			end
		end
		return nil
	end
	function Pickup:GetMurdererPace(threatRoot)
		if not threatRoot or not threatRoot.Parent then return RUN_SPEED_FLOOR end
		local velocity = threatRoot.AssemblyLinearVelocity; return math.max(RUN_SPEED_FLOOR, Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
	end
	function Pickup:IsMurdererHunting(root, threatRoot)
		if not threatRoot or not threatRoot.Parent then self.HuntRoot = nil; self.HuntGap = nil; self.HuntUntil = 0; return false end
		local now = os.clock(); local gap = self:GetThreatGap(root.Position, threatRoot)
		if self.HuntRoot ~= threatRoot then self.HuntRoot = threatRoot; self.HuntGap = gap; self.HuntGapAt = now end
		local toward = Vector3.new(root.Position.X - threatRoot.Position.X, 0, root.Position.Z - threatRoot.Position.Z); local velocity = threatRoot.AssemblyLinearVelocity
		local heading = Vector3.new(velocity.X, 0, velocity.Z)
		if heading.Magnitude <= 4 then
			local look = threatRoot.CFrame.LookVector
			heading = Vector3.new(look.X, 0, look.Z)
		end
		local facing = heading.Magnitude > 0.1 and toward.Magnitude > 0.01 and heading.Unit:Dot(toward.Unit) > 0.5
		local shrinking = now - self.HuntGapAt < 3 and self.HuntGap ~= nil and gap < self.HuntGap - 1; self.HuntGap = gap; self.HuntGapAt = now
		if (facing and shrinking) or self:IsMurdererDangerous(root.Position, threatRoot) then self.HuntUntil = now + 4; return true end
		return now < self.HuntUntil
	end

	-- Navigation
	local function createPath(from, to)
		local ok, path = pcall(
			function()
				return PathfindingService:CreatePath({
					AgentRadius = 2,
					AgentHeight = 5,
					AgentCanJump = true,
					AgentCanClimb = true,
					WaypointSpacing = 4,
				})
			end
		)
		if not ok or not path then return nil end
		local computeOk = pcall(function() path:ComputeAsync(from, to) end)
		if not computeOk or path.Status ~= Enum.PathStatus.Success then return nil end
		local waypointsOk, waypoints = pcall(function() return path:GetWaypoints() end)
		if not waypointsOk or type(waypoints) ~= "table" or #waypoints == 0 then return nil end
		return waypoints
	end
	local function pathLength(from, waypoints)
		local length = 0; local previous = from
		for _, waypoint in ipairs(waypoints) do
			length += (waypoint.Position - previous).Magnitude; previous = waypoint.Position
		end
		return length
	end
	function Pickup:GetThreatWalkDistance(threatRoot, gun, map)
		local now = os.clock(); local cache = self.ThreatPathCache
		if
			cache
			and cache.ThreatRoot == threatRoot
			and cache.Gun == gun
			and cache.Map == map
			and now - cache.At < 0.6
		then
			return cache.Distance
		end
		local part = getGunPart(gun); local distance = math.huge
		if part and threatRoot and threatRoot.Parent then
			local waypoints = createPath(threatRoot.Position, part.Position + Vector3.new(0, 2, 0))
			if waypoints then distance = pathLength(threatRoot.Position, waypoints) end
		end
		self.ThreatPathCache = {
			ThreatRoot = threatRoot,
			Gun = gun,
			Map = map,
			At = now,
			Distance = distance,
		}
		return distance
	end
	function Pickup:IsRouteSafe(waypoints, from, humanoid, threatRoot, firstWaypoint)
		if not self.SafetyEnabled or not threatRoot then return true end
		local chased = self.ActiveRoot ~= nil and self:IsMurdererHunting(self.ActiveRoot, threatRoot) or false; local speed = math.max(RUN_SPEED_FLOOR, tonumber(humanoid.WalkSpeed) or RUN_SPEED_FLOOR)
		local previous = from; local walked = 0
		for index = firstWaypoint or 1, #waypoints do
			local position = waypoints[index].Position; walked += (position - previous).Magnitude; previous = position; local murdererDistance = self:GetThreatGap(position, threatRoot)
			if murdererDistance < MIN_SAFE_GAP then return false end
			local myTime = walked / speed; local murdererTime = murdererDistance / self:GetMurdererPace(threatRoot); local margin = chased and 0.5 or 0.15
			if murdererTime <= myTime + margin then return false end
		end
		return true
	end

	-- SafetyChecks
	function Pickup:IsSafeToApproach(root, humanoid, gun, gunPart, map, roleData, waypoints)
		if not self.SafetyEnabled then return true, nil end
		local _, threatRoot = self:GetMurdererRoot(Player.Character, root, map, roleData)
		if not threatRoot then return true, nil end
		local gunDistance = waypoints and pathLength(root.Position, waypoints)
			or (root.Position - gunPart.Position).Magnitude
		local threatToPlayer = self:GetThreatGap(root.Position, threatRoot); local threatToGun = self:GetThreatGap(gunPart.Position, threatRoot)
		local directThreatToGun = (threatRoot.Position - gunPart.Position).Magnitude; local lineGap = gapToRoute(root.Position, gunPart.Position, threatRoot)
		local murdererPathDistance = self:GetThreatWalkDistance(threatRoot, gun, map)
		if
			self:IsMurdererDangerous(root.Position, threatRoot)
			or self:IsMurdererDangerous(gunPart.Position, threatRoot)
		then
			return false, threatRoot
		end
		if threatToPlayer < math.max(40, gunDistance) then return false, threatRoot end
		if threatToGun < 45 or lineGap < 25 or directThreatToGun < 30 or murdererPathDistance < 60 then return false, threatRoot end
		if waypoints and not self:IsRouteSafe(waypoints, root.Position, humanoid, threatRoot) then return false, threatRoot end
		return true, threatRoot
	end
	function Pickup:ShouldReplan(root, gunPart, threatRoot)
		if not self.SafetyEnabled or not threatRoot then return false end
		return self:GetThreatGap(root.Position, threatRoot) < 40
			or gapToRoute(root.Position, gunPart.Position, threatRoot) < 25
			or self:IsMurdererDangerous(root.Position, threatRoot)
	end

	-- RouteMovement
	function Pickup:RouteStillValid(character, humanoid, root, container, map, gun, requireGun)
		if
			not self.Enabled
			or Runtime.ShuttingDown
			or Player.Character ~= character
			or not character.Parent
			or not humanoid.Parent
			or humanoid.Health <= 0
			or not root.Parent
			or Player:GetAttribute("Alive") ~= true
			or self:HasGun(character)
			or container.Parent ~= map
			or map.Parent ~= Workspace
			or map:GetAttribute("MapID") == nil
			or pointInModel(map, root.Position, 20) ~= true
			or isInLobby(root.Position)
			or requireGun and not gunStillThere(gun)
		then
			return false
		end
		local roleData = self:GetRoleData(); local profile = roleData and roleData[Player.Name]; return type(roleData) == "table"
			and type(profile) == "table"
			and profile.Role == "Innocent"
			and not isProfileDead(profile)
	end
	function Pickup:FollowWaypoints(character, humanoid, root, container, map, gun, waypoints, mode, generation)
		if #waypoints <= 1 then return "arrived" end
		local nextSafetyCheck = 0
		local lastEscapeGap
		for index = 2, #waypoints do
			local waypoint = waypoints[index]
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
			end
			humanoid:MoveTo(waypoint.Position); local segmentDistance = (root.Position - waypoint.Position).Magnitude
			local speed = math.max(RUN_SPEED_FLOOR, tonumber(humanoid.WalkSpeed) or RUN_SPEED_FLOOR); local deadline = os.clock() + math.max(segmentDistance / speed + 1.5, 2)
			while (root.Position - waypoint.Position).Magnitude > 3 do
				if mode == "pickup" and self:HasGun(character) then return "collected" end
				if
					self.Generation ~= generation
					or not self:RouteStillValid(character, humanoid, root, container, map, gun, mode == "pickup")
				then
					return "stopped"
				end
				if mode == "escape" and os.clock() - nextSafetyCheck > 0.15 and self.SafetyEnabled then
					nextSafetyCheck = os.clock(); local _, threatRoot = self:GetMurdererRoot(character, root, map)
					if threatRoot then
						local gap = self:GetThreatGap(root.Position, threatRoot)
						if lastEscapeGap and gap < lastEscapeGap - 4 then return "replan" end
						lastEscapeGap = gap
					end
				end
				if mode == "pickup" and self.SafetyEnabled and os.clock() >= nextSafetyCheck then
					nextSafetyCheck = os.clock() + 0.15; local _, threatRoot = self:GetMurdererRoot(character, root, map)
					if threatRoot then
						local currentGunPart = getGunPart(gun)
						if not currentGunPart then return "gone" end
						if self:ShouldReplan(root, currentGunPart, threatRoot) then return "replan" end
						if not self:IsRouteSafe(waypoints, root.Position, humanoid, threatRoot, index) then return "replan" end
					end
				end
				if os.clock() >= deadline then return "stuck" end
				Services.RunService.Heartbeat:Wait()
			end
		end
		return "arrived"
	end
	function Pickup:TryEscape(character, humanoid, root, container, map, threatRoot, generation)
		if not threatRoot or not threatRoot.Parent then return false end
		local here = root.Position; local initialGap = self:GetThreatGap(here, threatRoot)
		if initialGap >= 60 then return false end
		local away = Vector3.new(here.X - threatRoot.Position.X, 0, here.Z - threatRoot.Position.Z)
		if away.Magnitude < 0.01 then
			local look = root.CFrame.LookVector
			away = Vector3.new(-look.X, 0, -look.Z)
		end
		if away.Magnitude < 0.01 then return false end
		away = away.Unit
		local bestWaypoints, bestScore
		for _, angle in ipairs({ 0, 45, -45, 90, -90, 135, -135, 180 }) do
			local direction = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(away); local destination = here + direction * 32 + Vector3.new(0, 2, 0)
			if pointInModel(map, destination, 20) == true then
				local waypoints = createPath(here, destination)
				if waypoints then
					local previous = here; local previousGap = initialGap; local routeSafe = true
					for _, waypoint in ipairs(waypoints) do
						local gap = self:GetThreatGap(waypoint.Position, threatRoot)
						if gap < previousGap - 4 then routeSafe = false; break end
						previousGap = gap
					end
					local score = previousGap - pathLength(here, waypoints) * 0.2
					if routeSafe and previousGap > initialGap + 3 and (not bestScore or score > bestScore) then bestWaypoints = waypoints; bestScore = score end
				end
			end
		end
		if bestWaypoints then self:FollowWaypoints(character, humanoid, root, container, map, nil, bestWaypoints, "escape", generation); return true end
		local deadline = os.clock() + 0.4
		while
			os.clock() < deadline
			and self.Generation == generation
			and self:RouteStillValid(character, humanoid, root, container, map, nil, false)
		do
			humanoid:Move(away, false); Services.RunService.Heartbeat:Wait()
		end
		humanoid:Move(Vector3.zero, false); return true
	end

	-- ReferencePickup
	function Pickup:TryPickup()
		if self.Busy or not self.Enabled or Runtime.ShuttingDown or os.clock() < self.NextAttemptAt then return end
		local ready, character, humanoid, root = self:GetActiveContext()
		if not ready or self:HasGun(character) then return end
		local gun, part = self:GetNearestDroppedGun(root)
		if not gun or not part then return end
		local touch = getTouchFunction()
		if not touch then self:ReportError("touch", "firetouchinterest indisponível"); self.NextAttemptAt = os.clock() + 2; return end
		self.Busy = true
		local ok, err = pcall(function()
			touch(root, part, 0)
			Services.RunService.Heartbeat:Wait()
			touch(root, part, 1)
		end)
		self.Busy = false
		self.NextAttemptAt = os.clock() + (ok and 0.4 or 1)
		if not ok then self:ReportError("coleta", err) end
	end

	-- KnifeThrowObservation
	local function observeKnifeThrow()
		if Runtime.ShuttingDown then return end
		local _, character, _, root, _, map, roleData = Pickup:GetActiveContext()
		if not character or not root or not map then return end
		local _, threatRoot = Pickup:GetMurdererRoot(character, root, map, roleData)
		if not threatRoot then return end
		local distance = (root.Position - threatRoot.Position).Magnitude
		if distance < KNIFE_REACH or distance > 400 then return end
		local previous = Pickup.ObservedThrowDistance; Pickup.ObservedThrowDistance = previous and math.max(previous * 0.7 + distance * 0.3, distance) or distance; Pickup.ThrowObservedAt = os.clock()
	end
	local function connectKnifeThrown(generation)
		local ok, service = pcall(function()
			local clientServices = ReplicatedStorage:WaitForChild("ClientServices", 5); local module = clientServices and clientServices:WaitForChild("WeaponService", 5)
			if not module or not module:IsA("ModuleScript") then return nil end
			return require(module)
		end)
		if not ok or type(service) ~= "table" then return end
		if not Pickup.Enabled or Pickup.Generation ~= generation or Runtime.ShuttingDown then return end
		local signal = rawget(service, "KnifeThrown")
		if not signal then return end
		local connectOk, connection = pcall(function()
			if typeof(signal) == "Instance" and signal:IsA("BindableEvent") then return signal.Event:Connect(observeKnifeThrow) end
			return signal:Connect(observeKnifeThrow)
		end)
		if connectOk and connection then Pickup.KnifeThrownConnection = Runtime:Track(connection) end
	end
	local function connectPlayerDataChanges()
		local remote = ReplicatedStorage:FindFirstChild("PlayerDataChanged", true)
		if not remote or not remote:IsA("RemoteEvent") then return end
		local ok, connection = pcall(function()
			return remote.OnClientEvent:Connect(function(changes)
				if type(changes) ~= "table" then return end
				if not Pickup.RoleData then Pickup.NextRoleRefreshAt = 0; return end
				for playerName, profile in pairs(changes) do
					if type(playerName) == "string" and type(profile) == "table" then Pickup.RoleData[playerName] = profile end
				end
				Pickup.RoleDataAt = os.clock(); Pickup.NextRoleRefreshAt = Pickup.RoleDataAt + ROLE_REFRESH_INTERVAL
			end)
		end)
		if ok and connection then Pickup.PlayerDataConnection = Runtime:Track(connection) end
	end

	-- Lifecycle
	function Pickup:SetSafetyEnabled(enabled)
		self.SafetyEnabled = enabled == true; return self.SafetyEnabled
	end
	function Pickup:Start()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true; self.Generation += 1; self.NextAttemptAt = 0; self.NextRoleRefreshAt = 0
		local generation = self.Generation
		local thread
		thread = task.spawn(function()
			while self.Enabled and self.Generation == generation and not Runtime.ShuttingDown do
				local ok, errorMessage = xpcall(function() self:TryPickup() end, Util.FormatError)
				if not ok then self:ReportError("ciclo", errorMessage) end
				task.wait(SCAN_INTERVAL)
			end
			if self.Thread == thread then self.Thread = nil end
		end)
		self.Thread = thread; connectPlayerDataChanges(); local throwThread = task.spawn(connectKnifeThrown, generation); Runtime:TrackTask(throwThread)
	end
	function Pickup:Stop()
		self.Enabled = false; self.Generation += 1; self.NextAttemptAt = 0
		if self.KnifeThrownConnection then
			pcall(function() self.KnifeThrownConnection:Disconnect() end)
			self.KnifeThrownConnection = nil
		end
		if self.PlayerDataConnection then
			pcall(function() self.PlayerDataConnection:Disconnect() end)
			self.PlayerDataConnection = nil
		end
		self.ActiveHumanoid = nil; self.ActiveRoot = nil
	end
	Runtime:OnShutdown(function() Pickup:Stop() end)

	return Pickup
end
