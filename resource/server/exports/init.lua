local ExportManager = {}
ExportManager.namespaces = {}

--- Register a new namespace for exports
---@param name string
---@param module any
function ExportManager:RegisterNamespace(name, module)
	self.namespaces[name] = setmetatable({}, {
		__index = module,
		__newindex = function()
			error("Attempt to modify read-only namespace '" .. tostring(name) .. "'")
		end,
		__metatable = false,
	})
end

-- Public API
function ExportManager:GetNamespace(name)
	return self.namespaces[name]
end

exports("RegisterNamespace", function(name, module)
	ExportManager:RegisterNamespace(name, module)
end)

exports("GetNamespace", function(name)
	return ExportManager:GetNamespace(name)
end)

return ExportManager
