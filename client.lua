ESX = exports["es_extended"]:getSharedObject()

verifiedPlates = {}
abandonedVehicles = {}
trackedNPCVehicles = {}
lockpickingVehicle = false
local lastLockpickCheck = 0
local hasLockpickCache = false
local rentalPlatesCache = {}
local lastRentalCheck = 0
local trackedMotorcycles = {}
local deadNPCVehicles = {}
local deadNPCUnlockChance = 30
local LOCKPICK_DURATION = 3500
local SPECIAL_MOTORCYCLE_HANDLING = true
local LOCKPICK_ANIM = {
    dict = 'missheistfbisetup1',
    anim = 'hassle_intro_loop_f'
}
local ALERT_BLIP = {
    sprite = 161,
    color = 1,
    scale = 0.8,
    duration = 60,
    flash = true
}

function markVehicleUnlockedOnServer(vehicle, vehicleId)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId and netId ~= 0 then
        TriggerServerEvent('vehicle_lockpick:markVehicleUnlocked', netId, vehicleId)
    end
end

RegisterNetEvent('vehicle_lockpick:syncUnlockedVehicle')
AddEventHandler('vehicle_lockpick:syncUnlockedVehicle', function(netId, vehicleId)
    abandonedVehicles[vehicleId] = true
    
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(vehicle) then
        unlockVehicle(vehicle)
    end
end)

function isVehicleBlacklisted(vehicle)
    if not DoesEntityExist(vehicle) then return false end

    if SPECIAL_MOTORCYCLE_HANDLING and shouldMotorcycleBeUnlocked(vehicle) then
        return true
    end

    local category = GetVehicleClass(vehicle)
    if Config.BlacklistedCategories and Config.BlacklistedCategories[category] then
        return true
    end

    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)):lower()
    if Config.BlacklistedModels[modelName] then
        return true
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    if plate then
        plate = string.gsub(plate, "%s+", "")
        for blacklistedPlate, _ in pairs(Config.BlacklistedPlates) do
            if string.find(plate:upper(), blacklistedPlate:upper()) then
                return true
            end
        end
    end

    return false
end

function shouldMotorcycleBeUnlocked(vehicle)
    local category = GetVehicleClass(vehicle)
    if category ~= 8 then
        return false
    end
    
    local vehicleId = getVehicleIdentifier(vehicle)
    if trackedMotorcycles[vehicleId] == true and not isVehicleOccupiedByNPC(vehicle) then
        abandonedVehicles[vehicleId] = true
        return true
    end
    
    return isVehicleOccupiedByNPC(vehicle)
end

function isPlayerOwnedVehicle(vehicle)
    local plate = GetVehicleNumberPlateText(vehicle)
    if plate then
        plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")
        
        if verifiedPlates[plate] ~= nil then
            return verifiedPlates[plate]
        end
        
        local result = nil
        ESX.TriggerServerCallback('vehicle_restriction:isPlayerOwnedVehicle', function(isOwned)
            result = isOwned
            verifiedPlates[plate] = isOwned
        end, plate)
        
        local timeout = 50
        while result == nil and timeout > 0 do
            Wait(10)
            timeout = timeout - 1
        end
        
        return result or false
    end
    return false
end

function isVehicleOccupiedByNPC(vehicle)
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped) then
            return true
        end
    end
    return false
end

function hasDeadNPCInVehicle(vehicle)
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and not IsPedAPlayer(ped) and IsPedDeadOrDying(ped) then
            return true
        end
    end
    return false
end

function isVehicleAbandoned(vehicleId)
    return abandonedVehicles and abandonedVehicles[vehicleId] == true
end

function isAnyVehicleDoorOpen(vehicle)
    for i = 0, 5 do
        if DoesVehicleHaveDoor(vehicle, i) and GetVehicleDoorAngleRatio(vehicle, i) > 0.0 then
            return true
        end
    end
    return false
end

function lockVehicle(vehicle)
    SetVehicleDoorsLocked(vehicle, 2)
end

function unlockVehicle(vehicle)
    SetVehicleDoorsLocked(vehicle, 0)
