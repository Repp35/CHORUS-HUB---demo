-- [[ robloxservices ]]

-- Services
return function()

	return {
		Players = game:GetService("Players"),
		RunService = game:GetService("RunService"),
		UserInputService = game:GetService("UserInputService"),
		Workspace = game:GetService("Workspace"),
		TweenService = game:GetService("TweenService"),
		PathfindingService = game:GetService("PathfindingService"),
		ReplicatedStorage = game:GetService("ReplicatedStorage"),
		CollectionService = game:GetService("CollectionService"),
		CoreGui = game:GetService("CoreGui"),
		HttpService = game:GetService("HttpService"),
	}
end
