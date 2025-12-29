--- Generates a unique user identifier with hash-based suffix
--- @param username string
--- @param options? table { prefix: string?, length: number? }
--- @return string
local function generateUserIdentifier(username, options)
	options = options or {}
	local prefix = options.prefix or "user_"
	local length = options.length or 12

	-- Combine various entropy sources
	local timestamp = tostring(os.time())
	local clock = tostring(os.clock() * 1000000)
	local random = tostring(math.random(1000000, 9999999))

	-- Simple Hashing
	local combined = timestamp .. clock .. random .. username
	local hash = 0
	for i = 1, #combined do
		hash = ((hash << 5) - hash) + string.byte(combined, i)
		hash = hash & 0xFFFFFFFF -- 32-bit Integer
	end

	local charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	local result = {}
	local num = math.abs(hash)

	for i = 1, length do
		local idx = (num % #charset) + 1
		result[i] = charset:sub(idx, idx)
		num = math.floor(num / #charset) + math.random(0, 35)
	end

	return prefix .. username .. "_" .. table.concat(result)
end

--- TODO: We will move this to a Player Utils later
---
--- Returns the Player License2
---@param source string
---@return string|nil
local function getPlayerLicense(source)
	local license = GetPlayerIdentifierByType(source, "license2")
	if license then
		---@diagnostic disable-next-line: redundant-return-value
		return license:gsub("license2:", "")
	end
	return nil
end

--- Possible absolut overkill, but whatever i love it
---
--- Generates a session token with Base64
--- @param byteLength? number Token length in bytes (default: 24, results in 32 chars)
--- @return string Base64-encoded token
local function generateSessionToken(byteLength)
	byteLength = byteLength or 24 -- 24 bytes = 32 Base64 chars

	local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
	local token = {}

	for i = 1, byteLength do
		local byte = math.random(0, 255)
		-- Jedes Byte liefert ~1.3 Base64-Zeichen
		token[#token + 1] = b64chars:sub((byte & 0xFC) >> 2 | 1, (byte & 0xFC) >> 2 | 1)
		if i % 3 ~= 0 or i == byteLength then
			token[#token + 1] = b64chars:sub(((byte & 0x03) << 4) | 1, ((byte & 0x03) << 4) | 1)
		end
	end

	return table.concat(token):sub(1, math.ceil(byteLength * 4 / 3))
end

--- Generates a UUID v4 according to RFC 4122
--- @return string
local function generateUUID()
	local random = math.random
	local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'

	return (string.gsub(template, '[xy]', function(c)
		local v = random(0, 15)
		if c == 'x' then
			return string.format('%x', v)
		else
			-- Für 'y': muss im Bereich 8-11 (binär 10xx) liegen
			-- (v AND 0x3) OR 0x8
			-- RFC 4122 v4 UUIDs
			return string.format('%x', (v & 0x3) | 0x8)
		end
	end))
end

return {
	generateUserIdentifier = generateUserIdentifier,
	getPlayerLicense = getPlayerLicense,
	generateSessionToken = generateSessionToken,
	generateUUID = generateUUID,
}
