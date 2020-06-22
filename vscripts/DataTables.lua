-- Creates stats tables for units
-- containts helper functions for manipulating data

-- Global Debug flag
require 'Debug';
 -- Other Flags
require 'Flags'
-- Makes a unit strong
require 'BuffUnit'
-- Settings
require 'Settings'
-- Convenience Utilities
require 'Utilities'

local role = require('RoleUtility')


-- local debug flags
local thisDebug = true
local isDebug = Debug.IsDebug() and thisDebug
local isChatDebug = Debug.IsDebug() and false
local isVerboseDebug = Debug.IsDebug() and true
-- Set to true to initialize data tables on loading this file every time
local isSoloDebug = false
-- Set to true to buff Fret if he's in the game
local isBuff = false
-- Warn Fret if he left this on
if isBuff then
  Utilities:Print('Hey Fret, isBuff is True!', MSG_BAD, DISASTAH)
end

-- Globals 
Bots = {}
Players = {}
PlayerBots = {}
AllUnits = {}

BotTeam = 0
HumanTeam = 0

-- convenient constants for dumb valve integers
RADIANT = 2
DIRE = 3

-- Instantiate the class
if DataTables == nil then
	DataTables = class({})
end

-- Sets up data tables, buffs Fret for debug
function DataTables:Initialize()
	Debug:Print('Initializing DataTables')
	-- Don't do this more than once.
	--if Flags.isStatsInitialized then return end;
	-- Lifted From Anarchy - Props
	Units = FindUnitsInRadius(2,
	                              Vector(0, 0, 0),
	                              nil,
	                              FIND_UNITS_EVERYWHERE,
	                              3,
	                              DOTA_UNIT_TARGET_HERO,
	                              88,
	                              FIND_ANY_ORDER,
	                              false);
 	Bots={};
	Players={};
	AllUnits = {};
	for i,unit in pairs(Units) do
		  Debug:Print(unit:GetName())
  		local id = PlayerResource:GetSteamID(unit:GetMainControllingPlayer());
  		local isFret = Debug:IsFret(id);
  		-- Buff Fret for Debug purposes
  		if isFret and not Flags.isDebugBuffed and isBuff then
        BuffUnit:Hero(unit)		   	      	
        Flags.isDebugBuffed = true
		  end  			
		  -- Initialize data tables for this unit
		  DataTables:GenerateStatsTables(unit);
    end
    
    -- Purge human side bots if we don't want to enable
    -- any bonus for playerbots
    if Settings.playerBots == nil or Settings.playerBots.enabled == false then
        -- Purge human side bots 
        DataTables:PurgeHumanSideBots()
    end

	-- Assign a support Pos 5
	DataTables:ResolveBotsPositionFive()
    -- Set Initialized Flag
    Flags.isStatsInitialized = true;
	
	-- debug prints
	if isDebug then
		if Players ~= nil then
			for i,unit in pairs(Players) do
				print('Stats table for Player '.. i)
				DeepPrintTable(unit.stats)
			end
		end
		if Bots ~= nil then
			for i,unit in pairs(Bots) do
				print('Stats table for Bot '.. i)
				DeepPrintTable(unit.stats)
			end
		end		
	end
	
end

-- Generates various data used to track bot stats
function DataTables:GenerateStatsTables(unit)
	-- Is this a bot?
  local thisIsBot = false
  local thisRole = 0
  local thisTeam = 0
	local thisId = 0
	local steamId = PlayerResource:GetSteamID(unit:GetMainControllingPlayer())
	-- Drop out for non-real hero units
	if not DataTables:IsRealHero(unit) then return end
	-- Is bot?
  if PlayerResource:GetSteamID(unit:GetMainControllingPlayer())==PlayerResource:GetSteamID(100) then
  	thisIsBot = true
    table.insert(Bots, unit)
  else
    table.insert(Players, unit)
  end
  table.insert(AllUnits,unit)	
