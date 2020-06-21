-- Dependencies
require 'Debug'
require 'Utilities'
--require 'Settings'

local RADIANT = 2 -- TODO: REMOVE THESE
local DIRE = 3

-- local debug flag
local thisDebug = true;
local isDebug = Debug.IsDebug() and thisDebug;

NeutralItemsTracker = {
    -- immutables
    settings =
    {
        allNeutralItems = {},
        neutralsByName = {},
        tierTimings = {},
        maxNeutralItemsPerTier = 5, -- per tier per team
        neutralItemMinInterval = 10,
        neutralItemMaxInterval = 60
    }
}

local __meta = {__index = NeutralItemsTracker}

-- example Neutrals
	-- --                                              roles= 1,2,3,4,5
	-- {name = 'item_arcane_ring', 					tier = 1, ranged = true, 	melee = true, 	roles={1,1,1,1,1}, realName = 'Arcane Ring'},
	-- {name = 'item_broom_handle', 					tier = 1, ranged = false, melee = true,		roles={1,1,1,0,0}, realName = 'Broom Handle'},

function NeutralItemsTracker:new(allNeutralItems, tierTimings)

    local neutralsByName = {}
    for _, neutral in pairs(allNeutralItems) do
        neutralsByName[neutral.name] = neutral
    end

    local newInstance =
    {
        settings = 
        {
            allNeutralItems = Utilities:ShallowCopy(allNeutralItems),
            neutralsByName = neutralsByName,
            tierTimings = tierTimings,
            maxNeutralItemsPerTier = 5, -- per tier per team
            neutralItemMinInterval = 10,
            neutralItemMaxInterval = 60
        },

        statePerTeam =
        {
            [RADIANT] =
            {
                neutralsGrantedPerTier = { 0, 0, 0, 0, 0 },
                nextNeutralTime = tierTimings[1],
                availableNeutrals = Utilities:ShallowCopy(allNeutralItems),
                fakeStashPerTier = { 0, 0, 0, 0, 0 }
            },
            [DIRE] =
            {
                neutralsGrantedPerTier = { 0, 0, 0, 0, 0 },
                nextNeutralTime = tierTimings[1],
                availableNeutrals = Utilities:ShallowCopy(allNeutralItems),
                fakeStashPerTier = { 0, 0, 0, 0, 0 }
            }
        }
    }

    setmetatable(newInstance, __meta)
    return newInstance
end

-- ideas:
-- keep track of number of neutral items gained per tier on either team
-- 

-- Neutral items come in 5 tiers. Items from each tier start dropping based on the time on the game clock.
-- Drop chance is calculated by pseudo-random distribution, and rolled individually for each team and each tier. Higher tiered items are rolled first.
-- Drop chance is only rolled when there is a hero within 750 radius of the killed creep.
-- A neutral creep loses its ability to drop an item when it gets taken over by a player. It must belong to the neutral team to drop items.
-- Neutral items do not drop if there is an enemy of the killing player within 600 radius of the killed neutral unit.
-- Only counts the five picked heroes of the enemy team. Any other enemy unit (including clones and illusions) is ignored.
-- The same item may only drop once for each team.
-- A maximum of four items per tier can drop for each team.

