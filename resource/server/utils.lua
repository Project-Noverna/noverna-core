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

	-- Hash the Username to avoid collisions
	return prefix .. username:lower() .. "_" .. table.concat(result)
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

--- Generates a UUID v4 according to RFC 4122
--- @return string
local function generateUUID()
	local random = math.random
	local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'

	return (string.gsub(template, '[xy]', function(c)
		local v = random(0, 15)
		-- Für 'x': nehme random value
		if c == 'x' then
			return string.format('%x', v)
		else
			-- Für 'y': muss im Bereich 8-11 (binär 10xx) liegen
			-- Bits: 10xx wobei xx = random
			local y = (v & 0x3) | 0x8 -- & 0x3 maskiert nur die letzten 2 bits
			return string.format('%x', y)
		end
	end))
end


--- absolut overkill, but whatever
---
--- Generates a session token with Base64
--- @param byteLength? number Token length in bytes (default: 24, results in 32 chars)
--- @return string Base64-encoded token
local function generateSessionToken(byteLength)
	byteLength = byteLength or 32

	-- Kombiniere mehrere Entropy-Quellen
	local parts = {
		tostring(os.time()),
		tostring(os.clock() * 1000000),
		generateUUID(),
		tostring(math.random(1000000, 9999999)),
	}

	-- Simple aber ausreichende Mischung
	local combined = table.concat(parts)
	local hash = 0
	for i = 1, #combined do
		hash = ((hash << 5) - hash) + string.byte(combined, i)
		hash = hash & 0xFFFFFFFF
	end

	return string.format("%x%s", hash, generateUUID():gsub("-", ""))
end

return {
	generateUserIdentifier = generateUserIdentifier,
	getPlayerLicense = getPlayerLicense,
	generateSessionToken = generateSessionToken,
	generateUUID = generateUUID,
}
