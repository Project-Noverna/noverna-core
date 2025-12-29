--- Just for Clarification: We will use the Original DB for Simplicity
--- Technically we should use a seperate Logging DB like ClickHouse or similar for better Performance and Scalability
--- But for now we will keep it simple so everyone can understand it, maybe
--- It would also be smart to use something like Grafana + Prometheus for better Log Visualization and Monitoring
--- we will release a seperate Logging Module in the future

local BaseStorage = require 'resource.server.storage.base_storage'
local logger = require 'shared.logger'

---@class LogStorage : BaseStorage
local LogStorage = {}
setmetatable(LogStorage, { __index = BaseStorage })

---@enum LogLevel
LogStorage.LogLevel = {
	INFO = 'info',
	WARN = 'warn',
	ERROR = 'error',
	DEBUG = 'debug',
	CRITICAL = 'critical',
}

---@enum ActionCategory
LogStorage.ActionCategory = {
	AUTHENTICATION = "auth",
	CHARACTER = "character",
	GAMEPLAY = "gameplay",
	ECONOMY = "economy",
	SOCIAL = "social",
	ADMIN = "admin",
	OTHER = "other",
}

---@enum ActionSeverity
LogStorage.ActionSeverity = {
	LOW = "low",
	MEDIUM = "medium",
	HIGH = "high",
	CRITICAL = "critical",
}

---@enum LogAccountType
LogStorage.LogAccountType = {
	CASH = "cash",
	BANK = "bank",
	CRYPTO = "crypto",
	COMPANY = "company",
	OTHER = "other",
}

---@enum ConnectionType
LogStorage.ConnectionType = {
	CONNECT = "connect",
	DISCONNECT = "disconnect",
	TIMEOUT = "timeout",
	KICKED = "kicked",
	BANNED = "banned",
}

---@enum RespawnType
LogStorage.RespawnType = {
	HOSPITAL = "hospital",
	EMS = "ems",
	ADMIN = "admin",
	BLEEDOUT = "bleedout",
}

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

-- ============================================================================
-- Allgemeine System-Logs
-- ============================================================================

---@class SystemLogCreation
---@field level LogLevel
---@field category string
---@field message string
---@field stack_trace? string
---@field resource_name? string
---@field source_file? string
---@field line_number? number
---@field metadata? table
---@field server_id? string
---@field server_uptime? number
---@field created_at? Date

--- Creates a System Log
---@param data SystemLogCreation
---@return number|nil logId
---@return string|nil error
---@async
function LogStorage:createSystemLog(data)
	if not data.level or not data.category or not data.message then
		return nil, "Missing required fields: level, category, message"
	end

	local query = [[
		INSERT INTO logs.system (
			level, category, message, stack_trace, resource_name,
			source_file, line_number, metadata, server_id, server_uptime
		)
		VALUES (
			:level, :category, :message, :stack_trace, :resource_name,
			:source_file, :line_number, :metadata, :server_id, :server_uptime
		)
		RETURNING id
	]]

	local params = {
		level = data.level,
		category = data.category,
		message = data.message,
		stack_trace = data.stack_trace,
		resource_name = data.resource_name,
		source_file = data.source_file,
		line_number = data.line_number,
		metadata = data.metadata and json.encode(data.metadata) or nil,
		server_id = data.server_id,
		server_uptime = data.server_uptime,
	}

	return self:create(query, params)
end

--- Fetches System Logs with optional filtering, pagination
---
--- I dont Recommend using it, since its better to use external Log Management Tools for better Performance and Scalability
---@param filter? table { level: LogLevel, category: string, resource_name: string, from_date: string, to_date: string }
---@param limit? number
---@param offset? number
---@return table[]|nil logs
---@return string|nil error
---@async
function LogStorage:fetchSystemLogs(filter, limit, offset)
	filter = filter or {}
	limit = limit or 100
	offset = offset or 0

	local conditions = {}
	local params = { limit = limit, offset = offset }

	if filter.level then
		table.insert(conditions, "level = :level")
		params.level = filter.level
	end

	if filter.category then
		table.insert(conditions, "category = :category")
		params.category = filter.category
	end

	if filter.resource_name then
		table.insert(conditions, "resource_name = :resource_name")
		params.resource_name = filter.resource_name
	end

	if filter.from_date then
		table.insert(conditions, "created_at >= :from_date")
		params.from_date = filter.from_date
	end

	if filter.to_date then
		table.insert(conditions, "created_at <= :to_date")
		params.to_date = filter.to_date
	end

	local whereClause = #conditions > 0 and ("WHERE " .. table.concat(conditions, " AND ")) or ""

	local query = string.format([[
		SELECT * FROM logs.system
		%s
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]], whereClause)

	return self:customQuery(nil, query, params, { single = false })
