
require 'Debug'
require 'Utilities'

-------------------------------- DEV NOTES -------------------------------------
-- TODO:
-- * Make it so the class keeps track of one team only, then someone can 
--   instantiate two of these, and one will track each team. Less if statements
--
-- * Make it so the ctor takes in all the bots for the team(s), and it will just
--   keep a reference to all the bots and their known states.
--   This is could be bad coupling...
--
-- * Optimize next interval so that if it's impossible to grant any more items
--   then we return nil on OnTimer so the timer can be unregistered
--
-- DONE:
-- * Invert the grant list so highest tier items are doled out first

--------------------------------------------------------------------------------

-- Neutral items come in 5 tiers. Items from each tier start dropping based on the time on the game clock.
-- Drop chance is calculated by pseudo-random distribution, and rolled individually for each team and each tier. Higher tiered items are rolled first.
-- Drop chance is only rolled when there is a hero within 750 radius of the killed creep.
-- A neutral creep loses its ability to drop an item when it gets taken over by a player. It must belong to the neutral team to drop items.
-- Neutral items do not drop if there is an enemy of the killing player within 600 radius of the killed neutral unit.
-- Only counts the five picked heroes of the enemy team. Any other enemy unit (including clones and illusions) is ignored.
-- The same item may only drop once for each team.
-- A maximum of four items per tier can drop for each team.

-- example Neutrals
-- {name = 'item_arcane_ring',  tier = 1, ranged = true, melee = true, roles={1,1,1,1,1}, realName = 'Arcane Ring'},
-- {name = 'item_broom_handle', tier = 1, ranged = false, melee = true, roles={1,1,1,0,0}, realName = 'Broom Handle'}

local RADIANT = 2
local DIRE = 3

-- local debug flag
local thisDebug = true;
local isDebug = Debug.IsDebug() and thisDebug;

NeutralItemsTracker = {
    settings =
    {
        allNeutralItems = {},
        neutralsByName = {},
        tierTimings = {},
        maxNeutralItemsPerTier = 4, -- per tier per team
        neutralItemMinInterval = 10,
        neutralItemMaxInterval = 60,
        maxTier = 5,
        minTier = 1
    }
}

local __meta = {__index = NeutralItemsTracker}

-- Ctor
-- Creates a new instance of the neutral items tracker, which tracks neutrals
-- for both teams
-- You must supply all the neutral items as definition
-- minInterval - minimum wait time between neutral item grants / availability checks
-- maxInterval - max wait time between neutral item availability checks
--   please note: these intervals are computed differently for each team
-- tierTimings - a 5 element array representing at what second game time each tier
--
function NeutralItemsTracker:new(allNeutralItems, minInterval, maxInterval, tierTimings)

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
            maxNeutralItemsPerTier = 4, -- per tier per team
            neutralItemMinInterval = minInterval,
            neutralItemMaxInterval = maxInterval,
            maxTier = 5,
            minTier = 1
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

