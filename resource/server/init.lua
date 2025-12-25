---@class NvCore
---@field private _initialized boolean
---@field private _ready boolean
---@field private _readyCallbacks function[]
---@field Functions table
---@field Constants table
---@field Database Postgres
---@field Cache RedisCache
NvCore = {
	_initialized = false,
	_ready = false,
	_readyCallbacks = {},
	Functions = {},
	Constants = {},
	Database = nil,
	Cache = nil,
}

local logger = require "shared.logger"

--- Public API: Warte auf Ready State
---@param callback function Callback der aufgerufen wird wenn Core bereit ist
function NvCore.OnReady(callback)
	if NvCore._ready then
		-- Bereits bereit, führe sofort aus
		callback()
	else
		-- Warte auf Ready
		table.insert(NvCore._readyCallbacks, callback)
	end
end

--- Public API: Prüfe Ready State
---@return boolean
function NvCore.IsReady()
	return NvCore._ready
end

local function initializeStage4()
	logger:info("^6[NvCore] Stage 4: Finalization^0")

	-- Setze Ready State
	NvCore._ready = true

	-- Trigger alle Ready Callbacks
	for _, callback in ipairs(NvCore._readyCallbacks) do
		local success, err = pcall(callback)
		if not success then
			logger:error("Error in ready callback", { error = err })
		end
	end

	-- Clear Callbacks
	NvCore._readyCallbacks = {}

	-- Trigger Global Event
	TriggerEvent("noverna:core:ready")

	logger:info("^2^1[NvCore] Framework Ready!^0")
	logger:info(string.format("^2[NvCore] Version: %s^0", NvCore.Constants.VERSION))
end

local function initializeStage3()
	logger:info("^6[NvCore] Stage 3: Loading Core Modules^0")

	CreateThread(function()
		-- Lade Storage Layer
		--require "server.storage.player_storage"
		--require "server.storage.vehicle_storage"

		-- Lade Core Functions
		--require "server.functions.player"
		--require "server.functions.inventory"

		-- Lade Event System
		--require "server.events.core_events"

		-- Lade Callback System
		--require "server.callbacks"

		logger:info("^2[NvCore] Stage 3 Complete^0")
		initializeStage4()
	end)
end

local function initializeStage2()
	logger:info("^6[NvCore] Stage 2: Loading Dependencies^0")

	CreateThread(function()
		local maxRetries = 3
		local retryDelay = 5000

		-- Load Cache mit Retry
		local cacheLoaded = false
		for i = 1, maxRetries do
			local Cache = exports["noverna-cache"]
			if Cache and Cache:isReady() then
				NvCore.Cache = Cache
				cacheLoaded = true
				logger:info("^2[NvCore] Cache loaded successfully^0")
				break
			end

			if i < maxRetries then
				logger:warn(string.format("^3[NvCore] Cache not ready, retry %d/%d in %dms^0",
					i, maxRetries, retryDelay))
				Wait(retryDelay)
			end
		end

		if not cacheLoaded then
			logger:error("^1[NvCore] CRITICAL: Cache failed to load after retries^0")
			return
		end

		-- Load Database mit Retry
		local dbLoaded = false
		for i = 1, maxRetries do
			local Database = exports["noverna-database"]
			if Database and Database:isReady() then
				NvCore.Database = Database
				dbLoaded = true
				logger:info("^2[NvCore] Database loaded successfully^0")
				break
			end

			if i < maxRetries then
				logger:warn(string.format("^3[NvCore] Database not ready, retry %d/%d in %dms^0",
					i, maxRetries, retryDelay))
				Wait(retryDelay)
			end
		end

		if not dbLoaded then
			logger:error("^1[NvCore] CRITICAL: Database failed to load after retries^0")
			return
		end

		-- Stage 2 abgeschlossen
		logger:info("^2[NvCore] Stage 2 Complete^0")
		initializeStage3()
	end)
end

local function initializeStage1()
	logger:info("Initializing NvCore Stage 1...")

	NvCore.Constants = require "resource.server.constants"

	NvCore.Exports = require "resource.server.exports.init"
	NvCore.Exports:RegisterNamespace("Constants", NvCore.Constants)
	NvCore.Exports:RegisterNamespace("Validation", require "resource.server.validation")

	-- Initialize Core Tables
	NvCore.Functions = {}
	NvCore.Players = {}

	--- Initialize Commands
	-- require "resource.server.commands"

	NvCore._initialized = true
	logger:info("NvCore Stage 1 Initialized.")
end


CreateThread(function()
	initializeStage1()
	Wait(1000) -- Kurze Verzögerung vor Stage 2
	initializeStage2()
end)

-- Public API: Get Core Object
--- Shouldn't be used instead use namespaces via ExportManager
--- example: exports["noverna-core"]:GetNamespace("Constants")
---
--- The Next Example only works if your personal resource uses ox_lib
--- or use the require '@noverna-core.resource.server.init' to get the Core Object, with the Ready Callback
--- @return NvCore
exports("GetCoreObject", function()
	return NvCore
end)

--[[
local NvCore = exports["noverna-core"]:GetCoreObject()

-- Warte auf Ready State
NvCore.OnReady(function()
  print("Core ist bereit, starte Inventory System")

  -- Jetzt sicher Database/Cache nutzen
  local items = NvCore.Database:query("SELECT * FROM items")
end)
]]

return NvCore
