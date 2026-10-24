-- [[ controlregistry ]]

return function(API)
	local Runtime = API.Runtime

	-- Registry
	local UIControlRegistry = {}; UIControlRegistry.__index = UIControlRegistry; UIControlRegistry.Importance = { Critical = 1, High = 2, Normal = 3, Low = 4 }
	local DEFAULT_IMPORTANCE = UIControlRegistry.Importance.Normal
	local function getImportance(definition)
		local value = definition.Importance
		if value == nil then return DEFAULT_IMPORTANCE end
		if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > 4 then error("Importance precisa ser um nível de 1 (Critical) a 4 (Low): " .. tostring(definition.Key), 3) end
		return value
	end
	function UIControlRegistry.new(tab, getContainer)
		return setmetatable({
			Tab = tab,
			GetContainer = getContainer,
			Items = {},
			ByKey = {},
			ByFlag = {},
		}, UIControlRegistry)

	end

	-- ContainerLookup
	function UIControlRegistry:GetItemContainer()
		if type(self.GetContainer) ~= "function" then error("O registro precisa de uma função para localizar o contêiner da aba.", 2) end
		local container = self.GetContainer()
		if not container or not container:IsA("ScrollingFrame") then error("Não foi possível localizar o contêiner da aba.", 2) end
		return container
	end

	-- ControlCreation
	function UIControlRegistry:CreateControl(definition, order)
		local isSection = definition.Type == "Section"; local target = self.Tab
		local container
		if isSection then
			if definition.SectionKey then error("Uma seção não pode estar dentro de outra seção.", 2) end
			container = self:GetItemContainer()
		elseif definition.SectionKey then
			local sectionNode = self.ByKey[definition.SectionKey]
			if not sectionNode or sectionNode.Definition.Type ~= "Section" then error("SectionKey sem seção anterior correspondente: " .. tostring(definition.SectionKey), 2) end
			target = sectionNode.Control; container = sectionNode.ContentContainer
		else
			container = self:GetItemContainer()
		end
		if not container or not container.Parent then error("O contêiner do controle " .. definition.Key .. " não está disponível.", 2) end
		local existing = {}
		for _, child in ipairs(container:GetChildren()) do
			existing[child] = true
		end
		local methodName = "Add" .. definition.Type; local addMethod = target[methodName]
		if type(addMethod) ~= "function" then error("A Orion não oferece " .. methodName .. ".", 2) end
		local control
		if definition.Type == "Label" then
			control = addMethod(target, definition.Text)
		else
			local config = table.clone(definition.Config or {})
			if definition.Flag then config.Flag = definition.Flag end
			control = addMethod(target, config)
		end
		local root
		for _, child in ipairs(container:GetChildren()) do
			if not existing[child] and child:IsA("GuiObject") then
				if root then error("A Orion criou mais de um elemento visual para " .. definition.Key .. ".", 2) end
				root = child
			end
		end
		if not root then error("A Orion não criou o elemento visual " .. definition.Key .. ".", 2) end
		root.LayoutOrder = order
		local contentContainer
		if isSection then
			contentContainer = root:FindFirstChild("Holder")
			if not contentContainer then error("A Orion criou a seção sem um contêiner interno.", 2) end
		end
		return {
			Key = definition.Key,
			Flag = definition.Flag,
			ParentFlag = definition.ParentFlag,
			Definition = definition,
			Control = control,
			ContentContainer = contentContainer,
			LayoutRoot = root,
			Children = {},
			Order = order,
			Importance = getImportance(definition),
		}

	end

	-- ChildHierarchy
	function UIControlRegistry:WrapWithChildren(parentNode)
		local originalRoot = parentNode.LayoutRoot; local originalParent = originalRoot.Parent
		if not originalParent then error("O controle pai " .. parentNode.Key .. " perdeu seu contêiner.", 2) end
		local group = Instance.new("Frame"); group.Name = "ChorusGroup_" .. parentNode.Key; group.BackgroundTransparency = 1; group.BorderSizePixel = 0
		group.ClipsDescendants = false; group.Size = UDim2.new(1, 0, 0, 0); group.LayoutOrder = originalRoot.LayoutOrder; group.Parent = originalParent
		local groupLayout = Instance.new("UIListLayout"); groupLayout.FillDirection = Enum.FillDirection.Vertical; groupLayout.SortOrder = Enum.SortOrder.LayoutOrder
		groupLayout.Padding = UDim.new(0, 5); groupLayout.Parent = group; originalRoot.Parent = group; originalRoot.LayoutOrder = 1
		local childHolder = Instance.new("Frame"); childHolder.Name = "Children"; childHolder.BackgroundTransparency = 1; childHolder.BorderSizePixel = 0
		childHolder.Size = UDim2.new(1, 0, 0, 0); childHolder.LayoutOrder = 2; childHolder.Parent = group; local childPadding = Instance.new("UIPadding")
		childPadding.PaddingLeft = UDim.new(0, 14); childPadding.Parent = childHolder; local childLayout = Instance.new("UIListLayout"); childLayout.FillDirection = Enum.FillDirection.Vertical
		childLayout.SortOrder = Enum.SortOrder.LayoutOrder; childLayout.Padding = UDim.new(0, 5); childLayout.Parent = childHolder
		for index, childNode in ipairs(parentNode.Children) do
			local childRoot = childNode.LayoutRoot; local childSize = childRoot.Size; childRoot.Size = UDim2.new(1, -14, childSize.Y.Scale, childSize.Y.Offset); childRoot.LayoutOrder = index
			childRoot.Parent = childHolder
		end
		local function updateGroupSize()
			if not group.Parent then return end
			childHolder.Size = UDim2.new(1, 0, 0, childLayout.AbsoluteContentSize.Y); group.Size = UDim2.new(1, 0, 0, groupLayout.AbsoluteContentSize.Y)
		end
		Runtime:Track(childLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGroupSize))
		Runtime:Track(groupLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGroupSize)); updateGroupSize(); parentNode.LayoutRoot = group
	end

	-- Ordering
	function UIControlRegistry:Build(definitions)
		local orderedDefinitions = {}
		local function appendSortedRun(firstIndex, lastIndex)
			local run = {}
			for sourceIndex = firstIndex, lastIndex do
				local definition = definitions[sourceIndex]
				table.insert(
					run,
					{ Definition = definition, SourceIndex = sourceIndex, Importance = getImportance(definition) }
				)
			end
			table.sort(run, function(left, right)
				if left.Importance == right.Importance then return left.SourceIndex < right.SourceIndex end
				return left.Importance < right.Importance
			end)
			for _, item in ipairs(run) do
				table.insert(orderedDefinitions, item.Definition)
			end
		end
		local runStart = 1
		for index, definition in ipairs(definitions) do
			if definition.Type == "Section" then
				if runStart < index then appendSortedRun(runStart, index - 1) end
				table.insert(orderedDefinitions, definition); runStart = index + 1
			end
		end
		if runStart <= #definitions then appendSortedRun(runStart, #definitions) end
		for index, definition in ipairs(orderedDefinitions) do
			if type(definition.Key) ~= "string" or definition.Key == "" then error("Todo controle da Orion precisa de uma Key única.", 2) end
			if self.ByFlag[definition.Key] then error("Key duplicada no registro de interface: " .. definition.Key, 2) end
			if definition.Flag and self.ByFlag[definition.Flag] then error("Flag duplicada no registro de interface: " .. definition.Flag, 2) end
			local node = self:CreateControl(definition, index); self.ByKey[definition.Key] = node; self.ByFlag[definition.Key] = node
			if definition.Flag then self.ByFlag[definition.Flag] = node end
			table.insert(self.Items, node)
		end
		for _, node in ipairs(self.Items) do
			if node.ParentFlag then
				local parentNode = self.ByFlag[node.ParentFlag]
				if not parentNode then error("ParentFlag sem controle correspondente: " .. node.ParentFlag, 2) end
				node.Parent = parentNode; table.insert(parentNode.Children, node)
			end
		end
		for _, node in ipairs(self.Items) do
			table.sort(node.Children, function(left, right)
				if left.Importance == right.Importance then return left.Order < right.Order end
				return left.Importance < right.Importance
			end)
		end
		local function getDepth(node, visiting, memo)
			if memo[node] then return memo[node] end
			if visiting[node] then error("Foi encontrada uma relação de filho circular na interface.", 2) end
			visiting[node] = true; local depth = node.Parent and (getDepth(node.Parent, visiting, memo) + 1) or 0; visiting[node] = nil; memo[node] = depth
			return depth
		end
		local memo = {}; local groupedNodes = {}
		for _, node in ipairs(self.Items) do
			getDepth(node, {}, memo)
			if #node.Children > 0 then table.insert(groupedNodes, node) end
		end
		table.sort(groupedNodes, function(left, right) return memo[left] > memo[right] end)
		for _, node in ipairs(groupedNodes) do
			self:WrapWithChildren(node)
		end
	end

	return UIControlRegistry
end
