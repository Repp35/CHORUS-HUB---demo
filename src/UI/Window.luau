-- [[ window ]]

return function(API)
	local Config = API.Config
	local Services = API.Roblox
	local Runtime = API.Runtime
	local Util = API.Util
	local UI = {
		Tabs = {},
		Screen = nil,
		Frame = nil,
	}

	UI.Host = Util.GetHost()

	-- Cleanup
	local function removeChild(parent, name)
		if not parent then
			return
		end
		for _, child in ipairs(parent:GetChildren()) do
			if child.Name == name then
				Util.DestroySafely(child)
			end
		end
	end
	removeChild(UI.Host, "ChorusMobileControls")
	if UI.Host ~= Services.CoreGui then
		removeChild(Services.CoreGui, "ChorusMobileControls")
	end
	removeChild(UI.Host, "Orion")
	if UI.Host ~= Services.CoreGui then
		removeChild(Services.CoreGui, "Orion")
	end
	local OrionLib = API:Require("src/UI/Orion")

	-- WindowLookup
	function UI:FindWindow()
		local screen = self.Host:FindFirstChild("Orion") or Services.CoreGui:FindFirstChild("Orion")
		if not screen or not screen:IsA("ScreenGui") then
			return nil, nil
		end
		self.Screen = screen
		for _, child in ipairs(screen:GetChildren()) do
			if child:IsA("Frame") and child:FindFirstChild("TopBar") then
				self.Frame = child
				return screen, child
			end
		end
		return screen, nil
	end
	function UI:WaitForWindow(timeout)
		local deadline = os.clock() + math.max(tonumber(timeout) or 5, 0)
		repeat
			local screen, frame = self:FindWindow()
			if screen and frame then
				return screen, frame
			end
			Services.RunService.Heartbeat:Wait()
		until os.clock() >= deadline
		return self:FindWindow()
	end
	function UI:GetItemContainer(tabName)
		local tab = self.Tabs[tabName]
		local container = tab and tab.Container
		if not container or not container.Parent then
			error("O contêiner da aba " .. tostring(tabName) .. " não está disponível.", 2)
		end
		return container
	end

	-- Visibility
	function UI:SetOpen(open)
		local screen, windowFrame = self:FindWindow()
		if screen then
			pcall(function()
				screen.Enabled = open
			end)
		end
		if windowFrame then
			pcall(function()
				windowFrame.Visible = open
			end)
		end
	end
	function UI:MakeTab(name)
		local _, windowFrame = self:FindWindow()
		if not windowFrame then
			_, windowFrame = self:WaitForWindow(5)
		end
		if not windowFrame then
			error("A janela da Orion ainda não está pronta para criar abas.", 2)
		end
		local existing = {}
		for _, child in ipairs(windowFrame:GetChildren()) do
			existing[child] = true
		end
		local tabApi = Util.InitializeComponent("criar a aba " .. name, function()
			return self.Window:MakeTab({
				Name = name,
				Icon = self:GetTabIcon(name),
				PremiumOnly = false,
			})
		end)
		local container
		local deadline = os.clock() + 2
		repeat
			for _, child in ipairs(windowFrame:GetChildren()) do
				if not existing[child] and child:IsA("ScrollingFrame") and child.Name == "ItemContainer" then
					container = child
					break
				end
			end
			if container then
				break
			end
			Services.RunService.Heartbeat:Wait()
		until os.clock() >= deadline
		if not tabApi or not container then
			error("A Orion não retornou a aba ou o contêiner " .. name .. ".", 2)
		end
		self.Tabs[name] = { API = tabApi, Container = container }
		return tabApi
	end

	-- TabIcons
	function UI:GetTabIcon(name)
		local fallback = "rbxassetid://4483345998"
		local icon = API.TabIcons and API.TabIcons[name]
		if type(icon) ~= "table" then
			return fallback
		end
		local assetGetter = type(getcustomasset) == "function" and getcustomasset or getsynasset
		if type(assetGetter) ~= "function" or type(writefile) ~= "function" then
			return fallback
		end
		local path = Config.ConfigFolder .. "/" .. icon.FileName
		local assetOk, asset = pcall(assetGetter, path)
		if assetOk and type(asset) == "string" and asset ~= "" then
			return asset
		end
		if type(makefolder) == "function" then
			pcall(makefolder, Config.ConfigFolder)
		end
		local downloadOk, imageData = pcall(function()
			return API:Fetch(icon.Source)
		end)
		if downloadOk and type(imageData) == "string" then
			pcall(writefile, path, imageData)
			assetOk, asset = pcall(assetGetter, path)
			if assetOk and type(asset) == "string" and asset ~= "" then
				return asset
			end
		end
		return fallback
	end
	local function canUseConfigStorage()
		if
			Config.SaveConfig ~= true
			or type(isfolder) ~= "function"
			or type(makefolder) ~= "function"
			or type(isfile) ~= "function"
			or type(readfile) ~= "function"
			or type(writefile) ~= "function"
		then
			return false
		end
		local checkOk, exists = pcall(isfolder, Config.ConfigFolder)
		if checkOk and exists == true then
			return true
		end
		local createOk = pcall(makefolder, Config.ConfigFolder)
		if not createOk then
			return false
		end
		local verifyOk, created = pcall(isfolder, Config.ConfigFolder)
		return verifyOk and created == true
	end

	-- Destroy
	function UI:Destroy()
		local screen = self.Screen
		if not screen or not screen.Parent then
			screen = self:FindWindow()
		end
		local connections = OrionLib and OrionLib.Connections
		if type(connections) == "table" then
			for _, connection in ipairs(connections) do
				pcall(function()
					connection:Disconnect()
				end)
			end
			table.clear(connections)
		end
		if OrionLib and type(OrionLib.Destroy) == "function" then
			pcall(OrionLib.Destroy, OrionLib)
		end
		Util.DestroySafely(screen)
		removeChild(self.Host, "Orion")
		removeChild(Services.CoreGui, "Orion")
		removeChild(self.Host, "ChorusMobileControls")
		removeChild(Services.CoreGui, "ChorusMobileControls")
	end
	Runtime:OnShutdown(function()
		UI:Destroy()
	end)
	local Window = Util.InitializeComponent("criar a janela", function()
		return OrionLib:MakeWindow({
			Name = Config.Name,
			ConfigFolder = Config.ConfigFolder,
			SaveConfig = canUseConfigStorage(),
			HidePremium = Config.HidePremium,
			IntroEnabled = Config.IntroEnabled,
			CloseCallback = function()
				Runtime:Shutdown()
			end,
		})
	end)
	if not Window or type(Window.MakeTab) ~= "function" then
		error("A Orion retornou uma janela incompatível.", 0)
	end
	UI.Window = Window
	UI:FindWindow()
	local Tabs = {
		["Auto Farm"] = UI:MakeTab("Auto Farm"),
		Combat = UI:MakeTab("Combat"),
		Visuals = UI:MakeTab("Visuals"),
		Player = UI:MakeTab("Player"),
		Settings = UI:MakeTab("Settings"),
	}

	return {
		UI = UI,
		Window = Window,
		OrionLib = OrionLib,
		Tabs = Tabs,
	}
end
