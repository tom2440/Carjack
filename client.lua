-- Script pour empêcher l'accès aux véhicules NPC avec système de crochetage
-- Compatibilité: ESX Legacy, ox_inventory

-- Initialiser la ressource ESX
ESX = exports["es_extended"]:getSharedObject()

-- Déclaration des variables globales
verifiedPlates = {}
abandonedVehicles = {} -- Véhicules abandonnés par des PNJ (déverrouillés)
trackedNPCVehicles = {} -- Véhicules avec leur état d'occupation
lockpickingVehicle = false -- Pour éviter de lancer plusieurs animations de crochetage
local lastLockpickCheck = 0 -- Timestamp de la dernière vérification de lockpick
local hasLockpickCache = false -- Cache pour éviter les appels répétitifs à ox_inventory
local rentalPlatesCache = {}
local lastRentalCheck = 0
local trackedMotorcycles = {} -- Table pour suivre l'état des motos conduites par des PNJ
local deadNPCVehicles = {} -- Table pour suivre les véhicules avec PNJ morts et leur état de déverrouillage
local deadNPCUnlockChance = 30 
local LOCKPICK_DURATION = 3500
local SPECIAL_MOTORCYCLE_HANDLING = true
local LOCKPICK_ANIM = {
    dict = 'missheistfbisetup1',
    anim = 'hassle_intro_loop_f'
}
local ALERT_BLIP = {
    sprite = 161,    -- Icône du blip (161 = Voleur)
    color = 1,       -- Couleur du blip (1 = Rouge)
    scale = 0.8,     -- Taille du blip
    duration = 60,   -- Durée d'affichage du blip en secondes
    flash = true     -- Le blip clignote ou non
}

-- Fonction pour marquer un véhicule comme déverrouillé côté serveur
function markVehicleUnlockedOnServer(vehicle, vehicleId)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId and netId ~= 0 then
        TriggerServerEvent('vehicle_lockpick:markVehicleUnlocked', netId, vehicleId)
    end
end

-- Événement pour synchroniser l'état des véhicules déverrouillés
RegisterNetEvent('vehicle_lockpick:syncUnlockedVehicle')
AddEventHandler('vehicle_lockpick:syncUnlockedVehicle', function(netId, vehicleId)
    -- Ajouter le véhicule à la liste des abandonnés localement
    abandonedVehicles[vehicleId] = true
    
    -- Essayer de déverrouiller le véhicule si on peut l'obtenir à partir de l'ID réseau
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(vehicle) then
        unlockVehicle(vehicle)
    end
end)

-- Fonction pour vérifier si un véhicule est blacklisté (jamais verrouillé)
function isVehicleBlacklisted(vehicle)
    if not DoesEntityExist(vehicle) then return false end

    -- Cas spécial: les motos avec des PNJ dessus sont toujours déverrouillées
    if SPECIAL_MOTORCYCLE_HANDLING and shouldMotorcycleBeUnlocked(vehicle) then
        return true -- La moto avec PNJ est considérée comme blacklistée (toujours déverrouillée)
    end

    -- 1. Vérification par catégorie GTA (le plus rapide en premier)
    local category = GetVehicleClass(vehicle)
    if Config.BlacklistedCategories and Config.BlacklistedCategories[category] then
        return true
    end

    -- 2. Vérification par modèle de véhicule
    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)):lower()
    if Config.BlacklistedModels[modelName] then
        return true
    end

    -- 3. Vérification par plaque d'immatriculation
    local plate = GetVehicleNumberPlateText(vehicle)
    if plate then
        plate = string.gsub(plate, "%s+", "") -- Supprime tous les espaces
        for blacklistedPlate, _ in pairs(Config.BlacklistedPlates) do
            if string.find(plate:upper(), blacklistedPlate:upper()) then
                return true
            end
        end
    end

    return false
end

-- Fonction pour vérifier si une moto devrait être déverrouillée
function shouldMotorcycleBeUnlocked(vehicle)
    -- Vérifier si c'est une moto
    local category = GetVehicleClass(vehicle)
    if category ~= 8 then
        return false -- Ce n'est pas une moto
    end
    
    -- Cas spécial: si la moto était précédemment conduite par un PNJ et est maintenant vide, elle reste déverrouillée
    local vehicleId = getVehicleIdentifier(vehicle)
    if trackedMotorcycles[vehicleId] == true and not isVehicleOccupiedByNPC(vehicle) then
        -- La moto était précédemment conduite par un PNJ et est maintenant vide
        abandonedVehicles[vehicleId] = true
        return true
    end
    
    -- Vérifier si la moto est occupée par un PNJ
    return isVehicleOccupiedByNPC(vehicle)
