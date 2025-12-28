local BaseStorage = require 'resource.server.storage.base_storage'
local logger = require 'shared.logger'

---@class LogSystemStorage : BaseStorage
local LogSystemStorage = {}
setmetatable(LogSystemStorage, { __index = BaseStorage })

--- Erstellt eine neue LogSystemStorage-Instanz
---@return LogSystemStorage
function LogSystemStorage:new()
	local self = BaseStorage:new({
		name = 'log_system',
		cachePrefix = 'storage:logs:system',
		defaultTTL = 1800, -- 30 Minuten Cache für Logs
		enableCache = true,
	})

	setmetatable(self, { __index = LogSystemStorage })
	return self
end

--- Erstellt einen neuen System-Log-Eintrag
---@param data table { level: string, category: string, message: string, stack_trace?: string, resource_name?: string, source_file?: string, line_number?: number, metadata?: table, server_id?: string, server_uptime?: number }
---@return number|nil logId
---@return string|nil error
---@async
function LogSystemStorage:createLog(data)
	-- Validierung
	if not data.level or not data.category or not data.message then
		return nil, "Missing required fields: level, category, message"
	end

	local query = [[
		INSERT INTO logs.system (
			level, category, message, stack_trace, resource_name,
			source_file, line_number, metadata, server_id, server_uptime
		) VALUES (
			:level, :category, :message, :stack_trace, :resource_name,
			:source_file, :line_number, :metadata, :server_id, :server_uptime
		) RETURNING id
	]]

	local params = {
		level = data.level,
		category = data.category,
		message = data.message,
		stack_trace = data.stack_trace,
		resource_name = data.resource_name or GetCurrentResourceName(),
		source_file = data.source_file,
		line_number = data.line_number,
		metadata = data.metadata and json.encode(data.metadata) or nil,
		server_id = data.server_id,
		server_uptime = data.server_uptime,
	}

	local insertId, err = self:create(query, params)
	if err then
		logger:error("Failed to create system log: " .. err)
		return nil, err
	end

	return insertId, nil
end

--- Holt einen Log-Eintrag nach ID
---@param logId number
---@param options? table { forceDb: boolean }
---@return table|nil log
---@return string|nil error
---@async
function LogSystemStorage:getLog(logId, options)
	local query = [[
		SELECT * FROM logs.system
		WHERE id = :id
	]]

	local params = { id = logId }
	return self:get(logId, query, params, options)
end

--- Holt Logs nach Level
---@param level string Log-Level ('debug', 'info', 'warn', 'error', 'critical')
---@param limit? number Max. Anzahl (Standard: 100)
---@param offset? number Offset für Pagination (Standard: 0)
---@return table[]|nil logs
---@return string|nil error
---@async
function LogSystemStorage:getLogsByLevel(level, limit, offset)
	limit = limit or 100
	offset = offset or 0

	local cacheKey = string.format("%s:level:%s:%d:%d", self.config.cachePrefix, level, limit, offset)

	local query = [[
		SELECT * FROM logs.system
		WHERE level = :level
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]]

	local params = {
		level = level,
		limit = limit,
		offset = offset,
	}

	return self:customQuery(cacheKey, query, params, {
		ttl = 300, -- 5 Minuten Cache für Listen
		single = false,
	})
end

--- Holt Logs nach Kategorie
---@param category string Kategorie (z.B. 'database', 'network', 'resource')
---@param limit? number Max. Anzahl (Standard: 100)
---@param offset? number Offset für Pagination (Standard: 0)
---@return table[]|nil logs
---@return string|nil error
---@async
function LogSystemStorage:getLogsByCategory(category, limit, offset)
	limit = limit or 100
	offset = offset or 0

	local cacheKey = string.format("%s:category:%s:%d:%d", self.config.cachePrefix, category, limit, offset)

	local query = [[
		SELECT * FROM logs.system
		WHERE category = :category
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]]

	local params = {
		category = category,
		limit = limit,
		offset = offset,
	}

	return self:customQuery(cacheKey, query, params, {
		ttl = 300,
		single = false,
	})
end

