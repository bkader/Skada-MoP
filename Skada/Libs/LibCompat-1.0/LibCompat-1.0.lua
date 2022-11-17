--
-- **LibCompat-1.0** provides few handy functions that can be embed to addons.
-- This library was originally created for Skada as of 1.8.50.
-- @author: Kader B (https://github.com/bkader/LibCompat-1.0)
--

local MAJOR, MINOR = "LibCompat-1.0-Skada", 37
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.embeds = lib.embeds or {}
lib.EmptyFunc = Multibar_EmptyFunc

local _G, pairs, type, max = _G, pairs, type, math.max
local format, tonumber = format or string.format, tonumber
local _

local Dispatch
local GetUnitIdFromGUID

-------------------------------------------------------------------------------

local Units
do
	-- solo and target targets
	local solo = {"player", "pet"}
	local target = {"target", "targettarget", "focus", "focustarget", "mouseover", "mouseovertarget"}

	-- boss
	local boss = {}
	for i = 1, 5 do
		boss[i] = format("boss%d", i)
		target[#target + 1] = format("boss%d", i)
	end

	-- party
	local party = {}
	local partypet = {}
	for i = 1, 4 do
		party[i] = format("party%d", i)
		partypet[i] = format("partypet%d", i)
		target[#target + 1] = format("party%dtarget", i)
	end

	-- raid
	local raid = {}
	local raidpet = {}
	for i = 1, 40 do
		raid[i] = format("raid%d", i)
		raidpet[i] = format("raidpet%d", i)
		target[#target + 1] = format("raid%dtarget", i)
	end

	-- arena
	local arena = {}
	local arenapet = {}
	for i = 1, 5 do
		arena[i] = format("arena%d", i)
		arenapet[i] = format("arenapet%d", i)
		target[#target + 1] = format("arena%d", i)
	end

	lib.Units = {
		-- solo and targets
		solo = solo,
		target = target,
		-- party units and pets
		party = party,
		partypet = partypet,
		-- raid units and pets
		raid = raid,
		raidpet = raidpet,
		-- arena units and pets
		arena = arena,
		arenapet = arenapet,
		-- boss units
		boss = boss
	}
	Units = lib.Units
end

-------------------------------------------------------------------------------

do
	local wipe, select, tconcat = wipe, select, table.concat
	local temp = {}
	local function _print(...)
		wipe(temp)
		for i = 1, select("#", ...) do
			temp[#temp + 1] = select(i, ...)
		end
		DEFAULT_CHAT_FRAME:AddMessage(tconcat(temp, " "))
	end

	function Dispatch(func, ...)
		if type(func) ~= "function" then
			_print("\124cffff9900Error\124r: Dispatch requires a function.")
			return
		end
		return func(...)
	end


	local pcall = pcall
	local function QuickDispatch(func, ...)
		if type(func) ~= "function" then return end
		local ok, err = pcall(func, ...)
		if not ok then
			_print("\124cffff9900Error\124r:" .. (err or "<no error given>"))
			return
		end
		return true
	end

	lib.Dispatch = Dispatch
	lib.QuickDispatch = QuickDispatch
end

-------------------------------------------------------------------------------

do
	local UnitExists, UnitAffectingCombat, UnitIsDeadOrGhost = _G.UnitExists, _G.UnitAffectingCombat, _G.UnitIsDeadOrGhost
	local UnitHealth, UnitHealthMax, UnitPower, UnitPowerMax = _G.UnitHealth, _G.UnitHealthMax, _G.UnitPower, _G.UnitPowerMax
	local GetNumRaidMembers, GetNumPartyMembers = _G.GetNumRaidMembers, _G.GetNumPartyMembers
	local GetNumGroupMembers, GetNumSubgroupMembers = _G.GetNumGroupMembers, _G.GetNumSubgroupMembers
	local IsInGroup, IsInRaid = _G.IsInGroup, _G.IsInRaid

	local function GetGroupTypeAndCount()
		if IsInRaid() then
			return "raid", 1, GetNumGroupMembers()
		elseif IsInGroup() then
			return "party", 0, GetNumSubgroupMembers()
		else
			return "solo", 0, 0
		end
	end

	local UnitIterator
	do
		local nmem, step, count

		local function SelfIterator(excPets)
			while step do
				local unit, owner
				if step == 1 then
					unit, owner, step = "player", nil, 2
				elseif step == 2 then
					if not excPets then
						unit, owner = "pet", "player"
					end
					step = nil
				end
				if unit and UnitExists(unit) then
					return unit, owner
				end
			end
		end

		local party = Units.party
		local partypet = Units.partypet
		local function PartyIterator(excPets)
			while step do
				local unit, owner
				if step <= 2 then
					unit, owner = SelfIterator(excPets)
					step = step or 3
				elseif step == 3 then
					unit, owner, step = party[count], nil, 4
				elseif step == 4 then
					if not excPets then
						unit, owner = partypet[count], party[count]
					end
					count = count + 1
					step = count <= nmem and 3 or nil
				end
				if unit and UnitExists(unit) then
					return unit, owner
				end
			end
		end

		local raid = Units.raid
		local raidpet = Units.raidpet
		local function RaidIterator(excPets)
			while step do
				local unit, owner
				if step == 1 then
					unit, owner, step = raid[count], nil, 2
				elseif step == 2 then
					if not excPets then
						unit, owner = raidpet[count], raid[count]
					end
					count = count + 1
					step = count <= nmem and 1 or nil
				end
				if unit and UnitExists(unit) then
					return unit, owner
				end
			end
		end

		function UnitIterator(excPets)
			nmem, step = GetNumGroupMembers(), 1
			if nmem == 0 then
				return SelfIterator, excPets
			end
			count = 1
			if IsInRaid() then
				return RaidIterator, excPets
			end
			return PartyIterator, excPets
		end
	end

	local function IsGroupDead()
		for unit in UnitIterator(true) do
			if not UnitIsDeadOrGhost(unit) then
				return false
			end
		end
		return true
	end

	local function IsGroupInCombat()
		for unit in UnitIterator() do
			if UnitAffectingCombat(unit) then
				return true
			end
		end
		return false
	end

	local function GroupIterator(func, ...)
		for unit, owner in UnitIterator() do
			Dispatch(func, unit, owner, ...)
		end
	end

	do
		local function FindUnitId(guid, units)
			if not units then return end
			for _, unit in next, units do
				if UnitExists(unit) and UnitGUID(unit) == guid then
					return unit
				end
			end
		end

		function GetUnitIdFromGUID(guid, grouped)
			-- start with group members
			if grouped then
				local unit = FindUnitId(guid, Units[IsInRaid() and "raid" or IsInGroup() and "party" or "solo"])
				unit = unit or FindUnitId(guid, Units[IsInRaid() and "raidpet" or IsInGroup() and "partypet" or "solo"])
				return unit or FindUnitId(guid, Units.target)
			end

			local unit = not grouped and FindUnitId(guid, Units.target)
			unit = unit or FindUnitId(guid, Units[IsInRaid() and "raid" or IsInGroup() and "party" or "solo"])
			return unit or FindUnitId(guid, Units[IsInRaid() and "raidpet" or IsInGroup() and "partypet" or "solo"])
		end
	end

	local function GetClassFromGUID(guid)
		local unit = GetUnitIdFromGUID(guid)
		local class
		if unit and unit:find("pet") then
			class = "PET"
		elseif unit and unit:find("boss") then
			class = "BOSS"
		elseif unit then
			_, class = UnitClass(unit)
		end
		return class, unit
	end

	local function GetCreatureId(guid)
		if guid then
			local _, _, _, _, _, id = strsplit("-", guid)
			return tonumber(id) or 0
		end
		return 0
	end

	local unknownUnits = {[_G.UKNOWNBEING] = true, [_G.UNKNOWNOBJECT] = true}

	local function UnitHealthInfo(unit, guid)
		unit = (unit and not unknownUnits[unit]) and unit or (guid and GetUnitIdFromGUID(guid))
		local percent, health, maxhealth
		if unit and UnitExists(unit) then
			health, maxhealth = UnitHealth(unit), UnitHealthMax(unit)
			if health and maxhealth then
				percent = 100 * health / max(1, maxhealth)
			end
		end
		return percent, health, maxhealth
	end

	local function UnitPowerInfo(unit, guid, powerType)
		unit = (unit and not unknownUnits[unit]) and unit or (guid and GetUnitIdFromGUID(guid))
		local percent, power, maxpower
		if unit and UnitExists(unit) then
			power, maxpower = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
			if power and maxpower then
				percent = 100 * power / max(1, maxpower)
			end
		end
		return percent, power, maxpower
	end

	lib.IsInRaid = IsInRaid
	lib.IsInGroup = IsInGroup
	lib.GetNumGroupMembers = GetNumGroupMembers
	lib.GetNumSubgroupMembers = GetNumSubgroupMembers
	lib.GetGroupTypeAndCount = GetGroupTypeAndCount
	lib.IsGroupDead = IsGroupDead
	lib.IsGroupInCombat = IsGroupInCombat
	lib.GroupIterator = GroupIterator
	lib.UnitIterator = UnitIterator
	lib.GetUnitIdFromGUID = GetUnitIdFromGUID
	lib.GetClassFromGUID = GetClassFromGUID
	lib.GetCreatureId = GetCreatureId
	lib.UnitHealthInfo = UnitHealthInfo
	lib.UnitPowerInfo = UnitPowerInfo
end

-------------------------------------------------------------------------------
-- Specs and Roles

do
	local setmetatable, rawset = setmetatable, rawset
	local UnitExists, UnitGUID = UnitExists, UnitGUID
	local LGT = LibStub("LibGroupInSpecT-1.0")

	local cachedSpecs = setmetatable({}, {__index = function(self, guid)
		local info = LGT:GetCachedInfo(guid)
		local spec = info and info.global_spec_id or nil
		rawset(self, guid, spec)
		return spec
	end})

	local cachedRoles = setmetatable({}, {__index = function(self, guid)
		local info = LGT:GetCachedInfo(guid)
		local role = info and info.spec_role or nil
		rawset(self, guid, role)
		return role
	end})

	local function GetUnitSpec(guid)
		return cachedSpecs[guid]
	end

	local function GetUnitRole(guid)
		return cachedRoles[guid]
	end

	LGT:RegisterCallback("GroupInSpecT_Update", function(_, guid, _, info)
		if not guid or not info then return end
		cachedSpecs[guid] = info.global_spec_id or cachedSpecs[guid]
		cachedRoles[guid] = info.spec_role or cachedRoles[guid]
	end)

	LGT:RegisterCallback("GroupInSpecT_Remove", function(_, guid)
		if not guid then return end
		cachedSpecs[guid] = nil
		cachedRoles[guid] = nil
	end)

	lib.GetUnitSpec = GetUnitSpec
	lib.GetUnitRole = GetUnitRole
end

-------------------------------------------------------------------------------
-- Pvp

do
	local IsInInstance, instanceType = IsInInstance, nil

	local function IsInPvP()
		_, instanceType = IsInInstance()
		return (instanceType == "pvp" or instanceType == "arena")
	end

	lib.IsInPvP = IsInPvP
end

-------------------------------------------------------------------------------

local mixins = {
	"Units",
	"EmptyFunc",
	"Dispatch",
	"QuickDispatch",
	-- roster util
	"IsInRaid",
	"IsInGroup",
	"IsInPvP",
	"GetNumGroupMembers",
	"GetNumSubgroupMembers",
	"GetGroupTypeAndCount",
	"IsGroupDead",
	"IsGroupInCombat",
	"GroupIterator",
	"UnitIterator",
	-- unit util
	"GetUnitIdFromGUID",
	"GetClassFromGUID",
	"GetCreatureId",
	"UnitHealthInfo",
	"UnitPowerInfo",
	"GetUnitSpec",
	"GetUnitRole"
}

function lib:Embed(target)
	for _, v in pairs(mixins) do
		target[v] = self[v]
	end
	self.embeds[target] = true
	return target
end

for addon in pairs(lib.embeds) do
	lib:Embed(addon)
end