end

-- Fonction pour vérifier si un véhicule appartient à un joueur
function isPlayerOwnedVehicle(vehicle)
    local plate = GetVehicleNumberPlateText(vehicle)
    if plate then
        plate = string.gsub(plate, "^%s*(.-)%s*$", "%1") -- Supprimer les espaces
        
        -- Vérifier si la plaque est dans le cache
        if verifiedPlates[plate] ~= nil then
            return verifiedPlates[plate]
        end
        
        -- Appeler le callback serveur pour vérifier
        local result = nil
        ESX.TriggerServerCallback('vehicle_restriction:isPlayerOwnedVehicle', function(isOwned)
            result = isOwned
            verifiedPlates[plate] = isOwned -- Mettre en cache le résultat
        end, plate)
        
        -- Attendre la réponse du serveur
        local timeout = 50 -- 500ms timeout
        while result == nil and timeout > 0 do
            Wait(10)
            timeout = timeout - 1
        end
        
        return result or false
    end
    return false
end

-- Fonction pour vérifier si un véhicule est occupé par un PNJ
function isVehicleOccupiedByNPC(vehicle)
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped) then
            return true
        end
    end
    return false
end

-- Fonction pour vérifier si un véhicule contient un PNJ mort
function hasDeadNPCInVehicle(vehicle)
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and not IsPedAPlayer(ped) and IsPedDeadOrDying(ped) then
            return true
        end
    end
    return false
end

-- Fonction pour vérifier si un véhicule est abandonné (déverrouillé)
function isVehicleAbandoned(vehicleId)
    return abandonedVehicles and abandonedVehicles[vehicleId] == true
end

-- Fonction pour vérifier si une des portes du véhicule est ouverte
function isAnyVehicleDoorOpen(vehicle)
    for i = 0, 5 do -- Vérifier toutes les portes (0-5: conducteur, passager, arrière gauche, arrière droite, capot, coffre)
        if DoesVehicleHaveDoor(vehicle, i) and GetVehicleDoorAngleRatio(vehicle, i) > 0.0 then
            return true
        end
    end
    return false
end

-- Fonction pour verrouiller un véhicule
function lockVehicle(vehicle)
    SetVehicleDoorsLocked(vehicle, 2) -- Niveau 2 = Verrouillé
end

-- Fonction pour déverrouiller un véhicule
function unlockVehicle(vehicle)
    SetVehicleDoorsLocked(vehicle, 0) -- Niveau 0 = Déverrouillé
    --SetVehicleEngineOn(vehicle, true, true, false) -- Laisser le moteur allumé
end

-- Fonction pour générer un identifiant unique pour un véhicule
function getVehicleIdentifier(vehicle)
    -- Utiliser seulement la plaque + modèle pour créer un identifiant unique stable
    local plate = GetVehicleNumberPlateText(vehicle) or ""
    local model = GetEntityModel(vehicle) or 0
    return plate .. "_" .. model
end

-- Fonction pour vérifier si le joueur possède un lockpick (OPTIMISÉE)
function hasLockpick()
    local currentTime = GetGameTimer()
    
    -- Ne vérifier que toutes les 3 secondes pour éviter les appels constants à ox_inventory
    if currentTime - lastLockpickCheck > 3000 then
        hasLockpickCache = exports.ox_inventory:Search('count', Config.LockpickItem) > 0
        lastLockpickCheck = currentTime
    end
    
    return hasLockpickCache
end

-- Fonction pour jouer l'animation de crochetage
-- function playLockpickAnimation()
--     local playerPed = PlayerPedId()
--     local dict = Config.LockpickAnim.dict
--     local anim = Config.LockpickAnim.anim
    
--     -- Charger l'animation
--     RequestAnimDict(dict)
--     while not HasAnimDictLoaded(dict) do
--         Citizen.Wait(10)
--     end
--     TriggerServerEvent('sounds:playSource', 'lockpick', 0.4)
--     -- Jouer l'animation
--     TaskPlayAnim(playerPed, dict, anim, 8.0, 8.0, -1, 49, 0, false, false, false)
-- end

-- Fonction pour arrêter l'animation de crochetage
function stopLockpickAnimation()
    local playerPed = PlayerPedId()
    ClearPedTasks(playerPed)
end

-- Fonction pour détecter le véhicule dans la direction du joueur
function GetVehicleInDirection(coordFrom, coordTo)
    local rayHandle = StartExpensiveSynchronousShapeTestLosProbe(coordFrom.x, coordFrom.y, coordFrom.z, coordTo.x, coordTo.y, coordTo.z, 10, PlayerPedId(), 0)
    local _, _, _, _, vehicle = GetShapeTestResult(rayHandle)
    return vehicle
