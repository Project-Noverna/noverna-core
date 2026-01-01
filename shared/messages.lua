local Messages = {
	de = {
		STORAGE_NOT_FOUND = "Ein interner Fehler ist aufgetreten. Bitte kontaktiere einen Administrator. [Fehlercode: %d]",
		PLAYER_BANNED = "Du wurdest vom Server gebannt. Grund: %s | Bis: %s",
		DATABASE_ERROR = "Datenbankfehler. Bitte versuche es später erneut.",
		INVALID_LICENSE = "Keine gültige Rockstar-Lizenz gefunden. Bitte stelle sicher, dass du GTA V legal besitzt.",
	},
	en = {
		STORAGE_NOT_FOUND = "An internal error occurred. Please contact an administrator. [Error code: %d]",
		PLAYER_BANNED = "You have been banned from this server. Reason: %s | Until: %s",
		DATABASE_ERROR = "Database error. Please try again later.",
		INVALID_LICENSE = "No valid Rockstar license found. Please ensure you own GTA V legally.",
	}
}

function Messages:get(key, locale, ...)
	locale = locale or "en"
	local message = Messages[locale] and Messages[locale][key]
	if not message then
		return key -- Fallback
	end
	return string.format(message, ...)
end

return Messages
