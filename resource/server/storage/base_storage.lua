-- Base Storage Class
-- Here we handle all the Storages, and export them like the Namespaces but seperately
-- This is done to avoid circular dependencies
local db = require "@noverna-database.lib.postgres"
local cache = require "@noverna-cache.lib.cache"

---@class BaseStorageConfig
---@field name string Name des Storage (z.B. "user", "character")
---@field cachePrefix string Prefix für Cache-Keys (z.B. "storage:user")
---@field defaultTTL number Standard TTL für Cache in Sekunden (Standard: 3600)
---@field enableCache boolean Cache aktivieren? (Standard: true)

---@class BaseStorage
---@field protected config BaseStorageConfig
---@field protected db Postgres
---@field protected cache RedisCache
local BaseStorage = {}
BaseStorage.__index = BaseStorage

--- Erstellt eine neue Storage-Instanz
---@param config BaseStorageConfig
---@return BaseStorage
function BaseStorage:new(config)
	-- Validierung
	if not config.name then
		error("Storage name is required")
	end
	if not config.cachePrefix then
		error("Storage cachePrefix is required")
	end

	local self = setmetatable({}, BaseStorage)
	self.config = {
		name = config.name,
		cachePrefix = config.cachePrefix,
		defaultTTL = config.defaultTTL or 3600,
		enableCache = config.enableCache ~= false,
	}
	self.db = db
	self.cache = cache

	return self
end

--- Generiert einen Cache-Key
---@param identifier string|number Identifier (z.B. user_id, license)
---@param suffix? string Optionaler Suffix (z.B. "metadata")
---@return string
function BaseStorage:getCacheKey(identifier, suffix)
	local key = string.format("%s:%s", self.config.cachePrefix, tostring(identifier))
	if suffix then
		key = key .. ":" .. suffix
	end
	return key
end

--- Holt Daten aus dem Cache oder der Datenbank (Cache-First)
---@param identifier string|number
---@param query string SQL Query
---@param params? table Query Parameter
---@param options? table { ttl: number, suffix: string, forceDb: boolean }
---@return table|nil data
---@return string|nil error
---@async
function BaseStorage:get(identifier, query, params, options)
	options = options or {}
	local cacheKey = self:getCacheKey(identifier, options.suffix)
	local ttl = options.ttl or self.config.defaultTTL

	-- Cache prüfen (wenn aktiviert und nicht force DB)
	if self.config.enableCache and not options.forceDb then
		local cached = self.cache:get(cacheKey)
		if cached then
			return cached, nil
		end
	end

	-- Aus Datenbank laden
	local result, err = self.db:single(query, params)
	if err then
		return nil, err
	end

	-- Im Cache speichern
	if result and self.config.enableCache then
		self.cache:set(cacheKey, result, { ex = ttl })
	end

	return result, nil
end

--- Holt mehrere Datensätze (Cache-First für jeden einzelnen)
---@param identifiers (string|number)[]
---@param queryBuilder fun(ids: table): string, table Funktion die Query + Params generiert
---@param options? table { ttl: number, suffix: string, forceDb: boolean }
---@return table[] data
---@return string|nil error
---@async
function BaseStorage:getMany(identifiers, queryBuilder, options)
	options = options or {}
	local results = {}
	local missingIds = {}
	local cacheKeyMap = {}

	-- Cache prüfen (wenn aktiviert)
	if self.config.enableCache and not options.forceDb then
		for _, id in ipairs(identifiers) do
			local cacheKey = self:getCacheKey(id, options.suffix)
			cacheKeyMap[cacheKey] = id
			local cached = self.cache:get(cacheKey)
			if cached then
				results[id] = cached
			else
				table.insert(missingIds, id)
			end
		end
	else
		missingIds = identifiers
	end

	-- Fehlende Daten aus DB laden
	if #missingIds > 0 then
		local query, params = queryBuilder(missingIds)
		local dbResults, err = self.db:query(query, params)
		if err then
			return {}, err
		end

		-- Ergebnisse zuordnen und cachen
		for _, row in ipairs(dbResults or {}) do
			local id = self:extractIdentifier(row)
			if id then
				results[id] = row
				if self.config.enableCache then
					local cacheKey = self:getCacheKey(id, options.suffix)
					self.cache:set(cacheKey, row, { ex = options.ttl or self.config.defaultTTL })
				end
			end
		end
	end

	-- Array erstellen
	local resultArray = {}
	for _, id in ipairs(identifiers) do
		if results[id] then
			table.insert(resultArray, results[id])
		end
	end

	return resultArray, nil
end

--- Erstellt einen neuen Datensatz
---@param query string INSERT Query
---@param params table Query Parameter
---@param options? table { identifier: string|number, cacheData: table, ttl: number }
---@return number|string|nil insertId
---@return string|nil error
---@async
function BaseStorage:create(query, params, options)
	options = options or {}

	-- In DB einfügen
	local insertId, err = self.db:insert(query, params)
	if err or not insertId then
		return nil, err or "Insert failed"
	end

	-- Cache aktualisieren (wenn Daten bereitgestellt wurden)
	if self.config.enableCache and options.cacheData then
		local identifier = options.identifier or insertId
		local cacheKey = self:getCacheKey(identifier, options.suffix)
		self.cache:set(cacheKey, options.cacheData, { ex = options.ttl or self.config.defaultTTL })
	end

	return insertId, nil