-- PlayerID, Team, Role
  if unit:GetPlayerID() ~= nil then
	  thisId = unit:GetPlayerID()
	  thisTeam=PlayerResource:GetTeam(thisId)
	  thisRole = 0;
	end
	-- name for debug purposes
 	local thisName = unit:GetName()
  thisRole = DataTables:GetRole(thisName)
 	
	-- create a stats table for the bot
	local stats = 
  {
  	-- Number of kills
  	kills 		=			0,
  	-- Number of deaths: There is listener for this, we should register and track there	
  	deaths 		= 		0,
  	-- If KillStreak gets large, negatively affect multiplier
  	killStreak = 0,
  	-- If DeathStreak grows, enhance multiplier
  	deathStreak = 0,
  	-- teamNetWorth could be useful for a multiplier for bonuses	  	
  	teamNetWorth = 0,
  	-- enemyTeamNetWorth could be useful for a multiplier for bonuses	  	
  	enemyTeamNetWorth = 0,
  	-- netowrth
  	netWorth = 0,
  	-- Bot Team Kills
  	botTeamKills = 0,
  	-- Current human team kill advantage
  	humanKillAdvantage = 0,
  	-- Human Team kills
  	humanTeamKills = 0,
  	-- Is this a bot?
  	isBot = thisIsBot,
  	-- Team
  	team = thisTeam,
  	-- Role
  	role = thisRole,
  	-- Damage Table (by type)
  	damageTable = {DAMAGE_TYPE_PHYSICAL=0, DAMAGE_TYPE_MAGICAL=0, DAMAGE_TYPE_PURE=0},
  	-- Unit name
  	internalName = thisName,
  	-- Better unit name (actual hero name)
  	name = Utilities:GetName(thisName),
  	-- Skill
  	skill = DataTables:GetSkill(thisName, thisRole, thisIsBot),
  	-- Current death bonus chances
  	chance = 
  	{
  	  gold 				= 0,
  	  armor 			= 0,
  	  magicResist = 0,
  	  levels 			= 0,
  	  neutral 		= 0,
  	  stats 			= 0	
  	},
  	-- Death bonus awards
  	awards = 
    {
 			gold 					= 0,
			armor 				= 0,
			magicResist 	= 0,
			levels 				= 0,
			neutral	      = 0,
			stats 				= 0   	
    },	
  	-- current level of neutral item
  	neutralTier = 0,
  	-- Timing for next level of neutral item
  	neutralTiming = Settings.neutralItems.timings[1] + Utilities:GetIntegerVariance(Settings.neutralItems.variance),
  	-- Hero isMelee
  	isMelee = role.IsMelee(unit:GetBaseAttackRange()),
  	-- player ID
  	id = thisId
  }
  -- Reduce human skill
  if not thisIsBot then stats.skill = stats.skill * 0.5 end
  -- Insert the stats object to the bot
  unit.stats = stats;
  -- update non-accruing deathBonus chances since they will never change
  for _, award in pairs(Settings.deathBonus.order) do
		if not Settings.deathBonus.accrue[award] then
			unit.stats.chance[award] = Settings.deathBonus.chance[award]
		end
	end	  
  if (isDebug) then
  	print('Data tables initialized for ' ..thisName .. '. Unit ID: ' .. tostring(stats.id))
  end
  -- Warn humans about bot skill if enabled and skill is high
  if Settings.skill.isWarn and stats.skill > Settings.skill.warningThreshold and thisIsBot then
 		Utilities:Print(stats.name.. ' is very talented!',  Utilities:GetPlayerColor(stats.id), ATTENTION)
 	end
end 

