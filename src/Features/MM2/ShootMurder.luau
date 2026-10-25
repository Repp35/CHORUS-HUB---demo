-- [[ shootmurder ]]

return function(API)
	local Players = API.Roblox.Players; local TweenService = API.Roblox.TweenService; local Workspace = API.Roblox.Workspace; local Player = API.Player
	local Runtime = API.Runtime; local MatchService = API.Services.Match; local Randomizer = Random.new(); local SHOT_COOLDOWN = 0.6
	local ROLE_REFRESH_INTERVAL = 0.45; local WORK_INTERVAL = 0.1; local FADE_TIME = 0.16; local EFFECT_TIME = 0.2
	local GUI_NAME = "ChorusManualShootMurder"
	local ShootMurder = {
		ManualEnabled = false,
		AutoEnabled = false,
		ManualAccuracy = 100,
		AutoAccuracy = 100,
		AllowOffscreen = true,
		WaitForKnife = false,
		RoleData = nil,
		NextRoleRefreshAt = 0,
		LastShotAt = 0,
		HudVisible = false,
		HudGeneration = 0,
		EffectGeneration = 0,
		Destroyed = false,
		Tweens = {},
	}

	local function getAliveCharacter(target, profile)
		if
			type(profile) ~= "table"
			or profile.Dead == true
			or profile.Killed == true
			or not target
			or target:GetAttribute("Alive") ~= true
		then
			return nil
		end
		local character = target.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			not character
			or not character:IsDescendantOf(Workspace)
			or not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA("BasePart")
		then
			return nil
		end
		return character, humanoid, root
	end
	function ShootMurder:RefreshRoleData(force)
		local now = os.clock()
		if not force and now < self.NextRoleRefreshAt then return self.RoleData end
		self.NextRoleRefreshAt = now + ROLE_REFRESH_INTERVAL; local ok, roleData = pcall(MatchService.GetPlayerData, MatchService); self.RoleData = ok and type(roleData) == "table" and roleData or nil
		return self.RoleData
	end
	function ShootMurder:GetLocalContext()
		local inRound = MatchService:GetRoundContext()
		if not inRound or Player:GetAttribute("Alive") ~= true then return nil end
		local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); local root = character and character:FindFirstChild("HumanoidRootPart")
		local profile = self.RoleData and self.RoleData[Player.Name]
		if
			type(profile) ~= "table"
			or profile.Role ~= "Sheriff"
			or profile.Dead == true
			or profile.Killed == true
			or not character
			or not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA("BasePart")
			or not character:IsDescendantOf(Workspace)
		then
			return nil
		end
		return character, humanoid, root
	end
	function ShootMurder:GetMurderer()
		if not self.RoleData then return nil end
		for _, target in ipairs(Players:GetPlayers()) do
			local profile = self.RoleData[target.Name]
			if target ~= Player and type(profile) == "table" and profile.Role == "Murderer" then
				local character, humanoid, root = getAliveCharacter(target, profile)
				if character then return target, character, humanoid, root end
			end
		end
		return nil
	end
	function ShootMurder:FindGun(character, humanoid)
		local gun = character:FindFirstChild("Gun")
		if gun then return gun end
		local backpack = Player:FindFirstChildOfClass("Backpack"); gun = backpack and backpack:FindFirstChild("Gun")
		if gun then
			pcall(function() humanoid:EquipTool(gun) end)
			return nil
		end
		return nil
	end
	function ShootMurder:GetClearAim(character, root, gun, localCharacter)
		local camera = Workspace.CurrentCamera; local originAttachment = root:FindFirstChild("GunRaycastAttachment")
		if not camera or not originAttachment or not originAttachment:IsA("Attachment") then return nil end
		local gunOrigin = originAttachment.WorldPosition; local viewportSize = camera.ViewportSize; local _, _, coinContainer = MatchService:GetRoundContext(); local ignored = { localCharacter, gun }
		if coinContainer then table.insert(ignored, coinContainer) end
		for _, instance in ipairs(Services.CollectionService:GetTagged("WeaponPassthrough")) do
			table.insert(ignored, instance)
		end
		local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = ignored; params.IgnoreWater = true
		local function weaponRay(from, to)
			local direction = to - from
			for _ = 1, 24 do
				local hit = Workspace:Raycast(from, direction, params)
				if not hit then return nil end
				if
					not hit.Instance:IsA("BasePart")
					or hit.Instance.Transparency ~= 1
					or table.find(ignored, hit.Instance)
				then
					return hit
				end
				table.insert(ignored, hit.Instance); params.FilterDescendantsInstances = ignored
			end
			return nil
		end
		local side = root.Position - gunOrigin; side = Vector3.new(-side.Z, 0, side.X); side = side.Magnitude > 0.01 and side.Unit * 1.1 or Vector3.zero
		local candidates =
			{ root.Position, root.Position + Vector3.new(0, 1.3, 0), root.Position + side, root.Position - side }
		local head = character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then table.insert(candidates, 2, head.Position) end
		local localHead = localCharacter:FindFirstChild("Head")
		for _, point in ipairs(candidates) do
			local viewportPoint, onScreen = camera:WorldToViewportPoint(point); local visibleOnScreen = onScreen
				and viewportPoint.Z > 0
				and viewportPoint.X >= 0
				and viewportPoint.Y >= 0
				and viewportPoint.X <= viewportSize.X
				and viewportPoint.Y <= viewportSize.Y
			if self.AllowOffscreen or visibleOnScreen then
				local ray = point - gunOrigin; local across = Vector3.new(-ray.Z, 0, ray.X); across = across.Magnitude > 0.01 and across.Unit * 0.9 or Vector3.zero
				local function hitsTarget(from, to)
					local hit = weaponRay(from, to); return hit ~= nil and hit.Instance:IsDescendantOf(character), hit and hit.Position
				end
				local centered, hitPosition = hitsTarget(gunOrigin, point); local left = centered and hitsTarget(gunOrigin + across, point)
				local right = left and hitsTarget(gunOrigin - across, point); local eyeClear = not localHead or hitsTarget(localHead.Position, point)
				if centered and left and right and eyeClear then return hitPosition end
			end
		end
		return nil
	end
	function ShootMurder:GetShotPoint(hitPosition, accuracy)
		accuracy = math.clamp(tonumber(accuracy) or 100, 0, 100); local inaccuracy = (100 - accuracy) / 100
		if inaccuracy <= 0 then return hitPosition end
		local likelyMiss = Randomizer:NextNumber() < inaccuracy * 0.45; local radius = likelyMiss and (2 + inaccuracy * 6) or (inaccuracy * 0.65)
		local direction =
			Vector3.new(Randomizer:NextNumber(-1, 1), Randomizer:NextNumber(-1, 1), Randomizer:NextNumber(-1, 1))
		if direction.Magnitude <= 0.001 then direction = Vector3.xAxis end
		return hitPosition + direction.Unit * radius
	end
	function ShootMurder:CancelTweens()
		for _, tween in ipairs(self.Tweens) do
			pcall(function() tween:Cancel() end)
		end
		table.clear(self.Tweens)
	end
	function ShootMurder:TweenHud(properties, duration)
		local button = self.Button; local stroke = self.Stroke
		if not button or not stroke then return end
		self:CancelTweens(); local info = TweenInfo.new(duration or FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for instance, goals in pairs({ [button] = properties.Button or {}, [stroke] = properties.Stroke or {} }) do
			local tween = TweenService:Create(instance, info, goals); table.insert(self.Tweens, tween); tween:Play()
		end
	end
	function ShootMurder:EnsureHud()
		if self.ScreenGui and self.ScreenGui.Parent then return end
		local playerGui = Player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then return end
		local oldGui = playerGui:FindFirstChild(GUI_NAME)
		if oldGui then oldGui:Destroy() end
		local screenGui = Instance.new("ScreenGui"); screenGui.Name = GUI_NAME; screenGui.ResetOnSpawn = false; screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = 100; screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; local button = Instance.new("TextButton"); button.Name = "ShootMurderButton"
		button.AnchorPoint = Vector2.new(1, 1); button.Position = UDim2.new(1, -145, 1, -170); button.Size = UDim2.fromOffset(65, 65); button.BackgroundColor3 = Color3.fromRGB(70, 170, 100)
		button.BackgroundTransparency = 1; button.BorderSizePixel = 0; button.AutoButtonColor = true; button.Font = Enum.Font.GothamBold
		button.Text = "🔫"; button.TextSize = 30; button.TextTransparency = 1; button.Parent = screenGui
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 15); corner.Parent = button; local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(105, 220, 140); stroke.Thickness = 1.5; stroke.Transparency = 1; stroke.Parent = button
		screenGui.Parent = playerGui; self.ScreenGui = screenGui; self.Button = button; self.Stroke = stroke
		Runtime:Track(button.Activated:Connect(function()
			if self.HudVisible and self.ManualEnabled then self:TryShoot() end
		end))
	end
	function ShootMurder:SetHudVisible(visible)
		if visible then
			self:EnsureHud()
			if not self.ScreenGui or not self.Button then return end
			if self.HudVisible then return end
			self.HudGeneration += 1; self.ScreenGui.Enabled = true; self.HudVisible = true
			self:TweenHud({
				Button = { BackgroundTransparency = 0.04, TextTransparency = 0 },
				Stroke = { Transparency = 0.35 },
			})

			return
		end
		if not self.HudVisible then return end
		self.HudVisible = false; self.HudGeneration += 1; self.EffectGeneration += 1; local generation = self.HudGeneration
		self:TweenHud({
			Button = { BackgroundTransparency = 1, TextTransparency = 1 },
			Stroke = { Transparency = 1 },
		})
		task.delay(FADE_TIME, function()
			if not self.Destroyed and generation == self.HudGeneration and self.ScreenGui then self.ScreenGui.Enabled = false end
		end)
	end
	function ShootMurder:ShowShotEffect()
		if not self.HudVisible or not self.Button then return end
		self.EffectGeneration += 1; local generation = self.EffectGeneration; self.Button.Text = "💥"; self.Button.TextTransparency = 1
		self:TweenHud(
			{ Button = { BackgroundTransparency = 0.04, TextTransparency = 0 }, Stroke = { Transparency = 0.35 } },
			0.07
		)
		task.delay(EFFECT_TIME, function()
			if self.Destroyed or generation ~= self.EffectGeneration or not self.HudVisible or not self.Button then return end
			self.Button.TextTransparency = 1; self.Button.Text = "🔫"
			self:TweenHud(
				{ Button = { BackgroundTransparency = 0.04, TextTransparency = 0 }, Stroke = { Transparency = 0.35 } },
				0.08
			)
		end)
	end
	function ShootMurder:TryShoot(automatic)
		local now = os.clock()
		if now - self.LastShotAt < SHOT_COOLDOWN then return false end
		local localCharacter, humanoid, localRoot = self:GetLocalContext()
		if not localCharacter then return false end
		local target, targetCharacter, _, targetRoot = self:GetMurderer()
		if not target then return false end
		if self.WaitForKnife and not targetCharacter:FindFirstChild("Knife") then return false end
		local gun = self:FindGun(localCharacter, humanoid)
		if not gun or gun.Parent ~= localCharacter then return false end
		local shootRemote = gun:FindFirstChild("Shoot")
		if not shootRemote or not shootRemote:IsA("RemoteEvent") then return false end
		local hitPosition = self:GetClearAim(targetCharacter, targetRoot, gun, localCharacter)
		if not hitPosition then return false end
		local origin = localRoot:FindFirstChild("GunRaycastAttachment")
		if not origin or not origin:IsA("Attachment") then return false end
		local shotPoint = self:GetShotPoint(hitPosition, automatic and self.AutoAccuracy or self.ManualAccuracy)
		local ok = pcall(function() shootRemote:FireServer(origin.WorldCFrame, CFrame.new(shotPoint)) end)
		if not ok then return false end
		self.LastShotAt = now; self:ShowShotEffect(); return true
	end
	function ShootMurder:Update()
		if self.Destroyed then return end
		if not self.ManualEnabled and not self.AutoEnabled then self.RoleData = nil; self.NextRoleRefreshAt = 0; self:SetHudVisible(false); return end
		local inRound = MatchService:GetRoundContext()
		if not inRound then self.RoleData = nil; self.NextRoleRefreshAt = 0; self:SetHudVisible(false); return end
		self:RefreshRoleData(false); local localCharacter = self:GetLocalContext(); local isSheriff = localCharacter ~= nil; self:SetHudVisible(self.ManualEnabled and isSheriff)
		if self.AutoEnabled and isSheriff then self:TryShoot(true) end
	end
	function ShootMurder:SetManualEnabled(enabled)
		self.ManualEnabled = enabled == true
		if not self.ManualEnabled then self:SetHudVisible(false) end
	end
	function ShootMurder:SetAutoEnabled(enabled) self.AutoEnabled = enabled == true end
	function ShootMurder:SetWaitForKnife(enabled) self.WaitForKnife = enabled == true end
	function ShootMurder:SetManualAccuracy(value) self.ManualAccuracy = math.clamp(tonumber(value) or 100, 0, 100) end
	function ShootMurder:SetAutoAccuracy(value) self.AutoAccuracy = math.clamp(tonumber(value) or 100, 0, 100) end
	function ShootMurder:SetAllowOffscreen(enabled) self.AllowOffscreen = enabled == true end
	function ShootMurder:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true; self.ManualEnabled = false; self.AutoEnabled = false; self:CancelTweens()
		if self.ScreenGui then self.ScreenGui:Destroy() end
		self.ScreenGui = nil; self.Button = nil; self.Stroke = nil
	end
	Runtime:TrackTask(task.spawn(function()
		while not ShootMurder.Destroyed do
			local ok, errorMessage = pcall(function() ShootMurder:Update() end)
			if not ok then warn("[Chorus MM2] Shoot Murder recuperando após erro: " .. tostring(errorMessage)) end
			task.wait(WORK_INTERVAL)
		end
	end))
	Runtime:OnShutdown(function() ShootMurder:Destroy() end)

	return ShootMurder
end