end

function getVehicleIdentifier(vehicle)
    local plate = GetVehicleNumberPlateText(vehicle) or ""
    local model = GetEntityModel(vehicle) or 0
    return plate .. "_" .. model
end

function hasLockpick()
    local currentTime = GetGameTimer()
    
    if currentTime - lastLockpickCheck > 3000 then
        hasLockpickCache = exports.ox_inventory:Search('count', Config.LockpickItem) > 0
        lastLockpickCheck = currentTime
    end
    
    return hasLockpickCache
end

function stopLockpickAnimation()
    local playerPed = PlayerPedId()
    ClearPedTasks(playerPed)
end

function GetVehicleInDirection(coordFrom, coordTo)
    local rayHandle = StartExpensiveSynchronousShapeTestLosProbe(coordFrom.x, coordFrom.y, coordFrom.z, coordTo.x, coordTo.y, coordTo.z, 10, PlayerPedId(), 0)
    local _, _, _, _, vehicle = GetShapeTestResult(rayHandle)
    return vehicle
end

function isVehicleIgnored(vehicle)
    if not DoesEntityExist(vehicle) then return false end

    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)):lower()
    if Config.IgnoredModels[modelName] then
        return true
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    if plate then
        plate = string.gsub(plate, "%s+", "")
        for ignoredPlate, _ in pairs(Config.IgnoredPlates) do
            if string.find(plate:upper(), ignoredPlate:upper()) then
                return true
            end
        end
    end

    return false
end

function makePedsWalkAway(coords, radius)
    local peds = GetGamePool('CPed')
    for _, ped in pairs(peds) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedInAnyVehicle(ped, true) then
            local pedCoords = GetEntityCoords(ped)
            local distance = #(coords - pedCoords)
            
            if distance <= radius then
                if not IsPedInMeleeCombat(ped) and not IsPedFleeing(ped) and not IsPedDeadOrDying(ped) then
                    local awayVector = vector3(
                        pedCoords.x - coords.x,
                        pedCoords.y - coords.y,
                        0
                    )
                    
                    local length = #awayVector
                    if length > 0 then
                        awayVector = vector3(
                            awayVector.x / length * 40.0,
                            awayVector.y / length * 40.0,
                            0
                        )
                    else
                        local randomAngle = math.random() * 2 * math.pi
                        awayVector = vector3(
                            math.cos(randomAngle) * 40.0,
                            math.sin(randomAngle) * 40.0,
                            0
                        )
                    end
                    
                    local destCoords = vector3(
                        pedCoords.x + awayVector.x,
                        pedCoords.y + awayVector.y,
                        pedCoords.z
                    )
                    
                    ClearPedTasksImmediately(ped)
                    SetPedMoveRateOverride(ped, 0.8 + (math.random() * 0.9))
                    TaskGoToCoordAnyMeans(ped, destCoords.x, destCoords.y, destCoords.z, 1.0, 0, false, 0, 0)
                end
            end
        end
    end
end