end

function isVehicleIgnored(vehicle)
    if not DoesEntityExist(vehicle) then return false end

    -- 1. Vérification par modèle de véhicule
    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)):lower()
    if Config.IgnoredModels[modelName] then
        return true
    end

    -- 2. Vérification par plaque d'immatriculation
    local plate = GetVehicleNumberPlateText(vehicle)
    if plate then
        plate = string.gsub(plate, "%s+", "") -- Supprime tous les espaces
        for ignoredPlate, _ in pairs(Config.IgnoredPlates) do
            if string.find(plate:upper(), ignoredPlate:upper()) then
                return true
            end
        end
    end

    return false
end

-- Fonction pour faire partir les PNJ à proximité (avec marche seulement)
function makePedsWalkAway(coords, radius)
    -- Récupérer tous les PNJ dans un rayon donné
    local peds = GetGamePool('CPed')
    for _, ped in pairs(peds) do
        -- Vérifier si c'est un PNJ et non un joueur
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedInAnyVehicle(ped, true) then
            -- Calculer la distance entre le PNJ et les coordonnées données
            local pedCoords = GetEntityCoords(ped)
            local distance = #(coords - pedCoords)
            
            -- Si le PNJ est à proximité
            if distance <= radius then
                -- Si le PNJ n'est pas déjà en train de faire quelque chose d'important
                if not IsPedInMeleeCombat(ped) and not IsPedFleeing(ped) and not IsPedDeadOrDying(ped) then
                    -- Calculer une direction opposée aux coordonnées données
                    local awayVector = vector3(
                        pedCoords.x - coords.x,
                        pedCoords.y - coords.y,
                        0
                    )
                    
                    -- Normaliser le vecteur
                    local length = #awayVector
                    if length > 0 then
                        awayVector = vector3(
                            awayVector.x / length * 40.0, -- Distance plus longue pour éviter qu'ils reviennent
                            awayVector.y / length * 40.0,
                            0
                        )
                    else
                        -- Direction aléatoire si le vecteur est nul
                        local randomAngle = math.random() * 2 * math.pi
                        awayVector = vector3(
                            math.cos(randomAngle) * 40.0,
                            math.sin(randomAngle) * 40.0,
                            0
                        )
                    end
                    
                    -- Calculer les coordonnées de destination
                    local destCoords = vector3(
                        pedCoords.x + awayVector.x,
                        pedCoords.y + awayVector.y,
                        pedCoords.z
                    )
                    
                    -- Utiliser TaskWanderInArea au lieu de TaskGoStraightToCoord pour un comportement plus naturel et permanent
                    ClearPedTasksImmediately(ped)
                    
                    -- Définir une vitesse de marche lente à moyenne (jamais de course)
                    SetPedMoveRateOverride(ped, 0.8 + (math.random() * 0.9)) -- Valeur entre 0.8 et 1.2
                    
                    -- Utiliser TaskGoToCoordAnyMeans avec le flag 0 pour ne pas courir
                    TaskGoToCoordAnyMeans(ped, destCoords.x, destCoords.y, destCoords.z, 1.0, 0, false, 0, 0)
                    
                    -- Méthode alternative 1: utiliser simplement un scénario de marche
                    -- TaskStartScenarioInPlace(ped, "WORLD_HUMAN_GUARD_PATROL", 0, false)
                    
                    -- Méthode alternative 2: utiliser TaskWanderInArea pour qu'ils restent dans la zone éloignée
                    -- TaskWanderInArea(ped, destCoords.x, destCoords.y, destCoords.z, 20.0, 1.0, 10000.0)
                end
            end
        end
    end
end


