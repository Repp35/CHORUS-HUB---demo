-- [[ config ]]

-- Configuration
return function()
	local ScriptInfo = {
		Name = "Chorus - MM2",
		Author = "Delta",
	}

	local function buildDisplayName(info) return string.format("%s - %s", info.Name, info.Author) end
	local function buildIntroText(info)
		return table.concat({
			buildDisplayName(info),
			"Autor: " .. info.Author,
		}, "\n")
	end

	return {
		ScriptInfo = ScriptInfo,
		Name = buildDisplayName(ScriptInfo),
		IntroText = buildIntroText(ScriptInfo),
		ConfigFolder = "ChorusMM2DeltaV2",
		SaveConfig = true,
		HidePremium = true,
		IntroEnabled = true,
		OrionSource = "https://raw.githubusercontent.com/Qanuir/orion-ui/refs/heads/main/source.lua",
		MapRefreshInterval = 1,
	}
end