end

-- ============================================================================
-- Player Action Logs
-- ============================================================================

---@class PlayerActionLogCreation
---@field source number
---@field license string
---@field character_id? number
---@field player_name? string
---@field action_type string
---@field action_category ActionCategory
---@field description? string
---@field position? table
---@field zone? string
---@field target_player? number
---@field target_entity? number
---@field metadata? table
---@field ip_address? string
---@field session_id? string

--- Creates a Player Action Log
---@param data PlayerActionLogCreation
---@return number|nil logId
---@return string|nil error
---@async
function LogStorage:createPlayerActionLog(data)
	if not data.source or not data.license or not data.action_type then
		return nil, "Missing required fields: source, license, action_type"
	end

	local query = [[
		INSERT INTO logs.player_actions (
			source, license, character_id, player_name, action_type,
			action_category, description, position, zone, target_player,
			target_entity, metadata, ip_address, session_id
		)
		VALUES (
			:source, :license, :character_id, :player_name, :action_type,
			:action_category, :description, :position, :zone, :target_player,
			:target_entity, :metadata, :ip_address, :session_id
		)
		RETURNING id
	]]

	local params = {
		source = data.source,
		license = data.license,
		character_id = data.character_id,
		player_name = data.player_name,
		action_type = data.action_type,
		action_category = data.action_category or LogStorage.ActionCategory.OTHER,
		description = data.description,
		position = data.position and json.encode(data.position) or nil,
		zone = data.zone,
		target_player = data.target_player,
		target_entity = data.target_entity,
		metadata = data.metadata and json.encode(data.metadata) or nil,
		ip_address = data.ip_address,
		session_id = data.session_id,
	}

	return self:create(query, params)
end

--- Fetches Player Action Logs
---@param filter? table { license: string, character_id: number, action_type: string, action_category: ActionCategory, from_date: string, to_date: string }
---@param limit? number
---@param offset? number
---@return table[]|nil logs
---@return string|nil error
---@async
function LogStorage:fetchPlayerActionLogs(filter, limit, offset)
	filter = filter or {}
	limit = limit or 100
	offset = offset or 0

	local conditions = {}
	local params = { limit = limit, offset = offset }

	if filter.license then
		table.insert(conditions, "license = :license")
		params.license = filter.license
	end

	if filter.character_id then
		table.insert(conditions, "character_id = :character_id")
		params.character_id = filter.character_id
	end

	if filter.action_type then
		table.insert(conditions, "action_type = :action_type")
		params.action_type = filter.action_type
	end

	if filter.action_category then
		table.insert(conditions, "action_category = :action_category")
		params.action_category = filter.action_category
	end

	if filter.from_date then
		table.insert(conditions, "created_at >= :from_date")
		params.from_date = filter.from_date
	end

	if filter.to_date then
		table.insert(conditions, "created_at <= :to_date")
		params.to_date = filter.to_date
	end

	local whereClause = #conditions > 0 and ("WHERE " .. table.concat(conditions, " AND ")) or ""

	local query = string.format([[
		SELECT * FROM logs.player_actions
		%s
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]], whereClause)

	return self:customQuery(nil, query, params, { single = false })
end

-- ============================================================================
-- Chat Logs
-- ============================================================================

---@class ChatLogCreation
---@field source number
---@field license string
---@field character_id? number
---@field sender_name? string
---@field channel string
---@field message string
---@field recipient_character_id? number
---@field recipient_name? string
---@field position? table
---@field zone? string
---@field is_command? boolean
---@field is_blocked? boolean
---@field block_reason? string
---@field metadata? table

--- Creates a Chat Log
---@param data ChatLogCreation
---@return number|nil logId
---@return string|nil error
---@async
function LogStorage:createChatLog(data)
	if not data.source or not data.license or not data.channel or not data.message then
		return nil, "Missing required fields: source, license, channel, message"
	end

	local query = [[
		INSERT INTO logs.chat (
			source, license, character_id, sender_name, channel, message,
			recipient_character_id, recipient_name, position, zone,
			is_command, is_blocked, block_reason, metadata
		)
		VALUES (
			:source, :license, :character_id, :sender_name, :channel, :message,
			:recipient_character_id, :recipient_name, :position, :zone,
			:is_command, :is_blocked, :block_reason, :metadata
		)
		RETURNING id
	]]

	local params = {
		source = data.source,
		license = data.license,
		character_id = data.character_id,
		sender_name = data.sender_name,
		channel = data.channel,
		message = data.message,
		recipient_character_id = data.recipient_character_id,
		recipient_name = data.recipient_name,
		position = data.position and json.encode(data.position) or nil,
		zone = data.zone,
		is_command = data.is_command or false,
		is_blocked = data.is_blocked or false,
		block_reason = data.block_reason,
		metadata = data.metadata and json.encode(data.metadata) or nil,
	}

	return self:create(query, params)