function lockpickVehicle(vehicle)
    -- Vérifier si le joueur est déjà en train de crocheter un véhicule
    if lockpickingVehicle then
        return
    end
    
    -- Vérifier si le joueur a un lockpick
    if not hasLockpick() then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.NoLockpick,
            type = 'error'
        })
        return
    end
    
    -- Vérifier si le véhicule appartient à un joueur
    if isPlayerOwnedVehicle(vehicle) then
        return
    end
    
    -- Vérifier si le véhicule est blacklisté
    if isVehicleBlacklisted(vehicle) then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.VehicleAlreadyUnlocked,
            type = 'error'
        })
        return
    end
    
    -- Vérifier si le véhicule est dans la liste des ignorés
    if isVehicleIgnored(vehicle) then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.CannotLockpick,
            type = 'error'
        })
        return
    end
    
    -- Vérifier si le véhicule est de location
    if isRentalVehicle(vehicle) then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.RentalVehicle,
            type = 'error'
        })
        return
    end
    
    -- Vérifier si le véhicule est occupé par un PNJ
    if isVehicleOccupiedByNPC(vehicle) then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.NPCInVehicle,
            type = 'error'
        })
        return
    end
    
    -- Vérifier si le véhicule est déjà déverrouillé
    local lockStatus = GetVehicleDoorLockStatus(vehicle)
    if lockStatus == 0 or lockStatus == 1 or isAnyVehicleDoorOpen(vehicle) then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.VehicleAlreadyUnlocked,
            type = 'info'
        })
        return
    end
    
    local vehicleId = getVehicleIdentifier(vehicle)
    if isVehicleAbandoned(vehicleId) then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.VehicleAlreadyUnlocked,
            type = 'info'
        })
        return
    end
    
    -- Commencer le crochetage
    lockpickingVehicle = true
    
    -- Récupérer le ped du joueur
    local playerPed = PlayerPedId()
    
    -- Vérifier si le joueur a une arme en main
    local hasWeapon = HasPedGotWeapon(playerPed, GetSelectedPedWeapon(playerPed), false)
    local weaponHash = GetSelectedPedWeapon(playerPed)
    
    -- Si le joueur a vraiment une arme (pas les poings)
    if hasWeapon and weaponHash ~= GetHashKey('WEAPON_UNARMED') then
        -- Méthode simple mais efficace pour orienter le joueur vers le véhicule
        local vehicleCoords = GetEntityCoords(vehicle)
        local playerCoords = GetEntityCoords(playerPed)
        
        -- Diriger le joueur vers le véhicule sans rotation exagérée
        local currentHeading = GetEntityHeading(playerPed)
        local targetHeading = GetHeadingFromVector_2d(vehicleCoords.x - playerCoords.x, vehicleCoords.y - playerCoords.y)
        
        -- Calculer l'angle le plus court pour tourner (éviter la rotation complète)
        local headingDiff = (((targetHeading - currentHeading) + 180) % 360) - 180
        if headingDiff > 180 then headingDiff = headingDiff - 360 end
        if headingDiff < -180 then headingDiff = headingDiff + 360 end
        
        -- Limiter la rotation à max 120 degrés dans chaque direction pour éviter les rotations complètes
        if headingDiff > 120 then headingDiff = 120 end
        if headingDiff < -120 then headingDiff = -120 end
        
        -- Appliquer la rotation limitée
        local newHeading = (currentHeading + headingDiff) % 360
        
        -- Tourner de façon naturelle
        TaskAchieveHeading(playerPed, newHeading, 750)
        Citizen.Wait(750)
        
        -- Jouer l'animation de rangement d'arme
        local dict = "reaction@intimidation@1h"
        local anim = "outro"
        
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Citizen.Wait(10)
        end
        
        TaskPlayAnim(playerPed, dict, anim, 8.0, 8.0, 1500, 50, 0, false, false, false)
        Citizen.Wait(1200) -- Attendre presque la fin de l'animation mais pas complètement
        RemoveAllPedWeapons(playerPed, true)
    else
        -- Méthode simple mais efficace pour orienter le joueur vers le véhicule
        local vehicleCoords = GetEntityCoords(vehicle)
        local playerCoords = GetEntityCoords(playerPed)
        
        -- Diriger le joueur vers le véhicule sans rotation exagérée
        local currentHeading = GetEntityHeading(playerPed)
        local targetHeading = GetHeadingFromVector_2d(vehicleCoords.x - playerCoords.x, vehicleCoords.y - playerCoords.y)
        
        -- Calculer l'angle le plus court pour tourner (éviter la rotation complète)
        local headingDiff = (((targetHeading - currentHeading) + 180) % 360) - 180
        if headingDiff > 180 then headingDiff = headingDiff - 360 end
        if headingDiff < -180 then headingDiff = headingDiff + 360 end
        
        -- Limiter la rotation à max 120 degrés dans chaque direction pour éviter les rotations complètes
        if headingDiff > 120 then headingDiff = 120 end
        if headingDiff < -120 then headingDiff = -120 end
        
        -- Appliquer la rotation limitée
        local newHeading = (currentHeading + headingDiff) % 360
        
        -- Tourner de façon naturelle
        TaskAchieveHeading(playerPed, newHeading, 750)
        Citizen.Wait(750)
    end
    
    -- Afficher la notification
    -- lib.notify({
    --     title = 'Action',
    --     description = Config.Notifications.Lockpicking,
    --     type = 'info'
    -- })
    
    -- Jouer l'animation de crochetage
    local lockpickDict = LOCKPICK_ANIM.dict
    local lockpickAnim = LOCKPICK_ANIM.anim
    
    RequestAnimDict(lockpickDict)
    while not HasAnimDictLoaded(lockpickDict) do
        Citizen.Wait(10)
    end
    
    TriggerServerEvent('sounds:playSource', 'lockpick', 0.1)
    -- Faire partir les PNJ à proximité (rayon de 10 mètres)
    local playerCoords = GetEntityCoords(playerPed)
