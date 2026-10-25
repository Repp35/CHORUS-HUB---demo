-- [[ maptools ]]

return function(API)
	local Player = API.Player; local Services = API.Roblox; local Runtime = API.Runtime; local MatchService = API.Services.Match
	local MapTools = {
		FavoriteMaps = {},
		MoveGeneration = 0,
		MoveThread = nil,
		VoteThread = nil,
		ManualMoveUntil = 0,
		IsWalking = false,
		MovementOwner = nil,
	}

	local function notify(content)
		local window = API.UI and API.UI.Window; local library = window and window.OrionLib
		if library and type(library.MakeNotification) == "function" then pcall(library.MakeNotification, library, { Name = "Map", Content = content, Time = 4 }) end
	end
	local function allowAntiFlingTeleport()
		local antiFling = API.Features.AntiFling
		if antiFling and type(antiFling.AllowTeleport) == "function" then antiFling:AllowTeleport(0.35) end
	end
	local function getTeleportContext()
		local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			not character
			or not character:IsDescendantOf(Services.Workspace)
			or not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA("BasePart")
		then
			return nil
		end
		return character
	end
	local function getMovementContext()
		local inRound = MatchService:GetRoundContext(); local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			inRound and Player:GetAttribute("Alive") ~= true
			or not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA("BasePart")
		then
			return nil
		end
		return character, humanoid, root, inRound == true
	end
	local function getLiveTarget(target, requireAliveAttribute)
		if not target or target == Player or requireAliveAttribute and target:GetAttribute("Alive") ~= true then return nil end
		local character = target.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			not character
			or not character:IsDescendantOf(Services.Workspace)
			or not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA("BasePart")
		then
			return nil
		end
		return character, humanoid, root
	end
	local function isProfileLive(target, profile)
		return type(profile) == "table"
			and profile.Dead ~= true
			and profile.Killed ~= true
			and target:GetAttribute("Alive") == true
			and getLiveTarget(target, true) ~= nil
	end
	function MapTools:GetPlayerOptions()
		local names = { "None" }
		for _, target in ipairs(Services.Players:GetPlayers()) do
			if target ~= Player then table.insert(names, target.Name) end
		end
		table.sort(names, function(left, right)
			if left == "None" then return true end
			if right == "None" then return false end
			return left:lower() < right:lower()
		end)
		return names
	end
	function MapTools:GetFavoriteMapOptions()
		local options = { "None" }; local seen = { None = true }
		for _, favourite in ipairs(self.FavoriteMaps) do
			if not seen[favourite] then seen[favourite] = true; table.insert(options, favourite) end
		end
		for _, entry in ipairs(self:GetVoteBoard()) do
			if not seen[entry.Name] then seen[entry.Name] = true; table.insert(options, entry.Name) end
		end
		table.sort(options, function(left, right)
			if left == "None" then return true end
			if right == "None" then return false end
			return left:lower() < right:lower()
		end)
		return options
	end
	function MapTools:TeleportToMap()
		local _, map = MatchService:GetRoundContext(); local character = getTeleportContext()
		if not map or not map.Parent then notify("Não há um mapa carregado no momento."); return false end
		if not character then notify("Seu personagem não está disponível para teleportar."); return false end
		local spawns = map:FindFirstChild("Spawns"); local spawn = spawns and spawns:FindFirstChildWhichIsA("BasePart", true)
		if not spawn then notify("Não encontrei um ponto de spawn no mapa."); return false end
		local ok = pcall(function() character:PivotTo(spawn.CFrame) end)
		if not ok then notify("Não foi possível teleportar para o mapa."); return false end
		allowAntiFlingTeleport(); notify("Teleportado para " .. tostring(map:GetAttribute("MapID")) .. "."); return true
	end
	function MapTools:TeleportToLobby()
		local lobby = Services.Workspace:FindFirstChild("RegularLobby"); local character = getTeleportContext()
		if not lobby then notify("Não encontrei o lobby."); return false end
		if not character then notify("Seu personagem não está disponível para teleportar."); return false end
		local spawn = lobby:FindFirstChildWhichIsA("SpawnLocation", true)
		if not spawn then
			for _, name in ipairs({ "LobbySpawn", "Spawn", "SpawnLocation", "SpawnPoint" }) do
				local candidate = lobby:FindFirstChild(name, true)
				if candidate and candidate:IsA("BasePart") then spawn = candidate; break end
			end
		end
		local destination
		if spawn then
			destination = spawn.CFrame + Vector3.new(0, 3, 0)
		elseif lobby:IsA("Model") or lobby:IsA("BasePart") then
			destination = lobby:GetPivot() + Vector3.new(0, 3, 0)
		else
			local part = lobby:FindFirstChildWhichIsA("BasePart", true)
			if part then destination = part.CFrame + Vector3.new(0, 3, 0) end
		end
		if not destination then notify("Não encontrei um ponto válido no lobby."); return false end
		local ok = pcall(function() character:PivotTo(destination) end)
		if not ok then notify("Não foi possível teleportar para o lobby."); return false end
		allowAntiFlingTeleport(); notify("Teleportado para o lobby."); return true
	end
	function MapTools:FindRoleTarget(role, includeHero)
		local data = MatchService:GetPlayerData()
		if not data then return nil end
		for name, profile in pairs(data) do
			if
				type(name) == "string"
				and type(profile) == "table"
				and (profile.Role == role or includeHero and role == "Sheriff" and profile.Role == "Hero")
			then
				local target = Services.Players:FindFirstChild(name)
				if target and isProfileLive(target, profile) then return target end
			end
		end
		return nil
	end
	function MapTools:FindGunHolder()
		local data = MatchService:GetPlayerData() or {}
		for _, target in ipairs(Services.Players:GetPlayers()) do
			local profile = data[target.Name]
			if target ~= Player and isProfileLive(target, profile) then
				local character = target.Character; local backpack = target:FindFirstChildOfClass("Backpack")
				if character:FindFirstChild("Gun") or backpack and backpack:FindFirstChild("Gun") then return target end
			end
		end
		return nil
	end
	function MapTools:TeleportToPlayer(target)
		local character = getTeleportContext()
		if not character then notify("Seu personagem não está disponível para teleportar."); return false end
		local targetCharacter, _, targetRoot = getLiveTarget(target, true)
		if not targetCharacter then notify("Escolha outro jogador vivo."); return false end
		local ok = pcall(function() character:PivotTo(targetRoot.CFrame * CFrame.new(0, 0, 3)) end)
		if not ok then notify("Não foi possível teleportar até o jogador."); return false end
		allowAntiFlingTeleport(); notify("Teleportado até " .. target.DisplayName .. "."); return true
	end
	function MapTools:TeleportToRole(role)
		local target
		if role == "GunHolder" then target = self:FindGunHolder()
		else target = self:FindRoleTarget(role, role == "Sheriff") end
		if not target then
			notify(
				role == "GunHolder" and "Não encontrei alguém vivo com a arma." or "Não encontrei esse papel vivo."
			)
			return false
		end
		return self:TeleportToPlayer(target)
	end
	function MapTools:StopMovement(owner)
		if owner and self.MovementOwner ~= owner then return end
		self.MoveGeneration += 1; local thread = self.MoveThread; self.MoveThread = nil
		if thread then pcall(task.cancel, thread) end
		local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then pcall(function() humanoid:MoveTo(root.Position) end) end
		end
		self.IsWalking = false; self.MovementOwner = nil
	end
	function MapTools:WalkToPosition(destination, label, manual, isTargetValid)
		local character, humanoid, root, startedInRound = getMovementContext()
		if not character then notify("Você precisa estar vivo para caminhar."); return false end
		self:StopMovement(); self.MoveGeneration += 1; local generation = self.MoveGeneration; self.IsWalking = true
		self.MovementOwner = manual and "manual" or "vote"
		if manual then self.ManualMoveUntil = os.clock() + 25 end
		local thread
		thread = task.defer(function()
			pcall(function()
				local path = Services.PathfindingService:CreatePath({
					AgentRadius = 2,
					AgentHeight = 5,
					AgentCanJump = true,
					WaypointSpacing = 4,
				})

				local computed = pcall(function() path:ComputeAsync(root.Position, destination) end)
				if not computed or path.Status ~= Enum.PathStatus.Success then notify("Não encontrei um caminho até " .. label .. "."); return end
				for _, waypoint in ipairs(path:GetWaypoints()) do
					if
						self.MoveGeneration ~= generation
						or Player.Character ~= character
						or startedInRound ~= (MatchService:GetRoundContext() == true)
						or startedInRound and Player:GetAttribute("Alive") ~= true
						or humanoid.Health <= 0
						or isTargetValid and not isTargetValid()
					then
						return
					end
					if waypoint.Action == Enum.PathWaypointAction.Jump then
						pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
					end
					humanoid:MoveTo(waypoint.Position); local deadline = os.clock()
						+ math.max(
							(root.Position - waypoint.Position).Magnitude / math.max(humanoid.WalkSpeed, 1) + 2,
							3
						)
					while
						self.MoveGeneration == generation
						and (root.Position - waypoint.Position).Magnitude > 3
						and os.clock() < deadline
						and startedInRound == (MatchService:GetRoundContext() == true)
						and (not startedInRound or Player:GetAttribute("Alive") == true)
						and (not isTargetValid or isTargetValid())
					do
						Services.RunService.Heartbeat:Wait()
					end
					if self.MoveGeneration ~= generation then return end
					if isTargetValid and not isTargetValid() then notify("O jogador não está mais disponível."); return end
					if (root.Position - waypoint.Position).Magnitude > 3 then notify("O caminho até " .. label .. " foi interrompido."); return end
				end
				if self.MoveGeneration == generation then notify("Você chegou até " .. label .. ".") end
			end)
			if self.MoveGeneration == generation then self.MoveThread = nil; self.IsWalking = false; self.MovementOwner = nil end
		end)
		self.MoveThread = Runtime:TrackTask(thread); return true
	end
	function MapTools:WalkToPlayer(target)
		local inRound = MatchService:GetRoundContext(); local targetCharacter, _, targetRoot = getLiveTarget(target, inRound)
		if not targetCharacter then notify("Escolha outro jogador vivo."); return false end
		return self:WalkToPosition(
			targetRoot.Position + Vector3.new(0, 0, 3),
			target.DisplayName,
			true,
			function() return getLiveTarget(target, inRound) ~= nil end
		)
	end
	local function normalizeMapName(value) return string.lower(tostring(value)):gsub("[%s%d_%-]", "") end
	function MapTools:GetVoteBoard()
		local lobby = Services.Workspace:FindFirstChild("RegularLobby"); local pads = lobby and lobby:FindFirstChild("VotePads")
		if not lobby or not pads then return {} end
		local board = {}
		for index = 1, 3 do
			local pad = lobby:FindFirstChild("VotePad" .. index); local detector = pads:FindFirstChild("Detector" .. index)
			local mapName
			if pad and detector and detector:IsA("BasePart") then
				for _, descendant in ipairs(pad:GetDescendants()) do
					if descendant:IsA("TextLabel") and descendant.Name == "MapName" then mapName = descendant.Text; break end
				end
				if mapName and mapName ~= "" and mapName ~= "MAP NAME" then table.insert(board, { Name = mapName, Detector = detector }) end
			end
		end
		return board
	end
	function MapTools:FindFavouriteVote(board)
		for _, favourite in ipairs(self.FavoriteMaps) do
			local wanted = normalizeMapName(favourite)
			for _, entry in ipairs(board) do
				local candidate = normalizeMapName(entry.Name)
				if
					candidate == wanted
					or wanted ~= "" and (candidate:find(wanted, 1, true) or wanted:find(candidate, 1, true))
				then
					return entry
				end
			end
		end
		return nil
	end
	function MapTools:VoteLoop()
		if self.VoteThread or Runtime.ShuttingDown then return end
		local thread
		thread = task.defer(function()
			while #self.FavoriteMaps > 0 and not Runtime.ShuttingDown do
				if not MatchService:GetRoundContext() and os.clock() >= self.ManualMoveUntil then
					local entry = self:FindFavouriteVote(self:GetVoteBoard()); local character, humanoid, root = getMovementContext()
					if
						entry
						and character
						and humanoid
						and not self.IsWalking
						and (root.Position - entry.Detector.Position).Magnitude > 4.5
					then
						self:WalkToPosition(entry.Detector.Position, "a votação de " .. entry.Name, false)
					end
				end
				task.wait(2)
			end
			if self.VoteThread == thread then self.VoteThread = nil end
		end)
		self.VoteThread = Runtime:TrackTask(thread)
	end
	function MapTools:SetFavoriteMaps(favorites)
		self.FavoriteMaps = {}
		if type(favorites) == "string" and favorites ~= "" and favorites ~= "None" and favorites ~= "Nenhum" then
			table.insert(self.FavoriteMaps, favorites)
		elseif type(favorites) == "table" then
			for _, name in ipairs(favorites) do
				if type(name) == "string" and name ~= "" then table.insert(self.FavoriteMaps, name) end
			end
		end
		if #self.FavoriteMaps > 0 then
			self:VoteLoop()
		else
			if self.VoteThread then pcall(task.cancel, self.VoteThread); self.VoteThread = nil end
			self:StopMovement("vote")
		end
	end
	Runtime:OnShutdown(function()
		MapTools:StopMovement()
		if MapTools.VoteThread then pcall(task.cancel, MapTools.VoteThread); MapTools.VoteThread = nil end
	end)

	return MapTools
end
