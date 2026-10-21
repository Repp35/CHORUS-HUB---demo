-- [[ espoptionsmodal ]]

return function(API)
	local Runtime = API.Runtime; local Util = API.Util; local UserInputService = game:GetService("UserInputService"); local ESPOptionsModal = {}
	local function create(className, properties, parent) return Util.Create(className, properties, parent) end
	local function setZIndex(root, value)
		if root:IsA("GuiObject") then root.ZIndex = value end
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("GuiObject") then descendant.ZIndex = value end
		end
	end
	function ESPOptionsModal.new(ui, optionRoots)
		local self = { IsOpen = false, Destroyed = false }; local existing = ui.Host:FindFirstChild("ChorusESPOptionsModal")
		if existing then Util.DestroySafely(existing) end
		local screen = create("ScreenGui", {
			Name = "ChorusESPOptionsModal",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = 10001,
			ZIndexBehavior = Enum.ZIndexBehavior.Global,
			Enabled = false,
		}, ui.Host)

		self.Screen = screen
		local backdrop = create("TextButton", {
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.42,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 1,
		}, screen)
		local panel = create("Frame", {
			Name = "Panel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.9, 0, 0.76, 0),
			BackgroundColor3 = Color3.fromRGB(30, 28, 40),
			BorderSizePixel = 0,
			ZIndex = 10,
		}, screen)
		create("UICorner", { CornerRadius = UDim.new(0, 12) }, panel); create("UIStroke", { Color = Color3.fromRGB(126, 102, 255), Thickness = 1.5, Transparency = 0.12 }, panel)
		create("UISizeConstraint", { MaxSize = Vector2.new(480, 560) }, panel)
		create("TextLabel", {
			Name = "Title",
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -68, 0, 25),
			BackgroundTransparency = 1,
			Text = "Opções do ESP",
			TextColor3 = Color3.fromRGB(245, 243, 255),
			TextSize = 17,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 11,
		}, panel)
		create("TextLabel", {
			Name = "Description",
			Position = UDim2.fromOffset(16, 39),
			Size = UDim2.new(1, -32, 0, 30),
			BackgroundTransparency = 1,
			Text = "Toque nas opções para ativar ou desativar. Você pode selecionar várias.",
			TextColor3 = Color3.fromRGB(184, 180, 199),
			TextSize = 12,
			Font = Enum.Font.Gotham,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 11,
		}, panel)
		local closeButton = create("TextButton", {
			Name = "Close",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 10),
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = Color3.fromRGB(48, 45, 62),
			BorderSizePixel = 0,
			Text = "×",
			TextColor3 = Color3.fromRGB(240, 238, 250),
			TextSize = 25,
			Font = Enum.Font.Gotham,
			AutoButtonColor = true,
			ZIndex = 12,
		}, panel)
		create("UICorner", { CornerRadius = UDim.new(0, 8) }, closeButton)
		local list = create("ScrollingFrame", {
			Name = "Options",
			Position = UDim2.new(0, 14, 0, 76),
			Size = UDim2.new(1, -28, 1, -118),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = Color3.fromRGB(126, 102, 255),
			Active = true,
			ZIndex = 11,
		}, panel)
		local layout = create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}, list)
		create("UIPadding", {
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 2),
			PaddingRight = UDim.new(0, 7),
		}, list)
		for index, root in ipairs(optionRoots) do
			local size = root.Size; root.Size = UDim2.new(1, 0, size.Y.Scale, size.Y.Offset); root.LayoutOrder = index; root.Parent = list
			setZIndex(root, 12)
		end
		local function updateCanvas() list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8) end
		Runtime:Track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)); updateCanvas()
		create("TextLabel", {
			Name = "Hint",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -10),
			Size = UDim2.new(1, -32, 0, 20),
			BackgroundTransparency = 1,
			Text = "As alterações são aplicadas imediatamente.",
			TextColor3 = Color3.fromRGB(151, 147, 167),
			TextSize = 11,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 11,
		}, panel)
		function self:Open()
			if self.Destroyed then return end
			self.IsOpen = true; screen.Enabled = true
		end
		function self:Close()
			if self.Destroyed then return end
			self.IsOpen = false; screen.Enabled = false
		end
		function self:Destroy()
			if self.Destroyed then return end
			self.Destroyed = true; self.IsOpen = false; Util.DestroySafely(screen)
		end
		Runtime:Track(backdrop.Activated:Connect(function() self:Close() end))
		Runtime:Track(closeButton.Activated:Connect(function() self:Close() end))
		Runtime:Track(UserInputService.InputBegan:Connect(function(input, processed)
			if self.IsOpen and not processed and input.KeyCode == Enum.KeyCode.Escape then self:Close() end
		end))
		if ui.Screen then
			Runtime:Track(ui.Screen:GetPropertyChangedSignal("Enabled"):Connect(function()
				if not ui.Screen.Enabled then self:Close() end
			end))
		end
		Runtime:OnShutdown(function() self:Destroy() end)
		return self
	end

	return ESPOptionsModal
end
