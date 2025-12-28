-- Storage Initialization
-- Initialisiert und registriert alle Storages
local StorageManager = require 'resource.server.storage.storage_manager'
local logger = require 'shared.logger'

-- Storage-Klassen importieren
local LogSystemStorage = require 'resource.server.storage.log_system_storage'
local UserStorage = require 'resource.server.storage.user_storage'
local CharacterStorage = require 'resource.server.storage.character_storage'

logger:info("Initializing storages...")

-- Warte auf DB und Cache
local success = CreateThread(function()
	-- Storages initialisieren
	local logSystemStorage = LogSystemStorage:new()
	local userStorage = UserStorage:new()
	local characterStorage = CharacterStorage:new()

	-- Warte bis alle bereit sind
	if not logSystemStorage:awaitReady(10000) then
		logger:error("Failed to initialize LogSystemStorage")
		return
	end

	if not userStorage:awaitReady(10000) then
		logger:error("Failed to initialize UserStorage")
		return
	end

	if not characterStorage:awaitReady(10000) then
		logger:error("Failed to initialize CharacterStorage")
		return
	end

	-- Storages registrieren
	StorageManager:Register('log_system', logSystemStorage)
	StorageManager:Register('user', userStorage)
	StorageManager:Register('character', characterStorage)

	logger:info("All storages initialized and registered successfully")
	logger:debug("Registered storages: " .. table.concat(StorageManager:GetAll(), ", "))
end)

return StorageManager
