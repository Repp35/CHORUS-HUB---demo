-- Chorus - MM2 | Delta
-- Entry point: resolves main once, then loads every module from that commit.

local MM2_GAME_ID = 66654135
local REPOSITORY = "Repp35/CHORUS-HUB---demo"
local BRANCH = "main"
local RUNTIME_KEY = "__ChorusMM2DeltaRuntime"

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
local PreviousRuntime = rawget(SharedEnvironment, RUNTIME_KEY)
local isMM2 = false
pcall(function()
	isMM2 = game.PlaceId == MM2_GAME_ID or game.GameId == MM2_GAME_ID
end)

if not isMM2 then
	if type(PreviousRuntime) == "table" and type(PreviousRuntime.Shutdown) == "function" then
		pcall(PreviousRuntime.Shutdown, PreviousRuntime)
	end
	return
end

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

	-- GitHub's Atom feed is a fallback if the unauthenticated API is rate limited.
	local feedUrl = "https://github.com/" .. REPOSITORY .. "/commits/" .. BRANCH .. ".atom"
	local feed = fetch(feedUrl)
	local sha = feed:match("GITCOMMIT/([%x]+)")
	if isCommitSha(sha) then
		return string.lower(sha)
	end
	error("Não foi possível resolver o último commit de " .. REPOSITORY .. ".", 2)
end

local latestCommitOk, commitOrError = pcall(resolveLatestCommit)
if not latestCommitOk then
	warn("[Chorus Loader] " .. tostring(commitOrError))
	return
end

local API = {
	Repository = REPOSITORY,
	Branch = BRANCH,
	Commit = commitOrError,
	SharedEnvironment = SharedEnvironment,
	Cache = {},
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
	if type(modulePath) ~= "string"
		or not modulePath:match("^src[%w_/%-]+$")
		or modulePath:find("..", 1, true) then
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
		local url = "https://raw.githubusercontent.com/" .. self.Repository
			.. "/" .. self.Commit .. "/" .. modulePath .. ".lua"
		local source = self:Fetch(url)
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
	end, formatError)
	self.Loading[modulePath] = nil
	if not ok then
		error("Falha ao carregar " .. modulePath .. ": " .. tostring(result), 2)
	end

	self.Cache[modulePath] = result
	return result
end

local ok, errorMessage = xpcall(function()
	API:Require("src/Main")
end, formatError)
if not ok then
	if API.Runtime and type(API.Runtime.Shutdown) == "function" then
		pcall(API.Runtime.Shutdown, API.Runtime)
	end
	warn("[Chorus Loader] " .. tostring(errorMessage))
end