-- Tries to see if the given team is ready to gain any more neutral items in
-- the hidden neutral stash given the current game time
function NeutralItemsTracker:ProcessAdditionalNeutralsForTeam(teamId, currentTime)
    local maxPossibleTier = self.settings.maxTier
    local minPossibleTier = self.settings.minTier

    local teamState = self.statePerTeam[teamId]

    if currentTime < teamState.nextNeutralTime then
        self:DebugPrint('Not yet time for neutrals for team '..teamId..' next one is at '..teamState.nextNeutralTime)
        return
    end

    -- We know we need to add some neutrals, so figure out what tier we're supposed
    -- to be on by iterating from tier 5 to 1, find the highest tier which the
    -- current game time exceeds
    local currentMaxTier = 0
    for i = maxPossibleTier, minPossibleTier, -1 do
        if currentTime >= self.settings.tierTimings[i] then
            currentMaxTier = i
            break
        end
    end

    self:DebugPrint('Current max tier for team '..teamId..' is '..currentMaxTier)

    if currentMaxTier == 0 then
        -- We're not at any eligible tier time yet
        return
    end

    -- loop through all tiers current and below to see find the first tier where
    -- we have not yet granted up to the maximum.
    local tierToAdd = 0
    for i = currentMaxTier, minPossibleTier, -1 do
        local neutralsGrantedForTier = teamState.neutralsGrantedPerTier[i]
        self:DebugPrint('Neutrals granted for tier '..i..' is '..neutralsGrantedForTier..' out of '..self.settings.maxNeutralItemsPerTier)
        if neutralsGrantedForTier < self.settings.maxNeutralItemsPerTier then
            tierToAdd = i
            break
        end
    end

    -- Now we need to randomly select the next timing to check for neutrals to
    -- add to our fake stash
    local nextTiming = math.random(
        self.settings.neutralItemMinInterval,
        self.settings.neutralItemMaxInterval)

    teamState.nextNeutralTime = currentTime + nextTiming
    self:DebugPrint('Next neutral scan is available at '..teamState.nextNeutralTime)

    -- No more neutrals can be added at this time for this tier
    if tierToAdd == 0 then return end

    self:DebugPrint('Adding tier '..tierToAdd..' neutral to team '..teamId)

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
            and ((neutral.ranged and not isMelee) or (neutral.melee and isMelee))
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

-- Get the neutral item definition for the hero's currently equipped neutral 
-- item if any, otherwise return nil
function NeutralItemsTracker:GetHeroCurrentNeutralDef(hero)
    local currentItem = hero:GetItemInSlot(16)

    if currentItem ~= nil then
        local itemName = currentItem:GetAbilityName()
        local neutralDef = self.settings.neutralsByName[itemName]
        if neutralDef ~= nil then
            return neutralDef
        else
            self:DebugPrint('Unrecognized item '..itemName..' in neutral definitions'
                            ..' treating hero as having no neutral')
            return nil
        end
    else
        -- bot has no item in neutral slot
        return nil
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

-- Marks a neutral item as having been force granted (outside of the tracker)
-- This is useful if you're an external system wanting to force grant neutral on
-- a hero, but you also want to make sure the tracker knows about it so that
-- 1. it doesn't grant the same item to any other bot on the same team
-- 2. it counts towards the total number of items for that tier
function NeutralItemsTracker:MarkNeutralForceGranted(itemName, teamId)
    local teamState = self.statePerTeam[teamId]

    if teamState == nil then return false end

    local removed = false
    -- find the neutral in the team's available neutrals, if it is available
    for index, neutralDef in pairs(teamState.availableNeutrals) do
        if neutralDef.name == itemName then
            table.remove(teamState.availableNeutrals, index)
            removed = true
            break
        end
    end

    if not removed then
        self:DebugPrint('Tried to remove '..itemName..' from team '..teamId..
            "'s neutrals, but it wasn't found")
    end

    -- increment the granted items for the tier
    local neutralDef = self.settings.neutralsByName[itemName]
    if neutralDef == nil then
        self:DebugPrint("Couldnt' find item "..itemName.." in all neutral defs")
        return false
    end

    local oldCount = teamState.fakeStashPerTier[neutralDef.tier]
    teamState.fakeStashPerTier[neutralDef.tier] = oldCount + 1

    return true
end

