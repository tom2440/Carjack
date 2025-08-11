-- Fonction pour vérifier si un véhicule appartient à un joueur (côté serveur)
ESX = exports["es_extended"]:getSharedObject()

-- Initialiser la table des véhicules déverrouillés
local unlockedVehicles = {}
local rentalCache = {}
local rentalCacheExpiry = {}
local CACHE_DURATION = 600 -- 10 minutes en secondes

-- Cache pour les véhicules appartenant à des joueurs
local ownedVehiclesCache = {}
local ownedVehiclesCacheExpiry = {}

ESX.RegisterServerCallback('vehicle_restriction:isPlayerOwnedVehicle', function(source, cb, plate)
    if plate then
        plate = string.gsub(plate, "^%s*(.-)%s*$", "%1") -- Supprimer les espaces
        
        -- Vérifier d'abord dans le cache
        if ownedVehiclesCache[plate] ~= nil and os.time() < ownedVehiclesCacheExpiry[plate] then
            cb(ownedVehiclesCache[plate])
            return
        end
        
        MySQL.query('SELECT 1 FROM owned_vehicles WHERE plate = ?', {plate}, function(result)
            local isOwned = result and #result > 0
            
            -- Mettre en cache le résultat pour 10 minutes
            ownedVehiclesCache[plate] = isOwned
            ownedVehiclesCacheExpiry[plate] = os.time() + CACHE_DURATION
            
            cb(isOwned)
        end)
    else
        cb(false)
    end
end)

-- Événement pour retirer un lockpick de l'inventaire d'un joueur
RegisterNetEvent('vehicle_lockpick:removeLockpick')
AddEventHandler('vehicle_lockpick:removeLockpick', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    -- Vérifier si le joueur a un lockpick
    if xPlayer then
        -- Utiliser ox_inventory pour retirer l'item
        exports.ox_inventory:RemoveItem(source, Config.LockpickItem, 1)
    end
end)

-- Nouvel événement pour marquer un véhicule comme déverrouillé
RegisterNetEvent('vehicle_lockpick:markVehicleUnlocked')
AddEventHandler('vehicle_lockpick:markVehicleUnlocked', function(vehicleNetId, vehicleId)
    local source = source
    
    -- Ajouter le véhicule à la liste des véhicules déverrouillés
    unlockedVehicles[vehicleId] = true
    
    -- Diffuser l'information à tous les autres joueurs
    TriggerClientEvent('vehicle_lockpick:syncUnlockedVehicle', -1, vehicleNetId, vehicleId)
    
    -- Debug
    -- print("^3[vehicle_restriction]^7 Véhicule " .. vehicleId .. " marqué comme déverrouillé par " .. GetPlayerName(source))
end)

-- Événement pour récupérer la liste des véhicules déverrouillés lors de la connexion d'un joueur
ESX.RegisterServerCallback('vehicle_lockpick:getUnlockedVehicles', function(source, cb)
    cb(unlockedVehicles)
end)

-- Fonction pour vérifier si un véhicule est loué (côté serveur) - OPTIMISÉE
-- ESX.RegisterServerCallback('vehicle_restriction:isRentalVehicle', function(source, cb, plate)
--     if not plate then
--         cb(false)
--         return
--     end
    
--     -- Nettoyer la plaque d'immatriculation
--     plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")
    
--     -- Vérification rapide dans la Config
--     for rentalPlate, _ in pairs(Config.RentalPlates) do
--         if string.find(plate:upper(), rentalPlate:upper()) then
--             cb(true)
--             return
--         end
--     end
    
--     -- Vérifier le cache d'abord
--     if rentalCache[plate] ~= nil and os.time() < rentalCacheExpiry[plate] then
--         cb(rentalCache[plate])
--         return
--     end
    
--     -- Si pas en cache ou cache expiré, faire la requête
--     MySQL.query('SELECT 1 FROM locveh WHERE plate = ?', {plate}, function(result)
--         local isRental = result and #result > 0
        
--         -- Mettre en cache le résultat
--         rentalCache[plate] = isRental
--         rentalCacheExpiry[plate] = os.time() + CACHE_DURATION
        
--         cb(isRental)
--     end)
-- end)