end

--- Fetches Chat Logs
---@param filter? table { license: string, character_id: number, channel: string, from_date: string, to_date: string }
---@param limit? number
---@param offset? number
---@return table[]|nil logs
---@return string|nil error
---@async
function LogStorage:fetchChatLogs(filter, limit, offset)
	filter = filter or {}
	limit = limit or 100
	offset = offset or 0

	local conditions = {}
	local params = { limit = limit, offset = offset }

	if filter.license then
		table.insert(conditions, "license = :license")
		params.license = filter.license
	end

	if filter.character_id then
		table.insert(conditions, "character_id = :character_id")
		params.character_id = filter.character_id
	end

	if filter.channel then
		table.insert(conditions, "channel = :channel")
		params.channel = filter.channel
	end

	if filter.from_date then
		table.insert(conditions, "created_at >= :from_date")
		params.from_date = filter.from_date
	end

	if filter.to_date then
		table.insert(conditions, "created_at <= :to_date")
		params.to_date = filter.to_date
	end

	local whereClause = #conditions > 0 and ("WHERE " .. table.concat(conditions, " AND ")) or ""

	local query = string.format([[
		SELECT * FROM logs.chat
		%s
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]], whereClause)

	return self:customQuery(nil, query, params, { single = false })
end

-- ============================================================================
-- Admin Action Logs
-- ============================================================================

---@class AdminActionLogCreation
---@field admin_license string
---@field admin_character_id? number
---@field admin_name? string
---@field action_type string
---@field action_severity? ActionSeverity
---@field command_used? string
---@field description? string
---@field target_license? string
---@field target_character_id? number
---@field target_name? string
---@field reason? string
---@field duration? number
---@field metadata? table
---@field success? boolean
---@field error_message? string

--- Creates an Admin Action Log
---@param data AdminActionLogCreation
---@return number|nil logId
---@return string|nil error
---@async
function LogStorage:createAdminActionLog(data)
	if not data.admin_license or not data.action_type then
		return nil, "Missing required fields: admin_license, action_type"
	end

	local query = [[
		INSERT INTO logs.admin_actions (
			admin_license, admin_character_id, admin_name, action_type,
			action_severity, command_used, description, target_license,
			target_character_id, target_name, reason, duration, metadata,
			success, error_message
		)
		VALUES (
			:admin_license, :admin_character_id, :admin_name, :action_type,
			:action_severity, :command_used, :description, :target_license,
			:target_character_id, :target_name, :reason, :duration, :metadata,
			:success, :error_message
		)
		RETURNING id
	]]

	local params = {
		admin_license = data.admin_license,
		admin_character_id = data.admin_character_id,
		admin_name = data.admin_name,
		action_type = data.action_type,
		action_severity = data.action_severity or LogStorage.ActionSeverity.MEDIUM,
		command_used = data.command_used,
		description = data.description,
		target_license = data.target_license,
		target_character_id = data.target_character_id,
		target_name = data.target_name,
		reason = data.reason,
		duration = data.duration,
		metadata = data.metadata and json.encode(data.metadata) or nil,
		success = data.success ~= false,
		error_message = data.error_message,
	}

	return self:create(query, params)
end

--- Fetches Admin Action Logs
---@param filter? table { admin_license: string, target_license: string, action_type: string, from_date: string, to_date: string }
---@param limit? number
---@param offset? number
---@return table[]|nil logs
---@return string|nil error
---@async
function LogStorage:fetchAdminActionLogs(filter, limit, offset)
	filter = filter or {}
	limit = limit or 100
	offset = offset or 0

	local conditions = {}
	local params = { limit = limit, offset = offset }

	if filter.admin_license then
		table.insert(conditions, "admin_license = :admin_license")
		params.admin_license = filter.admin_license
	end

	if filter.target_license then
		table.insert(conditions, "target_license = :target_license")
		params.target_license = filter.target_license
	end

	if filter.action_type then
		table.insert(conditions, "action_type = :action_type")
		params.action_type = filter.action_type
	end

	if filter.from_date then
		table.insert(conditions, "created_at >= :from_date")
		params.from_date = filter.from_date
	end

	if filter.to_date then
		table.insert(conditions, "created_at <= :to_date")
		params.to_date = filter.to_date
	end

	local whereClause = #conditions > 0 and ("WHERE " .. table.concat(conditions, " AND ")) or ""

	local query = string.format([[
		SELECT * FROM logs.admin_actions
		%s
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]], whereClause)

	return self:customQuery(nil, query, params, { single = false })