--- Holt Logs nach Resource
---@param resourceName string Name der Resource
---@param limit? number Max. Anzahl (Standard: 100)
---@param offset? number Offset für Pagination (Standard: 0)
---@return table[]|nil logs
---@return string|nil error
---@async
function LogSystemStorage:getLogsByResource(resourceName, limit, offset)
	limit = limit or 100
	offset = offset or 0

	local cacheKey = string.format("%s:resource:%s:%d:%d", self.config.cachePrefix, resourceName, limit, offset)

	local query = [[
		SELECT * FROM logs.system
		WHERE resource_name = :resource_name
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]]

	local params = {
		resource_name = resourceName,
		limit = limit,
		offset = offset,
	}

	return self:customQuery(cacheKey, query, params, {
		ttl = 300,
		single = false,
	})
end

--- Sucht Logs nach Message (Full-Text Search wäre hier besser, aber einfaches LIKE für Demo)
---@param searchTerm string Suchbegriff
---@param limit? number Max. Anzahl (Standard: 50)
---@return table[]|nil logs
---@return string|nil error
---@async
function LogSystemStorage:searchLogs(searchTerm, limit)
	limit = limit or 50

	local query = [[
		SELECT * FROM logs.system
		WHERE message ILIKE :search
		ORDER BY created_at DESC
		LIMIT :limit
	]]

	local params = {
		search = '%' .. searchTerm .. '%',
		limit = limit,
	}

	-- Keine Cache für Suchresultate
	return self:customQuery(nil, query, params, {
		single = false,
		skipCache = true,
	})
end

--- Holt die neuesten Logs
---@param limit? number Max. Anzahl (Standard: 50)
---@return table[]|nil logs
---@return string|nil error
---@async
function LogSystemStorage:getRecentLogs(limit)
	limit = limit or 50

	local cacheKey = string.format("%s:recent:%d", self.config.cachePrefix, limit)

	local query = [[
		SELECT * FROM logs.system
		ORDER BY created_at DESC
		LIMIT :limit
	]]

	local params = { limit = limit }

	return self:customQuery(cacheKey, query, params, {
		ttl = 60, -- 1 Minute Cache für recent logs
		single = false,
	})
end

--- Holt Logs in einem Zeitbereich
---@param startTime string|number Start-Zeitpunkt (ISO string oder Unix timestamp)
---@param endTime string|number End-Zeitpunkt (ISO string oder Unix timestamp)
---@param limit? number Max. Anzahl (Standard: 100)
---@return table[]|nil logs
---@return string|nil error
---@async
function LogSystemStorage:getLogsByTimeRange(startTime, endTime, limit)
	limit = limit or 100

	local query = [[
		SELECT * FROM logs.system
		WHERE created_at BETWEEN :start_time AND :end_time
		ORDER BY created_at DESC
		LIMIT :limit
	]]

	local params = {
		start_time = startTime,
		end_time = endTime,
		limit = limit,
	}

	-- Keine Cache für Zeitbereich-Queries
	return self:customQuery(nil, query, params, {
		single = false,
		skipCache = true,
	})
end

--- Zählt Logs nach Level
---@param level string Log-Level
---@return number|nil count
---@return string|nil error
---@async
function LogSystemStorage:countByLevel(level)
	local cacheKey = string.format("%s:count:level:%s", self.config.cachePrefix, level)

	local query = [[
		SELECT COUNT(*) as count FROM logs.system
		WHERE level = :level
	]]

	local params = { level = level }

	local result, err = self:customQuery(cacheKey, query, params, {
		ttl = 600, -- 10 Minuten Cache für Counts
		single = true,
	})

	if err then
		return nil, err
	end

	return result and result.count or 0, nil
end

--- Löscht alte Logs (älter als X Tage)
---@param daysToKeep number Anzahl Tage die behalten werden sollen
---@return number|nil deletedCount
---@return string|nil error
---@async
function LogSystemStorage:deleteOldLogs(daysToKeep)
	local query = [[
		DELETE FROM logs.system
		WHERE created_at < NOW() - INTERVAL ':days days'
	]]

	local params = { days = daysToKeep }

	local rowCount, err = self.db:execute(query, params)
	if err then
		logger:error("Failed to delete old logs: " .. err)
		return nil, err
	end

	-- Alle Caches invalidieren nach Massenlöschung
	self:invalidateAll()

	logger:info(string.format("Deleted %d old system logs (older than %d days)", rowCount, daysToKeep))
	return rowCount, nil
end

--- Override: Extrahiert Identifier aus Log-Row
---@param row table
---@return number|nil
function LogSystemStorage:extractIdentifier(row)
	return row.id
end

return LogSystemStorage