makePedsWalkAway(playerCoords, 50.0)
    -- Modifier le flag à 16 ou 48 pour empêcher le mouvement pendant l'animation
    TaskPlayAnim(playerPed, lockpickDict, lockpickAnim, 8.0, 8.0, -1, 16, 0, false, false, false)
    
    -- Remplacer la barre de progression par un délai fixe
    -- Attendre pendant la durée du crochetage
    local lockpickStartTime = GetGameTimer()
    
    -- Créer un thread séparé pour permettre l'annulation
    local canBeCancelled = true
    
    Citizen.CreateThread(function()
        while GetGameTimer() - lockpickStartTime < LOCKPICK_DURATION and canBeCancelled do
            -- Vérifier si le joueur appuie sur une touche pour annuler
            if IsControlJustPressed(0, 73) then -- 73 est la touche X sur le clavier
                canBeCancelled = false
                stopLockpickAnimation()
                lib.notify({
                    title = 'Information',
                    description = 'Crochetage annulé',
                    type = 'info'
                })
                lockpickingVehicle = false
                return
            end
            Citizen.Wait(1)
        end
    end)
    
    -- Attendre que la durée du crochetage soit écoulée
    Citizen.Wait(LOCKPICK_DURATION)
    
    -- Vérifier si le crochetage a été annulé
    if not canBeCancelled then
        return
    end
    
    -- Calculer si le crochetage réussit
    local success = math.random(100) <= Config.LockpickSuccessChance
    
    -- Calculer si le lockpick se casse
    local lockpickBreaks = math.random(100) <= Config.LockpickBreakChance
    
    -- Arrêter l'animation
    stopLockpickAnimation()
    
    -- Gérer le résultat du crochetage
    if success then
        -- Déverrouiller le véhicule localement
        unlockVehicle(vehicle)
        abandonedVehicles[vehicleId] = true
        
        -- Synchroniser avec le serveur pour tous les joueurs
        markVehicleUnlockedOnServer(vehicle, vehicleId)
        
        lib.notify({
            title = 'Succès',
            description = Config.Notifications.LockpickSuccess,
            type = 'success'
        })
    else
        lib.notify({
            title = 'Echec',
            description = Config.Notifications.LockpickFailed,
            type = 'error'
        })
        
        -- Vérifier si une alerte doit être envoyée à la police
        if math.random(100) <= Config.PoliceAlertChance then
            -- Récupérer les coordonnées du joueur pour l'alerte
            local alertCoords = GetEntityCoords(playerPed)
            alertPolice(alertCoords)
        end
    end
    
    -- Gérer le bris du lockpick
    if lockpickBreaks then
        TriggerServerEvent('vehicle_lockpick:removeLockpick')
        lib.notify({
            title = 'Information',
            description = Config.Notifications.LockpickBroken,
            type = 'warning'
        })
        
        -- Mettre à jour le cache immédiatement
        hasLockpickCache = false
        lastLockpickCheck = GetGameTimer()
    end
    
    lockpickingVehicle = false
end

-- Initialisation du script
Citizen.CreateThread(function()
    --print("Initialisation du système anti-vol de véhicules NPC avec crochetage")
    
    -- S'assurer que toutes les tables sont initialisées
    if not verifiedPlates then verifiedPlates = {} end
    if not abandonedVehicles then abandonedVehicles = {} end
    if not trackedNPCVehicles then trackedNPCVehicles = {} end
    
    --print("Tables initialisées avec succès")
end)

