-- [[ loader ]]

-- ExecutorIdentity
local function queryExecutorName(detector)
	if type(detector) ~= "function" then
		return nil
	end
	local ok, name = pcall(detector)
	if not ok then
		return nil
	end
	if type(name) == "table" then
		name = name.Name or name.name or name[1]
	end
	if type(name) ~= "string" then
		return nil
	end
	name = name:match("^%s*(.-)%s*$")
	local normalizedName = string.lower(name)
	if name == "" or normalizedName == "unknown" or normalizedName == "roblox" or normalizedName == "studio" then
		return nil
	end
	return name
end
local ExecutorName = queryExecutorName(identifyexecutor) or queryExecutorName(getexecutorname)
if not ExecutorName or type(loadstring) ~= "function" then
	return
end
local httpGetOk, httpGet = pcall(function()
	return game.HttpGet
end)
if not httpGetOk or type(httpGet) ~= "function" then
	return
end

-- Constants
local MM2_GAME_ID = 66654135
local REPOSITORY = "Repp35/CHORUS-HUB---demo"
local BRANCH = "main"
local RUNTIME_KEY = "__ChorusMM2DeltaRuntime"
local BOOTSTRAP_KEY = "__ChorusMM2DeltaBootstrap"
local TAB_ICONS = {
	["Auto Farm"] = {
		FileName = "autofarm-coin.png",
		Source = "https://cdn.jsdelivr.net/gh/twitter/twemoji@latest/assets/72x72/1fa99.png",
	},
	Visuals = {
		FileName = "visuals-eye.png",
		Source = "https://cdn.jsdelivr.net/gh/twitter/twemoji@latest/assets/72x72/1f441.png",
	},
	Player = {
		FileName = "player-user.png",
		Source = "https://cdn.jsdelivr.net/gh/twitter/twemoji@latest/assets/72x72/1f464.png",
	},
	Settings = {
		FileName = "settings-gear.png",
		Source = "https://cdn.jsdelivr.net/gh/twitter/twemoji@latest/assets/72x72/2699.png",
	},
}

-- Environment
local function getSharedEnvironment()
	if type(getgenv) == "function" then
		local ok, environment = pcall(getgenv)
		if ok and type(environment) == "table" then
			return environment
		end
	end
	return _G
end
local SharedEnvironment = getSharedEnvironment()
local isMM2 = false
pcall(function()
	isMM2 = game.PlaceId == MM2_GAME_ID or game.GameId == MM2_GAME_ID
end)
if not isMM2 then
	return
end
local PreviousRuntime = rawget(SharedEnvironment, RUNTIME_KEY)
if type(PreviousRuntime) == "table" and type(PreviousRuntime.Shutdown) == "function" then
	pcall(PreviousRuntime.Shutdown, PreviousRuntime)
end
if rawget(SharedEnvironment, BOOTSTRAP_KEY) ~= nil then
	return
end
local BootstrapToken = {}
rawset(SharedEnvironment, BOOTSTRAP_KEY, BootstrapToken)

-- Diagnostics
local function formatError(message)
	local debugLibrary = debug
	if type(debugLibrary) == "table" and type(debugLibrary.traceback) == "function" then
		local ok, result = pcall(debugLibrary.traceback, tostring(message), 2)
		if ok then
			return result
		end
	end
	return tostring(message)
end

-- Networking
local function fetch(url)
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if not ok or type(body) ~= "string" or body == "" then
		error("Falha ao baixar " .. url .. ": " .. tostring(body), 2)
	end
	return body
end
local function isCommitSha(value)
	return type(value) == "string" and #value == 40 and value:match("^%x+$") ~= nil
end
local function resolveLatestCommit()
	local httpService = game:GetService("HttpService")
	local apiUrl = "https://api.github.com/repos/" .. REPOSITORY .. "/commits/" .. BRANCH
	local apiOk, apiBody = pcall(fetch, apiUrl)
	if apiOk then
		local decodeOk, data = pcall(function()
			return httpService:JSONDecode(apiBody)
		end)
		if decodeOk and type(data) == "table" and isCommitSha(data.sha) then
			return string.lower(data.sha)
		end
	end
	local feedUrl = "https://github.com/" .. REPOSITORY .. "/commits/" .. BRANCH .. ".atom"
	local feed = fetch(feedUrl)
	local sha = feed:match("GITCOMMIT/([%x]+)")
	if isCommitSha(sha) then
		return string.lower(sha)
	end
	error("Não foi possível resolver o último commit de " .. REPOSITORY .. ".", 2)
