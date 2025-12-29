--- Player Connecting Event

local storageManager = require 'resource.server.storage.storage_manager'
local constants = require 'resource.server.constants'
local utils = require 'resource.server.utils'
local validation = require 'resource.server.validation'
local logger = require 'shared.logger'
local GenerateUserIdentifier = utils.GenerateUserIdentifier
local GetPlayerLicense = utils.GetPlayerLicense

---@class Deferrals
---@field defer fun()
---@field update fun(message: string)
---@field presentCard fun(cardType: string, cb: fun(success: boolean, message?: string)) -- We dont use this but its here for completion
---@field done fun(reason?: string)

--- Handels player connection
---@param playerName string
---@param _ fun(reason: string)
---@param deferrals Deferrals
AddEventHandler("playerConnecting", function(playerName, _, deferrals)
	deferrals.defer()
	local src = source -- Get the source of the player connecting

	-- Filter out usernames that contains invalid characters or trying to exploit
	local success, err = validation.validators.username(playerName)

	if not success and err then
		deferrals.done(err)
		return
	end

	if not storageManager:Has("user") then
		deferrals.done(("There was an error, its not your fault, contact server administrator. [Error: %d]")
			:format(constants.ErrorCodes.STORAGE_NOT_FOUND))
		return
	end

	---@class UserStorage : BaseStorage
	local userStorage = storageManager:Get("user")

	local license = GetPlayerLicense(src)

	deferrals.update("Checking user license...")

	if not license then
		deferrals.done("No valid license found. Please ensure you have a valid Rockstar license.")
		return
	end

	local userData = userStorage:getByLicense(license)

	if not userData then
		-- User does not exist, create a new one
		deferrals.update("Creating user account...")
		local newUser = userStorage:createUser({ -- This calls database and cache internally
			license = license,
			username = playerName,
			identifier = GenerateUserIdentifier(playerName, { prefix = "user_" })
		})

		-- If we want to access the new user we can call it throgh the userStorage again or directly over the cache with the key storage:user:<license>
		-- local createdUser = userStorage:getByLicense(license)
		-- local cachedUser = exports["noverna-cache"]:cache:get("storage:user:" .. license)

		-- Failed to create user
		if not newUser then
			deferrals.done("Failed to create user account. Please try again later.")
			return
		end
	end

	-- Checking if the user is Banned or other checks can be done here

	logger:info(("Player '%s' connected with license '%s'"):format(playerName, license))
	deferrals.done()
end)
