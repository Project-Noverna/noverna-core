-- I will put all Logs and DB Operations in this Storage File

local BaseStorage = require 'resource.server.storage.base_storage'
local logger = require 'shared.logger'

---@class LogStorage : BaseStorage
local LogStorage = {}
setmetatable(LogStorage, { __index = BaseStorage })

--- Erstellt eine neue LogStorage-Instanz
--- @return LogStorage
function LogStorage:new()
	local self = BaseStorage:new({
		name = 'logs',
		cachePrefix = 'storage:logs',
		defaultTTL = 1800, -- 30 Minuten Cache für Logs
		enableCache = true,
	})
	setmetatable(self, { __index = LogStorage })
	return self
end