end

-- ModuleAPI
local API = {
	Repository = REPOSITORY,
	Branch = BRANCH,
	Commit = nil,
	ExecutorName = ExecutorName,
	SharedEnvironment = SharedEnvironment,
	Cache = {},
	Sources = {},
	ExternalSources = {},
	Loading = {},
	Config = nil,
	Roblox = nil,
	Player = nil,
	Runtime = nil,
	Util = nil,
	Services = {},
	Features = {},
	UI = {},
}

function API:Fetch(url)
	local cached = self.ExternalSources[url]
	if cached ~= nil then
		return cached
	end
	return fetch(url)
end
function API:Compile(source, chunkName)
	local compiler = loadstring
	if type(compiler) ~= "function" then
		error("loadstring não está disponível neste executor.", 2)
	end
	return compiler(source, chunkName)
end
function API:Require(modulePath)
	if type(modulePath) ~= "string" or not modulePath:match("^src[%w_/%-]+$") or modulePath:find("..", 1, true) then
		error("Caminho de módulo inválido: " .. tostring(modulePath), 2)
	end
	if self.Cache[modulePath] ~= nil then
		return self.Cache[modulePath]
	end
	if self.Loading[modulePath] then
		error("Dependência circular detectada em " .. modulePath .. ".", 2)
	end
	self.Loading[modulePath] = true
	local ok, result = xpcall(function()
		local source = self.Sources[modulePath]
		if type(source) ~= "string" or source == "" then
			local url = "https://raw.githubusercontent.com/"
				.. self.Repository
				.. "/"
				.. self.Commit
				.. "/"
				.. modulePath
				.. ".luau"
			source = self:Fetch(url)
		end
		local chunk, compileError = self:Compile(source, "@" .. modulePath .. "@" .. self.Commit)
		if not chunk then
			error("Erro ao compilar " .. modulePath .. ": " .. tostring(compileError), 2)
		end
		local factory = chunk()
		if type(factory) ~= "function" then
			error("O módulo " .. modulePath .. " precisa retornar uma fábrica.", 2)
		end
		local exported = factory(self)
		if exported == nil then
			error("O módulo " .. modulePath .. " não retornou uma API.", 2)
		end
		return exported
	end, function(errorMessage)
		return tostring(errorMessage)
	end)
	self.Loading[modulePath] = nil
	if not ok then
		error("Falha ao carregar " .. modulePath .. ": " .. tostring(result), 0)
	end
	self.Cache[modulePath] = result
	return result
end

-- ParallelLoading
local function fetchParallel(jobs, concurrency)
	local failures = {}
	local nextJob = 1
	local activeJobs = 0
	while nextJob <= #jobs or activeJobs > 0 do
		while activeJobs < concurrency and nextJob <= #jobs do
			local job = jobs[nextJob]
			nextJob += 1
			activeJobs += 1
			task.spawn(function()
				local ok, jobError = pcall(function()
					local value = job.Run()
					job.Complete(value)
				end)
				if not ok then
					if job.Optional then
						pcall(job.Complete, false)
					else
						failures[job.Name] = tostring(jobError)
					end
				end
				activeJobs -= 1
			end)
		end
		if activeJobs > 0 then
			task.wait()
		end
	end
	for _, job in ipairs(jobs) do
		if failures[job.Name] then
			error("Falha ao carregar " .. job.Name .. ": " .. failures[job.Name], 2)
		end
	end
end
local function moduleUrl(modulePath)
	return "https://raw.githubusercontent.com/" .. API.Repository .. "/" .. API.Commit .. "/" .. modulePath .. ".luau"
