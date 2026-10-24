-- [[ config ]]

-- Configuration
return function()
	local ScriptInfo = {
		Name = "Chorus - MM2 | Delta",
		Author = "Delta",
		Version = "1.0.0",
	}

	local function buildDisplayName(info) return string.format("%s | v%s", info.Name, info.Version) end
	local function buildIntroText(info)
		return table.concat({
			info.Name,
			"Autor: " .. info.Author,
			"Versão: " .. info.Version,
		}, "\n")
	end

	return {
		ScriptInfo = ScriptInfo,
		Name = buildDisplayName(ScriptInfo),
		IntroText = buildIntroText(ScriptInfo),
		ConfigFolder = "ChorusMM2Delta",
		SaveConfig = true,
		HidePremium = true,
		IntroEnabled = true,
		OrionSource = "https://raw.githubusercontent.com/Qanuir/orion-ui/refs/heads/main/source.lua",
		MapRefreshInterval = 1,
	}
end