end

-- ============================================================================
-- Economy/Transaction Logs
-- ============================================================================

---@class EconomyLogCreation
---@field license string
---@field character_id? number
---@field player_name? string
---@field transaction_type string
---@field amount number
---@field account_type? LogAccountType
---@field balance_before? number
---@field balance_after? number
---@field reason? string
---@field source? string
---@field target_player? number
---@field company_id? number
---@field metadata? table

--- Creates an Economy Log
---@param data EconomyLogCreation
---@return number|nil logId
---@return string|nil error
---@async
function LogStorage:createEconomyLog(data)
	if not data.license or not data.transaction_type or not data.amount then
		return nil, "Missing required fields: license, transaction_type, amount"
	end

	local query = [[
		INSERT INTO logs.economy (
			license, character_id, player_name, transaction_type, amount,
			account_type, balance_before, balance_after, reason, source,
			target_player, company_id, metadata
		)
		VALUES (
			:license, :character_id, :player_name, :transaction_type, :amount,
			:account_type, :balance_before, :balance_after, :reason, :source,
			:target_player, :company_id, :metadata
		)
		RETURNING id
	]]

	local params = {
		license = data.license,
		character_id = data.character_id,
		player_name = data.player_name,
		transaction_type = data.transaction_type,
		amount = data.amount,
		account_type = data.account_type or LogStorage.LogAccountType.CASH,
		balance_before = data.balance_before,
		balance_after = data.balance_after,
		reason = data.reason,
		source = data.source,
		target_player = data.target_player,
		company_id = data.company_id,
		metadata = data.metadata and json.encode(data.metadata) or nil,
	}

	return self:create(query, params)
end

--- Fetches Economy Logs
---@param filter? table { license: string, character_id: number, transaction_type: string, from_date: string, to_date: string }
---@param limit? number
---@param offset? number
---@return table[]|nil logs
---@return string|nil error
---@async
function LogStorage:fetchEconomyLogs(filter, limit, offset)
	filter = filter or {}
	limit = limit or 100
	offset = offset or 0

	local conditions = {}
	local params = { limit = limit, offset = offset }

	if filter.license then
		table.insert(conditions, "license = :license")
		params.license = filter.license
	end

	if filter.character_id then
		table.insert(conditions, "character_id = :character_id")
		params.character_id = filter.character_id
	end

	if filter.transaction_type then
		table.insert(conditions, "transaction_type = :transaction_type")
		params.transaction_type = filter.transaction_type
	end

	if filter.from_date then
		table.insert(conditions, "created_at >= :from_date")
		params.from_date = filter.from_date
	end

	if filter.to_date then
		table.insert(conditions, "created_at <= :to_date")
		params.to_date = filter.to_date
	end

	local whereClause = #conditions > 0 and ("WHERE " .. table.concat(conditions, " AND ")) or ""

	local query = string.format([[
		SELECT * FROM logs.economy
		%s
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]], whereClause)

	return self:customQuery(nil, query, params, { single = false })
end

-- ============================================================================
-- Connection Logs
-- ============================================================================

---@class ConnectionLogCreation
---@field license string
---@field player_name? string
---@field connection_type ConnectionType
---@field ip_address? string
---@field identifiers? table
---@field session_id? string
---@field session_duration? number
---@field reason? string
---@field kicked_by? string
---@field hardware_id? string
---@field metadata? table

--- Creates a Connection Log
---@param data ConnectionLogCreation
---@return number|nil logId
---@return string|nil error
---@async
function LogStorage:createConnectionLog(data)
	if not data.license or not data.connection_type then
		return nil, "Missing required fields: license, connection_type"
	end

	local query = [[
		INSERT INTO logs.connections (
			license, player_name, connection_type, ip_address, identifiers,
			session_id, session_duration, reason, kicked_by, hardware_id, metadata
		)
		VALUES (
			:license, :player_name, :connection_type, :ip_address, :identifiers,
			:session_id, :session_duration, :reason, :kicked_by, :hardware_id, :metadata
		)
		RETURNING id
	]]

	local params = {
		license = data.license,
		player_name = data.player_name,
		connection_type = data.connection_type,
		ip_address = data.ip_address,
		identifiers = data.identifiers and json.encode(data.identifiers) or nil,
		session_id = data.session_id,
		session_duration = data.session_duration,
		reason = data.reason,
		kicked_by = data.kicked_by,
		hardware_id = data.hardware_id,
		metadata = data.metadata and json.encode(data.metadata) or nil,
	}

	return self:create(query, params)
