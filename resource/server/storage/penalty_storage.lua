--- Penalty Storage Module
--- We handle all types of Database Operations regarding penalties here

local BaseStorage = require 'resource.server.storage.base_storage'
local logger = require 'shared.logger'

---@class PenaltyStorage : BaseStorage
local PenaltyStorage = {}
setmetatable(PenaltyStorage, { __index = BaseStorage })

function PenaltyStorage:new()
	local self = BaseStorage:new({
		name = 'penalty',
		cachePrefix = 'storage:penalty',
		defaultTTL = 600, -- 10 Minuten
		enableCache = true,
	})

	setmetatable(self, { __index = PenaltyStorage })
	return self
end

---@class Penalty
---@field id number
---@field user_id number
---@field reason string
---@field banned_at Date
---@field banned_by string
---@field pardoned boolean
---@field pardon_reason string
---@field pardoned_by string
---@field pardoned_at Date
---@field expires_at Date
---@field created_at Date
---@field updated_at Date

-- Get a Active Penalty for a specific user
---@param userId number
---@return Penalty|nil penalty
---@return string|nil error
---@async
function PenaltyStorage:getActivePenaltyByUserId(userId)
	if not userId then
		logger:error('userId is required')
		return nil, 'userId is required'
	end

	local query = [[
		SELECT * FROM bans
		WHERE user_id = $1
		AND expires_at > NOW()
		LIMIT 1
	]]

	local result, err = self.db:rawQuery(query, { userId })

	if err then
		logger:error(('Failed to get active penalty for userId %d: %s'):format(userId, err))
		return nil, err
	end

	if result and result[1] then
		return result[1], nil
	end

	return nil, nil
end

---@class PenaltyAdd
---@field user_id number
---@field reason string
---@field banned_by? string
---@field expires_at? Date

-- Add a new Penalty
---@param penaltyData PenaltyAdd
---@return number|nil penaltyId
---@return string|nil error
---@async
function PenaltyStorage:addPenalty(penaltyData)
	if not penaltyData.user_id or not penaltyData.reason then
		return nil, 'Invalid penalty data: user_id and reason are required'
	end

	if not penaltyData.banned_by then
		penaltyData.banned_by = 'System'
	end

	if not penaltyData.expires_at then
		-- Default to 30 days ban
		---@diagnostic disable-next-line: assign-type-mismatch
		penaltyData.expires_at = os.date('%Y-%m-%d %H:%M:%S', os.time() + 30 * 24 * 60 * 60)
	end

	local query = [[
		INSERT INTO bans (user_id, reason, banned_by, expires_at, created_at, updated_at)
		VALUES (:user_id, :reason, :banned_by, :expires_at, NOW(), NOW())
		RETURNING id
	]]

	local params = {
		user_id = penaltyData.user_id,
		reason = penaltyData.reason,
		banned_by = penaltyData.banned_by,
		expires_at = penaltyData.expires_at,
	}

	local result, err = self.db:insert(query, params)

	if not result or err then
		logger:error(('Failed to add penalty for userId %d: %s'):format(penaltyData.user_id, err or 'no error'))
		return nil, err
	end

	-- Since the Original Table has 'id' as number, it will guarantee that the returned value is also a number.
	---@diagnostic disable-next-line: return-type-mismatch
	return result, nil
end

--- Pardon a penalty
---@param user_id number
---@param pardonReason string
---@param pardonedBy string
---@return boolean success
---@return string|nil error
---@async
function PenaltyStorage:pardonPenalty(user_id, pardonReason, pardonedBy)
	local query = [[
		UPDATE bans
		SET pardoned = TRUE,
			pardon_reason = :pardon_reason,
			pardoned_by = :pardoned_by,
			pardoned_at = NOW(),
			updated_at = NOW()
		WHERE user_id = :user_id
		AND pardoned = FALSE
		AND expires_at > NOW()
	]]

	local params = {
		user_id = user_id,
		pardon_reason = pardonReason,
		pardoned_by = pardonedBy,
	}

	local result, err = self.db:update(query, params)

	if err then
		logger:error(('Failed to pardon penalty for userId %d: %s'):format(user_id, err))
		return false, err
	end

	if result == 0 then
		return false, 'No active penalty found to pardon'
	end

	return true, nil
end

return PenaltyStorage
