ESX = exports["es_extended"]:getSharedObject()

local unlockedVehicles = {}
local rentalCache = {}
local rentalCacheExpiry = {}
local CACHE_DURATION = 600

local ownedVehiclesCache = {}
local ownedVehiclesCacheExpiry = {}

ESX.RegisterServerCallback('vehicle_restriction:isPlayerOwnedVehicle', function(source, cb, plate)
    if plate then
        plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")
        
        if ownedVehiclesCache[plate] ~= nil and os.time() < ownedVehiclesCacheExpiry[plate] then
            cb(ownedVehiclesCache[plate])
            return
        end
        
        MySQL.query('SELECT 1 FROM owned_vehicles WHERE plate = ?', {plate}, function(result)
            local isOwned = result and #result > 0
            
            ownedVehiclesCache[plate] = isOwned
            ownedVehiclesCacheExpiry[plate] = os.time() + CACHE_DURATION
            
            cb(isOwned)
        end)
    else
        cb(false)
    end
end)

RegisterNetEvent('vehicle_lockpick:removeLockpick')
AddEventHandler('vehicle_lockpick:removeLockpick', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if xPlayer then
        exports.ox_inventory:RemoveItem(source, Config.LockpickItem, 1)
    end
end)

RegisterNetEvent('vehicle_lockpick:markVehicleUnlocked')
AddEventHandler('vehicle_lockpick:markVehicleUnlocked', function(vehicleNetId, vehicleId)
    local source = source
    
    unlockedVehicles[vehicleId] = true
    
    TriggerClientEvent('vehicle_lockpick:syncUnlockedVehicle', -1, vehicleNetId, vehicleId)
end)

ESX.RegisterServerCallback('vehicle_lockpick:getUnlockedVehicles', function(source, cb)
    cb(unlockedVehicles)
end)

ESX.RegisterServerCallback('vehicle_restriction:batchCheckRentalVehicles', function(source, cb, plates)
    if not plates or #plates == 0 then
        cb({})
        return
    end
    
    local response = {}
    
    for i=1, #plates do
        local plate = plates[i]
        response[plate] = false
        
        for rentalPlate, _ in pairs(Config.RentalPlates) do
            if string.find(plate:upper(), rentalPlate:upper()) then
                response[plate] = true
                break
            end
        end
    end
    
    cb(response)
end)

CreateThread(function()
    while true do
        Wait(300000)
        
        local currentTime = os.time()
        local expiredCount = 0
        
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
    end
end)

RegisterNetEvent('vehicle_lockpick:alertPolice')
AddEventHandler('vehicle_lockpick:alertPolice', function(coords, streetName)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local xPlayers = ESX.GetExtendedPlayers('job', Config.PoliceJobName) or {}
    
    if next(xPlayers) ~= nil then
        for _, xPolice in pairs(xPlayers) do
            TriggerClientEvent('sound:play', xPolice.source, 'radio-on', 0.1)
            
            TriggerClientEvent('esx:showAdvancedNotification', xPolice.source, 
                "Alerte: Tentative de vol de véhicule", 
                'Localisation: ' .. streetName, 
                "Un individu a été aperçu en train d'essayer de voler un véhicule.", 
                'CHAR_CALL911',
                1
            )
            
            TriggerClientEvent('vehicle_lockpick:createBlip', xPolice.source, coords)
        end
    end
end)

CreateThread(function()
    Wait(5000)
    
    MySQL.query('CREATE INDEX IF NOT EXISTS idx_owned_vehicles_plate ON owned_vehicles (plate)', {}, function()
    end)
end)