end
local function preloadModules(modulePaths, externalSources)
	local jobs = {}
	for _, modulePath in ipairs(modulePaths) do
		local path = modulePath
		if API.Sources[path] == nil then
			jobs[#jobs + 1] = {
				Name = path,
				Run = function()
					return fetch(moduleUrl(path))
				end,
				Complete = function(source)
					API.Sources[path] = source
				end,
			}
		end
	end
	for _, sourceInfo in ipairs(externalSources or {}) do
		local name = sourceInfo.Name
		local url = sourceInfo.Url
		if API.ExternalSources[url] == nil then
			jobs[#jobs + 1] = {
				Name = name,
				Optional = sourceInfo.Optional == true,
				Run = function()
					return fetch(url)
				end,
				Complete = function(source)
					API.ExternalSources[url] = source
				end,
			}
		end
	end
	fetchParallel(jobs, 8)
end
local function compileFactory(modulePath)
	local chunk, compileError = API:Compile(API.Sources[modulePath], "@" .. modulePath .. "@" .. API.Commit)
	if not chunk then
		error("Erro ao compilar " .. modulePath .. ": " .. tostring(compileError), 2)
	end
	local factory = chunk()
	if type(factory) ~= "function" then
		error("O módulo " .. modulePath .. " precisa retornar uma fábrica.", 2)
	end
	return factory
end
local function collectModulePaths(manifest)
	local paths = {}
	local added = {}
	local function add(path)
		if type(path) == "string" and not added[path] then
			added[path] = true
			paths[#paths + 1] = path
		end
	end
	for _, path in ipairs({
		"src/Main",
		"src/Core/Config",
		"src/Core/RobloxServices",
		"src/Core/Runtime",
		"src/Core/Util",
		"src/Manifest",
		"src/UI/Window",
		"src/UI/Orion",
		"src/UI/Settings",
		"src/UI/ControlRegistry",
	}) do
		add(path)
	end
	for _, groupName in ipairs({ "Services", "Features" }) do
		for _, entry in ipairs(manifest[groupName] or {}) do
			add(entry.Path)
		end
	end

	return paths
end

-- Bootstrap
local function clearAPI()
	for _, key in ipairs({ "Cache", "Sources", "ExternalSources", "Loading", "Services", "Features", "UI", "TabIcons" }) do
		local value = API[key]
		if type(value) == "table" then
			table.clear(value)
		end
		API[key] = nil
	end
	for _, key in ipairs({ "Config", "Roblox", "Player", "Runtime", "Util", "SharedEnvironment" }) do
		API[key] = nil
	end
end
local function bootstrap()
	API.Commit = resolveLatestCommit()
	preloadModules({ "src/Manifest", "src/Core/Config" })
	local manifest = compileFactory("src/Manifest")(API)
	local config = compileFactory("src/Core/Config")(API)
	if type(manifest) ~= "table" or type(config) ~= "table" then
		error("O manifest ou a configuração do Chorus está inválido.", 2)
	end
	API.Config = config
	local modulePaths = collectModulePaths(manifest)
	local externalSources = { { Name = "a biblioteca Orion", Url = config.OrionSource } }
	API.TabIcons = TAB_ICONS
	local canLoadCustomAsset = (type(getcustomasset) == "function" or type(getsynasset) == "function")
		and type(writefile) == "function"
	if canLoadCustomAsset then
		for tabName, icon in pairs(TAB_ICONS) do
			local fileExists = false
			if type(isfile) == "function" then
				local ok, exists = pcall(isfile, config.ConfigFolder .. "/" .. icon.FileName)
				fileExists = ok and exists == true
			end
			if not fileExists then
				externalSources[#externalSources + 1] = {
					Name = "o ícone da aba " .. tabName,
					Url = icon.Source,
					Optional = true,
				}
			end
		end
	end
	preloadModules(modulePaths, externalSources)
	API:Require("src/Main")
	if not API.Runtime then
		error("O runtime do Chorus não foi inicializado.", 2)
	end
	API.Runtime:OnShutdown(clearAPI)
end
task.defer(function()
	print("[Chorus Loader] Executor: " .. ExecutorName)
	local ok, errorMessage = xpcall(bootstrap, formatError)
	if not ok then
		if API.Runtime and type(API.Runtime.Shutdown) == "function" then
			pcall(API.Runtime.Shutdown, API.Runtime)
		end
		clearAPI()
		warn("[Chorus Loader] " .. tostring(errorMessage))
	end
	if rawget(SharedEnvironment, BOOTSTRAP_KEY) == BootstrapToken then
		rawset(SharedEnvironment, BOOTSTRAP_KEY, nil)
	end
end)