-- Thread principal pour gérer les véhicules (OPTIMISÉ ET CORRIGÉ)
Citizen.CreateThread(function()
    -- Attendre que le script soit complètement chargé
    Citizen.Wait(1000)
    
    while true do
        Citizen.Wait(500)
        local playerPed = PlayerPedId()
        local pos = GetEntityCoords(playerPed)
        local radius = 100.0
        local vehicles = GetGamePool('CVehicle')
        
        for k, vehicle in pairs(vehicles) do
            local distance = #(pos - GetEntityCoords(vehicle))
            
            if distance < radius and DoesEntityExist(vehicle) then
                -- Utiliser un identifiant basé sur les propriétés du véhicule
                local vehicleId = getVehicleIdentifier(vehicle)
                
                -- Vérifier si le véhicule est blacklisté
                local isBlacklisted = isVehicleBlacklisted(vehicle)
                local isMotorcycle = (GetVehicleClass(vehicle) == 8)

                -- Vérifier si le véhicule doit être ignoré
                if isVehicleIgnored(vehicle) then
                    -- Ne rien faire pour les véhicules ignorés
                    -- print("Véhicule ignoré: " .. vehicleId)
                
                -- Vérifier si c'est un véhicule de location
                elseif isRentalVehicle(vehicle) then
                    -- Ne pas toucher au verrouillage des véhicules de location
                    -- Ils seront gérés par le système de clés standard
                
                -- Si ce n'est pas un véhicule appartenant à un joueur
                elseif not isPlayerOwnedVehicle(vehicle) then
                    -- Vérifier d'abord si le véhicule est dans la blacklist
                    if isBlacklisted then
                        -- Forcer le déverrouillage des véhicules blacklistés
                        local lockStatus = GetVehicleDoorLockStatus(vehicle)
                        if lockStatus > 1 then -- Si verrouillé (état 2 ou plus)
                            -- Debug pour le marquis
                            local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
                            if modelName == "MARQUIS" then
                                --print("Déverrouillage forcé du Marquis - État avant: " .. lockStatus)
                            end
                            
                            -- Forcer le déverrouillage
                            unlockVehicle(vehicle)
                            
                            -- Vérifier si ça a fonctionné
                            if modelName == "MARQUIS" then
                                --print("États après déverrouillage: " .. GetVehicleDoorLockStatus(vehicle))
                            end
                        end
                    -- Si le véhicule est dans la liste des abandonnés, il reste déverrouillé
                    elseif isVehicleAbandoned(vehicleId) or isAnyVehicleDoorOpen(vehicle) then
                        unlockVehicle(vehicle)
                    else
                        -- Vérifier l'état actuel du véhicule
                        local isOccupied = isVehicleOccupiedByNPC(vehicle)
                        local hasDeadNPC = hasDeadNPCInVehicle(vehicle)
                        local wasPlayerDriving = false
                        
                        -- Vérifier si le joueur conduisait ce véhicule
                        local player = PlayerId()
                        if GetVehiclePedIsIn(GetPlayerPed(player), true) == vehicle then
                            wasPlayerDriving = true
                            -- Si le joueur était dans ce véhicule, le considérer comme abandonné
                            unlockVehicle(vehicle)
                            abandonedVehicles[vehicleId] = true
                        else
                            -- Gérer les véhicules avec PNJ morts
                            if hasDeadNPC and not deadNPCVehicles[vehicleId] then
                                -- Premier passage sur ce véhicule avec PNJ mort
                                local unlockChance = math.random(100)
                                if unlockChance <= Config.DeadNPCUnlockChance then                                    -- 30% de chance de déverrouiller
                                    unlockVehicle(vehicle)
                                    abandonedVehicles[vehicleId] = true
                                    deadNPCVehicles[vehicleId] = "unlocked"
                                else
                                    -- 70% de chance de rester verrouillé
                                    lockVehicle(vehicle)
                                    deadNPCVehicles[vehicleId] = "locked"
                                end
                            elseif deadNPCVehicles[vehicleId] == "unlocked" then
                                -- Véhicule avec PNJ mort déjà déverrouillé, maintenir l'état
                                unlockVehicle(vehicle)
                            elseif deadNPCVehicles[vehicleId] == "locked" then
                                -- Véhicule avec PNJ mort qui doit rester verrouillé, maintenir l'état
                                lockVehicle(vehicle)
                            else
                                -- Traitement standard pour les véhicules sans PNJ morts
                                -- Traitement spécial pour les motos
                                if isMotorcycle then
                                    -- Pour les motos : si pas occupée = déverrouillée, si occupée = déverrouillée aussi
                                    if not isOccupied then
                                        -- La moto n'est plus occupée (PNJ descendu, tombé, etc.), la déverrouiller définitivement
                                        unlockVehicle(vehicle)
                                        abandonedVehicles[vehicleId] = true
                                    else
                                        -- Moto occupée par un PNJ, la laisser déverrouillée pour éviter les problèmes
                                        unlockVehicle(vehicle)
                                    end
                                    
                                    -- Mettre à jour l'état d'occupation de la moto
                                    trackedMotorcycles[vehicleId] = isOccupied
                                else
                                    -- Traitement standard pour les autres véhicules
                                    -- Si le véhicule était occupé avant et est maintenant vide
                                    if trackedNPCVehicles[vehicleId] and trackedNPCVehicles[vehicleId] == true and not isOccupied then
                                        -- Un PNJ vient de sortir, déverrouiller définitivement
                                        unlockVehicle(vehicle)
                                        abandonedVehicles[vehicleId] = true
                                    elseif not isVehicleAbandoned(vehicleId) then
                                        -- Véhicule occupé ou jamais tracké, verrouiller
                                        lockVehicle(vehicle)
                                    end
                                    
                                    -- Mettre à jour l'état d'occupation sauf si le joueur vient de l'utiliser
                                    if not wasPlayerDriving then
                                        trackedNPCVehicles[vehicleId] = isOccupied
                                    end
                                end
                            end
                        end
                        
                        -- Mettre à jour l'état d'occupation sauf si le joueur vient de l'utiliser (seulement pour les véhicules non-motos)
                        if not wasPlayerDriving and not isMotorcycle and not hasDeadNPC then
                            trackedNPCVehicles[vehicleId] = isOccupied
                        end
                    end
                end
            end
        end
    end
end)

