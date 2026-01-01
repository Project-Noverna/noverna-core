-- IO Operations only work on server side.
local isServer = IsDuplicityVersion()

---@class Logger
local Logger = {}

Logger.levels = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4
}

Logger.currentLevel = Logger.levels.DEBUG

-- Farben für Console Output
local colors = {
	DEBUG = "^7", -- Weiß
	INFO = "^5", -- Blau
	WARN = "^3", -- Gelb
	ERROR = "^1", -- Rot
	RESET = "^7"
}

-- Hilfsfunktionen für ISO 8601 Format
local function getISODateTime()
	return os.date("%Y-%m-%dT%H:%M:%S")
end

local function getISODate()
	return os.date("%Y-%m-%d")
end

local MAX_LOG_SIZE = 10 * 1024 * 1024 -- 10MB
local MAX_LOG_FILES = 7               -- 7 Tage

local function rotateLogIfNeeded(fileName)
	local content = LoadResourceFile(GetCurrentResourceName(), fileName)
	if not content then return end

	if #content > MAX_LOG_SIZE then
		-- Rotiere: log_2024-01-01.log -> log_2024-01-01.1.log
		local rotatedName = fileName .. ".1"
		SaveResourceFile(GetCurrentResourceName(), rotatedName, content, -1)

		-- Lösche alten Inhalt
		SaveResourceFile(GetCurrentResourceName(), fileName, "", -1)

		-- Cleanup: Lösche alte Rotationen
		for i = MAX_LOG_FILES, 2, -1 do
			local oldFile = fileName .. "." .. tostring(i)
			local content = LoadResourceFile(GetCurrentResourceName(), oldFile)
			if content then
				-- In FiveM kann man Files nicht direkt löschen,
				-- aber man kann sie überschreiben
			end
		end
	end
end

-- Log-Datei schreiben (nur Server)
local function writeToFile(level, message, data)
	if not isServer then return end

	local resourceName = GetCurrentResourceName()
	local fileName = string.format("logs/noverna_%s.log", getISODate())

	-- Prüfe Rotation
	rotateLogIfNeeded(fileName)

	local timestamp = getISODateTime()
	local logEntry = string.format("[%s] [%s] %s", timestamp, level, message)

	if data then
		logEntry = logEntry .. " | Data: " .. json.encode(data)
	end

	logEntry = logEntry .. "\n"

	-- SaveResourceFile erstellt automatisch das Verzeichnis
	SaveResourceFile(resourceName, fileName, (LoadResourceFile(resourceName, fileName) or "") .. logEntry, -1)
end

-- Hauptfunktion für Logging
local function log(level, levelName, message, data)
	if level < Logger.currentLevel then
		return
	end

	local timestamp = getISODateTime()
	local prefix = string.format("[%s] [%s]", timestamp, levelName)
	local fullMessage = string.format("%s%s %s^7", colors[levelName], prefix, message)

	print(fullMessage)

	if data then
		print(string.format("^7Data: %s^7", json.encode(data, { indent = true })))
	end

	-- In Datei schreiben (nur Server)
	if isServer then
		writeToFile(levelName, message, data)
	end
end

-- Public API
function Logger:debug(message, data)
	log(self.levels.DEBUG, "DEBUG", message, data)
end

function Logger:info(message, data)
	log(self.levels.INFO, "INFO", message, data)
end

function Logger:warn(message, data)
	log(self.levels.WARN, "WARN", message, data)
end

function Logger:error(message, data)
	log(self.levels.ERROR, "ERROR", message, data)
end

function Logger:setLevel(level)
	if self.levels[level] then
		self.currentLevel = self.levels[level]
		self:info(string.format("Log level set to %s", level))
	else
		self:warn(string.format("Invalid log level: %s", level))
	end
end

-- Spezialisierte Server-Funktion für strukturierte Logs
if isServer then
	function Logger:writeCustomLog(fileName, content)
		local resourceName = GetCurrentResourceName()
		local fullPath = string.format("logs/%s_%s.log", fileName, getISODate())
		local timestamp = getISODateTime()
		local logEntry = string.format("[%s] %s\n", timestamp, content)

		SaveResourceFile(resourceName, fullPath, (LoadResourceFile(resourceName, fullPath) or "") .. logEntry, -1)
	end

	-- Fehlerprotokollierung mit Stack Trace
	function Logger:logException(err, context)
		local errorInfo = {
			error = err,
			context = context or "Unknown",
			trace = debug.traceback(),
			timestamp = getISODateTime()
		}

		self:error(string.format("Exception in %s: %s", errorInfo.context, err), errorInfo)

		-- Separate Error-Log-Datei
		local resourceName = GetCurrentResourceName()
		local fileName = string.format("logs/errors_%s.log", getISODate())
		local logEntry = string.format(
			"[%s] Context: %s\nError: %s\nTrace:\n%s\n\n",
			errorInfo.timestamp,
			errorInfo.context,
			err,
			errorInfo.trace
		)

		SaveResourceFile(resourceName, fileName, (LoadResourceFile(resourceName, fileName) or "") .. logEntry, -1)
	end
end

return Logger
