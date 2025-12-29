fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'Noverna-Core - Core resource for Noverna framework'
version '1.0.0'
author 'Noverna'

-- Dont Worry, we will clean this mess up, if its ready to be used.

server_scripts {
	"resource/server/init.lua",
	"resource/server/events/**/*.lua",
}

client_scripts {
	"resource/client/**/*.lua"
}

shared_scripts {
	"@ox_lib/init.lua"
}

files {
	"shared/**/*.lua"
}

dependencies {
	'/onesync',
	'/server:22253', -- Minimal FXServer version - At the current, but we will always try to use the newest version
}
