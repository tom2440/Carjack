fx_version 'cerulean'
game 'gta5'

author 'tom2440'
description 'Système de verrouillage de véhicules NPC avec crochetage synchronisé'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependencies {
    'es_extended',
    'ox_inventory',
    'ox_lib',
    'ox_target'
}
