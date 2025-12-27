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
	if not self:validateMigrationChecksum(migration) then
		logger:info(("^1[Migration]^7 Aborting migration %s due to checksum mismatch"):format(migration.version))
		-- Idiot safety: Abbruch bei Checksum-Fehler
		logger:error("Migration checksum mismatch, never in your life touch a already executed migration!")
		return false
	end

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

---- Adding Convar Check here:
local dbCommands = GetConvar("enable_database_commands", "false")
local environment = GetConvar("environment", "development")

if dbCommands == "true" and environment == "development" then
	-- I know duplicated message, but we are creating something for the FiveM Community....
	logger:info("^2[Database] Be aware that database commands are enabled. This should only be used in development environments.^0")

	---Löscht alle Tabellen aus der Datenbank (GEFÄHRLICH!)
	---@return boolean success
	---@return string? error
	function Migration:dropAllTables()
		logger:warn("^1[Migration]^7 ⚠️  WARNING: Dropping ALL tables from database!")

		if not db:isReady() then
			return false, "Database is not ready"
		end

		-- Schritt 1: Alle Tabellennamen aus BEIDEN Schemas abrufen
		local tablesQuery = [[
		SELECT schemaname, tablename
		FROM pg_tables
		WHERE schemaname IN ('public', 'logs')
		ORDER BY schemaname, tablename;
	]]

		local tables, err = db:query(tablesQuery)
		if err then
			return false, "Failed to fetch tables: " .. tostring(err)
		end

		if not tables or #tables == 0 then
			logger:info("^3[Migration]^7 No tables found to drop")
			return true
		end

		logger:info(("^3[Migration]^7 Found %d tables to drop across schemas"):format(#tables))

		-- Schritt 2: DROP CASCADE für jede Tabelle
		local droppedCount = 0
		for _, tableRow in ipairs(tables) do
			local schemaName = tableRow.schemaname
			local tableName = tableRow.tablename
			local fullTableName = string.format("%s.%s", schemaName, tableName)
			local dropQuery = string.format("DROP TABLE IF EXISTS %s CASCADE;", fullTableName)

			logger:info(("^3[Migration]^7 Dropping table: %s"):format(fullTableName))

			local _, dropErr = db:rawQuery(dropQuery)
			if dropErr then
				logger:warn(("^1[Migration]^7 Failed to drop table %s: %s"):format(fullTableName, dropErr))
			else
				droppedCount = droppedCount + 1
			end
		end

		logger:info(("^2[Migration]^7 Successfully dropped %d/%d tables"):format(droppedCount, #tables))

		-- Schritt 3: Lösche alle ENUM Types aus beiden Schemas
		logger:info("^3[Migration]^7 Dropping ENUM types...")
		local enumsQuery = [[
		SELECT n.nspname as schema_name, t.typname as type_name
		FROM pg_type t
		JOIN pg_namespace n ON n.oid = t.typnamespace
		WHERE t.typtype = 'e'
		AND n.nspname IN ('public', 'logs')
		ORDER BY n.nspname, t.typname;
	]]

		local enums, enumErr = db:query(enumsQuery)
		if not enumErr and enums then
			for _, enumRow in ipairs(enums) do
				local fullEnumName = string.format("%s.%s", enumRow.schema_name, enumRow.type_name)
				local dropEnumQuery = string.format("DROP TYPE IF EXISTS %s CASCADE;", fullEnumName)
				logger:info(("^3[Migration]^7 Dropping enum: %s"):format(fullEnumName))
				db:rawQuery(dropEnumQuery)
			end
		end

		-- Schritt 4: Lösche alle Functions/Procedures
		logger:info("^3[Migration]^7 Dropping functions...")
		local functionsQuery = [[
		SELECT n.nspname as schema_name, p.proname as function_name,
		       pg_get_function_identity_arguments(p.oid) as args
		FROM pg_proc p
		JOIN pg_namespace n ON n.oid = p.pronamespace
		WHERE n.nspname IN ('public', 'logs')
		ORDER BY n.nspname, p.proname;
	]]

		local functions, funcErr = db:query(functionsQuery)
		if not funcErr and functions then
			for _, funcRow in ipairs(functions) do
				local fullFuncName = string.format("%s.%s(%s)", funcRow.schema_name, funcRow.function_name, funcRow.args or "")
				local dropFuncQuery = string.format("DROP FUNCTION IF EXISTS %s CASCADE;", fullFuncName)
				logger:info(("^3[Migration]^7 Dropping function: %s"):format(fullFuncName))
				db:rawQuery(dropFuncQuery)
			end
		end

		-- Schritt 5: Lösche alle Views
		logger:info("^3[Migration]^7 Dropping views...")
		local viewsQuery = [[
		SELECT schemaname, viewname
		FROM pg_views
		WHERE schemaname IN ('public', 'logs')
		ORDER BY schemaname, viewname;
	]]

		local views, viewErr = db:query(viewsQuery)
		if not viewErr and views then
			for _, viewRow in ipairs(views) do
				local fullViewName = string.format("%s.%s", viewRow.schemaname, viewRow.viewname)
				local dropViewQuery = string.format("DROP VIEW IF EXISTS %s CASCADE;", fullViewName)
				logger:info(("^3[Migration]^7 Dropping view: %s"):format(fullViewName))
				db:rawQuery(dropViewQuery)
			end
		end

		-- Schritt 6: Prüfe ob noch Tabellen vorhanden sind
		local remainingTables, checkErr = db:query(tablesQuery)
		if checkErr then
			return false, "Failed to verify table deletion: " .. tostring(checkErr)
		end

		if remainingTables and #remainingTables > 0 then
			local tableNames = {}
			for _, t in ipairs(remainingTables) do
				table.insert(tableNames, string.format("%s.%s", t.schemaname, t.tablename))
			end
			return false, "Some tables could not be dropped: " .. table.concat(tableNames, ", ")
		end

		logger:info("^2[Migration]^7 All tables, enums, functions and views dropped successfully")
		return true
	end

	---Stellt sicher dass benötigte Schemas existieren
	---@return boolean success
	---@return string? error
	function Migration:ensureSchemas()
		logger:info("^3[Migration]^7 Ensuring required schemas exist...")

		-- Erstelle logs Schema falls nicht vorhanden
		local createLogsSchema = [[
		CREATE SCHEMA IF NOT EXISTS logs;
	]]

		local _, err = db:rawQuery(createLogsSchema)
		if err then
			return false, "Failed to create logs schema: " .. tostring(err)
		end

		logger:info("^2[Migration]^7 Schema 'logs' ensured")
		logger:info("^2[Migration]^7 Schema 'public' exists by default")

		return true
	end

	---Setzt die komplette Datenbank zurück und führt Migrationen neu aus
	---@return boolean success
	---@return number migrationsRun
	---@return string? error
	function Migration:renewDatabase()
		logger:warn("^1[Migration]^7 ==========================================")
		logger:warn("^1[Migration]^7 ⚠️  DATABASE RENEW INITIATED")
		logger:warn("^1[Migration]^7 ⚠️  ALL DATA WILL BE DELETED!")
		logger:warn("^1[Migration]^7 ==========================================")

		-- Schritt 1: Warte auf Datenbank
		if not db:awaitReady(15000) then
			return false, 0, "Database connection timeout"
		end

		-- Schritt 2: Lösche alle Tabellen
		logger:info("^3[Migration]^7 Step 1/3: Dropping all tables...")
		local dropSuccess, dropErr = self:dropAllTables()
		if not dropSuccess then
			return false, 0, dropErr
		end

		-- Schritt 3: Stelle sicher dass benötigte Schemas existieren
		logger:info("^3[Migration]^7 Step 2/3: Ensuring schemas exist...")
		local schemaSuccess, schemaErr = self:ensureSchemas()
		if not schemaSuccess then
			return false, 0, schemaErr
		end

		-- Schritt 4: Führe Migrationen neu aus
		logger:info("^3[Migration]^7 Step 3/3: Running migrations...")
		local migrationSuccess, migrationsRun = self:runPendingMigrations()

		if not migrationSuccess then
			return false, migrationsRun, "Migration execution failed"
		end

		logger:info("^2[Migration]^7 ==========================================")
		logger:info(("^2[Migration]^7 ✓ DATABASE RENEWED SUCCESSFULLY"))
		logger:info(("^2[Migration]^7 ✓ Executed %d migrations"):format(migrationsRun))
		logger:info("^2[Migration]^7 ==========================================")

		return true, migrationsRun
	end
end

-- Erstelle globale Instanz
local instance = Migration:new()

-- Exportiere
_G.Migration = Migration
_G.migration = instance

return instance