function NeutralItemsTracker:ProcessAdditionalNeutralsForTeam(teamId, currentTime)
    local teamState = self.statePerTeam[teamId]

    if currentTime < teamState.nextNeutralTime then
        self:DebugPrint('Not yet time for neutrals for team '..teamId..' next one is at '..teamState.nextNeutralTime)
        return
    end

    -- We know we need to add some neutrals, so figure out what tier we're supposed
    -- to be on by iterating from tier 5 to 1, find the highest tier which the
    -- current game time exceeds
    local currentTier = 0
    for i = 5, 1, -1 do
        if currentTime >= self.settings.tierTimings[i] then
            currentTier = i
        end
    end

    if currentTier == 0 then
        -- We're not at any eligible tier time yet
        return
    end

    -- loop through all tiers current and below to see find the first tier where
    -- we have not yet granted the maximum.
    local tierToAdd = 0
    for i = currentTier, 1, -1 do
        local neutralsGrantedForTier = teamState.neutralsGrantedPerTier[currentTier]
        if neutralsGrantedForTier < self.settings.maxNeutralItemsPerTier then
            tierToAdd = i
            break
        end
    end

    -- No more neutrals can be added at this time
    if tierToAdd == 0 then return end

    -- we're eligible for more neutrals for this tier, so let's increment our
    -- fake stash. We don't choose the actual item here because choosing the right
    -- hero for an item is much harder than choosing the right item for a hero
    local previousCount = teamState.fakeStashPerTier[tierToAdd]
    teamState.fakeStashPerTier[tierToAdd] = previousCount + 1

    -- Once we add it to the fake stash, we consider it available generally so
    -- we should increment our "granted" count to prevent somehow exceeding our 
    -- limit just because we added something to the stash but it hasn't been 
    -- given to any unit yet.
    local prev = teamState.neutralsGrantedPerTier[tierToAdd]
    teamState.neutralsGrantedPerTier[tierToAdd] = prev + 1

    self:DebugPrint('Adding tier '..tierToAdd..' neutral to team '..teamId)

    -- Now we need to randomly select the next timing to check for neutrals to
    -- add to our fake stash
    local nextTiming = math.random(
        self.settings.neutralItemMinInterval,
        self.settings.neutralItemMaxInterval)

    teamState.nextNeutralTime = currentTime + nextTiming
    self:DebugPrint('Next neutral is available at '..teamState.nextNeutralTime)
end

-- returns table candidates and candidate count
-- candidate = { teamNeutralsIndex = X, itemdef = neutral }
function NeutralItemsTracker:GetNeutralItemCandidates(teamId, tier, position, isMelee)
    -- we search through all items available at the given tier for the unit's
    -- given team
    local teamState = self.statePerTeam[teamId]
    local allAvailableNeutrals = teamState.availableNeutrals

    local neutralCandidates = {}
    local candidateCount = 0
    for i, neutral in pairs(allAvailableNeutrals) do
        if (neutral.tier == tier) -- ensure item is of the right tier
            and ((neutral.ranged and not isMelee) or (neutral.mele and isMelee))
            and (neutral.roles[position] ~= 0) -- item is right for the position
        then
            local candidate =
            {
                teamNeutralsIndex = i, -- keep track of it in the original table
                itemDef = neutral
            }
            table.insert(neutralCandidates, candidate)
            candidateCount = candidateCount + 1
        end
    end

    return neutralCandidates, candidateCount
end

function NeutralItemsTracker:IsHeroEligibleForNeutral(hero, tier)
    -- a hero is eligible for a neutral if he has no neutral items or has a
    -- neutral item of equal or higher tier already
    local currentItem = hero:GetItemInSlot(16)

    if currentItem ~= nil then
        local itemName = currentItem:GetAbilityName()
        local neutralDef = self.settings.neutralsByName[itemName]
        if neutralDef ~= nil then
            return neutralDef.tier < tier -- we're eligible if we're at a lower tier
        else
            self:DebugPrint('Unrecognized item '..itemName..' in neutral definitions'
                            ..' treating hero as ineligible for neutral')
            return false
        end
    else
        -- bot has no item in neutral slot
        return true
    end
end

