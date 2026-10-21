return function(API)
local Runtime = API.Runtime

local UIControlRegistry = {}
UIControlRegistry.__index = UIControlRegistry

function UIControlRegistry.new(tab, getContainer)
	return setmetatable({
		Tab = tab,
		GetContainer = getContainer,
		Items = {},
		ByFlag = {},
	}, UIControlRegistry)
end

function UIControlRegistry:GetItemContainer()
	if type(self.GetContainer) ~= "function" then
		error("O registro precisa de uma função para localizar o contêiner da aba.", 2)
	end
	local container = self.GetContainer()
	if not container or not container:IsA("ScrollingFrame") then
		error("Não foi possível localizar o contêiner da aba.", 2)
	end
	return container
end

function UIControlRegistry:CreateControl(definition, order)
	local container = self:GetItemContainer()
	local existing = {}
	for _, child in ipairs(container:GetChildren()) do
		existing[child] = true
	end

	local methodName = "Add" .. definition.Type
	local addMethod = self.Tab[methodName]
	if type(addMethod) ~= "function" then
		error("A Orion não oferece " .. methodName .. ".", 2)
	end

	local control
	if definition.Type == "Label" then
		control = addMethod(self.Tab, definition.Text)
	else
		local config = table.clone(definition.Config or {})
		if definition.Flag then
			config.Flag = definition.Flag
		end
		control = addMethod(self.Tab, config)
	end

	local root
	for _, child in ipairs(container:GetChildren()) do
		if not existing[child] and child:IsA("GuiObject") then
			if root then
				error("A Orion criou mais de um elemento visual para " .. definition.Key .. ".", 2)
			end
			root = child
		end
	end
	if not root then
		error("A Orion não criou o elemento visual " .. definition.Key .. ".", 2)
	end
	root.LayoutOrder = order

	return {
		Key = definition.Key,
		Flag = definition.Flag,
		ParentFlag = definition.ParentFlag,
		Definition = definition,
		Control = control,
		LayoutRoot = root,
		Children = {},
		Order = order,
	}
end

function UIControlRegistry:WrapWithChildren(parentNode)
	local originalRoot = parentNode.LayoutRoot
	local originalParent = originalRoot.Parent
	if not originalParent then
		error("O controle pai " .. parentNode.Key .. " perdeu seu contêiner.", 2)
	end

	local group = Instance.new("Frame")
	group.Name = "ChorusGroup_" .. parentNode.Key
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.ClipsDescendants = false
	group.Size = UDim2.new(1, 0, 0, 0)
	group.LayoutOrder = originalRoot.LayoutOrder
	group.Parent = originalParent

	local groupLayout = Instance.new("UIListLayout")
	groupLayout.FillDirection = Enum.FillDirection.Vertical
	groupLayout.SortOrder = Enum.SortOrder.LayoutOrder
	groupLayout.Padding = UDim.new(0, 5)
	groupLayout.Parent = group

	originalRoot.Parent = group
	originalRoot.LayoutOrder = 1

	local childHolder = Instance.new("Frame")
	childHolder.Name = "Children"
	childHolder.BackgroundTransparency = 1
	childHolder.BorderSizePixel = 0
	childHolder.Size = UDim2.new(1, 0, 0, 0)
	childHolder.LayoutOrder = 2
	childHolder.Parent = group

	local childPadding = Instance.new("UIPadding")
	childPadding.PaddingLeft = UDim.new(0, 14)
	childPadding.Parent = childHolder

	local childLayout = Instance.new("UIListLayout")
	childLayout.FillDirection = Enum.FillDirection.Vertical
	childLayout.SortOrder = Enum.SortOrder.LayoutOrder
	childLayout.Padding = UDim.new(0, 5)
	childLayout.Parent = childHolder

	for index, childNode in ipairs(parentNode.Children) do
		local childRoot = childNode.LayoutRoot
		local childSize = childRoot.Size
		childRoot.Size = UDim2.new(1, -14, childSize.Y.Scale, childSize.Y.Offset)
		childRoot.LayoutOrder = index
		childRoot.Parent = childHolder
	end

	local function updateGroupSize()
		if not group.Parent then
			return
		end
		childHolder.Size = UDim2.new(1, 0, 0, childLayout.AbsoluteContentSize.Y)
		group.Size = UDim2.new(1, 0, 0, groupLayout.AbsoluteContentSize.Y)
	end

	Runtime:Track(childLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGroupSize))
	Runtime:Track(groupLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGroupSize))
	updateGroupSize()
	parentNode.LayoutRoot = group
end

function UIControlRegistry:Build(definitions)
	for index, definition in ipairs(definitions) do
		if type(definition.Key) ~= "string" or definition.Key == "" then
			error("Todo controle da Orion precisa de uma Key única.", 2)
		end
		if self.ByFlag[definition.Key] then
			error("Key duplicada no registro de interface: " .. definition.Key, 2)
		end
		if definition.Flag and self.ByFlag[definition.Flag] then
			error("Flag duplicada no registro de interface: " .. definition.Flag, 2)
		end

		local node = self:CreateControl(definition, index)
		self.ByFlag[definition.Key] = node
		if definition.Flag then
			self.ByFlag[definition.Flag] = node
		end
		table.insert(self.Items, node)
	end

	for _, node in ipairs(self.Items) do
		if node.ParentFlag then
			local parentNode = self.ByFlag[node.ParentFlag]
			if not parentNode then
				error("ParentFlag sem controle correspondente: " .. node.ParentFlag, 2)
			end
			node.Parent = parentNode
			table.insert(parentNode.Children, node)
		end
	end

	local function getDepth(node, visiting, memo)
		if memo[node] then
			return memo[node]
		end
		if visiting[node] then
			error("Foi encontrada uma relação de filho circular na interface.", 2)
		end
		visiting[node] = true
		local depth = node.Parent and (getDepth(node.Parent, visiting, memo) + 1) or 0
		visiting[node] = nil
		memo[node] = depth
		return depth
	end

	local memo = {}
	local groupedNodes = {}
	for _, node in ipairs(self.Items) do
		getDepth(node, {}, memo)
		if #node.Children > 0 then
			table.insert(groupedNodes, node)
		end
	end
	table.sort(groupedNodes, function(left, right)
		return memo[left] > memo[right]
	end)
	for _, node in ipairs(groupedNodes) do
		self:WrapWithChildren(node)
	end
end
return UIControlRegistry
end
