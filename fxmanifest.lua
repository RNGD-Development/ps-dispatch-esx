-- ps-dispatch — original work by Project Sloth & OK1ez (GPLv3).
-- ESX Legacy bridge contributed by RNGD-Development; see CREDITS.md and
-- CHANGES.md. The `bridge/` files below are additive: on QBCore/QBX servers
-- they resolve to the same QBCore calls this resource always made.

fx_version 'cerulean'

game "gta5"

author "Project Sloth & OK1ez"
version '3.0.0'

lua54 'yes'

ui_page 'html/index.html'
-- ui_page 'http://localhost:5173/' --for dev

client_script {
  '@PolyZone/client.lua',
  '@PolyZone/CircleZone.lua',
  '@PolyZone/BoxZone.lua',
  'bridge/client.lua',
  'client/**',
}
server_script {
  'bridge/server.lua',
  "server/**",
}
shared_script {
  "shared/**",
  '@ox_lib/init.lua',
  'bridge/shared.lua',
}

files {
  'html/**',
  'locales/*.json',
}

ox_lib 'locale' -- v3.8.0 or above
