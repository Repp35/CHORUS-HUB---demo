-- [[ window ]]

return function(API)
	local Config = API.Config; local Services = API.Roblox; local Runtime = API.Runtime; local Util = API.Util
	local OrionLib = API:Require("src/UI/Orion")
	local UI = {
		Tabs = {},
		Screen = nil,
		Frame = nil,
		FloatingGui = nil,
		FloatingButton = nil,
	}

	UI.Host = Util.GetHost()

	-- Cleanup
	local function removeChild(parent, name)
		local child = parent and parent:FindFirstChild(name)
		if child then Util.DestroySafely(child) end
	end
	removeChild(UI.Host, "ChorusMobileControls")
	if UI.Host ~= Services.CoreGui then removeChild(Services.CoreGui, "ChorusMobileControls") end
	if Runtime.PreviousRuntime then
		removeChild(UI.Host, "Orion")
		if UI.Host ~= Services.CoreGui then removeChild(Services.CoreGui, "Orion") end
	end
	UI.FloatingGui = Util.Create("ScreenGui", {
		Name = "ChorusMobileControls",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10000,
	}, UI.Host)
	UI.FloatingButton = Util.Create("TextButton", {
		Name = "ReopenHub",
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.new(0, 14, 1, -70),
		BackgroundColor3 = Color3.fromRGB(112, 82, 245),
		Text = "C",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 100,
	}, UI.FloatingGui)
	Util.Create("UICorner", { CornerRadius = UDim.new(1, 0) }, UI.FloatingButton); Util.Create("UIStroke", { Color = Color3.fromRGB(173, 153, 255), Thickness = 1 }, UI.FloatingButton)

	-- WindowLookup
	function UI:FindWindow()
		local screen = self.Host:FindFirstChild("Orion") or Services.CoreGui:FindFirstChild("Orion")
		if not screen or not screen:IsA("ScreenGui") then return nil, nil end
		self.Screen = screen
		for _, child in ipairs(screen:GetChildren()) do
			if child:IsA("Frame") and child:FindFirstChild("TopBar") then self.Frame = child; return screen, child end
		end
		return screen, nil
	end
	function UI:GetItemContainer(tabName)
		local tab = self.Tabs[tabName]; local container = tab and tab.Container
		if not container or not container.Parent then error("O contêiner da aba " .. tostring(tabName) .. " não está disponível.", 2) end
		return container
	end

	-- Visibility
	function UI:SetOpen(open)
		local screen, windowFrame = self:FindWindow()
		if screen then pcall(function() screen.Enabled = open end) end
		if windowFrame then pcall(function() windowFrame.Visible = open end) end
		if self.FloatingButton and self.FloatingButton.Parent then self.FloatingButton.Visible = not open or screen == nil end
	end
	function UI:MakeTab(name)
		local _, windowFrame = self:FindWindow()
		if not windowFrame then error("A janela da Orion ainda não está pronta para criar abas.", 2) end
		local existing = {}
		for _, child in ipairs(windowFrame:GetChildren()) do
			existing[child] = true
		end
		local tabApi = Util.InitializeComponent(
			"criar a aba " .. name,
			function()
				return self.Window:MakeTab({
					Name = name,
					Icon = name == "Player" and self:GetSettingsIcon() or "rbxassetid://4483345998",
					PremiumOnly = false,
				})

			end
		)
		local container
		for _, child in ipairs(windowFrame:GetChildren()) do
			if not existing[child] and child:IsA("ScrollingFrame") and child.Name == "ItemContainer" then container = child; break end
		end
		if not tabApi or not container then error("A Orion não retornou a aba ou o contêiner " .. name .. ".", 2) end
		self.Tabs[name] = { API = tabApi, Container = container }; return tabApi
	end

	-- SettingsIcon
	function UI:GetSettingsIcon()
		local fallback = "rbxassetid://4483345998"
		if type(getcustomasset) ~= "function" or type(writefile) ~= "function" then return fallback end
		local path = Config.ConfigFolder .. "/settings-emoji.png"; local fileExists = false
		if type(isfile) == "function" then local ok, exists = pcall(isfile, path); fileExists = ok and exists == true end
		if not fileExists then
			if type(makefolder) == "function" then pcall(makefolder, Config.ConfigFolder) end
			local downloadOk, imageData = pcall(
				function() return API:Fetch("https://cdn.jsdelivr.net/gh/twitter/twemoji@latest/assets/72x72/2699.png") end
			)
			if downloadOk and type(imageData) == "string" then pcall(writefile, path, imageData) end
		end
		if type(isfile) == "function" then
			local existsOk, exists = pcall(isfile, path)
			if existsOk and exists then
				local assetOk, asset = pcall(getcustomasset, path)
				if assetOk and type(asset) == "string" and asset ~= "" then return asset end
			end
		end
		return fallback
	end

	-- Destroy
	function UI:Destroy()
		Util.DestroySafely(self.FloatingGui); local screen = self.Screen
		if not screen then screen = self:FindWindow() end
		Util.DestroySafely(screen)
	end
	Runtime:OnShutdown(function() UI:Destroy() end)
	Runtime:Track(UI.FloatingButton.Activated:Connect(function() UI:SetOpen(true) end))
	local Window = Util.InitializeComponent("criar a janela", function()
		return OrionLib:MakeWindow({
			Name = Config.Name,
			ConfigFolder = Config.ConfigFolder,
			SaveConfig = Config.SaveConfig,
			HidePremium = Config.HidePremium,
			IntroEnabled = Config.IntroEnabled,
			CloseCallback = function() UI:SetOpen(false) end,
		})
	end)
	if not Window or type(Window.MakeTab) ~= "function" then error("A Orion retornou uma janela incompatível.", 0) end
	UI.Window = Window; UI:FindWindow()
	local Tabs = {
		["Auto Farm"] = UI:MakeTab("Auto Farm"),
		Visuals = UI:MakeTab("Visuals"),
		Player = UI:MakeTab("Player"),
	}

	return {
		UI = UI,
		Window = Window,
		OrionLib = OrionLib,
		Tabs = Tabs,
	}
end
