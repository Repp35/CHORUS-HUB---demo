-- [[ util ]]

return function(API)
	local Util = {}

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
		local ok, result = xpcall(callback, Util.FormatError)
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
