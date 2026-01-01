local Validation = {}

-- Validatoren
Validation.validators = {
	string = function(value, min, max)
		if type(value) ~= "string" then return false, "Must be string" end
		local len = string.len(value)
		if min and len < min then return false, "Too short" end
		if max and len > max then return false, "Too long" end
		return true
	end,

	number = function(value, min, max)
		if type(value) ~= "number" then return false, "Must be number" end
		if min and value < min then return false, "Too small" end
		if max and value > max then return false, "Too large" end
		return true
	end,

	username = function(value)
		if type(value) ~= "string" then return false, "Invalid username" end
		if not string.match(value, "^[a-zA-Z0-9_]+$") then
			return false, "Username can only contain letters, numbers, and underscores"
		end
		if #value < 3 or #value > 16 then
			return false, "Username must be between 3 and 16 characters"
		end
		return true
	end,

	citizenId = function(value)
		if type(value) ~= "string" then return false, "Invalid citizenId" end
		-- Format: ABC12345
		if not string.match(value, "^[A-Z]{3}%d{5}$") then
			return false, "Invalid citizenId format"
		end
		return true
	end,

	license = function(value)
		if type(value) ~= "string" then return false, "Invalid license" end
		if not string.match(value, "^license:") then
			return false, "Invalid license format"
		end
		return true
	end,

	email = function(value)
		if type(value) ~= "string" then return false, "Invalid email" end
		-- Basic email validation
		if not value:match("^[%w._%+-]+@[%w.-]+%.%w+$") then
			return false, "Invalid email format"
		end
		return true
	end,

	discord = function(value)
		if type(value) ~= "string" then return false, "Invalid Discord ID" end
		-- Discord IDs sind 17-19 Zeichen lange Zahlen
		if not value:match("^%d{17,19}$") then
			return false, "Invalid Discord ID format"
		end
		return true
	end,

	url = function(value)
		if type(value) ~= "string" then return false, "Invalid URL" end
		if not value:match("^https?://") then
			return false, "URL must start with http:// or https://"
		end
		return true
	end,

	array = function(value, itemValidator)
		if type(value) ~= "table" then return false, "Must be array" end
		for i, item in ipairs(value) do
			if itemValidator then
				local valid, err = itemValidator(item)
				if not valid then
					return false, string.format("Item %d: %s", i, err)
				end
			end
		end
		return true
	end,

	enum = function(value, allowedValues)
		for _, allowed in ipairs(allowedValues) do
			if value == allowed then
				return true
			end
		end
		return false, "Value not in allowed list"
	end,
}

-- Schema Validation
function Validation:validate(data, schema)
	for field, rules in pairs(schema) do
		local value = data[field]

		-- Required Check
		if rules.required and value == nil then
			return false, string.format("Field '%s' is required", field)
		end

		-- Type Check
		if value ~= nil and rules.type then
			local validator = self.validators[rules.type]
			if validator then
				local valid, err = validator(value, rules.min, rules.max)
				if not valid then
					return false, string.format("Field '%s': %s", field, err)
				end
			end
		end

		-- Custom Validator
		if value ~= nil and rules.custom then
			local valid, err = rules.custom(value)
			if not valid then
				return false, string.format("Field '%s': %s", field, err)
			end
		end
	end

	return true
end

return Validation
