-- [[ runtime ]]

return function(API)
	local environment = API.SharedEnvironment; local runtimeKey = "__ChorusMM2DeltaRuntime"; local previousRuntime = rawget(environment, runtimeKey)

	-- RuntimeState
	local Runtime = {
		Connections = {},
		Tasks = {},
		Cleanups = {},
		ShuttingDown = false,
		PreviousRuntime = previousRuntime,
	}

	-- Tracking
	function Runtime:Track(connection)
		if not connection then return nil end
		if self.ShuttingDown then
			pcall(function() connection:Disconnect() end)
			return connection
		end
		table.insert(self.Connections, connection); return connection
	end
	function Runtime:TrackTask(thread)
		if not thread then return nil end
		if self.ShuttingDown then pcall(task.cancel, thread); return thread end
		table.insert(self.Tasks, thread); return thread
	end
	function Runtime:OnShutdown(callback)
		if type(callback) ~= "function" then return false end
		if self.ShuttingDown then pcall(callback); return false end
		table.insert(self.Cleanups, callback); return true
	end

	-- Shutdown
	function Runtime:Shutdown()
		if self.ShuttingDown then return end
		self.ShuttingDown = true
		for _, cleanup in ipairs(self.Cleanups) do
			pcall(cleanup)
		end
		table.clear(self.Cleanups)
		for _, connection in ipairs(self.Connections) do
			pcall(function() connection:Disconnect() end)
		end
		table.clear(self.Connections)
		for _, thread in ipairs(self.Tasks) do
			pcall(task.cancel, thread)
		end
		table.clear(self.Tasks)
		if rawget(environment, runtimeKey) == self then rawset(environment, runtimeKey, nil) end
	end
	if type(previousRuntime) == "table" and type(previousRuntime.Shutdown) == "function" then pcall(previousRuntime.Shutdown, previousRuntime) end
	rawset(environment, runtimeKey, Runtime)

	return Runtime
end