end

--- Fetches Connection Logs
---@param filter? table { license: string, connection_type: ConnectionType, from_date: string, to_date: string }
---@param limit? number
---@param offset? number
---@return table[]|nil logs
---@return string|nil error
---@async
function LogStorage:fetchConnectionLogs(filter, limit, offset)
	filter = filter or {}
	limit = limit or 100
	offset = offset or 0

	local conditions = {}
	local params = { limit = limit, offset = offset }

	if filter.license then
		table.insert(conditions, "license = :license")
		params.license = filter.license
	end

	if filter.connection_type then
		table.insert(conditions, "connection_type = :connection_type")
		params.connection_type = filter.connection_type
	end

	if filter.from_date then
		table.insert(conditions, "created_at >= :from_date")
		params.from_date = filter.from_date
	end

	if filter.to_date then
		table.insert(conditions, "created_at <= :to_date")
		params.to_date = filter.to_date
	end

	local whereClause = #conditions > 0 and ("WHERE " .. table.concat(conditions, " AND ")) or ""

	local query = string.format([[
		SELECT * FROM logs.connections
		%s
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]], whereClause)

	return self:customQuery(nil, query, params, { single = false })
end

-- ============================================================================
-- Security Logs
-- ============================================================================

---@class SecurityLogCreation
---@field source number
---@field license string
---@field character_id? number
---@field player_name? string
---@field event_type string
---@field severity? ActionSeverity
---@field description string
---@field detection_method? string
---@field triggered_rule? string
---@field evidence? table
---@field action_taken? string
---@field auto_action? boolean
---@field ip_address? string
---@field session_id? string
---@field metadata? table

--- Creates a Security Log
---@param data SecurityLogCreation
---@return number|nil logId
---@return string|nil error
---@async
function LogStorage:createSecurityLog(data)
	if not data.source or not data.license or not data.event_type or not data.description then
		return nil, "Missing required fields: source, license, event_type, description"
	end

	local query = [[
		INSERT INTO logs.security (
			source, license, character_id, player_name, event_type,
			severity, description, detection_method, triggered_rule,
			evidence, action_taken, auto_action, ip_address, session_id, metadata
		)
		VALUES (
			:source, :license, :character_id, :player_name, :event_type,
			:severity, :description, :detection_method, :triggered_rule,
			:evidence, :action_taken, :auto_action, :ip_address, :session_id, :metadata
		)
		RETURNING id
	]]

	local params = {
		source = data.source,
		license = data.license,
		character_id = data.character_id,
		player_name = data.player_name,
		event_type = data.event_type,
		severity = data.severity or LogStorage.ActionSeverity.MEDIUM,
		description = data.description,
		detection_method = data.detection_method,
		triggered_rule = data.triggered_rule,
		evidence = data.evidence and json.encode(data.evidence) or nil,
		action_taken = data.action_taken,
		auto_action = data.auto_action or false,
		ip_address = data.ip_address,
		session_id = data.session_id,
		metadata = data.metadata and json.encode(data.metadata) or nil,
	}

	return self:create(query, params)
end

--- Fetches Security Logs
---@param filter? table { license: string, event_type: string, severity: ActionSeverity, from_date: string, to_date: string }
---@param limit? number
---@param offset? number
---@return table[]|nil logs
---@return string|nil error
---@async
function LogStorage:fetchSecurityLogs(filter, limit, offset)
	filter = filter or {}
	limit = limit or 100
	offset = offset or 0

	local conditions = {}
	local params = { limit = limit, offset = offset }

	if filter.license then
		table.insert(conditions, "license = :license")
		params.license = filter.license
	end

	if filter.event_type then
		table.insert(conditions, "event_type = :event_type")
		params.event_type = filter.event_type
	end

	if filter.severity then
		table.insert(conditions, "severity = :severity")
		params.severity = filter.severity
	end

	if filter.from_date then
		table.insert(conditions, "created_at >= :from_date")
		params.from_date = filter.from_date
	end

	if filter.to_date then
		table.insert(conditions, "created_at <= :to_date")
		params.to_date = filter.to_date
	end

	local whereClause = #conditions > 0 and ("WHERE " .. table.concat(conditions, " AND ")) or ""

	local query = string.format([[
		SELECT * FROM logs.security
		%s
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]], whereClause)

	return self:customQuery(nil, query, params, { single = false })
end

return LogStorage