-- Vider le cache des plaques vérifiées toutes les 5 minutes
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300000) -- 5 minutes
        verifiedPlates = {}
    end
end)

-- Nettoyer les tables de suivi pour éviter les fuites de mémoire
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(600000) -- Toutes les 10 minutes
        
        -- Limiter la taille des tables de suivi
        -- Pour les véhicules standard
        local countTracking = 0
        local newTracking = {}
        for k, v in pairs(trackedNPCVehicles) do
            countTracking = countTracking + 1
            if countTracking < 1000 then -- Garder seulement les 1000 plus récents
                newTracking[k] = v
            end
        end
        trackedNPCVehicles = newTracking
        
        -- Pour les motos
        local countMotorcycles = 0
        local newMotorcycleTracking = {}
        for k, v in pairs(trackedMotorcycles) do
            countMotorcycles = countMotorcycles + 1
            if countMotorcycles < 500 then -- Garder seulement les 500 plus récents
                newMotorcycleTracking[k] = v
            end
        end
        trackedMotorcycles = newMotorcycleTracking
        
        -- Pour les véhicules avec PNJ morts
        local countDeadNPC = 0
        local newDeadNPCVehicles = {}
        for k, v in pairs(deadNPCVehicles) do
            countDeadNPC = countDeadNPC + 1
            if countDeadNPC < 500 then -- Garder seulement les 500 plus récents
                newDeadNPCVehicles[k] = v
            end
        end
        deadNPCVehicles = newDeadNPCVehicles
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000) -- Vérifier toutes les secondes
        
        local playerPed = PlayerPedId()
        if IsPedInAnyVehicle(playerPed, false) then
            local vehicle = GetVehiclePedIsIn(playerPed, false)
            
            -- Si le véhicule existe et n'appartient pas à un joueur
            if DoesEntityExist(vehicle) and not isPlayerOwnedVehicle(vehicle) then
                local vehicleId = getVehicleIdentifier(vehicle)
                
                -- Marquer ce véhicule comme abandonné pour qu'il reste déverrouillé
                if not isVehicleBlacklisted(vehicle) then
                    abandonedVehicles[vehicleId] = true
                end
            end
        end
    end
end)

Citizen.CreateThread(function()
    -- Attendre que le joueur soit complètement chargé
    Citizen.Wait(5000)
    
    -- Récupérer la liste des véhicules déverrouillés du serveur
    ESX.TriggerServerCallback('vehicle_lockpick:getUnlockedVehicles', function(unlockedVehiclesList)
        -- Vérifier si la liste existe avant d'itérer
        if unlockedVehiclesList then
            local count = 0
            for vehicleId, _ in pairs(unlockedVehiclesList) do
                abandonedVehicles[vehicleId] = true
                count = count + 1
            end
            --print("^3[vehicle_restriction]^7 Récupération de " .. count .. " véhicules déverrouillés")
        else
            -- Initialiser la table si elle est nil
            --print("^3[vehicle_restriction]^7 Aucun véhicule déverrouillé trouvé")
        end
    end)
end)

