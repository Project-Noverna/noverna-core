local BaseStorage = require 'resource.server.storage.base_storage'
local logger = require 'shared.logger'

---@class CharacterStorage : BaseStorage
local CharacterStorage = {}
setmetatable(CharacterStorage, { __index = BaseStorage })

--- Erstellt eine neue CharacterStorage-Instanz
---@return CharacterStorage
function CharacterStorage:new()
	local self = BaseStorage:new({
		name = 'character',
		cachePrefix = 'storage:character',
		defaultTTL = 3600, -- 1 Stunde
		enableCache = true,
	})

	setmetatable(self, { __index = CharacterStorage })
	return self
end

--- Holt einen Character nach ID
---@param characterId number
---@param options? table { forceDb: boolean, includeRelations: boolean }
---@return table|nil character
---@return string|nil error
---@async
function CharacterStorage:getById(characterId, options)
	options = options or {}

	local query
	if options.includeRelations then
		query = [[
			SELECT
				c.*,
				json_agg(DISTINCT jsonb_build_object(
					'account_type', ca.account_type,
					'balance', ca.balance
				)) FILTER (WHERE ca.id IS NOT NULL) as accounts,
				cp.position,
				cm.metadata,
				capp.appearance
			FROM characters c
			LEFT JOIN character_accounts ca ON c.id = ca.character_id
			LEFT JOIN character_positions cp ON c.id = cp.character_id
			LEFT JOIN character_metadata cm ON c.id = cm.character_id
			LEFT JOIN character_appearances capp ON c.id = capp.character_id
			WHERE c.id = :id
			GROUP BY c.id, cp.position, cm.metadata, capp.appearance
		]]
	else
		query = [[
			SELECT * FROM characters
			WHERE id = :id
		]]
	end

	local params = { id = characterId }
	local suffix = options.includeRelations and "full" or nil

	return self:get(characterId, query, params, { suffix = suffix, forceDb = options.forceDb })
end

--- Holt alle Characters eines Users
---@param userId number
---@param options? table { forceDb: boolean }
---@return table[]|nil characters
---@return string|nil error
---@async
function CharacterStorage:getByUserId(userId, options)
	options = options or {}
	local cacheKey = self:getCacheKey(userId, "user")

	-- Cache prüfen
	if self.config.enableCache and not options.forceDb then
		local cached = self.cache:get(cacheKey)
		if cached then
			return cached, nil
		end
	end

	local query = [[
		SELECT * FROM characters
		WHERE user_id = :user_id
		ORDER BY last_played DESC
	]]

	local params = { user_id = userId }

	local result, err = self.db:query(query, params)
	if err then
		return nil, err
	end

	-- Cachen
	if result and self.config.enableCache then
		self.cache:set(cacheKey, result, { ex = self.config.defaultTTL })
	end

	return result, nil
end

--- Erstellt einen neuen Character
---@param data table Character-Daten
---@return number|nil characterId
---@return string|nil error
---@async
function CharacterStorage:createCharacter(data)
	if not data.user_id or not data.first_name or not data.last_name or not data.date_of_birth or not data.sex then
		return nil, "Missing required fields"
	end

	local query = [[
		INSERT INTO characters (
			user_id, first_name, last_name, date_of_birth, sex, height,
			job, job_grade, job_label, gang, gang_grade, gang_label
		) VALUES (
			:user_id, :first_name, :last_name, :date_of_birth, :sex, :height,
			:job, :job_grade, :job_label, :gang, :gang_grade, :gang_label
		) RETURNING id
	]]

	local params = {
		user_id = data.user_id,
		first_name = data.first_name,
		last_name = data.last_name,
		date_of_birth = data.date_of_birth,
		sex = data.sex,
		height = data.height or 180,
		job = data.job or 'unemployed',
		job_grade = data.job_grade or 0,
		job_label = data.job_label,
		gang = data.gang or 'none',
		gang_grade = data.gang_grade or 0,
		gang_label = data.gang_label,
	}

	local characterId, err = self:create(query, params)
	if err then
		logger:error("Failed to create character: " .. err)
		return nil, err
	end

	-- User-Characters Cache invalidieren
	self:invalidateCache(data.user_id, "user")

	return characterId, nil
end

