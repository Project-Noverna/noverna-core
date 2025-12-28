local BaseStorage = require 'resource.server.storage.base_storage'
local logger = require 'shared.logger'

---@class UserStorage : BaseStorage
local UserStorage = {}
setmetatable(UserStorage, { __index = BaseStorage })

--- Erstellt eine neue UserStorage-Instanz
---@return UserStorage
function UserStorage:new()
	local self = BaseStorage:new({
		name = 'user',
		cachePrefix = 'storage:user',
		defaultTTL = 3600, -- 1 Stunde
		enableCache = true,
	})

	setmetatable(self, { __index = UserStorage })
	return self
end

--- Holt einen User nach License
---@param license string
---@param options? table { forceDb: boolean }
---@return table|nil user
---@return string|nil error
---@async
function UserStorage:getByLicense(license, options)
	local query = [[
		SELECT * FROM users
		WHERE license = :license
	]]

	local params = { license = license }
	return self:get(license, query, params, options)
end

--- Get the User Account by Identifier
---@param identifier string
---@param options? table { forceDb: boolean }
function UserStorage:getByIdentifier(identifier, options)
	local query = [[
		SELECT * FROM users
		WHERE identifier = :identifier
	]]

	local params = { identifier = identifier }
	return self:get(identifier, query, params, options)
end

--- Holt einen User nach ID
---@param userId number
---@param options? table { forceDb: boolean }
---@return table|nil user
---@return string|nil error
---@async
function UserStorage:getById(userId, options)
	local query = [[
		SELECT * FROM users
		WHERE id = :id
	]]

	local params = { id = userId }
	return self:get(userId, query, params, options)
end

--- Holt einen User nach Username
---@param username string
---@param options? table { forceDb: boolean }
---@return table|nil user
---@return string|nil error
---@async
function UserStorage:getByUsername(username, options)
	local cacheKey = self:getCacheKey(username, "username")

	local query = [[
		SELECT * FROM users
		WHERE username = :username
	]]

	local params = { username = username }

	-- Cache prüfen
	if self.config.enableCache and not (options and options.forceDb) then
		local cached = self.cache:get(cacheKey)
		if cached then
			return cached, nil
		end
	end

	-- Aus DB laden
	local result, err = self.db:single(query, params)
	if err then
		return nil, err
	end

	-- Cachen
	if result and self.config.enableCache then
		self.cache:set(cacheKey, result, { ex = self.config.defaultTTL })
	end

	return result, nil
end

--- Erstellt einen neuen User
---@param data table { username: string, license: string, identifier: string }
---@return number|nil userId
---@return string|nil error
---@async
function UserStorage:createUser(data)
	if not data.username or not data.license or not data.identifier then
		return nil, "Missing required fields: username, license, identifier"
	end

	local query = [[
		INSERT INTO users (username, license, identifier, last_connection)
		VALUES (:username, :license, :identifier, NOW())
		RETURNING id
	]]

	local params = {
		username = data.username,
		license = data.license,
		identifier = data.identifier,
	}

	local userId, err = self:create(query, params, {
		identifier = data.license,
		cacheData = {
			id = userId,
			username = data.username,
			license = data.license,
			identifier = data.identifier,
		},
	})

	if err then
		logger:error("Failed to create user: " .. err)
		return nil, err
	end

	return userId, nil
end

--- Aktualisiert die last_connection eines Users
---@param license string
---@return number rowCount
---@return string|nil error
---@async
function UserStorage:updateLastConnection(license)
	local query = [[
		UPDATE users
		SET last_connection = NOW(), updated_at = NOW()
		WHERE license = :license
	]]

	local params = { license = license }

	return self:update(license, query, params, {
		invalidateOnly = true, -- Nur Cache invalidieren
	})
end

--- Aktualisiert einen User
---@param license string
---@param data table Zu aktualisierende Felder
---@return number rowCount
---@return string|nil error
---@async
function UserStorage:updateUser(license, data)
	-- Dynamischen UPDATE-Query bauen
	local fields = {}
	local params = { license = license }

	for key, value in pairs(data) do
		if key ~= "id" and key ~= "license" and key ~= "created_at" then
			table.insert(fields, key .. " = :" .. key)
			params[key] = value
		end
	end

	if #fields == 0 then
		return 0, "No fields to update"
	end

	table.insert(fields, "updated_at = NOW()")

	local query = string.format([[
		UPDATE users
		SET %s
		WHERE license = :license
	]], table.concat(fields, ", "))

	return self:update(license, query, params, {
		invalidateOnly = true,
	})
end

--- Löscht einen User
---@param license string
---@return number rowCount
---@return string|nil error
---@async
function UserStorage:deleteUser(license)
	local query = [[
		DELETE FROM users
		WHERE license = :license
	]]

	local params = { license = license }
	return self:delete(license, query, params)
end

--- Prüft ob ein User existiert
---@param license string
---@return boolean exists
---@async
function UserStorage:exists(license)
	local user, err = self:getByLicense(license)
	return user ~= nil and err == nil
end

--- Holt alle Users (mit Pagination)
---@param limit? number Max. Anzahl (Standard: 50)
---@param offset? number Offset für Pagination (Standard: 0)
---@return table[]|nil users
---@return string|nil error
---@async
function UserStorage:getAll(limit, offset)
	limit = limit or 50
	offset = offset or 0

	local cacheKey = string.format("%s:all:%d:%d", self.config.cachePrefix, limit, offset)

	local query = [[
		SELECT * FROM users
		ORDER BY created_at DESC
		LIMIT :limit OFFSET :offset
	]]

	local params = {
		limit = limit,
		offset = offset,
	}

	return self:customQuery(cacheKey, query, params, {
		ttl = 300, -- 5 Minuten Cache für Listen
		single = false,
	})
end

--- Override: Extrahiert Identifier aus User-Row
---@param row table
---@return string|nil
function UserStorage:extractIdentifier(row)
	return row.license
end

return UserStorage
