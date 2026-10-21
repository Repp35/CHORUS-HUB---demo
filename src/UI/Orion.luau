-- [[ orion ]]

return function(API)

	-- Source
	local Config = API.Config
	local OrionLib

	-- Validation
	local ok, result = pcall(function()
		local source = API:Fetch(Config.OrionSource); local chunk, compileError = API:Compile(source, "@Chorus/Orion")
		if not chunk then error(compileError or "A fonte da Orion não pôde ser compilada.") end
		return chunk()
	end)
	if not ok or type(result) ~= "table" then error("Falha ao carregar a Orion: " .. tostring(result), 0) end
	if type(result.MakeWindow) ~= "function" or type(result.Init) ~= "function" then error("A fonte carregada não oferece a API esperada da Orion.", 0) end

	return result
end
