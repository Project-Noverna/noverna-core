-- Storage Manager
-- Verwaltet alle registrierten Storage-Instanzen und stellt sie via Exports bereit
local logger = require 'shared.logger'

---@class StorageManager
---@field private storages table<string, BaseStorage>
local StorageManager = {}
StorageManager.__index = StorageManager
StorageManager.storages = {}

--- Registriert einen neuen Storage
---@param name string Name des Storage (z.B. "user", "character")
---@param storage BaseStorage Storage-Instanz
function StorageManager:Register(name, storage)
	if self.storages[name] then
		logger:warn(string.format("Storage '%s' is already registered. Overwriting...", name))
	end

	self.storages[name] = storage

	logger:debug(string.format("Storage '%s' registered successfully", name))
end

--- Holt einen registrierten Storage
---@param name string Name des Storage
---@return BaseStorage|nil
function StorageManager:Get(name)
	local storage = self.storages[name]
	if not storage then
		logger:error(string.format("Storage '%s' not found", name))
		return nil
	end

	return storage
end

--- Prüft ob ein Storage registriert ist
---@param name string Name des Storage
---@return boolean
function StorageManager:Has(name)
	return self.storages[name] ~= nil
end

--- Gibt alle registrierten Storage-Namen zurück
---@return string[]
function StorageManager:GetAll()
	local names = {}
	for name, _ in pairs(self.storages) do
		table.insert(names, name)
	end
	return names
end

--- Wartet bis alle Storages bereit sind
---@param timeout? number Timeout in ms (Standard: 10000)
---@return boolean success
function StorageManager:AwaitAll(timeout)
	timeout = timeout or 10000
	for name, storage in pairs(self.storages) do
		logger:debug(string.format("Waiting for storage '%s' to be ready...", name))
		if not storage:awaitReady(timeout) then
			logger:error(string.format("Storage '%s' failed to initialize", name))
			return false
		end
	end
	logger:info("All storages are ready")
	return true
end

-- Export für andere Resourcen
exports('GetStorage', function(name)
	return StorageManager:Get(name)
end)

return StorageManager
