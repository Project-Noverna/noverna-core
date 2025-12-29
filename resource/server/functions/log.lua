--- Base Function File for Logging and more

local logger = require 'shared.logger'

local storageManager = require 'resource.server.storage.storage_manager'
local logStorage = storageManager:Get('log')

if not logStorage then
	logger:error("LogStorage is not initialized!")
	return
end

---@class LogModule
local LogModule = {}


return LogModule
