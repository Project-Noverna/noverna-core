---@class Migration
local Migration = {}
Migration.__index = Migration

---@class Postgres
local db = require '@noverna-database.lib.postgres'
local logger = require 'shared.logger'

local MIGRATION_PATH = "data/migrations/"
local MIGRATION_TABLE = "migration_history"
local MIGRATION_FILE_PATTERN = "^(%d+)_(.+)%.sql$" -- e.g., 001_initial_setup.sql

---Erstellt eine neue Migration-Instanz
---@return Migration
function Migration:new()
	return setmetatable({}, Migration)
end

---Erstellt die Migration History Tabelle falls nicht vorhanden
---@return boolean success
function Migration:createMigrationTable()
	if not db:isReady() then
		return false
	end

	local query = [[
        CREATE TABLE IF NOT EXISTS migration_history (
            id SERIAL PRIMARY KEY,
            version VARCHAR(50) NOT NULL,
            name VARCHAR(255) NOT NULL,
            checksum VARCHAR(64),
            executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            execution_time_ms INTEGER,
            success BOOLEAN DEFAULT TRUE,
            error_message TEXT,

            CONSTRAINT unique_migration_version UNIQUE(version)
        );

        CREATE INDEX IF NOT EXISTS idx_migration_history_version ON migration_history(version);
        CREATE INDEX IF NOT EXISTS idx_migration_history_executed_at ON migration_history(executed_at);
    ]]

	local result, err = db:rawQuery(query)

	if result then
		return true
	else
		if err then
			logger:info(("^1[Migration]^7 Error details: " .. tostring(err)))
		else
			logger:info("^1[Migration]^7 No error details available - result is nil")
		end
		return false
	end
end

---Berechnet SHA256 Checksum einer Datei
---@param content string Dateiinhalt
---@return string checksum
function Migration:calculateChecksum(content)
	-- Einfacher Hash-Algorithmus (in Production sollte ein richtiger SHA256 verwendet werden)
	local hash = 0
	for i = 1, #content do
		hash = (hash * 31 + string.byte(content, i)) % 4294967296
	end
	return string.format("%x", hash)
end

