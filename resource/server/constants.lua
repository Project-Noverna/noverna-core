---@class NvConstants
local Constants = {}

-- Version Info
Constants.VERSION = "1.0.0"
Constants.BUILD = os.date("%Y%m%d")
Constants.API_VERSION = 1

-- Storage Types
---@enum StorageType
Constants.StorageType = {
	FILE = 1,
	DATABASE = 2,
	REDIS = 3,
	IN_MEMORY = 4,
}

-- Database Table Names (zentral verwaltet)
Constants.Tables = {
	USERS = "users",
	CHARACTERS = "characters",
	VEHICLES = "vehicles",
	ITEMS = "items",
	INVENTORY = "inventory",
	JOBS = "jobs",
	GANGS = "gangs",
}

-- Limits & Thresholds
Constants.Limits = {
	MAX_CHARACTERS_PER_USER = 5,
	MAX_INVENTORY_SLOTS = 50,
	MAX_VEHICLE_STORAGE = 30,
	MAX_MONEY = 999999999,

	-- Rate Limits
	RATE_LIMIT_WINDOW = 60, -- seconds
	RATE_LIMIT_MAX_REQUESTS = 100,
}

-- Timeouts
Constants.Timeouts = {
	DATABASE_QUERY = 30000, -- 30s
	CACHE_OPERATION = 5000, -- 5s
	PLAYER_LOAD = 60000,  -- 60s
	RESOURCE_START = 120000, -- 2min
}

-- Feature Flags (Easy Enable/Disable)
Constants.Features = {
	USE_INVENTORY_WEIGHT = true,
	USE_VEHICLE_KEYS = true,
	USE_PHONE_SYSTEM = true,
	USE_HOUSING_SYSTEM = false, -- In development

	-- Performance Features
	CACHE_PLAYER_DATA = true,
	CACHE_INVENTORY = true,
	USE_LAZY_LOADING = true,
}

-- Performance Settings
Constants.Performance = {
	-- Wie oft soll Player Data gesaved werden? (ms)
	PLAYER_SAVE_INTERVAL = 300000, -- 5min

	-- Cache TTL (seconds)
	CACHE_TTL_SHORT = 60,      -- 1min
	CACHE_TTL_MEDIUM = 300,    -- 5min
	CACHE_TTL_LONG = 3600,     -- 1h
	CACHE_TTL_PERSISTENT = 86400, -- 24h

	-- Batch Sizes
	BATCH_SIZE_SMALL = 10,
	BATCH_SIZE_MEDIUM = 50,
	BATCH_SIZE_LARGE = 100,
}

-- Error Codes (für konsistente Error Handling)
Constants.ErrorCodes = {
	-- General (1000-1999)
	UNKNOWN_ERROR = 1000,
	VALIDATION_ERROR = 1001,
	PERMISSION_DENIED = 1002,
	INVALID_INPUT = 1003,
	TIMEOUT = 1004,

	-- Player (2000-2999)
	PLAYER_NOT_FOUND = 2000,
	PLAYER_NOT_LOADED = 2001,
	CHARACTER_NOT_FOUND = 2002,
	MAX_CHARACTERS_REACHED = 2003,
	PLAYER_BANNED = 2004,

	-- Database (3000-3999)
	DATABASE_ERROR = 3000,
	QUERY_TIMEOUT = 3001,
	CONNECTION_LOST = 3002,
	MIGRATION_FAILED = 3003,

	-- Cache (4000-4999)
	CACHE_ERROR = 4000,
	CACHE_TIMEOUT = 4001,
	CACHE_MISS = 4002,

	-- Storage (5000-5999)
	STORAGE_NOT_FOUND = 5000,
	STORAGE_NOT_READY = 5001,
	STORAGE_OPERATION_FAILED = 5002,
}

Constants.StateBagIdentifier = {
	USER_SESSION = "user:session_id",
	IS_PLAYER_LOADED = "isPlayerLoaded",
	PLAYER_CURRENT_CHARACTER = "currentCharacter",
}

-- Make Constants Immutable
local function makeImmutable(tbl)
	return setmetatable({}, {
		__index = tbl,
		__newindex = function(_, key, _)
			error(string.format("Attempt to modify read-only constant: %s", key))
		end,
		__metatable = false,
		-- Wichtig: auch nested tables schützen
		__pairs = function(t)
			return pairs(tbl)
		end,
		__ipairs = function(t)
			return ipairs(tbl)
		end,
	})
end

-- Schütze alle nested tables
for key, value in pairs(Constants) do
	if type(value) == "table" then
		Constants[key] = makeImmutable(value)
	end
end

-- Schütze Main Table
Constants = makeImmutable(Constants)

return Constants
