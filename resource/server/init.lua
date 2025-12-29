---@class NvCore
---@field private _initialized boolean
---@field private _ready boolean
---@field private _readyCallbacks function[]
---@field Functions table
---@field Constants table
---@field Database? Postgres
---@field Cache? RedisCache
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
	logger:info("^6[Noverna] Stage 4: Finalization^0")

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

	logger:info("^2^1[Noverna] Framework Ready!^0")
	logger:info(string.format("^2[Noverna] Version: %s^0", NvCore.Constants.VERSION))
end

local function initializeStage3()
	logger:info("^6[Noverna] Stage 3: Loading Core Modules^0")

	CreateThread(function()
		-- Lade Storage Layer
		--require "server.storage.player_storage"
		--require "server.storage.vehicle_storage"
		local storageManager = require 'resource.server.storage.init'
		NvCore.Storage = storageManager
		-- We will take a look into it, if its better to export each storage individually or to export the whole manager as a namespace
		-- Or we keep the other export to get single storages and let the user decide
		NvCore.Exports:RegisterNamespace("Storage", storageManager)

		-- Lade Core Functions
		--require "server.functions.player"
		--require "server.functions.inventory"

		-- Lade Event System
		--require "server.events.core_events"

		-- Lade Callback System
		--require "server.callbacks"

		logger:info("^2[Noverna] Stage 3 Complete^0")
		initializeStage4()
	end)
end

local function initializeStage2()
	logger:info("^6[Noverna] Stage 2: Loading Dependencies^0")

	CreateThread(function()
		local maxRetries = 3
		local retryDelay = 5000

		-- Load Cache mit Retry
		local cacheLoaded = false
		for i = 1, maxRetries do
			---@class RedisCache
			local Cache = require '@noverna-cache.lib.cache'
			if Cache and Cache:isReady() then
				NvCore.Cache = Cache
				cacheLoaded = true
				logger:info("^2[Noverna] Cache loaded successfully^0")
				break
			end

			if i < maxRetries then
				logger:warn(string.format("^3[Noverna] Cache not ready, retry %d/%d in %dms^0",
					i, maxRetries, retryDelay))
				Wait(retryDelay)
			end
		end

		if not cacheLoaded then
			logger:error("^1[Noverna] CRITICAL: Cache failed to load after retries^0")
			return
		end

		-- Load Database mit Retry
		local dbLoaded = false
		for i = 1, maxRetries do
			---@class Postgres
			local Database = require '@noverna-database.lib.postgres'
			if Database and Database:isReady() then
				NvCore.Database = Database
				dbLoaded = true
				logger:info("^2[Noverna] Database loaded successfully^0")
				break
			end

			if i < maxRetries then
				logger:warn(string.format("^3[Noverna] Database not ready, retry %d/%d in %dms^0",
					i, maxRetries, retryDelay))
				Wait(retryDelay)
			end
		end

		if not dbLoaded then
			logger:error("^1[Noverna] CRITICAL: Database failed to load after retries^0")
			return
		end

		local dbMigrationsEnabled = GetConvar("database_migrations", "true")

		-- Checking if migrations are enabled
		if (dbMigrationsEnabled == "true") then
			logger:info("^3[Noverna]^7 Starting database migrations...")

			local MigrationManager = require "resource.server.database.migration"

			local success, executed = MigrationManager:runPendingMigrations()

			if success then
				logger:info(("^2[Noverna]^7 Database is ready! Executed %d migrations."):format(executed))
			else
				logger:info("^1[Noverna]^7 Migration failed! Check logs above.")
			end
		else
			logger:info("^3[Noverna]^7 Database migrations are disabled via configuration.")
		end

		-- Stage 2 abgeschlossen
		logger:info("^2[Noverna] Stage 2 Complete^0")
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

	SetConvarServerInfo("Noverna Version", NvCore.Constants.VERSION)
	SetConvarServerInfo("Noverna Framework", "Noverna Framework")
	SetConvarServerInfo("Noverna Author", "Noverna Development Team")

	-- Setting random seed to the session
	math.randomseed(os.time() ~ os.clock() * 1000000)

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
--- or you just Listen to this event 'noverna:core:ready' it gets called after the onReady Callbacks
--- @return NvCore
exports("GetCoreObject", function()
	return NvCore
end)

exports("OnReady", function()
	return NvCore.OnReady
end)

--[[
local NvCore = exports["noverna-core"]:GetCoreObject()

-- Warte auf Ready State
NvCore.OnReady(function()
  logger:info("Core ist bereit, starte Inventory System")

  -- Jetzt sicher Database/Cache nutzen
  local items = NvCore.Database:query("SELECT * FROM items")
end)

or:
local Core = exports["noverna-core"]:OnReady(function()
	logger:info("Core ist bereit, starte Inventory System")

  -- Jetzt sicher Database/Cache nutzen
  local items = NvCore.Database:query("SELECT * FROM items")
end)

]]