-- Traitement par lots pour les véhicules de location (optimisation majeure)
ESX.RegisterServerCallback('vehicle_restriction:batchCheckRentalVehicles', function(source, cb, plates)
    if not plates or #plates == 0 then
        cb({})
        return
    end
    
    local response = {}
    
    for i=1, #plates do
        local plate = plates[i]
        response[plate] = false
        
        -- Vérifier uniquement dans la Config
        for rentalPlate, _ in pairs(Config.RentalPlates) do
            if string.find(plate:upper(), rentalPlate:upper()) then
                response[plate] = true
                break
            end
        end
    end
    
    cb(response)
end)

-- Nettoyer le cache périodiquement (OPTIMISÉ)
CreateThread(function()
    while true do
        Wait(300000) -- 5 minutes
        
        local currentTime = os.time()
        local expiredCount = 0
        
        -- Nettoyer seulement les entrées expirées des caches
        for plate, expiry in pairs(rentalCacheExpiry) do
            if expiry <= currentTime then
                rentalCache[plate] = nil
                rentalCacheExpiry[plate] = nil
                expiredCount = expiredCount + 1
            end
        end
        
        for plate, expiry in pairs(ownedVehiclesCacheExpiry) do
            if expiry <= currentTime then
                ownedVehiclesCache[plate] = nil
                ownedVehiclesCacheExpiry[plate] = nil
                expiredCount = expiredCount + 1
            end
        end
        
        -- Debug
        -- print("^3[vehicle_restriction]^7 Nettoyage de cache effectué: " .. expiredCount .. " entrées supprimées")
    end
end)

-- Événement pour alerter la police d'une tentative de crochetage
RegisterNetEvent('vehicle_lockpick:alertPolice')
AddEventHandler('vehicle_lockpick:alertPolice', function(coords, streetName)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    -- Récupérer tous les policiers en service avec vérification de sécurité
    local xPlayers = ESX.GetExtendedPlayers('job', Config.PoliceJobName) or {}
    
    -- Vérifier si on a bien des joueurs
    if next(xPlayers) ~= nil then
        -- Envoyer une notification à tous les policiers
        for _, xPolice in pairs(xPlayers) do
            -- Jouer le son de radio pour la notification
            TriggerClientEvent('sound:play', xPolice.source, 'radio-on', 0.1)
            
            -- Notification
            TriggerClientEvent('esx:showAdvancedNotification', xPolice.source, 
                "Alerte: Tentative de vol de véhicule", 
                'Localisation: ' .. streetName, 
                "Un individu a été aperçu en train d'essayer de voler un véhicule.", 
                'CHAR_CALL911',
                1
            )
            
            -- Créer un blip sur la carte pour les policiers
            TriggerClientEvent('vehicle_lockpick:createBlip', xPolice.source, coords)
        end
    end
end)

-- Création d'index sur la base de données
CreateThread(function()
    Wait(5000) -- Attendre que le serveur soit bien démarré
    
    -- Créer les index nécessaires s'ils n'existent pas déjà - CORRECTION ICI: séparer les requêtes
    -- MySQL.query('CREATE INDEX IF NOT EXISTS idx_locveh_plate ON locveh (plate)', {}, function()
    --     --print("^2[vehicle_restriction]^7 Index créé pour la table locveh")
    -- end)
    
    MySQL.query('CREATE INDEX IF NOT EXISTS idx_owned_vehicles_plate ON owned_vehicles (plate)', {}, function()
        --print("^2[vehicle_restriction]^7 Index créé pour la table owned_vehicles")
    end)
    
    --print("^2[vehicle_restriction]^7 Serveur démarré avec système de crochetage synchronisé et optimisé")
end)