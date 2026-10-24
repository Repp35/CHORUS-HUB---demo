-- [[ util ]]

return function(API)
	local Util = {}; local MAX_WORLD_COORDINATE = 1000000
	function Util.IsFiniteVector3(value)
		if typeof(value) ~= "Vector3" then return false end
		return value.X == value.X
			and value.Y == value.Y
			and value.Z == value.Z
			and math.abs(value.X) < MAX_WORLD_COORDINATE
			and math.abs(value.Y) < MAX_WORLD_COORDINATE
			and math.abs(value.Z) < MAX_WORLD_COORDINATE
	end

	-- Diagnostics
	function Util.FormatError(errorMessage)
		local debugLibrary = debug
		if type(debugLibrary) == "table" and type(debugLibrary.traceback) == "function" then
			local ok, trace = pcall(debugLibrary.traceback, tostring(errorMessage), 2)
			if ok then return trace end
		end
		return tostring(errorMessage)
	end
	function Util.InitializeComponent(label, callback)
		local ok, result = xpcall(callback, function(errorMessage) return tostring(errorMessage) end)
		if not ok then
			if API.Runtime then API.Runtime:Shutdown() end
			error("Falha ao " .. label .. ": " .. tostring(result), 0)
		end
		return result
	end

	-- Instances
	function Util.Create(className, properties, parent)
		local object = Instance.new(className)
		for property, value in pairs(properties or {}) do
			if property ~= "Parent" then object[property] = value end
		end
		object.Parent = parent or (properties and properties.Parent); return object
	end

	-- GUIHost
	function Util.GetHost()
		if type(gethui) == "function" then
			local ok, host = pcall(gethui)
			if ok and typeof(host) == "Instance" then return host end
		end
		return API.Roblox.CoreGui
	end
	function Util.DestroySafely(instance)
		if instance then pcall(function() instance:Destroy() end) end
	end

	return Util
end
