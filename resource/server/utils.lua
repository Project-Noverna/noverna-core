--- Generates a "unique" user identifier based on the username and optional parameters.
---@param username string
---@param options table? { prefix: string }
---@return unknown
function GenerateUserIdentifier(username, options)
	options = options or {}
	local prefix = options.prefix or "user_"
	local timestamp = os.time()
	local randomPart = math.random(1000, 9999)
	return prefix .. username .. "_" .. timestamp .. "_" .. randomPart
end

---	Generates a random session token.
---@return string
function GenerateSessionToken()
	local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local tokenLength = 32
	local token = ""
	for i = 1, tokenLength do
		local randomIndex = math.random(1, #charset)
		token = token .. charset:sub(randomIndex, randomIndex)
	end
	return token
end

--- Generates a UUID
--- @return string
--- @source https://gist.github.com/jrus/3197011
function GenerateUUID()
	local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
	return (string.gsub(template, '[xy]', function(c)
		local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format('%x', v)
	end))
end