-- Fonction pour compter les éléments d'une table
table.count = function(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Thread spécifique pour gérer les véhicules de location
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        
        local playerPed = PlayerPedId()
        if IsPedInAnyVehicle(playerPed, false) then
            local vehicle = GetVehiclePedIsIn(playerPed, false)
            
            -- Si le véhicule est de location, on s'assure qu'il reste déverrouillé
            if DoesEntityExist(vehicle) and isRentalVehicle(vehicle) then
                -- Forcer le déverrouillage pour être sûr
                SetVehicleDoorsLocked(vehicle, 1) -- 1 = déverrouillé
                SetVehicleDoorsLockedForAllPlayers(vehicle, false)
                SetVehicleEngineOn(vehicle, true, true, false)
            end
        end
    end
end)

function isRentalVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return false end

    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate then return false end
    
    plate = string.gsub(plate, "^%s*(.-)%s*$", "%1") -- Supprimer les espaces
    
    -- Vérifier uniquement dans le cache et la config
    if rentalPlatesCache[plate] ~= nil then
        return rentalPlatesCache[plate]
    end
    
    -- Vérifier avec le pattern de plaque
    for rentalPlate, _ in pairs(Config.RentalPlates) do
        if string.find(plate:upper(), rentalPlate:upper()) then
            rentalPlatesCache[plate] = true
            return true
        end
    end
    
    rentalPlatesCache[plate] = false
    return false
end

-- Citizen.CreateThread(function()
--     while true do
--         Citizen.Wait(300000) -- 5 minutes
--         rentalPlatesCache = {}
--     end
-- end)

-- Initialisation du système de target
Citizen.CreateThread(function()
    Citizen.Wait(500) -- Attendre que tout soit chargé
    
    -- Ajouter l'option de crochetage sur les véhicules
    exports.ox_target:addGlobalVehicle({
        {
            name = 'vehicle_lockpick',
            icon = 'fa-solid fa-unlock',
            label = 'Crocheter',
            distance = 1.0,
            canInteract = function(entity, distance, coords, name)
                -- Vérifier si le véhicule peut être crocheté
                if not DoesEntityExist(entity) then 
                    return false 
                end
                
                -- Ne pas montrer l'option si le joueur n'a pas de lockpick
                if not hasLockpick() then
                    return false
                end
                
                -- Ne pas montrer pour les véhicules de joueurs
                if isPlayerOwnedVehicle(entity) then
                    return false
                end
                
                -- Ne pas montrer pour les véhicules blacklistés
                if isVehicleBlacklisted(entity) then
                    return false
                end
                
                -- Ne pas montrer pour les véhicules ignorés
                if isVehicleIgnored(entity) then
                    return false
                end
                
                -- Ne pas montrer pour les véhicules de location
                if isRentalVehicle(entity) then
                    return false
                end
                
                -- Ne pas montrer si le véhicule est occupé par un NPC
                if isVehicleOccupiedByNPC(entity) then
                    return false
                end
                
                -- Ne pas montrer si le véhicule est déjà déverrouillé
                local lockStatus = GetVehicleDoorLockStatus(entity)
                if lockStatus == 0 or lockStatus == 1 or isAnyVehicleDoorOpen(entity) then
                    return false
                end
                
                -- Ne pas montrer si le véhicule est déjà considéré comme abandonné
                local vehicleId = getVehicleIdentifier(entity)
                if isVehicleAbandoned(vehicleId) then
                    return false
                end
                
                -- Si toutes les vérifications passent, afficher l'option
                return true
            end,
            onSelect = function(data)
                lockpickVehicle(data.entity)
            end
        }
    })
end)

-- Fonction pour envoyer une alerte à la police avec blip
function alertPolice(coords)
    local streetName, crossingRoad = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetName)
    
    if crossingRoad and crossingRoad ~= 0 then
        street = street .. " / " .. GetStreetNameFromHashKey(crossingRoad)
    end
    
    -- Envoyer l'alerte au serveur pour distribution aux policiers
    TriggerServerEvent('vehicle_lockpick:alertPolice', coords, street)
end

-- Fonction pour créer un blip temporaire à l'emplacement du crochetage (côté client uniquement pour les policiers)
RegisterNetEvent('vehicle_lockpick:createBlip')
AddEventHandler('vehicle_lockpick:createBlip', function(coords)
    -- Créer le blip
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    
    -- Configurer le blip selon les paramètres
    SetBlipSprite(blip, ALERT_BLIP.sprite)
    SetBlipColour(blip, ALERT_BLIP.color)
    SetBlipScale(blip, ALERT_BLIP.scale)
    if ALERT_BLIP.flash then
        SetBlipFlashes(blip, true)
    end
    
    -- Ajouter un texte au blip
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Tentative de vol")
    EndTextCommandSetBlipName(blip)
    
    -- Supprimer le blip après la durée spécifiée
    Citizen.SetTimeout(ALERT_BLIP.duration * 1000, function()
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)
end)