---Liest alle Migrations-Dateien aus dem Verzeichnis
---@return table<number, {version: string, name: string, filename: string}> migrations
function Migration:loadMigrationFiles()
	local migrations = {}
	local resourceName = GetCurrentResourceName()
	local migrationsPath = ("@%s/%s"):format(resourceName, MIGRATION_PATH)

	-- Lese alle Dateien aus dem Migrations-Verzeichnis
	local dirHandle = io.readdir(migrationsPath)

	if not dirHandle then
		logger:info(("^1[Migration]^7 Failed to read migrations directory: %s"):format(migrationsPath))
		return migrations
	end

	-- Iteriere über alle Dateien im Verzeichnis
	for filename in dirHandle:lines() do
		-- Prüfe ob es eine .sql Datei mit dem richtigen Pattern ist
		if filename:match("%.sql$") then
			local version, name = string.match(filename, MIGRATION_FILE_PATTERN)
			if version and name then
				table.insert(migrations, {
					version = version,
					name = name,
					filename = filename,
					fullPath = MIGRATION_PATH .. filename
				})
			end
		end
	end

	dirHandle:close()

	-- Sortiere nach Version
	table.sort(migrations, function(a, b)
		return tonumber(a.version) < tonumber(b.version)
	end)

	logger:info(("^2[Migration]^7 Discovered %d migration files"):format(#migrations))
	return migrations
end

---Prüft ob eine Migration bereits ausgeführt wurde
---@param version string Version der Migration
---@return boolean executed
function Migration:isMigrationExecuted(version)
	local query = [[
        SELECT version FROM migration_history
        WHERE version = :version AND success = TRUE
        LIMIT 1
    ]]

	local result, err = db:single(query, { version = version })
	if err then
		logger:info(("^1[Migration]^7 Error checking migration status for version %s: %s"):format(version, err))
		return false
	end
	return result ~= nil
end

---Liest den Inhalt einer Migrations-Datei
---@param filepath string Pfad zur Datei
---@return string? content
function Migration:readMigrationFile(filepath)
	local resourceName = GetCurrentResourceName()
	local content = LoadResourceFile(resourceName, filepath)

	if not content then
		logger:info(("^1[Migration]^7 Failed to read migration file: %s"):format(filepath))
		return nil
	end

	return content
end

---Führt eine einzelne Migration aus
---@param migration {version: string, name: string, filename: string, fullPath: string}
---@return boolean success
function Migration:executeMigration(migration)
	logger:info(("^3[Migration]^7 Executing migration %s: %s"):format(migration.version, migration.name))

	local content = self:readMigrationFile(migration.fullPath)
	if not content then
		return false
	end

	local checksum = self:calculateChecksum(content)
	local startTime = GetGameTimer()

	-- Führe die Migration aus (pg führt automatisch als Transaction aus wenn mehrere Statements)
	local result, err = db:rawQuery(content)

	local success = result ~= nil
	if not success then
		logger:info(("^1[Migration]^7 Failed to execute migration SQL: %s"):format(err or "Unknown error"))
	end

	local executionTime = GetGameTimer() - startTime

	-- Speichere das Ergebnis in der History
	if success then
		local _, insertErr = db:execute([[
            INSERT INTO migration_history (version, name, checksum, execution_time_ms, success)
            VALUES (:version, :name, :checksum, :execution_time, TRUE)
        ]], {
			version = migration.version,
			name = migration.name,
			checksum = checksum,
			execution_time = executionTime
		})

		if insertErr then
			logger:info(("^1[Migration]^7 Warning: Failed to save migration history for %s: %s"):format(migration.version, insertErr))
		end

		logger:info(("^2[Migration]^7 Successfully executed migration %s in %dms"):format(migration.version, executionTime))
		return true
	else
		local _, insertErr = db:execute([[
            INSERT INTO migration_history (version, name, checksum, execution_time_ms, success, error_message)
            VALUES (:version, :name, :checksum, :execution_time, FALSE, :error)
        ]], {
			version = migration.version,
			name = migration.name,
			checksum = checksum,
			execution_time = executionTime,
			error = "Transaction failed"
		})

		if insertErr then
			logger:info(("^1[Migration]^7 Warning: Failed to save error history: %s"):format(insertErr))
		end

		logger:info(("^1[Migration]^7 Failed to execute migration %s"):format(migration.version))
		return false
	end
end

---Führt alle ausstehenden Migrationen aus
---@return boolean success
---@return number executed Anzahl ausgeführter Migrationen
function Migration:runPendingMigrations()
	logger:info("^3[Migration]^7 Starting migration process...")

	-- Warte auf Datenbank-Verbindung
	if not db:awaitReady(15000) then
		logger:info("^1[Migration]^7 Database connection timeout")
		return false, 0
	end

	-- Erstelle Migration History Tabelle
	if not self:createMigrationTable() then
		return false, 0
	end

	-- Lade alle Migrations-Dateien
	local migrations = self:loadMigrationFiles()
	logger:info(("^3[Migration]^7 Found %d migration files"):format(#migrations))

	local executed = 0
	local failed = 0

	-- Führe jede Migration aus
	for _, migration in ipairs(migrations) do
		if self:isMigrationExecuted(migration.version) then
			logger:info(("^2[Migration]^7 Skipping already executed migration %s: %s"):format(migration.version, migration.name))
		else
			local success = self:executeMigration(migration)
			if success then
				executed = executed + 1
			else
				failed = failed + 1
				logger:info(("^1[Migration]^7 Migration %s failed. Stopping migration process."):format(migration.version))
				break -- Stoppe bei Fehler
			end
		end
	end

	logger:info(("^2[Migration]^7 Migration process completed. Executed: %d, Failed: %d"):format(executed, failed))
	return failed == 0, executed
end

---Zeigt den Status aller Migrationen an
---@return table<number, {version: string, name: string, executed: boolean, executed_at: string?}>
function Migration:getStatus()
	local migrations = self:loadMigrationFiles()
	local status = {}

	for _, migration in ipairs(migrations) do
		local query = [[
            SELECT executed_at, success, error_message
            FROM migration_history
            WHERE version = :version
        ]]

		local result = db:single(query, { version = migration.version })

		table.insert(status, {
			version = migration.version,
			name = migration.name,
			executed = result ~= nil,
			executed_at = result and result.executed_at or nil,
			success = result and result.success or false,
			error = result and result.error_message or nil
		})
	end

	return status
end

---Erstellt eine neue Migration-Datei
---@param name string Name der Migration
---@return string? filename
function Migration:createMigration(name)
	-- Finde die nächste freie Versionsnummer
	local migrations = self:loadMigrationFiles()
	local lastVersion = 0

	for _, migration in ipairs(migrations) do
		local version = tonumber(migration.version)
		if version > lastVersion then
			lastVersion = version
		end
	end

	local newVersion = string.format("%03d", lastVersion + 1)
	local filename = string.format("%s_%s.sql", newVersion, name)

	logger:info(("^3[Migration]^7 Create new migration file: %s"):format(filename))
	logger:info(("^3[Migration]^7 Path: %s%s"):format(MIGRATION_PATH, filename))

	return filename
end

function Migration:validateMigrationChecksum(migration)
	local content = self:readMigrationFile(migration.fullPath)
	if not content then return false end

	local currentChecksum = self:calculateChecksum(content)

	local query = [[
        SELECT checksum FROM migration_history
        WHERE version = :version AND success = TRUE
    ]]

	local result = db:single(query, { version = migration.version })

	if result and result.checksum ~= currentChecksum then
		logger:info(("^1[Migration]^7 WARNING: Migration %s has been modified after execution!"):format(migration.version))
		return false
	end

	return true
end

-- Erstelle globale Instanz
local instance = Migration:new()

-- Exportiere
_G.Migration = Migration
_G.migration = instance

return instance