-- returns true or false for whether the item was added
---
-- updates internal state tracking for the corresponding team
-- which makes the item no longer available for the hero's team
-- as well as increments the number of neutrals granted for the team
-- for the item's given tier
function NeutralItemsTracker:TryAddNeutralItemToHero(hero, itemName)
    local teamId = hero:GetTeam()
    local teamState = self.statePerTeam[teamId]

    local currentItem = hero:GetItemInSlot(16)
    -- remove if so
    if currentItem ~= nil then
        hero:RemoveItem(currentItem)
    end

    if hero:HasRoomForItem(itemName, true, true) then
        self:DebugPrint('trying to grant item '..itemName..' to hero')
        local item = CreateItem(itemName, hero, hero)
        item:SetPurchaseTime(0)
        hero:AddItem(item)

        -- After we grant the item, we want to increment the tracking for the team
        local teamNeutrals = teamState.availableNeutrals
        local found = false
        for i, neutral in pairs(teamNeutrals) do
            if neutral.name == itemName then
                table.remove(teamNeutrals, i)
                local oldCount = teamState.neutralsGrantedPerTier[neutral.tier]
                teamState.neutralsGrantedPerTier[neutral.tier] = oldCount + 1
                found = true
                break
            end
        end

        if not found then
            self:DebugPrint("Hero was granted "..itemName.." but it couldn't be"
             .." found in our tracking tables and therfore was not tracked")
        end

        self:DebugPrint('Granting '..itemName..' to hero on '..teamId)

        return true
    else
        return false
    end
end

function NeutralItemsTracker:OnTimer(currentTime, bots)
    --
    local teamsToProcess = { RADIANT, DIRE }
    for _, teamId in pairs(teamsToProcess) do
        -- Check what tier the team is on based on time
        self:ProcessAdditionalNeutralsForTeam(teamId, currentTime)

        local teamState = self.statePerTeam[teamId]

        if isDebug then
            DeepPrintTable(teamState.fakeStashPerTier)
        end

        -- TODO: REVERSE THIS, NEED TO GRANT FROM HIGEST TIER TO LOWESTuit
        for tier, neutralCount in pairs(teamState.fakeStashPerTier) do
            self:DebugPrint('looping through tier '..tier)
            for i = 1, neutralCount, 1 do
                self:DebugPrint('processing neutral '..i..' out of '..neutralCount)
                -- this one just goes through all the bots on the team, so we
                -- could end up upgrading a bot who has higher tier items already
                -- TODO: Improve this so bots with shittier items get priority
                for _, bot in pairs(bots) do
                    -- TODO: hard dep on fret's data structure
                    local botTeam = bot.stats.team
                    local position = bot.stats.role
                    local isMelee = bot.stats.isMelee
                    if botTeam == teamId and self:IsHeroEligibleForNeutral(bot, tier) then
                        self:DebugPrint('doing bot '..bot.stats.name)
                        local itemCandidates, candidatesCount =
                            self:GetNeutralItemCandidates(teamId, tier, position, isMelee)

                        if candidatesCount > 0 then
                            local candidateChosen = itemCandidates[math.random(candidatesCount)]
                            local itemChosen = candidateChosen.itemDef
                            local added = self:TryAddNeutralItemToHero(bot, itemChosen.name)
                            if added then
                                teamState.fakeStashPerTier[tier] = teamState.fakeStashPerTier[tier] - 1
                                neutralCount = neutralCount - 1
                            end
                        end
                    end
                end
            end
        end
    end
end

function NeutralItemsTracker:RegisterItemDropListener()
    print('Registering item spawned listener')
    ListenToGameEvent('dota_item_spawned', Dynamic_Wrap(NeutralItemsTracker, 'OnItemSpawned'), self)
    
end

function NeutralItemsTracker:OnItemSpawned(event)
    print('Item Spawned Event!!')

    DeepPrintTable(event)

    local item = EntIndexToHScript(event.item_ent_index)
    print('item: '..item:GetAbilityName())

    local player = PlayerResource:GetPlayer(event.player_id)
    local playerName = PlayerResource:GetPlayerName(event.player_id)
    local heroName = PlayerResource:GetSelectedHeroName(event.player_id)

    if player ~= nil then
        print('obtained by '..playerName..' on '..heroName)
    end
end

function NeutralItemsTracker:DebugPrint(msg)
    if isDebug then
        print(msg)
    end
end

-- local allNeutralItems = require 'SettingsNeutralItemTable'
-- local tracker = NeutralItemsTracker:new(allNeutralItems, { 420, 720, 920, 1024, 2046 })
-- tracker:RegisterItemDropListener()