function lockpickVehicle(vehicle)
    if lockpickingVehicle then
        return
    end
    
    if not hasLockpick() then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.NoLockpick,
            type = 'error'
        })
        return
    end
    
    if isPlayerOwnedVehicle(vehicle) then
        return
    end
    
    if isVehicleBlacklisted(vehicle) then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.VehicleAlreadyUnlocked,
            type = 'error'
        })
        return
    end
    
    if isVehicleIgnored(vehicle) then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.CannotLockpick,
            type = 'error'
        })
        return
    end
    
    if isRentalVehicle(vehicle) then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.RentalVehicle,
            type = 'error'
        })
        return
    end
    
    if isVehicleOccupiedByNPC(vehicle) then
        lib.notify({
            title = 'Information',
            description = Config.Notifications.NPCInVehicle,
            type = 'error'
        })
        return
    end
    
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
    
    lockpickingVehicle = true
    
    local playerPed = PlayerPedId()
    local hasWeapon = HasPedGotWeapon(playerPed, GetSelectedPedWeapon(playerPed), false)
    local weaponHash = GetSelectedPedWeapon(playerPed)
    
    if hasWeapon and weaponHash ~= GetHashKey('WEAPON_UNARMED') then
        local vehicleCoords = GetEntityCoords(vehicle)
        local playerCoords = GetEntityCoords(playerPed)
        
        local currentHeading = GetEntityHeading(playerPed)
        local targetHeading = GetHeadingFromVector_2d(vehicleCoords.x - playerCoords.x, vehicleCoords.y - playerCoords.y)
        
        local headingDiff = (((targetHeading - currentHeading) + 180) % 360) - 180
        if headingDiff > 180 then headingDiff = headingDiff - 360 end
        if headingDiff < -180 then headingDiff = headingDiff + 360 end
        
        if headingDiff > 120 then headingDiff = 120 end
        if headingDiff < -120 then headingDiff = -120 end
        
        local newHeading = (currentHeading + headingDiff) % 360
        
        TaskAchieveHeading(playerPed, newHeading, 750)
        Citizen.Wait(750)
        
        local dict = "reaction@intimidation@1h"
        local anim = "outro"
        
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Citizen.Wait(10)
        end
        
        TaskPlayAnim(playerPed, dict, anim, 8.0, 8.0, 1500, 50, 0, false, false, false)
        Citizen.Wait(1200)
        RemoveAllPedWeapons(playerPed, true)
    else
        local vehicleCoords = GetEntityCoords(vehicle)
        local playerCoords = GetEntityCoords(playerPed)
        
        local currentHeading = GetEntityHeading(playerPed)
        local targetHeading = GetHeadingFromVector_2d(vehicleCoords.x - playerCoords.x, vehicleCoords.y - playerCoords.y)
        
        local headingDiff = (((targetHeading - currentHeading) + 180) % 360) - 180
        if headingDiff > 180 then headingDiff = headingDiff - 360 end
        if headingDiff < -180 then headingDiff = headingDiff + 360 end
        
        if headingDiff > 120 then headingDiff = 120 end
        if headingDiff < -120 then headingDiff = -120 end
        
        local newHeading = (currentHeading + headingDiff) % 360
        
        TaskAchieveHeading(playerPed, newHeading, 750)
        Citizen.Wait(750)
    end
    
    local lockpickDict = LOCKPICK_ANIM.dict
    local lockpickAnim = LOCKPICK_ANIM.anim
    
    RequestAnimDict(lockpickDict)
    while not HasAnimDictLoaded(lockpickDict) do
        Citizen.Wait(10)
    end
    
    TriggerServerEvent('sounds:playSource', 'lockpick', 0.1)
    local playerCoords = GetEntityCoords(playerPed)
    makePedsWalkAway(playerCoords, 50.0)
    TaskPlayAnim(playerPed, lockpickDict, lockpickAnim, 8.0, 8.0, -1, 16, 0, false, false, false)
    
    local lockpickStartTime = GetGameTimer()
    local canBeCancelled = true
    
    Citizen.CreateThread(function()
        while GetGameTimer() - lockpickStartTime < LOCKPICK_DURATION and canBeCancelled do
            if IsControlJustPressed(0, 73) then
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
    
    Citizen.Wait(LOCKPICK_DURATION)
    
    if not canBeCancelled then
        return
    end
    
    local success = math.random(100) <= Config.LockpickSuccessChance
    local lockpickBreaks = math.random(100) <= Config.LockpickBreakChance
    
    stopLockpickAnimation()
    
    if success then
        unlockVehicle(vehicle)
        abandonedVehicles[vehicleId] = true
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
        
        if math.random(100) <= Config.PoliceAlertChance then
            local alertCoords = GetEntityCoords(playerPed)
            alertPolice(alertCoords)
        end
    end
    
    if lockpickBreaks then
        TriggerServerEvent('vehicle_lockpick:removeLockpick')
        lib.notify({
            title = 'Information',
            description = Config.Notifications.LockpickBroken,
            type = 'warning'
        })
        
        hasLockpickCache = false
        lastLockpickCheck = GetGameTimer()
    end
    
    lockpickingVehicle = false
end

Citizen.CreateThread(function()
    if not verifiedPlates then verifiedPlates = {} end
    if not abandonedVehicles then abandonedVehicles = {} end
    if not trackedNPCVehicles then trackedNPCVehicles = {} end
end)

Citizen.CreateThread(function()
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
                local vehicleId = getVehicleIdentifier(vehicle)
                local isBlacklisted = isVehicleBlacklisted(vehicle)
                local isMotorcycle = (GetVehicleClass(vehicle) == 8)

                if isVehicleIgnored(vehicle) then
                
                elseif isRentalVehicle(vehicle) then
                
                elseif not isPlayerOwnedVehicle(vehicle) then
                    if isBlacklisted then
                        local lockStatus = GetVehicleDoorLockStatus(vehicle)
                        if lockStatus > 1 then
                            unlockVehicle(vehicle)
                        end
                    elseif isVehicleAbandoned(vehicleId) or isAnyVehicleDoorOpen(vehicle) then
                        unlockVehicle(vehicle)
                    else
                        local isOccupied = isVehicleOccupiedByNPC(vehicle)
                        local hasDeadNPC = hasDeadNPCInVehicle(vehicle)
                        local wasPlayerDriving = false
                        
                        local player = PlayerId()
                        if GetVehiclePedIsIn(GetPlayerPed(player), true) == vehicle then
                            wasPlayerDriving = true
                            unlockVehicle(vehicle)
                            abandonedVehicles[vehicleId] = true
                        else
                            if hasDeadNPC and not deadNPCVehicles[vehicleId] then
                                local unlockChance = math.random(100)
                                if unlockChance <= Config.DeadNPCUnlockChance then
                                    unlockVehicle(vehicle)
                                    abandonedVehicles[vehicleId] = true
                                    deadNPCVehicles[vehicleId] = "unlocked"
                                else
                                    lockVehicle(vehicle)
                                    deadNPCVehicles[vehicleId] = "locked"
                                end
                            elseif deadNPCVehicles[vehicleId] == "unlocked" then
                                unlockVehicle(vehicle)
                            elseif deadNPCVehicles[vehicleId] == "locked" then
                                lockVehicle(vehicle)
                            else
                                if isMotorcycle then
                                    if not isOccupied then
                                        unlockVehicle(vehicle)
                                        abandonedVehicles[vehicleId] = true
                                    else
                                        unlockVehicle(vehicle)
                                    end
                                    
                                    trackedMotorcycles[vehicleId] = isOccupied
                                else
                                    if trackedNPCVehicles[vehicleId] and trackedNPCVehicles[vehicleId] == true and not isOccupied then
                                        unlockVehicle(vehicle)
                                        abandonedVehicles[vehicleId] = true
                                    elseif not isVehicleAbandoned(vehicleId) then
                                        lockVehicle(vehicle)
                                    end
                                    
                                    if not wasPlayerDriving then
                                        trackedNPCVehicles[vehicleId] = isOccupied
                                    end
                                end
                            end
                        end
                        
                        if not wasPlayerDriving and not isMotorcycle and not hasDeadNPC then
                            trackedNPCVehicles[vehicleId] = isOccupied
                        end
                    end
                end
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300000)
        verifiedPlates = {}
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(600000)
        
        local countTracking = 0
        local newTracking = {}
        for k, v in pairs(trackedNPCVehicles) do
            countTracking = countTracking + 1
            if countTracking < 1000 then
                newTracking[k] = v
            end
        end
        trackedNPCVehicles = newTracking
        
        local countMotorcycles = 0
        local newMotorcycleTracking = {}
        for k, v in pairs(trackedMotorcycles) do
            countMotorcycles = countMotorcycles + 1
            if countMotorcycles < 500 then
                newMotorcycleTracking[k] = v
            end
        end
        trackedMotorcycles = newMotorcycleTracking
        
        local countDeadNPC = 0
        local newDeadNPCVehicles = {}
        for k, v in pairs(deadNPCVehicles) do
            countDeadNPC = countDeadNPC + 1
            if countDeadNPC < 500 then
                newDeadNPCVehicles[k] = v
            end
        end
        deadNPCVehicles = newDeadNPCVehicles
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        
        local playerPed = PlayerPedId()
        if IsPedInAnyVehicle(playerPed, false) then
            local vehicle = GetVehiclePedIsIn(playerPed, false)
            
            if DoesEntityExist(vehicle) and not isPlayerOwnedVehicle(vehicle) then
                local vehicleId = getVehicleIdentifier(vehicle)
                
                if not isVehicleBlacklisted(vehicle) then
                    abandonedVehicles[vehicleId] = true
                end
            end
        end
    end
end)

