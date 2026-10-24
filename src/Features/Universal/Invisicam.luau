-- [[ invisicam ]]

return function(API)
	local Services = API.Roblox; local Player = API.Player; local Runtime = API.Runtime; local Workspace = Services.Workspace
	local CameraAssist = {
		Enabled = false,
		Sources = {},
		Connection = nil,
		RaycastParams = nil,
		OverlapParams = nil,
		SavedOcclusionMode = nil,
		OcclusionModeManaged = false,
		OriginalLocalTransparency = setmetatable({}, { __mode = "k" }),
		CurrentOccluders = {},
		OccluderTransparency = 0.82,
		CheckInterval = 0.1,
		LastCheckAt = 0,
		LastWarningAt = -math.huge,
	}

	local OCCLUSION_MODE = Enum.DevCameraOcclusionMode.Invisicam

	-- Diagnostics
	function CameraAssist:_Warn(message)
		local now = os.clock()
		if now - self.LastWarningAt < 5 then return end
		self.LastWarningAt = now; warn("[Chorus MM2] Invisicam: " .. message)
	end

	-- Visibility
	function CameraAssist:_FadeOccluder(part)
		if self.OcclusionModeManaged or not part:IsA("BasePart") then return end
		if self.OriginalLocalTransparency[part] == nil then
			local readOk, original = pcall(function() return part.LocalTransparencyModifier end)
			if not readOk then return end
			self.OriginalLocalTransparency[part] = original
		end
		self.CurrentOccluders[part] = true
		pcall(function() part.LocalTransparencyModifier = self.OccluderTransparency end)
	end
	function CameraAssist:_IsOccluder(part)
		if not part or not part:IsA("BasePart") then return false end
		local ok, transparency, localTransparency = pcall(
			function() return part.Transparency, part.LocalTransparencyModifier end
		)
		return ok and transparency < 0.98 and localTransparency < 0.98
	end
	function CameraAssist:_RestoreUnusedOccluders()
		for part, original in pairs(self.OriginalLocalTransparency) do
			if not self.CurrentOccluders[part] then
				if part.Parent then pcall(function() part.LocalTransparencyModifier = original end) end
				self.OriginalLocalTransparency[part] = nil
			end
		end
	end
	function CameraAssist:_RestoreAllOccluders()
		for part, original in pairs(self.OriginalLocalTransparency) do
			if part.Parent then pcall(function() part.LocalTransparencyModifier = original end) end
			self.OriginalLocalTransparency[part] = nil
		end
		table.clear(self.CurrentOccluders)
	end
	function CameraAssist:_TracePath(origin, targetPosition, excludedParts, excludedInstances)
		local direction = targetPosition - origin
		if direction.Magnitude <= 0.05 then return false end
		local occluded = false
		for _ = 1, 16 do
			self.RaycastParams.FilterDescendantsInstances = excludedInstances; local result = Workspace:Raycast(origin, direction, self.RaycastParams)
			if not result then return occluded end
			local instance = result.Instance
			if instance == Workspace.Terrain then return true end
			if not instance:IsA("BasePart") or excludedParts[instance] then return occluded end
			if self:_IsOccluder(instance) then occluded = true; self:_FadeOccluder(instance) end
			excludedParts[instance] = true; table.insert(excludedInstances, instance)
		end
		return occluded
	end
	local function getBodySamples(part)
		local size = part.Size
		local axes = {
			{ Size = size.X, Vector = part.CFrame.RightVector },
			{ Size = size.Y, Vector = part.CFrame.UpVector },
			{ Size = size.Z, Vector = part.CFrame.LookVector },
		}

		table.sort(axes, function(left, right) return left.Size > right.Size end)
		local samples = { part.Position }
		for index = 1, math.min(2, #axes) do
			local offset = axes[index].Vector * axes[index].Size * 0.42; table.insert(samples, part.Position + offset); table.insert(samples, part.Position - offset)
		end
		return samples
	end
	function CameraAssist:_UpdateOccluders(camera, character, humanoid, root)
		local cameraPosition = camera.CFrame.Position; table.clear(self.CurrentOccluders); local excludedParts = { [character] = true }; local excludedInstances = { character }
		self.RaycastParams.FilterDescendantsInstances = excludedInstances; self.OverlapParams.FilterDescendantsInstances = excludedInstances
		local insideParts =
			Workspace:GetPartBoundsInBox(CFrame.new(cameraPosition), Vector3.new(0.08, 0.08, 0.08), self.OverlapParams)
		for _, part in ipairs(insideParts) do
			if self:_IsOccluder(part) then
				self:_FadeOccluder(part)
				if not excludedParts[part] then excludedParts[part] = true; table.insert(excludedInstances, part) end
			end
		end
		local targets = {}
		for _, part in ipairs(character:GetChildren()) do
			if part:IsA("BasePart") and part ~= root and part.Transparency < 1 then table.insert(targets, part) end
		end
		if #targets == 0 then self:_RestoreUnusedOccluders(); return end
		if humanoid.Health > 0 then
			for _, target in ipairs(targets) do
				for _, sample in ipairs(getBodySamples(target)) do
					local pathExcludedParts = {}; local pathExcludedInstances = {}
					for _, instance in ipairs(excludedInstances) do
						pathExcludedParts[instance] = true; table.insert(pathExcludedInstances, instance)
					end
					self:_TracePath(cameraPosition, sample, pathExcludedParts, pathExcludedInstances)
				end
			end
		end
		self:_RestoreUnusedOccluders()
	end
	function CameraAssist:_Update()
		if not self.Enabled or Runtime.ShuttingDown then return end
		local now = os.clock()
		if now - self.LastCheckAt < self.CheckInterval then return end
		self.LastCheckAt = now
		if self.OcclusionModeManaged then
			local modeOk, currentMode = pcall(function() return Player.DevCameraOcclusionMode end)
			if modeOk and currentMode ~= OCCLUSION_MODE then
				local setOk = pcall(function() Player.DevCameraOcclusionMode = OCCLUSION_MODE end)
				if not setOk then self.OcclusionModeManaged = false end
			end
		end
		local camera = Workspace.CurrentCamera; local character = Player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not camera or not character or not humanoid or humanoid.Health <= 0 then self:_RestoreAllOccluders(); return end
		local ok, updateError = pcall(function() self:_UpdateOccluders(camera, character, humanoid, root) end)
		if not ok then self:_RestoreAllOccluders(); self:_Warn("não foi possível atualizar a transparência da câmera: " .. tostring(updateError)) end
	end

	-- Lifecycle
	function CameraAssist:_HasActiveSource()
		for _, active in pairs(self.Sources) do
			if active then return true end
		end
		return false
	end
	function CameraAssist:SetSource(source, enabled)
		if type(source) ~= "string" or source == "" or Runtime.ShuttingDown then return false end
		if enabled then self.Sources[source] = true
		else self.Sources[source] = nil end
		if self:_HasActiveSource() then self:_Activate()
		else self:_Deactivate() end
		return true
	end
	function CameraAssist:_Activate()
		if self.Enabled or Runtime.ShuttingDown then return end
		self.Enabled = true
		local readOk, originalMode = pcall(function() return Player.DevCameraOcclusionMode end)
		if readOk then
			local setOk, setError = pcall(function() Player.DevCameraOcclusionMode = OCCLUSION_MODE end)
			if setOk then self.SavedOcclusionMode = originalMode; self.OcclusionModeManaged = true
			else self:_Warn("o modo Invisicam não pôde ser ativado: " .. tostring(setError)) end
		end
		local setupOk, setupError = pcall(function()
			local raycastParams = RaycastParams.new(); raycastParams.FilterType = Enum.RaycastFilterType.Exclude; local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude; overlapParams.MaxParts = 32; self.RaycastParams = raycastParams; self.OverlapParams = overlapParams
			self.Connection = Services.RunService.RenderStepped:Connect(function()
				local updateOk, updateError = pcall(function() self:_Update() end)
				if not updateOk then self:_Warn("erro ao atualizar a câmera: " .. tostring(updateError)) end
			end)
		end)
		if not setupOk then self:_Deactivate(); self:_Warn("não foi possível iniciar a assistência da câmera: " .. tostring(setupError)) end
	end
	function CameraAssist:_Deactivate()
		self.Enabled = false
		if self.Connection then
			pcall(function() self.Connection:Disconnect() end)
			self.Connection = nil
		end
		if self.OcclusionModeManaged then
			pcall(function() Player.DevCameraOcclusionMode = self.SavedOcclusionMode end)
		end
		self.SavedOcclusionMode = nil; self.OcclusionModeManaged = false; self:_RestoreAllOccluders(); self.RaycastParams = nil
		self.OverlapParams = nil
	end
	function CameraAssist:Shutdown()
		table.clear(self.Sources); self:_Deactivate()
	end
	Runtime:OnShutdown(function() CameraAssist:Shutdown() end)

	return CameraAssist
end