end

--- Aktualisiert einen Datensatz
---@param identifier string|number
---@param query string UPDATE Query
---@param params table Query Parameter
---@param options? table { invalidateOnly: boolean, newData: table, suffix: string }
---@return number rowCount
---@return string|nil error
---@async
function BaseStorage:update(identifier, query, params, options)
	options = options or {}

	-- DB aktualisieren
	local rowCount, err = self.db:update(query, params)
	if err then
		return 0, err
	end

	-- Cache invalidieren oder aktualisieren
	if self.config.enableCache then
		local cacheKey = self:getCacheKey(identifier, options.suffix)

		if options.invalidateOnly or not options.newData then
			-- Nur invalidieren
			self.cache:delete(cacheKey)
		else
			-- Mit neuen Daten aktualisieren
			self.cache:set(cacheKey, options.newData, { ex = self.config.defaultTTL })
		end
	end

	return rowCount, nil
end

--- Löscht einen Datensatz
---@param identifier string|number
---@param query string DELETE Query
---@param params table Query Parameter
---@param options? table { suffix: string }
---@return number rowCount
---@return string|nil error
---@async
function BaseStorage:delete(identifier, query, params, options)
	options = options or {}

	-- Aus DB löschen
	local rowCount, err = self.db:execute(query, params)
	if err then
		return 0, err
	end

	-- Cache invalidieren
	if self.config.enableCache then
		local cacheKey = self:getCacheKey(identifier, options.suffix)
		self.cache:delete(cacheKey)
	end

	return rowCount, nil
end

--- Invalidiert Cache für einen Identifier
---@param identifier string|number
---@param suffix? string
---@return boolean success
function BaseStorage:invalidateCache(identifier, suffix)
	if not self.config.enableCache then
		return true
	end

	local cacheKey = self:getCacheKey(identifier, suffix)
	return self.cache:delete(cacheKey)
end

--- Invalidiert Cache für mehrere Identifiers
---@param identifiers (string|number)[]
---@param suffix? string
---@return number count Anzahl gelöschter Keys
function BaseStorage:invalidateCacheMany(identifiers, suffix)
	if not self.config.enableCache then
		return 0
	end

	local keys = {}
	for _, id in ipairs(identifiers) do
		table.insert(keys, self:getCacheKey(id, suffix))
	end

	return self.cache:deleteMany(keys)
end

--- Invalidiert alle Caches dieses Storage
---@return number count Anzahl gelöschter Keys
function BaseStorage:invalidateAll()
	if not self.config.enableCache then
		return 0
	end

	local pattern = self.config.cachePrefix .. ":*"
	return self.cache:deletePattern(pattern)
end

--- Setzt einen Wert direkt im Cache (ohne DB)
---@param identifier string|number
---@param data table
---@param options? table { ttl: number, suffix: string }
---@return boolean success
function BaseStorage:setCache(identifier, data, options)
	if not self.config.enableCache then
		return false
	end

	options = options or {}
	local cacheKey = self:getCacheKey(identifier, options.suffix)
	return self.cache:set(cacheKey, data, { ex = options.ttl or self.config.defaultTTL })
end

--- Holt einen Wert nur aus dem Cache
---@param identifier string|number
---@param suffix? string
---@return table|nil
function BaseStorage:getCacheOnly(identifier, suffix)
	if not self.config.enableCache then
		return nil
	end

	local cacheKey = self:getCacheKey(identifier, suffix)
	return self.cache:get(cacheKey)
end

--- Führt eine Custom Query aus (mit optionalem Caching)
---@param cacheKey? string Optionaler Cache-Key
---@param query string SQL Query
---@param params? table Query Parameter
---@param options? table { ttl: number, skipCache: boolean, single: boolean }
---@return table|table[]|nil result
---@return string|nil error
---@async
function BaseStorage:customQuery(cacheKey, query, params, options)
	options = options or {}

	-- Cache prüfen
	if cacheKey and self.config.enableCache and not options.skipCache then
		local cached = self.cache:get(cacheKey)
		if cached then
			return cached, nil
		end
	end

	-- Query ausführen
	local result, err
	if options.single then
		result, err = self.db:single(query, params)
	else
		result, err = self.db:query(query, params)
	end

	if err then
		return nil, err
	end

	-- Im Cache speichern
	if cacheKey and result and self.config.enableCache then
		self.cache:set(cacheKey, result, { ex = options.ttl or self.config.defaultTTL })
	end

	return result, nil
end

--- Extrahiert Identifier aus einem Datensatz (muss von Subklassen überschrieben werden)
---@param row table
---@return string|number|nil
function BaseStorage:extractIdentifier(row)
	-- Standard: versuche 'id' zu finden
	return row.id or row.identifier or row.license
end

--- Wartet bis DB und Cache bereit sind
---@param timeout? number Timeout in ms (Standard: 10000)
---@return boolean success
function BaseStorage:awaitReady(timeout)
	timeout = timeout or 10000
	local dbReady = self.db:awaitReady(timeout)
	local cacheReady = self.cache:awaitReady(timeout)
	return dbReady and cacheReady
end

return BaseStorage
