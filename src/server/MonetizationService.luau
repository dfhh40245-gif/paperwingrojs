--!nonstrict
-- MonetizationService: gamepass ownership, perk aggregation and product receipts.
--
-- Ownership is cached per player and refreshed on join and after a purchase.
-- In Studio (or wherever the Marketplace API is unavailable) the pcall simply
-- reports "not owned", so nothing errors and the game stays playable.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared:WaitForChild("Monetization"))

local MonetizationService = {}

local perksByPlayer: { [Player]: any } = {}
local ownedByPlayer: { [Player]: { [string]: boolean } } = {}
local testOwned: { [Player]: { [string]: boolean } } = {}

-- Set by GameService before Start(); receives (player, productKey, product).
local productHandler: ((Player, string, any) -> boolean)? = nil

function MonetizationService.SetProductHandler(handler)
	productHandler = handler
end

function MonetizationService.GetPerks(player: Player)
	return perksByPlayer[player] or Monetization.EmptyPerks()
end

-- Keys of the passes this player owns, for the store UI.
function MonetizationService.GetOwnedKeys(player: Player): { [string]: boolean }
	return ownedByPlayer[player] or {}
end

function MonetizationService.OwnsPass(player: Player, key: string): boolean
	local owned = ownedByPlayer[player]
	return owned ~= nil and owned[key] == true
end

local function readOwnership(player: Player)
	local owned = {}
	for key, pass in pairs(Monetization.Gamepasses) do
		local forced = testOwned[player]
		if forced and forced[key] then
			owned[key] = true
		elseif Monetization.IsConfigured(pass.Id) then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and result then
				owned[key] = true
			end
		end
	end
	return owned
end

-- Returns true when the aggregated perks changed.
function MonetizationService.Refresh(player: Player): boolean
	local owned = readOwnership(player)
	ownedByPlayer[player] = owned

	local perks = Monetization.Aggregate(owned)

	local previous = perksByPlayer[player]
	perksByPlayer[player] = perks
	if not previous then
		return true
	end
	for _, field in ipairs({ "CoinMult", "GemMult", "DamageMult", "HealthMult", "SpeedMult", "MagnetMult", "LuckMult", "Revives", "ExtraAllySlots", "ExtraProjectiles", "AutoCollect", "Vip" }) do
		if previous[field] ~= perks[field] then
			return true
		end
	end
	return false
end

function MonetizationService.GrantTestPass(player: Player, key: string)
	if not Monetization.Gamepasses[key] then
		return false
	end
	testOwned[player] = testOwned[player] or {}
	testOwned[player][key] = true
	MonetizationService.Refresh(player)
	return true
end

-- Client-requested prompts. Failures (unconfigured pass, API blocked) are
-- reported to the client as a toast rather than thrown.
function MonetizationService.PromptPass(player: Player, key: string): (boolean, string)
	local pass = Monetization.Gamepasses[key]
	if not pass then
		return false, "Unknown pass"
	end
	if not Monetization.IsConfigured(pass.Id) then
		return false, pass.Name .. " is not on sale yet"
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end)
	if not ok then
		warn("[Monetization] prompt failed:", err)
		return false, "Could not open the purchase window"
	end
	return true, ""
end

function MonetizationService.PromptProduct(player: Player, key: string): (boolean, string)
	local product = Monetization.Products[key]
	if not product then
		return false, "Unknown product"
	end
	if not Monetization.IsConfigured(product.Id) then
		return false, product.Name .. " is not on sale yet"
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end)
	if not ok then
		warn("[Monetization] prompt failed:", err)
		return false, "Could not open the purchase window"
	end
	return true, ""
end

local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local key, product = Monetization.ProductByAssetId(receiptInfo.ProductId)
	if not product then
		warn("[Monetization] unknown product id:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not productHandler then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(function()
		return productHandler(player, key, product)
	end)
	if ok and granted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	warn("[Monetization] product grant failed for", player.Name, key, granted)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		-- A receipt must never throw; a thrown error makes Roblox retry forever.
		local ok, decision = pcall(processReceipt, receiptInfo)
		if ok then
			return decision
		end
		warn("[Monetization] ProcessReceipt error:", decision)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end
		if MonetizationService.Refresh(player) then
			MonetizationService.OnPerksChanged(player)
		end
		local key = nil
		for passKey, pass in pairs(Monetization.Gamepasses) do
			if pass.Id == passId then
				key = passKey
				break
			end
		end
		if key then
			MonetizationService.OnPassPurchased(player, key)
		end
	end)
end

-- Assigned by GameService to push state after a change.
MonetizationService.OnPerksChanged = function(_player: Player) end
MonetizationService.OnPassPurchased = function(_player: Player, _key: string) end

function MonetizationService.Forget(player: Player)
	perksByPlayer[player] = nil
	ownedByPlayer[player] = nil
	testOwned[player] = nil
end

return MonetizationService
