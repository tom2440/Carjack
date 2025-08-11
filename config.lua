Config = {}

-- ===================================
-- SYSTÈME DE CROCHETAGE
-- ===================================

-- Item requis pour crocheter (doit exister dans ox_inventory)
Config.LockpickItem = 'lockpick'

-- Pourcentage de chance de réussir le crochetage (0-100)
Config.LockpickSuccessChance = 70

-- Pourcentage de chance que le lockpick se casse pendant l'utilisation (0-100)
Config.LockpickBreakChance = 10

-- Pourcentage de chance que le véhicule soit déverrouillé quand le PNJ meurt (0-100)
Config.DeadNPCUnlockChance = 30

-- Pourcentage de chance d'alerter la police en cas d'échec de crochetage (0-100)
Config.PoliceAlertChance = 60

-- Nom du job de police dans votre base de données ESX
Config.PoliceJobName = 'police'

-- ===================================
-- VÉHICULES DE LOCATION
-- ===================================

Config.RentalPlates = {
    ["RENT"] = true,    -- Plaques contenant "RENT" (ex: RENT001, RENTCAR, etc.)
    
    -- AJOUTEZ VOS PATTERNS DE LOCATION ICI :
}

-- Véhicules IGNORÉS par le script (ni verrouillés ni déverrouillés automatiquement)

-- Plaques ignorées (le script ne touche pas à ces véhicules)
Config.IgnoredPlates = {
    ["POLICE"] = true,   -- Véhicules de police
    ["EMS"] = true,      -- Véhicules médicaux
    ["TAXI"] = true,     -- Taxis joueurs
    ["TAXINPC"] = true,  -- Taxis NPC
    ["MECANO"] = true,   -- Véhicules mécaniciens
    ["YELLOW"] = true,   -- Taxis jaunes
    ["DYNASTY8"] = true, -- Véhicules d'immobilier
    ["LSFD"] = true,     -- Pompiers
    ["GOFAST"] = true,   -- Véhicules de livraison
    ["CARDEAL"] = true,  -- Concessionnaires
    ["RENT CAR"] = true, -- Location
    ["RALLY"] = true,    -- Rallye
    ["GARBAGE"] = true,  -- Éboueurs
    ["DELIVTRK"] = true, -- Camions de livraison
    ["BAHAMA"] = true,   -- Bahama
    ["456YB45"] = true   -- Plaque spécifique
}

-- Modèles de véhicules ignorés
Config.IgnoredModels = {
    ['police'] = true,    -- Voitures de police
    ['ambulance'] = true, -- Ambulances
    ['rentbus'] = true,   -- Bus de location
    ['firetruk'] = true,  -- Camions de pompiers
    ['bus'] = true,       -- Bus publics
    ['kart'] = true,      -- Karts
}

-- ===================================
-- VÉHICULES JAMAIS VERROUILLÉS (BLACKLIST)
-- ===================================

-- Ces véhicules sont TOUJOURS déverrouillés (comme les vélos, bateaux, etc.)

-- Modèles spécifiques toujours déverrouillés
Config.BlacklistedModels = {
    -- Ajoutez ici des modèles de véhicules qui doivent toujours être déverrouillés
    -- Exemple: ['frogger'] = true,
}

-- Plaques toujours déverrouillées
Config.BlacklistedPlates = {
    ["ADMIN"] = true,   -- Véhicules d'administration
    ["CW-SHOW"] = true, -- Véhicules d'exposition
}

-- CATÉGORIES GTA toujours déverrouillées (par code de classe)
Config.BlacklistedCategories = {
    [0] = false,  -- Voitures normales → restent verrouillées
    [8] = false,     -- Motos → false = verrouillées quand abandonnées (recommandé)
    [13] = true,     -- Vélos → toujours déverrouillés
    [14] = true,     -- Bateaux → toujours déverrouillés
    [16] = true,     -- Avions → toujours déverrouillés
    
    
}


Config.Notifications = {
    NoLockpick = "Vous n'avez pas de lockpick",
    CannotLockpick = "Vous ne pouvez pas crocheter ce véhicule",
    Lockpicking = "Crochetage en cours...",
    LockpickSuccess = "Crochetage réussi !",
    LockpickFailed = "Crochetage échoué !",
    LockpickBroken = "Votre lockpick s'est cassé !",
    VehicleAlreadyUnlocked = "Ce véhicule est déjà déverrouillé",
    PlayerVehicle = "Ce véhicule appartient à un joueur et ne peut pas être crocheté",
    NPCInVehicle = "Il y a quelqu'un dans ce véhicule",
    IgnoredVehicle = "Ce véhicule ne peut pas être modifié",
    RentalVehicle = "Ce véhicule est de location et ne peut pas être crocheté",
}