-- Called by OnEntityKilled to update stats of the victim
function DataTables:DoDeathUpdate(victim, killer)
	-- Always update team kills
	victim.stats.botTeamKills = PlayerResource:GetTeamKills(BotTeam)
	victim.stats.humanTeamKills = PlayerResource:GetTeamKills(HumanTeam)
	victim.stats.humanKillAdvantage = victim.stats.humanTeamKills - victim.stats.botTeamKills
	-- ignore kills by non-heroes (they won't have stats tables)
	if killer.stats == nil then return end
	-- don't track players		
  if not victim.stats.isBot then return end
  -- Most of these numbers are predicated on being killed by the enemy team (ignore denies)
  if victim.stats.team == killer.stats.team then return end
	-- get current kills/deaths (as opposed to stats table)
	local kills = PlayerResource:GetKills(victim.stats.id)
	-- Determine the killstreak at the time of death
	local killStreak = kills - victim.stats.kills 
 -- if killstreak at death is zero, increment death streak
	victim.stats.deathStreak = victim.stats.deathStreak + 1
	-- Kill streak is obviously zero now
  victim.stats.killStreak = 0
	-- Update deaths
	victim.stats.deaths = PlayerResource:GetDeaths(victim.stats.id)
	-- Update kills
	victim.stats.kills = kills
	-- Update Team Worths
	victim.stats.teamNetWorth = DataTables:GetTeamNetWorth(victim.stats.team)
	victim.stats.enemyTeamNetWorth = DataTables:GetTeamNetWorth(killer.stats.team)
	if isDebug then
		print('Updated stats table for ' .. victim.stats.name)
		if isVerboseDebug then DeepPrintTable(victim.stats) end
	end
end

-- Get team net worth 
function DataTables:GetTeamNetWorth(team)
	local net = 0;
	for _,unit in pairs(AllUnits) do
		if unit.stats.team == team then
			net = net + PlayerResource:GetNetWorth(unit.stats.id)
		end
	end
	return net
end
	
-- Returns the net worth of the comparable position on the human side	
-- or zero if there is no mathing human
function DataTables:GetRoleNetWorth(bot)
	local worths = {}
	for _,unit in pairs(AllUnits) do
		if unit.stats.team ~= bot.stats.team then
			table.insert(worths,PlayerResource:GetNetWorth(unit.stats.id))
		end
	end
	Utilities:SortHighToLow(worths)
	if worths[bot.stats.role] ~= nil then
	  return worths[bot.stats.role]
	else
		return 0
	end
end

-- Returns the GPM table of a team ranked from highest to lowest
-- Each entry in the table is { gpm, unit.stats }
function DataTables:GetRankedGPMTable(team)
	local data = {}
	-- Go through all the players and add them to our ranking table
	for _, unit in pairs(Players) do
		if unit.stats.team == team then
			local gpm = PlayerResource:GetGoldPerMin(unit.stats.id)
			table.insert(data, { gpm, unit.stats })
		end
	end

	for _, unit in pairs(Bots) do
		if unit.stats.team == team then
			local gpm = PlayerResource:GetGoldPerMin(unit.stats.id)
			table.insert(data, { gpm, unit.stats })
		end
	end

	-- Sort highest to lowest, since the gpm element is the first
	-- in the tuple, we use index 1
	local gpmPosition = 1
	table.sort(data, function (a, b) return a[gpmPosition] > b[gpmPosition] end)

	return data
end

-- Gets the best-match GPM for an intended position. Will return gpm for other positions
-- if no matching gpm is available for the intended position.
--
-- Returns { gpm, ranking, matchingUnit.stats }
function DataTables:GetBestMatchGPMForPosition(targetPosition, allowBots, gpmTable)
	-- the gpm table is populated from highest to lowest.
	-- it's possible we don't have gpm for our given position
	-- due to lack of qualified opponents, so we search from our intended
	-- position to the highest position (1), of which there should be at least 1.
	local match = nil
	local foundPosition = 0
	for i = targetPosition, 1, -1 do
		local currentEntry = gpmTable[i]
		if currentEntry ~= nil then
			-- we found a GPM entry
			if not currentEntry[2].isBot then
				-- if it's not a bot, it's a human and let's do it
				match = currentEntry
				foundPosition = i
				break
			elseif allowBots then
				-- it's a bot, but we'll allow it, so return it
				match = currentEntry
				foundPosition = i
				break
			-- otherwise keep trucking
			end
		end
	end

	if match == nil then
		local result =
		{
			gpm = 0,
			stats = nil,
			position = 0
		}
		return result
	else
		local result =
		{
			gpm = match[1],
			stats = match[2],
			position = foundPosition
		}
		return result
	end
end

-- Returns the GPM the comparable position on the human / opposing side
-- or zero if there is no mathing human
-- Returns GPM, playerName
function DataTables:GetRoleGPM(bot)
	-- TODO: Can probably just compute the GPM/role tables every minute and cache it
	-- as these values are unlikely going to change between each bot that asks for it
	local botTeam = bot.stats.team
	local data = {}
	local names = {}
	for _, unit in pairs(Players) do
		if unit.stats.team ~= botTeam then
			local gpm = PlayerResource:GetGoldPerMin(unit.stats.id)
			table.insert(data, { unit.stats.name, gpm, unit.stats })
			table.insert(names, unit.stats.name)
		end
	end

	if Settings.playerBots ~= nil and Settings.playerBots.enabled then
		for _, unit in pairs(Bots) do
			if unit.stats.team ~= botTeam then
				local gpm = PlayerResource:GetGoldPerMin(unit.stats.id)
				table.insert(data, { unit.stats.name, gpm, unit.stats })
				table.insert(names, unit.stats.name)
			end
		end
	end

	-- Sort highest to lowest
	table.sort(data, function (a, b) return a[2] > b[2]	end)

	if isVerboseDebug then
		print('GPM Table:')
		for _, tuple in pairs(data) do
			print(tuple[1]..' - gpm: '..tuple[2])
		end
	end

	if data[bot.stats.role] ~= nil then
		local gpm = data[bot.stats.role][2]
		-- 3rd item is whether the target is a bot or not
		-- local targetStats = data[bot.stats.role][3]
		-- if targetStats.isBot then 
		-- 	local adjustedGpm = gpm * bot.stats.skill / targetStats.skill
		-- 	if isVerboseDebug then 
		-- 		print(bot.stats.name..' target gpm adjusted from '..gpm..' to '..adjustedGpm)
		-- 	end
		-- 	gpm = adjustedGpm
		-- end
		return gpm, data[bot.stats.role][1]
	-- specific debug case, pretend we have more players than we do
	elseif isDebug and #Players == 1 then
		return data[1][2] / bot.stats.role, names[1]
	else
		return 0, nil
	end
end

-- Returns the XPM of the comparable position on the human side	
-- or zero if there is no matching human
function DataTables:GetRoleXPM(bot)
	local data = {}
	local names = {}
	for _,unit in pairs(Players) do
		local num = PlayerResource:GetXPPerMin(unit.stats.id)
		table.insert(data,num)
		table.insert(names, unit.stats.name)
	end
	Utilities:SortHighToLow(data)
	if isVerboseDebug then
		print('XPM Table:')
		DeepPrintTable(data)
	end
	-- edge case: bot mid is pos2 but the human mid will probably be 1st in this chart
	-- so swap these
	local role = bot.stats.role
	if role == 2 then 
		role = 1
	elseif role == 1 then
		role = 2
	end
	if data[role] ~= nil then
	  return data[role], names[role]
	-- specific debug case, pretend we have more players than we do
	elseif isDebug and #Players == 1 then
		return data[1] / role, names[1]	  
	else
		return 0	
	end
end

-- Returns GPM and XPM tables for humans
function DataTables:GetPerMinuteTables()
	local gpm = {}
	local xpm = {}
	local names = {}
	for _,unit in pairs(Players) do
		local gp = PlayerResource:GetGoldPerMin(unit.stats.id)
		local xp = PlayerResource:GetXPPerMin(unit.stats.id)
		table.insert(gpm,gp)
		table.insert(xpm,xp)
		table.insert(names, unit.stats.name)
	end
	-- specific debug case, pretend we have more players than we do
	if isDebug and #Players == 1 then
		for i=2,5 do
			table.insert(gpm, gpm[1] / i) 
			table.insert(xpm, xpm[1] / i) 			 
		end
	end
	Utilities:SortHighToLow(gpm)
	Utilities:SortHighToLow(xpm)
	-- Special case: since these tables are consumed by role, swap XP for 1 and 2
	local temp = xpm[1]
	xpm[1] = xpm[2]
	xpm[2] = temp
	Debug:Print(gpm, 'GPM Table')
	Debug:Print(xpm, 'XPM Table')
	return gpm, xpm
end

-- returns a flat multiplier to represent the skill of the bot, combined with their role.
-- This affects all numeric bonuses
function DataTables:GetSkill(name, role, isBot)
	-- valid roles only
	if role < 1 or role > 5 then return 0 end
	-- remember math.Random only returns integers, so multiply / divide by 100
  local skill = math.random(Settings.skill.variance[role][1] * 100, Settings.skill.variance[role][2] * 100) / 100
  return skill
end
	
-- removes bots on the human team from the bots table
-- note that if there are humans on both sides, it will purge the side with more humans
function DataTables:PurgeHumanSideBots()	
  -- determine humans per side
  local radiant = 0
  local dire = 0
  for _,unit in pairs(AllUnits) do
  	if not unit.stats.isBot and unit.stats.team == RADIANT then
  		radiant = radiant + 1
  	elseif not unit.stats.isBot and unit.stats.team == DIRE then
  		dire = dire + 1
  	end
  end
  if isDebug then 
  	print('Radiant Humans: '..radiant..' Dire Humans: '..dire)
  end
  local team
  local countToRemove
  if radiant > dire then 
  	team = RADIANT
  	HumanTeam = RADIANT
  	BotTeam = DIRE
  	countToRemove = 5 - radiant
  else
  	team = DIRE
  	HumanTeam = DIRE
  	BotTeam = RADIANT  	
  	countToRemove = 5 - dire
  end
  if isDebug then 
  	print('Removing '..countToRemove..' bots from the human side.')
  end
  local attempts = 0
  local removed = 0
  while removed < countToRemove and attempts < countToRemove do
  	attempts = attempts + 1
	  for i, unit in pairs(Bots) do
	  	if unit.stats.team == team then
	  		table.remove(Bots,i)
	  		removed = removed + 1
	  		print('Removing '..unit.stats.name..' from the bots list.')
	  		table.insert(PlayerBots, unit)
	  		break
	  	end
	  end 
	end
end
	
-- Both support bots will initially be set to position four.  
-- Make one bot support 5 (at random)
function DataTables:ResolveBotsPositionFive()
  for _, bot in pairs(Bots) do
  	-- The first position four selected is the unlucky one
  	if bot.stats.role == 4 then 
  		bot.stats.role = 5
  		break
  	end
  end
end	
	
function DataTables:GetRole(hero)
	-- Carry?
	if role.CanBeSafeLaneCarry(hero) then
		if isDebug then print(hero..': role: '..1) end
		return 1
	-- MidLane
	elseif role.CanBeMidlaner(hero) then
		if isDebug then print(hero..': role: '..2) end
		return 2
	-- Offlane
	elseif role.CanBeOfflaner(hero) then
		if isDebug then print(hero..': role: '..3) end
		return 3
	-- Support is slightly more tricky
  elseif role.CanBeSupport(hero) then
  	if isDebug then print(hero..': role: '..4) end
    return 4
  else 
  	if isDebug then print(hero..': role: '..5) end
  	return 5
  end 	
end	
	
-- Returns true if the unit is an actual hero and not a hero-like unit
function DataTables:IsRealHero(unit)
	return unit:IsHero() and unit:IsRealHero() and not unit:IsIllusion() and not unit:IsClone()	
end

-- Initialize (if Debug)
if isSoloDebug then 
	DataTables:Initialize()
	DeepPrintTable(Bots)
end
