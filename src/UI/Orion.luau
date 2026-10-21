-- [[ orion ]]

return function(API)
	local Config = API.Config
	local ICONS_EXPRESSION =
		'Icons = HttpService:JSONDecode(game:HttpGetAsync("https://raw.githubusercontent.com/evoincorp/lucideblox/master/src/modules/util/icons.json")).icons'
	local REQUIRED_API = { "Init", "MakeWindow", "Destroy", "ToggleUi" }

	local function lines(...)
		return table.concat({ ... }, "\n")
	end

	local function replaceOnce(source, original, replacement, label)
		local startAt, endAt = string.find(source, original, 1, true)
		if not startAt then
			error("A versão da Orion não contém o trecho esperado: " .. label, 0)
		end
		if string.find(source, original, endAt + 1, true) then
			error("O trecho da Orion não é único: " .. label, 0)
		end
		return string.sub(source, 1, startAt - 1) .. replacement .. string.sub(source, endAt + 1)
	end

	local function replaceRange(source, startMarker, endMarker, replacement, label)
		local startAt = string.find(source, startMarker, 1, true)
		local endAt = startAt and string.find(source, endMarker, startAt, true)
		if not startAt or not endAt then
			error("A versão da Orion não contém o bloco esperado: " .. label, 0)
		end
		return string.sub(source, 1, startAt - 1) .. replacement .. string.sub(source, endAt)
	end

	local function replaceRepeated(source, original, replacement, expectedCount, label)
		local result = {}
		local cursor = 1
		local count = 0
		while true do
			local startAt, endAt = string.find(source, original, cursor, true)
			if not startAt then
				table.insert(result, string.sub(source, cursor))
				break
			end
			table.insert(result, string.sub(source, cursor, startAt - 1))
			table.insert(result, replacement)
			cursor = endAt + 1
			count += 1
		end
		if count ~= expectedCount then
			error(
				"A versão da Orion mudou no trecho "
					.. label
					.. " (encontrado "
					.. count
					.. ", esperado "
					.. expectedCount
					.. ").",
				0
			)
		end
		return table.concat(result)
	end

	local function cleanupOrionGui()
		local hosts = { API.Roblox.CoreGui }
		if type(gethui) == "function" then
			local ok, host = pcall(gethui)
			if ok and typeof(host) == "Instance" and host ~= hosts[1] then
				table.insert(hosts, host)
			end
		end
		for _, host in ipairs(hosts) do
			for _, child in ipairs(host:GetChildren()) do
				if child.Name == "Orion" then
					pcall(function()
						child:Destroy()
					end)
				end
			end
		end
	end

	local function patchSource(source)
		source = string.gsub(source, "\r\n", "\n")
		source = replaceOnce(source, ICONS_EXPRESSION, "Icons = {}", "carregamento opcional de ícones")
		source = replaceRange(
			source,
			'local Orion = Instance.new("ScreenGui")',
			"local function AddConnection",
			lines(
				"local function GetOrionHost()",
				'\tif type(gethui) == "function" then',
				"\t\tlocal ok, host = pcall(gethui)",
				'\t\tif ok and typeof(host) == "Instance" then return host end',
				"\tend",
				'\treturn game:GetService("CoreGui")',
				"end",
				"local OrionHost = GetOrionHost()",
				'local Orion = Instance.new("ScreenGui")',
				'Orion.Name = "Orion"',
				"local executorApi = syn",
				'if type(executorApi) == "table" and type(executorApi.protect_gui) == "function" then pcall(executorApi.protect_gui, Orion) end',
				"Orion.Parent = OrionHost",
				"for _, interface in ipairs(OrionHost:GetChildren()) do",
				"\tif interface.Name == Orion.Name and interface ~= Orion then",
				"\t\tpcall(function() interface:Destroy() end)",
				"\tend",
				"end",
				"function OrionLib:IsRunning()",
				"\treturn Orion.Parent == OrionHost",
				"end",
				""
			),
			"criação da janela e seleção do host"
		)
		source = replaceOnce(
			source,
			lines(
				"local function SetProps(Element, Props)",
				"\ttable.foreach(Props, function(Property, Value)",
				"\t\tElement[Property] = Value",
				"\tend)",
				"\treturn Element",
				"end"
			),
			lines(
				"local function SetProps(Element, Props)",
				"\tfor Property, Value in pairs(Props or {}) do",
				"\t\tElement[Property] = Value",
				"\tend",
				"\treturn Element",
				"end"
			),
			"helper SetProps"
		)
		source = replaceOnce(
			source,
			lines(
				"local function SetChildren(Element, Children)",
				"\ttable.foreach(Children, function(_, Child)",
				"\t\tChild.Parent = Element",
				"\tend)",
				"\treturn Element",
				"end"
			),
			lines(
				"local function SetChildren(Element, Children)",
				"\tfor _, Child in pairs(Children or {}) do",
				"\t\tChild.Parent = Element",
				"\tend",
				"\treturn Element",
				"end"
			),
			"helper SetChildren"
		)
		source = replaceOnce(
			source,
			lines(
				"local function LoadCfg(Config)",
				"\tlocal Data = HttpService:JSONDecode(Config)",
				"\ttable.foreach(Data, function(a,b)",
				"\t\tif OrionLib.Flags[a] then",
				"\t\t\tspawn(function() ",
				'\t\t\t\tif OrionLib.Flags[a].Type == "Colorpicker" then',
				"\t\t\t\t\tOrionLib.Flags[a]:Set(UnpackColor(b))",
				"\t\t\t\telse",
				"\t\t\t\t\tOrionLib.Flags[a]:Set(b)",
				"\t\t\t\tend    ",
				"\t\t\tend)",
				"\t\telse",
				'\t\t\twarn("Orion Library Config Loader - Could not find ", a ,b)',
				"\t\tend",
				"\tend)",
				"end"
			),
			lines(
				"local function LoadCfg(Config)",
				"\tlocal Data = HttpService:JSONDecode(Config)",
				'\tif type(Data) ~= "table" then return end',
				"\tfor a, b in pairs(Data) do",
				"\t\tif OrionLib.Flags[a] then",
				"\t\t\tspawn(function()",
				'\t\t\t\tif OrionLib.Flags[a].Type == "Colorpicker" then OrionLib.Flags[a]:Set(UnpackColor(b))',
				"\t\t\t\telse OrionLib.Flags[a]:Set(b) end",
				"\t\t\tend)",
				"\t\telse",
				'\t\t\twarn("Orion Library Config Loader - Could not find ", a, b)',
				"\t\tend",
				"\tend",
				"end"
			),
			"carregamento da configuração"
		)
		source = replaceOnce(
			source,
			lines(
				"local function SaveCfg(Name)",
				"\tlocal Data = {}",
				"\tfor i,v in pairs(OrionLib.Flags) do",
				"\t\tif v.Save then",
				'\t\t\tif v.Type == "Colorpicker" then',
				"\t\t\t\tData[i] = PackColor(v.Value)",
				"\t\t\telse",
				"\t\t\t\tData[i] = v.Value",
				"\t\t\tend",
				"\t\tend\t",
				"\tend",
				'\twritefile(OrionLib.Folder .. "/" .. Name .. ".txt", tostring(HttpService:JSONEncode(Data)))',
				"end"
			),
			lines(
				"local function SaveCfg(Name)",
				'\tif not OrionLib.SaveCfg or type(writefile) ~= "function" then return end',
				"\tlocal Data = {}",
				"\tfor i, v in pairs(OrionLib.Flags) do",
				"\t\tif v.Save then",
				'\t\t\tif v.Type == "Colorpicker" then Data[i] = PackColor(v.Value)',
				"\t\t\telse Data[i] = v.Value end",
				"\t\tend",
				"\tend",
				"\tlocal ok, encoded = pcall(function() return HttpService:JSONEncode(Data) end)",
				'\tif ok then pcall(writefile, OrionLib.Folder .. "/" .. Name .. ".txt", encoded) end',
				"end"
			),
			"salvamento da configuração"
		)
		source = replaceOnce(
			source,
			lines("\t\t\t\t\tSaveCfg(game.GameId)", "\t\t\t\t\tToggle:Set(not Toggle.Value)"),
			lines("\t\t\t\t\tToggle:Set(not Toggle.Value)", "\t\t\t\t\tSaveCfg(game.GameId)"),
			"ordem de salvamento do toggle"
		)
		source = replaceOnce(
			source,
			lines(
				"\tAddConnection(CloseBtn.MouseButton1Up, function()",
				"\t\tMainWindow.Visible = false",
				"\t\tUIHidden = true",
				"\t\tOrionLib:MakeNotification({",
				'\t\t\tName = "Interface Hidden",',
				'\t\t\tContent = "Tap RightShift to reopen the interface",',
				"\t\t\tTime = 5",
				"\t\t})",
				"\t\tWindowConfig.CloseCallback()",
				"\tend)"
			),
			lines(
				"\tAddConnection(CloseBtn.MouseButton1Up, function()",
				"\t\tMainWindow.Visible = false",
				"\t\tUIHidden = true",
				"\t\tWindowConfig.CloseCallback()",
				"\tend)"
			),
			"callback de fechamento da janela"
		)
		source = replaceOnce(
			source,
			lines(
				"\t\t\t\tSliderBar.InputEnded:Connect(function(Input) ",
				"\t\t\t\t\tif Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then ",
				"\t\t\t\t\t\tDragging = false ",
				"\t\t\t\t\tend ",
				"\t\t\t\tend)"
			),
			lines(
				"\t\t\t\tSliderBar.InputEnded:Connect(function(Input)",
				"\t\t\t\t\tif Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then",
				"\t\t\t\t\t\tDragging = false",
				"\t\t\t\t\t\tSaveCfg(game.GameId)",
				"\t\t\t\t\tend",
				"\t\t\t\tend)"
			),
			"salvamento do slider ao concluir a interação"
		)
		source = replaceOnce(
			source,
			lines(
				"\t\t\t\t\t\tSlider:Set(SliderConfig.Min + ((SliderConfig.Max - SliderConfig.Min) * SizeScale)) ",
				"\t\t\t\t\t\tSaveCfg(game.GameId)"
			),
			"\t\t\t\t\t\tSlider:Set(SliderConfig.Min + ((SliderConfig.Max - SliderConfig.Min) * SizeScale))",
			"atualização do slider sem gravação por quadro"
		)

		for _, connectionPatch in ipairs({
			{
				"DragPoint.InputBegan:Connect(function(Input)",
				"AddConnection(DragPoint.InputBegan, function(Input)",
				1,
				"arraste: entrada",
			},
			{
				"Input.Changed:Connect(function()",
				"AddConnection(Input.Changed, function()",
				1,
				"arraste: estado da entrada",
			},
			{
				"DragPoint.InputChanged:Connect(function(Input)",
				"AddConnection(DragPoint.InputChanged, function(Input)",
				1,
				"arraste: movimento",
			},
			{
				"UserInputService.InputChanged:Connect(function(Input)",
				"AddConnection(UserInputService.InputChanged, function(Input)",
				2,
				"entrada global",
			},
			{
				"SliderBar.InputBegan:Connect(function(Input)",
				"AddConnection(SliderBar.InputBegan, function(Input)",
				1,
				"slider: início",
			},
			{
				"SliderBar.InputEnded:Connect(function(Input)",
				"AddConnection(SliderBar.InputEnded, function(Input)",
				1,
				"slider: fim",
			},
		}) do
			source =
				replaceRepeated(source, connectionPatch[1], connectionPatch[2], connectionPatch[3], connectionPatch[4])
		end

		return source
	end

	local ok, result = pcall(function()
		local source = API:Fetch(Config.OrionSource)
		if type(source) ~= "string" or source == "" then
			error("A fonte da Orion está vazia ou inválida.")
		end
		source = patchSource(source)
		local chunk, compileError = API:Compile(source, "@Chorus/Orion")
		if not chunk then
			error(compileError or "A fonte da Orion não pôde ser compilada.")
		end
		return chunk()
	end)
	if not ok or type(result) ~= "table" then
		cleanupOrionGui()
		error("Falha ao carregar a Orion: " .. tostring(result), 0)
	end
	for _, methodName in ipairs(REQUIRED_API) do
		if type(result[methodName]) ~= "function" then
			cleanupOrionGui()
			error("A fonte carregada da Orion não oferece o método " .. methodName .. ".", 0)
		end
	end

	return result
end