-- Invoke this at regular intervals, and pass it the list of bots that need to be
-- processed as well as the current game time.
--
-- returns the number of seconds the next invocation should be OR nil if the timer
-- no longer needs to be invoked
function NeutralItemsTracker:OnTimer(currentTime, bots)
    local teamsToProcess = { RADIANT, DIRE }
    for _, teamId in pairs(teamsToProcess) do

        -- Check what tier the team is on based on time
        self:ProcessAdditionalNeutralsForTeam(teamId, currentTime)

        local teamState = self.statePerTeam[teamId]

        if isDebug then
            print('Stash for team '..teamId..' after additions:')
            DeepPrintTable(teamState.fakeStashPerTier)
        end

        -- Loop through all the tiers from highest to lowest
        for tier = self.settings.maxTier, self.settings.minTier, -1 do
            local neutralsRemaining = teamState.fakeStashPerTier[tier]

            -- Loop through all the bots that match our current team and is
            -- eligible for the neutral of our current tier. this is a bit
            -- inefficient but we can optimize later
            for _, bot in pairs(bots) do
                if neutralsRemaining == 0 then break end

                -- There's a hard dependency here on fret's bot data structure
                local botTeam = bot.stats.team
                local position = bot.stats.role
                local isMelee = bot.stats.isMelee
                local botName = bot.stats.name

                if botTeam == teamId then
                    --self:DebugPrint('Checking tier '..tier..' neutral eligibility for '..botName..' on team '..teamId..' with '..neutralsRemaining..' left')

                    local heroCurrentNeutral = self:GetHeroCurrentNeutralDef(bot)
                    local heroCurrentTier = 0
                    if heroCurrentNeutral ~= nil then heroCurrentTier = heroCurrentNeutral.tier end
                    if heroCurrentTier < tier then
                        self:DebugPrint('bot '..botName..' is eligible for tier '..tier..' neutrals')

                        local itemCandidates, candidatesCount =
                            self:GetNeutralItemCandidates(teamId, tier, position, isMelee)

                        if candidatesCount > 0 then
                            local candidateChosen = itemCandidates[math.random(candidatesCount)]
                            local itemChosen = candidateChosen.itemDef
                            local added = self:TryAddNeutralItemToHero(bot, itemChosen.name)
                            if added then
                                local heroPreviousNeutral = heroCurrentNeutral
                                -- remove the stash count
                                teamState.fakeStashPerTier[tier] = teamState.fakeStashPerTier[tier] - 1
                                -- decrement  number of neutrals we need to process for the current tier
                                neutralsRemaining = neutralsRemaining - 1

                                -- since we replaced an item, let's increment the count in the original tier
                                -- so later on in processing, other bots can benefit from trickle down upgrade
                                --
                                -- this logic works because we process tiers from highest to lowest, and the
                                -- previous tier MUST be lower than the current tier we're processing, so we
                                -- are guaranteed to process this additional neutral in the following passes
                                if heroPreviousNeutral ~= nil then
                                    teamState.fakeStashPerTier[heroPreviousNeutral.tier] =
                                        teamState.fakeStashPerTier[heroPreviousNeutral.tier] + 1

                                    local previousNeutral = self.settings.neutralsByName[heroPreviousNeutral.name]
                                    table.insert(teamState.availableNeutrals, previousNeutral)
                                    self:DebugPrint('re-adding '..previousNeutral.name..' back to available neutrals')
                                end
                                break
                            end
                        end
                    end
                end
            end
            self:DebugPrint('Finished processing tier '..tier..' for team '..teamId..' with '..neutralsRemaining..' neutrals left.')
        end

        if isDebug then
            print('Stash for team '..teamId..' after granting to bots:')
            DeepPrintTable(teamState.fakeStashPerTier)
        end
    end

    -- after processing the teams, let's figure out how long before we should
    -- fire up this timer again. Keep in mind this would be the recommended
    -- value
    local radiantNextNeutralTime = self.statePerTeam[RADIANT].nextNeutralTime
    local direNextNeutralTime = self.statePerTeam[DIRE].nextNeutralTime

    local nextTime = math.min(radiantNextNeutralTime, direNextNeutralTime)

    -- Have a little grace period of 1 seconds so we fire AFTER the timer's past
    local interval = math.max(nextTime - currentTime + 1, 0)
    self:DebugPrint('Next recommended call is after '..interval..' seconds')

    return interval
end

function NeutralItemsTracker:RegisterItemDropListener()
    print('Registering item spawned listener')
    ListenToGameEvent('dota_item_spawned', Dynamic_Wrap(NeutralItemsTracker, 'OnItemSpawned'), self)
    
end

-- WIP: Ignore, this is non-functional
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