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