--- Aktualisiert einen Character
---@param characterId number
---@param data table Zu aktualisierende Felder
---@return number rowCount
---@return string|nil error
---@async
function CharacterStorage:updateCharacter(characterId, data)
	local fields = {}
	local params = { id = characterId }

	for key, value in pairs(data) do
		if key ~= "id" and key ~= "user_id" and key ~= "created_at" then
			table.insert(fields, key .. " = :" .. key)
			params[key] = value
		end
	end

	if #fields == 0 then
		return 0, "No fields to update"
	end

	table.insert(fields, "updated_at = NOW()")

	local query = string.format([[
		UPDATE characters
		SET %s
		WHERE id = :id
	]], table.concat(fields, ", "))

	local rowCount, err = self:update(characterId, query, params, {
		invalidateOnly = true,
	})

	-- Full-Relation Cache auch invalidieren
	if rowCount > 0 then
		self:invalidateCache(characterId, "full")
	end

	return rowCount, err
end

--- Aktualisiert Job eines Characters
---@param characterId number
---@param job string Job-Name
---@param grade number Job-Grade
---@param label? string Job-Label
---@return number rowCount
---@return string|nil error
---@async
function CharacterStorage:updateJob(characterId, job, grade, label)
	local query = [[
		UPDATE characters
		SET job = :job, job_grade = :grade, job_label = :label, updated_at = NOW()
		WHERE id = :id
	]]

	local params = {
		id = characterId,
		job = job,
		grade = grade,
		label = label,
	}

	return self:update(characterId, query, params, { invalidateOnly = true })
end

--- Aktualisiert Gang eines Characters
---@param characterId number
---@param gang string Gang-Name
---@param grade number Gang-Grade
---@param label? string Gang-Label
---@return number rowCount
---@return string|nil error
---@async
function CharacterStorage:updateGang(characterId, gang, grade, label)
	local query = [[
		UPDATE characters
		SET gang = :gang, gang_grade = :grade, gang_label = :label, updated_at = NOW()
		WHERE id = :id
	]]

	local params = {
		id = characterId,
		gang = gang,
		grade = grade,
		label = label,
	}

	return self:update(characterId, query, params, { invalidateOnly = true })
end

--- Setzt Character als tot/lebendig
---@param characterId number
---@param isDead boolean
---@return number rowCount
---@return string|nil error
---@async
function CharacterStorage:setDead(characterId, isDead)
	local query = [[
		UPDATE characters
		SET is_dead = :is_dead, updated_at = NOW()
		WHERE id = :id
	]]

	local params = {
		id = characterId,
		is_dead = isDead,
	}

	return self:update(characterId, query, params, { invalidateOnly = true })
end

--- Aktualisiert last_played Timestamp
---@param characterId number
---@return number rowCount
---@return string|nil error
---@async
function CharacterStorage:updateLastPlayed(characterId)
	local query = [[
		UPDATE characters
		SET last_played = NOW(), updated_at = NOW()
		WHERE id = :id
	]]

	local params = { id = characterId }

	return self:update(characterId, query, params, { invalidateOnly = true })
end

--- Löscht einen Character
---@param characterId number
---@return number rowCount
---@return string|nil error
---@async
function CharacterStorage:deleteCharacter(characterId)
	-- Hole character für user_id (um Cache zu invalidieren)
	local char, _ = self:getById(characterId)

	local query = [[
		DELETE FROM characters
		WHERE id = :id
	]]

	local params = { id = characterId }
	local rowCount, err = self:delete(characterId, query, params)

	-- User-Characters Cache invalidieren
	if rowCount > 0 and char then
		self:invalidateCache(char.user_id, "user")
	end

	return rowCount, err
end

--- Holt Character nach Name
---@param firstName string
---@param lastName string
---@return table|nil character
---@return string|nil error
---@async
function CharacterStorage:getByName(firstName, lastName)
	local query = [[
		SELECT * FROM characters
		WHERE first_name = :first_name AND last_name = :last_name
	]]

	local params = {
		first_name = firstName,
		last_name = lastName,
	}

	-- Kein Cache für Namenssuche
	return self:customQuery(nil, query, params, {
		single = true,
		skipCache = true,
	})
end

--- Override: Extrahiert Identifier aus Character-Row
---@param row table
---@return number|nil
function CharacterStorage:extractIdentifier(row)
	return row.id
end

return CharacterStorage
