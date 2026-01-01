-- Storage Initialization
-- Initialisiert und registriert alle Storages
local StorageManager = require 'resource.server.storage.storage_manager'
local logger = require 'shared.logger'

-- Storage-Klassen importieren
local UserStorage = require 'resource.server.storage.user_storage'
local CharacterStorage = require 'resource.server.storage.character_storage'
local LogStorage = require 'resource.server.storage.log_storage'
local PenaltyStorage = require 'resource.server.storage.penalty_storage'


logger:info("Initializing storages...")

-- Warte auf DB und Cache
local success = CreateThread(function()
	local userStorage = UserStorage:new()
	local characterStorage = CharacterStorage:new()
	local logStorage = LogStorage:new()
	local penaltyStorage = PenaltyStorage:new()
	-- Warten bis alle Storages bereit sind


	if not userStorage:awaitReady(10000) then
		logger:error("Failed to initialize UserStorage")
		return
	end

	if not characterStorage:awaitReady(10000) then
		logger:error("Failed to initialize CharacterStorage")
		return
	end

	if not logStorage:awaitReady(10000) then
		logger:error("Failed to initialize LogStorage")
		return
	end

	if not penaltyStorage:awaitReady(10000) then
		logger:error("Failed to initialize PenaltyStorage")
		return
	end

	-- Storages registrieren
	StorageManager:Register('user', userStorage)
	StorageManager:Register('character', characterStorage)
	StorageManager:Register('penalty', penaltyStorage)

	-- System relevant storages
	StorageManager:Register('log', logStorage)

	logger:info("All storages initialized and registered successfully")
	logger:debug("Registered storages: " .. table.concat(StorageManager:GetAll(), ", "))
end)

return StorageManager
