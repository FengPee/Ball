-- Loads and saves player progress with DataStoreService.
-- In Studio, saving only works with Game Settings > Security > "Enable Studio
-- Access to API Services" turned on. Without it the game still runs; progress
-- just isn't kept between sessions.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Rolls = require(ReplicatedStorage.Shared.Rolls)

local PlayerData = {}

local store
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Config.Data.storeName)
	end)
	if not ok then
		warn("[PlayerData] DataStore unavailable, progress will not save:", err)
	end
end

local function defaults()
	local found = table.create(#Config.Tiers, false)
	found[1] = true
	return {
		v = 1,
		keys = 0,
		dust = 0,
		rolls = 0,
		pity = 0,
		kills = 0,
		zone = 1,
		best = 1,
		found = found,
		equipped = Rolls.starterItem(),
	}
end

local function reconcile(saved)
	local data = defaults()
	if type(saved) ~= "table" then
		return data
	end
	for k, v in saved do
		if data[k] ~= nil and type(v) == type(data[k]) then
			data[k] = v
		end
	end
	for i = 1, #Config.Tiers do
		if type(data.found[i]) ~= "boolean" then
			data.found[i] = false
		end
	end
	local eq = data.equipped
	if type(eq.tier) ~= "number" or not Config.Tiers[eq.tier] or not Config.WeaponTypes[eq.wtype] then
		data.equipped = Rolls.starterItem()
	end
	data.equipped.level = data.equipped.level or 1
	data.zone = math.clamp(data.zone, 1, #Config.Zones)
	return data
end

local function key(player: Player): string
	return "p_" .. player.UserId
end

function PlayerData.load(player: Player)
	if not store then
		return defaults(), false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok then
			return reconcile(result), true
		end
		warn(string.format("[PlayerData] load failed for %s (attempt %d): %s", player.Name, attempt, tostring(result)))
		if RunService:IsStudio() then
			break -- usually "API access disabled": don't make the tester wait
		end
		task.wait(attempt)
	end
	-- Never save over real data we failed to read.
	return defaults(), false
end

function PlayerData.save(player: Player, data, canSave: boolean)
	if not store or not canSave then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(key(player), data)
	end)
	if not ok then
		warn("[PlayerData] save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

return PlayerData
