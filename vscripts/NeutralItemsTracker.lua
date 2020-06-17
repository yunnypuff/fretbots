-- Dependencies
require 'Debug'
require 'Utilities'
--require 'Settings'

local RADIANT = 2 -- TODO: REMOVE THESE
local DIRE = 3

-- local debug flag
local thisDebug = true;
local isDebug = Debug.IsDebug() and thisDebug;

local NeutralItemsTracker = {
    allNeutralItems = {},
    tierTimings = {},
    maxNeutralItemsPerTier = 5, -- per tier per team
    availalbleNeutralsByTeam =
    {
        [RADIANT] = {},
        [DIRE] = {}
    },
    neutralsGrantedPerTeamPerTier = {}
}

local __meta = {__index = NeutralItemsTracker}

function NeutralItemsTracker:new(allNeutralItems, tierTimings)
    local newInstance = 
    {
        allNeutralItems = Utilities:ShallowCopy(allNeutralItems),
        tierTimings = tierTimings,
        maxNeutralItemsPerTier = 5, -- per tier per team
        availalbleNeutralsByTeam =
        {
            [RADIANT] = Utilities:ShallowCopy(allNeutralItems),
            [DIRE] = Utilities:ShallowCopy(allNeutralItems)
        },
        neutralsGrantedPerTeamPerTier =
        {
            [RADIANT] = { 0, 0, 0, 0, 0 },
            [DIRE] = { 0, 0, 0, 0, 0 }
        }
    }

    setmetatable(newInstance, __meta)
    return newInstance
end

function DebugThis()
	Units = FindUnitsInRadius(2,
	                              Vector(0, 0, 0),
	                              nil,
	                              FIND_UNITS_EVERYWHERE,
	                              3,
	                              DOTA_UNIT_TARGET_HERO,
	                              88,
	                              FIND_ANY_ORDER,
	                              false);
	for i,unit in pairs(Units) do
		Debug:Print(unit:GetName())
        local id = PlayerResource:GetSteamID(unit:GetMainControllingPlayer());
        Debug:Print('unit effects:')
        local hasRoyalJelly = false
        local royalJelly = unit:FindModifierByName("modifier_royal_jelly")
        if royalJelly ~= nil then
            print('has royal jelly...')
            royalJelly:StartIntervalThink(1)
            hasRoyalJelly = true
        end
        -- for key, value in pairs(allModifiers) do
        --     print('modifier: '..key)
        --     DeepPrintTable(value)
        -- end

        if hasRoyalJelly then
            Debug:Print('removing modifier...')
            unit:RemoveModifierByName("modifier_royal_jelly")
        else
            local currentItem = unit:GetItemInSlot(16)
            if currentItem ~= nil then
                DeepPrintTable(currentItem)
                Debug:Print(currentItem:GetAbilityName())

                --Debug:Print('try adding modifier...')
                --local mod = unit:AddNewModifier(unit, currentItem, "modifier_royal_jelly", {})
                --currentItem:SpendCharge()

                unit:CastAbilityOnTarget(unit, currentItem, unit:GetPlayerOwnerID())
            end
        end
    end
end

local IsEntityHurtRegistered = false

-- Instantiate ourself
if EntityHurt == nil then
  EntityHurt = {}
end

-- Event Listener
function EntityHurt:OnEntityHurt(event)
  -- Get Event Data
	isHero = EntityHurt:GetIsHero(event);
	-- Drop out for non hero damage
	if not isHero then return end;
	-- Get other event data
    
    EntityHurt:GetEntityHurtEventData(event);
end

-- returns true if the victim was a hero
function EntityHurt:GetIsHero(event)
	-- IsHero
	local isHero = false;
	local victim = EntIndexToHScript(event.entindex_killed);
	if victim:IsHero() and victim:IsRealHero() and not victim:IsIllusion() and not victim:IsClone() then
		isHero = true;
	end
  return isHero;
end

-- returns other useful data from the event
function EntityHurt:GetEntityHurtEventData(event)
  print('!!!!!!!! SOMEONE GOT HURT !!!!!!!!!!!!!!!!')
  local attacker = nil;
  local victim = nil;	
  if event.entindex_attacker ~= nil and event.entindex_killed ~= nil then
	  attacker = EntIndexToHScript(event.entindex_attacker)
	  victim = EntIndexToHScript(event.entindex_killed)
	end
	-- Lifted from Anarchy. Props!
	-- Damage Type
	local damageType = nil;
	if event.entindex_inflictor~=nil then
        inflictor_table=EntIndexToHScript(event.entindex_inflictor):GetAbilityKeyValues()
        print('---damage inflictor ability---')
        DeepPrintTable(inflictor_table)
		if inflictor_table['AbilityUnitDamageType'] == nil then -- assume item damage is magical
			damageType='DAMAGE_TYPE_MAGICAL'
		else
			damageType=tostring(inflictor_table['AbilityUnitDamageType'])
		end
	else
		damageType=tostring('DAMAGE_TYPE_PHYSICAL')
	end
  -- get damage value
    local damage=event.damage
    print(attacker:GetUnitName()..' hit '..victim:GetUnitName()..' for '..damage..' with '..damageType)
    if attacker == victim then
        print('attacker IS VICTIM')
    end
end

-- Registers Event Listener    
function EntityHurt:RegisterEvents()
	if not IsEntityHurtRegistered then
	  ListenToGameEvent("entity_hurt", Dynamic_Wrap(EntityHurt, 'OnEntityHurt'), EntityHurt)
    print("EntityHurt Event Listener Registered.")
  end
end

-- Register
EntityHurt:RegisterEvents()