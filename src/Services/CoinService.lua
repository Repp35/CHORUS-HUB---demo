return function(API)
	local Config = API.Config
	local CoinService = {}

	function CoinService:NormalizeKind(value)
		if type(value) ~= "string" then
			return nil
		end

		local normalized = string.lower(value)
		if normalized == "candy" then
			return "candy"
		end
		if normalized == "coin" then
			return "coin"
		end
		return nil
	end

	function CoinService:GetKind(part)
		if not part then
			return nil
		end
		local kind = self:NormalizeKind(part:GetAttribute("CoinID"))
		if kind then
			return kind
		end
		return part:FindFirstChild("CoinVisual") and "coin" or nil
	end

	function CoinService:IsCollectable(part, container, respectFarmFilter)
		if not part or not part:IsA("BasePart") or not part.Parent or not container then
			return false
		end
		if not part:IsDescendantOf(container) or part:GetAttribute("Collected") then
			return false
		end
		if not part:FindFirstChild("TouchInterest") then
			return false
		end

		local kind = self:GetKind(part)
		if not kind then
			return false
		end
		local selectedFilter = type(Config.CoinFilter) == "string" and string.lower(Config.CoinFilter) or "todos"
		if respectFarmFilter ~= false and selectedFilter ~= "todos" and kind ~= selectedFilter then
			return false
		end

		local visual = part:FindFirstChild("CoinVisual")
		local isNewMM2Candy = kind == "candy" and part.Transparency == 1
		if visual then
			if visual:GetAttribute("Delete") or visual:GetAttribute("Collected") then
				return false
			end
			local mainCoin = visual:FindFirstChild("MainCoin")
			local visualIsReady = mainCoin and mainCoin:IsA("BasePart") and mainCoin.Transparency < 0.95
			if not visualIsReady and not isNewMM2Candy then
				return false
			end
		elseif not isNewMM2Candy then
			return false
		end
		return true
	end

	function CoinService:GetCollectableParts(container, respectFarmFilter)
		local parts = {}
		if not container then
			return parts
		end
		for _, instance in ipairs(container:GetChildren()) do
			if instance:IsA("BasePart") and self:IsCollectable(instance, container, respectFarmFilter) then
				table.insert(parts, instance)
			end
		end
		return parts
	end

	return CoinService
end
