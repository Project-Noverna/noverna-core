local dbCommands = GetConvar("enable_database_commands", "false")
local environment = GetConvar("environment", "development")

if dbCommands ~= "true" or environment ~= "development" then return end

local logger = require 'shared.logger'
local dbMigrations = require 'server.database.migration'

logger:info("^2[Database] Be aware that database commands are enabled. This should only be used in development environments.^0")

RegisterCommand("__db:migrate", function(source, args, rawCommand)
	if source > 0 then
		logger:warn("^3[Database Commands] This command can only be run from the server console.^0")
		return
	end

	if not NvCore.Database or not NvCore.Database:isReady() then
		logger:error("^1[Database Commands] Database is not initialized or ready.^0")
		return
	end

	local migrationsRun, err = dbMigrations:runPendingMigrations() -- Add a Custom Method to run migrations even if they were already run on startup and ignore the migration_history
	if err then
		logger:error("^1[Database Commands] Migration failed: " .. tostring(err) .. "^0")
	else
		logger:info("^2[Database Commands] Migrations completed successfully. Total migrations run: " .. tostring(migrationsRun) .. "^0")
	end
end, false)

RegisterCommand("__db:renew", function(source, args, rawCommand)
	if source > 0 then
		logger:warn("^3[Database Commands] This command can only be run from the server console.^0")
		return
	end

	if not NvCore.Database or not NvCore.Database:isReady() then
		logger:error("^1[Database Commands] Database is not initialized or ready.^0")
		return
	end

	-- Sicherheitsabfrage - erfordert Bestätigung
	logger:warn("^1[Database Commands] ==========================================^0")
	logger:warn("^1[Database Commands] ⚠️  WARNING: DATABASE RENEW^0")
	logger:warn("^1[Database Commands] ⚠️  This will DELETE ALL DATA!^0")
	logger:warn("^1[Database Commands] ==========================================^0")
	logger:warn("^3[Database Commands] Type '__db:renew_confirm' to proceed^0")
end, false)

RegisterCommand("__db:renew_confirm", function(source, args, rawCommand)
	if source > 0 then
		logger:warn("^3[Database Commands] This command can only be run from the server console.^0")
		return
	end

	if not NvCore.Database or not NvCore.Database:isReady() then
		logger:error("^1[Database Commands] Database is not initialized or ready.^0")
		return
	end

	logger:info("^3[Database Commands] Starting database renewal process...^0")

	local success, migrationsRun, err = dbMigrations:renewDatabase()

	if not success then
		logger:error("^1[Database Commands] Database renewal failed: " .. tostring(err) .. "^0")
	else
		logger:info("^2[Database Commands] Database renewed successfully!^0")
		logger:info("^2[Database Commands] Migrations executed: " .. tostring(migrationsRun) .. "^0")
	end
end, false)