Citizen.CreateThread(function()
    Citizen.Wait(5000)
    
    ESX.TriggerServerCallback('vehicle_lockpick:getUnlockedVehicles', function(unlockedVehiclesList)
        if unlockedVehiclesList then
            local count = 0
            for vehicleId, _ in pairs(unlockedVehiclesList) do
                abandonedVehicles[vehicleId] = true
                count = count + 1
            end
        end
    end)
end)

table.count = function(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        
        local playerPed = PlayerPedId()
        if IsPedInAnyVehicle(playerPed, false) then
            local vehicle = GetVehiclePedIsIn(playerPed, false)
            
            if DoesEntityExist(vehicle) and isRentalVehicle(vehicle) then
                SetVehicleDoorsLocked(vehicle, 1)
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
    
    plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")
    
    if rentalPlatesCache[plate] ~= nil then
        return rentalPlatesCache[plate]
    end
    
    for rentalPlate, _ in pairs(Config.RentalPlates) do
        if string.find(plate:upper(), rentalPlate:upper()) then
            rentalPlatesCache[plate] = true
            return true
        end
    end
    
    rentalPlatesCache[plate] = false
    return false
end

Citizen.CreateThread(function()
    Citizen.Wait(500)
    
    exports.ox_target:addGlobalVehicle({
        {
            name = 'vehicle_lockpick',
            icon = 'fa-solid fa-unlock',
            label = 'Crocheter',
            distance = 1.0,
            canInteract = function(entity, distance, coords, name)
                if not DoesEntityExist(entity) then 
                    return false 
                end
                
                if not hasLockpick() then
                    return false
                end
                
                if isPlayerOwnedVehicle(entity) then
                    return false
                end
                
                if isVehicleBlacklisted(entity) then
                    return false
                end
                
                if isVehicleIgnored(entity) then
                    return false
                end
                
                if isRentalVehicle(entity) then
                    return false
                end
                
                if isVehicleOccupiedByNPC(entity) then
                    return false
                end
                
                local lockStatus = GetVehicleDoorLockStatus(entity)
                if lockStatus == 0 or lockStatus == 1 or isAnyVehicleDoorOpen(entity) then
                    return false
                end
                
                local vehicleId = getVehicleIdentifier(entity)
                if isVehicleAbandoned(vehicleId) then
                    return false
                end
                
                return true
            end,
            onSelect = function(data)
                lockpickVehicle(data.entity)
            end
        }
    })
end)

function alertPolice(coords)
    local streetName, crossingRoad = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetName)
    
    if crossingRoad and crossingRoad ~= 0 then
        street = street .. " / " .. GetStreetNameFromHashKey(crossingRoad)
    end
    
    TriggerServerEvent('vehicle_lockpick:alertPolice', coords, street)
end

RegisterNetEvent('vehicle_lockpick:createBlip')
AddEventHandler('vehicle_lockpick:createBlip', function(coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    
    SetBlipSprite(blip, ALERT_BLIP.sprite)
    SetBlipColour(blip, ALERT_BLIP.color)
    SetBlipScale(blip, ALERT_BLIP.scale)
    if ALERT_BLIP.flash then
        SetBlipFlashes(blip, true)
    end
    
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Tentative de vol")
    EndTextCommandSetBlipName(blip)
    
    Citizen.SetTimeout(ALERT_BLIP.duration * 1000, function()
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)
end)
