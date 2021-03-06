-- This table is used by the client to show items in the equipment menu, and by
-- the server to check if a certain role is allowed to buy a certain item.local math = math
local table = table
local net = net
local player = player
local pairs = pairs
local ipairs = ipairs
local util = util
local hook = hook

-- Details you shouldn't need:
-- The number should increase by a factor of two for every item (ie. ids
-- should be powers of two).
EQUIP_NONE = 0
EQUIP_ARMOR = 1
EQUIP_RADAR = 2
EQUIP_DISGUISE = 4

EQUIP_MAX = 4

-- Stick to around 35 characters per description line, and add a "\n" where you
-- want a new line to start.

Equipment = CLIENT and (Equipment or {}) or nil
SYNC_EQUIP = SYNC_EQUIP or {}
RANDOMSHOP = RANDOMSHOP or {} -- player equipment
RANDOMTEAMSHOPS = RANDOMTEAMSHOPS or {} -- team equipment
RANDOMSAVEDSHOPS = RANDOMSAVEDSHOPS or {} -- saved random shops

-- JUST used to convert old items to new ones
local itemMt = {
	__newindex = function(tbl, key, val)
		print("[TTT2][INFO] You are using an add-on that is trying to add a new ITEM ('" .. key .. "' = '" .. val .. "') in the wrong way. This will not be available in the shop and lead to errors!")
	end
}

EquipmentItems = EquipmentItems or setmetatable(
	{
		[ROLE_TRAITOR] = setmetatable({}, itemMt),
		[ROLE_DETECTIVE] = setmetatable({}, itemMt)
	},
	{
		__index = function(tbl, key)
			ErrorNoHalt("\n[TTT2][WARNING] You are using an add-on that is trying to access an unsupported var ('" .. key .. "'). This will lead to errors!\n\n")
		end,
		__newindex = function(tbl, key, val)
			ErrorNoHalt("\n[TTT2][WARNING] You are using an add-on that is trying to add a new role ('" .. key .. "' = '" .. val .. "') to an unsupported var. This will lead to errors!\n\n")

			if istable(val) then
				tbl[key] = setmetatable(val, itemMt)
			end
		end
	}
)

function GetEquipmentBase(data, eq)
	if not eq or eq.inited then
		return eq
	end

	local name = WEPS.GetClass(eq)

	if not name then return end

	local tbl = {
		id = name,
		name = name,
		PrintName = data.name or data.PrintName or eq.PrintName or name,
		limited = eq.limited or eq.LimitedStock,
		kind = eq.Kind or WEAPON_NONE,
		slot = (eq.Slot or 0) + 1,
		material = eq.Icon or eq.material or "vgui/ttt/icon_id",
		-- the below should be specified in EquipMenuData, in which case
		-- these values are overwritten
		type = "Type not specified",
		model = "models/weapons/w_bugbait.mdl",
		desc = "No description specified.",
		inited = true
	}

	table.Merge(tbl, data)

	for key in pairs(ShopEditor.savingKeys) do
		if not tbl[key] then
			tbl[key] = eq[key]
		end
	end

	for k, v in pairs(tbl) do
		eq[k] = v
	end

	return eq
end

function CreateEquipment(eq)
	if not eq.Doublicated then
		return GetEquipmentBase(eq.EquipMenuData or {}, eq)
	end
end

function AddWeaponIntoFallbackTable(wepClass, roleData)
	if not roleData.fallbackTable then return end

	local wep = weapons.GetStored(wepClass)
	if not wep then return end

	wep.CanBuy = wep.CanBuy or {}

	if not table.HasValue(wep.CanBuy, roleData.index) then
		table.insert(wep.CanBuy, roleData.index)
	end

	local eq = CreateEquipment(wep)
	if not eq then return end

	if not table.HasValue(roleData.fallbackTable, eq) then
		table.insert(roleData.fallbackTable, eq)
	end
end

function GetShopFallback(subrole, tbl)
	local rd = GetRoleByIndex(subrole)
	local shopFallback = GetGlobalString("ttt_" .. rd.abbr .. "_shop_fallback")
	local fb = GetRoleByName(shopFallback).index

	if not fb or shopFallback == SHOP_UNSET or shopFallback == SHOP_DISABLED then
		return subrole, fb
	end

	if not tbl then
		tbl = {subrole, fb}

		fb, subrole = GetShopFallback(fb, tbl)
	elseif not table.HasValue(tbl, fb) then
		table.insert(tbl, fb)

		local nfb

		nfb, subrole = GetShopFallback(fb, tbl)

		if nfb ~= fb then
			subrole = fb
			fb = nfb
		end
	end

	return fb, subrole -- return deepest value and the value before the deepest value
end

function GetShopFallbackTable(subrole)
	local rd = GetRoleByIndex(subrole)

	local shopFallback = GetGlobalString("ttt_" .. rd.abbr .. "_shop_fallback")
	if shopFallback == SHOP_DISABLED then return end

	local fallback

	subrole, fallback = GetShopFallback(subrole)

	if fallback == ROLE_INNOCENT then -- fallback is SHOP_UNSET
		rd = GetRoleByIndex(subrole)

		if rd.fallbackTable then
			return rd.fallbackTable
		end
	end
end

if CLIENT then
	function GetEquipmentForRole(ply, subrole, noModification)
		local fallbackTable = GetShopFallbackTable(subrole)

		if not noModification then
			fallbackTable = GetModifiedEquipment(ply, fallbackTable)
		end

		if fallbackTable then
			return fallbackTable
		end

		local fallback = GetShopFallback(subrole)

		Equipment = Equipment or {}

		-- need to build equipment cache?
		if not Equipment[fallback] then
			local tbl = {}

			-- find buyable items to load info from
			for _, v in ipairs(items.GetList()) do
				if v and not v.Doublicated and v.CanBuy and table.HasValue(v.CanBuy, fallback) then
					local data = v.EquipMenuData or {}

					local base = GetEquipmentBase(data, v)
					if base then
						table.insert(tbl, base)
					end
				end
			end

			-- find buyable weapons to load info from
			for _, v in ipairs(weapons.GetList()) do
				if v and not v.Doublicated and v.CanBuy and table.HasValue(v.CanBuy, fallback) then
					local data = v.EquipMenuData or {}

					local base = GetEquipmentBase(data, v)
					if base then
						table.insert(tbl, base)
					end
				end
			end

			-- mark custom items
			for _, i in ipairs(tbl) do
				if i and i.id then
					i.custom = not table.HasValue(DefaultEquipment[fallback], i.id) -- TODO
				end
			end

			Equipment[fallback] = tbl
		end

		return not noModification and GetModifiedEquipment(ply, Equipment[fallback]) or Equipment[fallback]
	end
end

-- Sync Equipment
local function EncodeForStream(tbl)
	-- may want to filter out data later
	-- just serialize for now

	local result = util.TableToJSON(tbl)
	if not result then
		ErrorNoHalt("Round report event encoding failed!\n")

		return false
	else
		return result
	end
end

-- Search if an item is in the equipment table of a given subrole, and return it if
-- it exists, else return nil.
if SERVER then
	local random_shops = CreateConVar("ttt2_random_shops", "0", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_SERVER_CAN_EXECUTE}, "Set to 0 to disable")
	local random_team_shops = CreateConVar("ttt2_random_team_shops", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_SERVER_CAN_EXECUTE}, "Set to 0 to disable")

	util.AddNetworkString("TTT2SyncRandomShops")

	local function SyncRandomShops(plys)
		if not RANDOMSHOP then return end

		for ply, tbl in pairs(RANDOMSHOP) do
			if plys and not table.HasValue(plys, ply) then continue end

			local tmp = {}

			for _, equip in ipairs(tbl) do
				tmp[#tmp + 1] = equip.id
			end

			if #tmp <= 0 then continue end

			local s = EncodeForStream(tmp)
			if not s then continue end

			-- divide into happy lil bits.
			-- this was necessary with user messages, now it's
			-- a just-in-case thing if a round somehow manages to be > 64K
			local cut = {}
			local max = 64000

			while #s ~= 0 do
				local bit = string.sub(s, 1, max - 1)

				table.insert(cut, bit)

				s = string.sub(s, max, - 1)
			end

			local parts = #cut

			for k, bit in ipairs(cut) do
				net.Start("TTT2SyncRandomShops")
				net.WriteBit(k ~= parts) -- continuation bit, 1 if there's more coming
				net.WriteString(bit)
				net.Send(ply)
			end
		end
	end

	function UpdateRandomShops(plys, val, team)
		if plys then
			for _, ply in ipairs(plys) do
				RANDOMSHOP[ply] = {} -- reset ply
			end
		else
			RANDOMSHOP = {} -- reset everyone
			RANDOMTEAMSHOPS = {} -- reset team equipment
			RANDOMSAVEDSHOPS = {} -- reset saved shops
		end

		local tbl = GetShopRoles()

		-- at first, get all available equipment per team
		for _, rd in pairs(tbl) do
			local fallback = GetShopFallback(rd.index)

			if not RANDOMSAVEDSHOPS[fallback] then
				local amount = val
				local fallbackTable = GetShopFallbackTable(fallback)

				if not fallbackTable then
					fallbackTable = {}

					for _, equip in ipairs(items.GetList()) do
						if equip.CanBuy and table.HasValue(equip.CanBuy, fallback) then
							fallbackTable[#fallbackTable + 1] = equip
						end
					end

					for _, equip in ipairs(weapons.GetList()) do
						if equip.CanBuy and table.HasValue(equip.CanBuy, fallback) then
							fallbackTable[#fallbackTable + 1] = equip
						end
					end
				end

				RANDOMSAVEDSHOPS[fallback] = fallbackTable

				local length = #fallbackTable

				if team and not RANDOMTEAMSHOPS[fallback] then
					if amount < length then
						RANDOMTEAMSHOPS[fallback] = {}

						local tmp2 = {}

						for _, equip in ipairs(fallbackTable) do
							if not equip.notBuyable then
								if equip.NoRandom then
									amount = amount - 1

									RANDOMTEAMSHOPS[fallback][#RANDOMTEAMSHOPS[fallback] + 1] = equip
								else
									tmp2[#tmp2 + 1] = equip
								end
							end
						end

						if amount > 0 then
							for i = 1, amount do
								local rndm = math.random(1, #tmp2)

								RANDOMTEAMSHOPS[fallback][#RANDOMTEAMSHOPS[fallback] + 1] = tmp2[rndm]

								table.remove(tmp2, rndm)
							end
						end
					else
						RANDOMTEAMSHOPS[fallback] = fallbackTable
					end
				end
			end
		end

		-- now set the individual random shop
		if team then -- the shop is synced with the team
			for _, ply in ipairs(plys and plys or player.GetAll()) do
				local sr = ply:GetSubRole()

				if not IsShoppingRole(sr) then continue end

				RANDOMSHOP[ply] = RANDOMTEAMSHOPS[GetShopFallback(sr)]
			end
		else -- every player has his own shop
			for _, ply in ipairs(plys and plys or player.GetAll()) do
				local sr = ply:GetSubRole()

				if not IsShoppingRole(sr) then continue end

				local fallbackTable = RANDOMSAVEDSHOPS[GetShopFallback(sr)]
				local length = #fallbackTable
				local amount = val
				local tmp2 = {}

				RANDOMSHOP[ply] = {}

				for _, equip in ipairs(fallbackTable) do
					if not equip.notBuyable then
						if equip.NoRandom then
							amount = amount - 1

							RANDOMSHOP[ply][#RANDOMSHOP[ply] + 1] = equip
						else
							tmp2[#tmp2 + 1] = equip
						end
					end
				end

				if amount > 0 then
					for i = 1, amount do
						local rndm = math.random(1, #tmp2)

						RANDOMSHOP[ply][#RANDOMSHOP[ply] + 1] = tmp2[rndm]

						table.remove(tmp2, rndm)
					end
				end
			end
		end

		SyncRandomShops(plys)
	end

	cvars.AddChangeCallback("ttt2_random_shops", function(name, old, new)
		local tmp = tonumber(new)

		SetGlobalInt("ttt2_random_shops", tmp)

		if tmp > 0 then
			UpdateRandomShops(nil, tmp, GetGlobalBool("ttt2_random_team_shops", true))
		end
	end, "ttt2changeshops")

	cvars.AddChangeCallback("ttt2_random_team_shops", function(name, old, new)
		local tmp = tobool(new)
		local amount = GetGlobalInt("ttt2_random_shops")

		SetGlobalBool("ttt2_random_team_shops", tmp)

		if new ~= old and amount > 0 then
			UpdateRandomShops(nil, amount, tmp)
		end
	end, "ttt2changeteamshops")

	hook.Add("TTTPrepareRound", "TTT2InitRandomShops", function()
		local amount = GetGlobalInt("ttt2_random_shops")
		if amount > 0 then
			UpdateRandomShops(nil, amount, GetGlobalBool("ttt2_random_team_shops", true))
		end
	end)

	hook.Add("TTT2UpdateSubrole", "TTT2UpdateRandomShop", function(ply)
		local amount = GetGlobalInt("ttt2_random_shops")
		if amount > 0 then
			UpdateRandomShops({ply}, amount, GetGlobalBool("ttt2_random_team_shops", true))
		end
	end)

	hook.Add("PlayerInitialSpawn", "TTT2InitRandomShops", function(ply)
		local amount = random_shops:GetInt()

		SetGlobalInt("ttt2_random_shops", amount)
		SetGlobalBool("ttt2_random_team_shops", random_team_shops:GetBool())

		if amount > 0 then
			SyncRandomShops({ply})
		end
	end)
else
	local buff = ""

	local function TTT2SyncRandomShops(len)
		local cont = net.ReadBit() == 1

		buff = buff .. net.ReadString()

		if cont then
			return
		else
			-- do stuff with buffer contents
			local json_shop = buff -- util.Decompress(buff)

			if not json_shop then
				ErrorNoHalt("RANDOMSHOP decompression failed!\n")
			else
				-- convert the json string back to a table
				local tmp = util.JSONToTable(json_shop)

				if istable(tmp) then
					local tmp2 = {}

					for _, id in ipairs(tmp) do
						local equip = not items.IsItem(id) and weapons.GetStored(id) or items.GetStored(id)

						tmp2[#tmp2 + 1] = equip
					end

					RANDOMSHOP[LocalPlayer()] = tmp2
				else
					ErrorNoHalt("RANDOMSHOP decoding failed!\n")
				end
			end

			-- flush
			buff = ""
		end
	end
	net.Receive("TTT2SyncRandomShops", TTT2SyncRandomShops)
end

function GetModifiedEquipment(ply, fallback)
	if ply and fallback and RANDOMSHOP[ply] and GetGlobalInt("ttt2_random_shops") > 0 then
		local tmp = {}

		for _, equip in ipairs(RANDOMSHOP[ply]) do
			for _, eq in pairs(fallback) do
				if eq.id == equip.id then
					tmp[#tmp + 1] = eq
				end
			end
		end

		if #tmp > 0 then
			return tmp
		end
	end

	return fallback
end

-- Utility function to register a new Equipment ID
function GenerateNewEquipmentID()
	EQUIP_MAX = EQUIP_MAX * 2

	local val = EQUIP_MAX

	timer.Simple(0, function()
		for _, v in ipairs(items.GetList()) do
			if v.oldId == val and v.id then
				print("[TTT2][WARNING] TTT2 doesn't support old items completely since they are limited to an amount of 16. If the item '" .. v.id .. "' with id '" .. val .. "' doesn't work as intended, modify the old item and use the new items system instead.")

				break
			end
		end
	end)

	return EQUIP_MAX
end

function EquipmentTableHasValue(tbl, equip)
	if not tbl then
		return false
	end

	for _, eq in pairs(tbl) do
		if eq.id == equip.id or eq.name == equip.name then
			return true
		end
	end

	return false
end

function InitFallbackShops()
	for _, v in ipairs({TRAITOR, DETECTIVE}) do
		local fallback = GetShopFallbackTable(v.index)
		if fallback then
			for _, eq in ipairs(fallback) do
				local equip = GetEquipmentByName(eq.id)
				if equip then
					equip.CanBuy = equip.CanBuy or {}

					if not table.HasValue(equip.CanBuy, v.index) then
						table.insert(equip.CanBuy, v.index)
					end
				end
			end
		end
	end
end

function InitFallbackShop(roleData, fallbackTable, avoidSet)
	if not avoidSet then
		roleData.fallbackTable = fallbackTable
	end

	local fallback = GetShopFallbackTable(roleData.index)
	if fallback then
		for _, eq in ipairs(fallbackTable) do
			local equip = GetEquipmentByName(eq.id)
			if equip then
				equip.CanBuy = equip.CanBuy or {}

				if not table.HasValue(equip.CanBuy, roleData.index) then
					table.insert(equip.CanBuy, roleData.index)
				end
			end
		end
	end
end

function AddToShopFallback(fallback, subrole, eq)
	if not table.HasValue(fallback, eq) then
		table.insert(fallback, eq)
	end

	if GetShopFallbackTable(subrole) then
		local equip = GetEquipmentByName(eq.id)
		if equip then
			equip.CanBuy = equip.CanBuy or {}

			if not table.HasValue(equip.CanBuy, subrole) then
				table.insert(equip.CanBuy, subrole)
			end
		end
	end
end

local function InitDefaultEquipmentForRole(roleData)
	-- set default equipment tables
	local itms = items.GetList()
	local sweps = weapons.GetList()

	-- TRAITOR
	local tbl = {}

	-- find buyable items to load info from
	for _, v in ipairs(itms) do
		if v and not v.Doublicated and v.CanBuy and table.HasValue(v.CanBuy, roleData.index) then
			local data = v.EquipMenuData or {}

			local base = GetEquipmentBase(data, v)
			if base then
				tbl[#tbl + 1] = base
			end
		end
	end

	-- find buyable weapons to load info from
	for _, v in ipairs(sweps) do
		if v and not v.Doublicated and v.CanBuy and table.HasValue(v.CanBuy, roleData.index) then
			local data = v.EquipMenuData or {}

			local base = GetEquipmentBase(data, v)
			if base then
				tbl[#tbl + 1] = base
			end
		end
	end

	-- mark custom items
	for _, i in pairs(tbl) do
		if i and i.id then
			i.custom = not table.HasValue(DefaultEquipment[roleData.index], i.id) -- TODO
		end
	end

	roleData.fallbackTable = tbl
end

function InitDefaultEquipment()
	InitDefaultEquipmentForRole(TRAITOR)
	InitDefaultEquipmentForRole(DETECTIVE)
end

if SERVER then
	util.AddNetworkString("TTT2SyncEquipment")

	function SyncEquipment(ply, add)
		add = add or true

		--print("[TTT2][SHOP] Sending new SHOP list to " .. ply:Nick() .. "...")

		local s = EncodeForStream(SYNC_EQUIP)
		if not s then return end

		-- divide into happy lil bits.
		-- this was necessary with user messages, now it's
		-- a just-in-case thing if a round somehow manages to be > 64K
		local cut = {}
		local max = 65499

		while #s ~= 0 do
			local bit = string.sub(s, 1, max - 1)

			table.insert(cut, bit)

			s = string.sub(s, max, - 1)
		end

		local parts = #cut

		for k, bit in ipairs(cut) do
			net.Start("TTT2SyncEquipment")
			net.WriteBool(add)
			net.WriteBit(k ~= parts) -- continuation bit, 1 if there's more coming
			net.WriteString(bit)
			net.Send(ply)
		end
	end

	function SyncSingleEquipment(ply, role, equipId, add)
		local s = EncodeForStream({[role] = {equipId}})
		if not s then return end

		-- divide into happy lil bits.
		-- this was necessary with user messages, now it's
		-- a just-in-case thing if a round somehow manages to be > 64K
		local cut = {}
		local max = 65498

		while #s ~= 0 do
			local bit = string.sub(s, 1, max - 1)

			table.insert(cut, bit)

			s = string.sub(s, max, - 1)
		end

		local parts = #cut

		for k, bit in ipairs(cut) do
			net.Start("TTT2SyncEquipment")
			net.WriteBool(add)
			net.WriteBit(k ~= parts) -- continuation bit, 1 if there's more coming
			net.WriteString(bit)
			net.Send(ply)
		end
	end

	function LoadSingleShopEquipment(roleData)
		local fallback = GetGlobalString("ttt_" .. roleData.abbr .. "_shop_fallback")

		if fallback ~= roleData.name then return end -- TODO why? remove and replace SHOP_UNSET with index of the current role

		hook.Run("TTT2LoadSingleShopEquipment", roleData)

		SYNC_EQUIP = SYNC_EQUIP or {}
		SYNC_EQUIP[roleData.index] = {} -- reset

		-- init equipment
		local result = ShopEditor.GetShopEquipments(roleData)

		for _, v in ipairs(result) do
			local equip = GetEquipmentByName(v.name)
			if equip then
				equip.CanBuy = equip.CanBuy or {}

				if not table.HasValue(equip.CanBuy, roleData.index) then
					table.insert(equip.CanBuy, roleData.index)
				end
				--

				SYNC_EQUIP[roleData.index] = SYNC_EQUIP[roleData.index] or {}

				if not table.HasValue(SYNC_EQUIP[roleData.index], equip.id) then
					table.insert(SYNC_EQUIP[roleData.index], equip.id)
				end
			end
		end
	end

	function AddEquipmentToRole(subrole, equip_table)
		equip_table.CanBuy = equip_table.CanBuy or {}

		if not table.HasValue(equip_table.CanBuy, subrole) then
			table.insert(equip_table.CanBuy, subrole)
		end
		--

		SYNC_EQUIP[subrole] = SYNC_EQUIP[subrole] or {}

		if not table.HasValue(SYNC_EQUIP[subrole], equip_table.id) then
			table.insert(SYNC_EQUIP[subrole], equip_table.id)
		end

		for _, v in ipairs(player.GetAll()) do
			SyncSingleEquipment(v, subrole, equip_table.id, true)
		end
	end

	function RemoveEquipmentFromRole(subrole, equip_table)
		if not equip_table.CanBuy then
			equip_table.CanBuy = {}
		else
			for k, v in ipairs(equip_table.CanBuy) do
				if v == subrole then
					table.remove(equip_table.CanBuy, k)

					break
				end
			end
		end
		--

		SYNC_EQUIP[subrole] = SYNC_EQUIP[subrole] or {}

		for k, v in pairs(SYNC_EQUIP[subrole]) do
			if v == equip_table.id then
				table.remove(SYNC_EQUIP[subrole], k)

				break
			end
		end

		for _, v in ipairs(player.GetAll()) do
			SyncSingleEquipment(v, subrole, equip_table.id, false)
		end
	end

	hook.Add("TTT2UpdateTeam", "TTT2SyncTeambuyEquipment", function(ply, oldTeam, team)
		if TEAMBUYTABLE then
			if oldTeam and oldTeam ~= TEAM_NONE then
				net.Start("TTT2ResetTBEq")
				net.WriteString(oldTeam)
				net.Send(ply)
			end

			if team and team ~= TEAM_NONE and not TEAMS[team].alone and TEAMBUYTABLE[team] then
				local filter = GetTeamFilter(team)

				for id in pairs(TEAMBUYTABLE[team]) do
					net.Start("TTT2ReceiveTBEq")
					net.WriteString(id)
					net.Send(filter)
				end
			end
		end
	end)
else -- CLIENT
	local function ReceiveTeambuyEquipment()
		local s = net.ReadString()
		local team = LocalPlayer():GetTeam()

		if team and team ~= TEAM_NONE and not TEAMS[team].alone then
			TEAMBUYTABLE[team] = TEAMBUYTABLE[team] or {}
			TEAMBUYTABLE[team][s] = true
		end
	end
	net.Receive("TTT2ReceiveTBEq", ReceiveTeambuyEquipment)

	local function ReceiveGlobalbuyEquipment()
		local s = net.ReadString()

		BUYTABLE[s] = true
	end
	net.Receive("TTT2ReceiveGBEq", ReceiveGlobalbuyEquipment)

	local function ResetTeambuyEquipment()
		local s = net.ReadString()

		if not s or s == TEAM_NONE then return end

		TEAMBUYTABLE[s] = nil
	end
	net.Receive("TTT2ResetTBEq", ResetTeambuyEquipment)

	function AddEquipmentToRoleEquipment(subrole, equip)
		-- start with all the non-weapon goodies
		local toadd

		-- find buyable equip to load info from
		equip.CanBuy = equip.CanBuy or {}

		if not table.HasValue(equip.CanBuy, subrole) then
			table.insert(equip.CanBuy, subrole)
		end

		if equip and not equip.Doublicated then
			local data = equip.EquipMenuData or {}

			local base = GetEquipmentBase(data, equip)
			if base then
				toadd = base
			end
		end

		-- mark custom items
		if toadd and toadd.id then
			toadd.custom = not table.HasValue(DefaultEquipment[subrole], toadd.id) -- TODO
		end

		Equipment[subrole] = Equipment[subrole] or {}

		if toadd and not EquipmentTableHasValue(Equipment[subrole], toadd) then
			table.insert(Equipment[subrole], toadd)
		end
	end

	function RemoveEquipmentFromRoleEquipment(subrole, equip)
		for k, v in ipairs(equip.CanBuy) do
			if v == subrole then
				table.remove(equip.CanBuy, k)

				break
			end
		end

		for k, eq in pairs(Equipment[subrole]) do
			if eq.id == equip.id then
				table.remove(Equipment[subrole], k)

				break
			end
		end
	end

	-- sync GetRoles()
	local buff = ""

	local function TTT2SyncEquipment(len)
		--print("[TTT2][SHOP] Received new SHOP list from server! Updating...")

		local add = net.ReadBool()
		local cont = net.ReadBit() == 1

		buff = buff .. net.ReadString()

		if cont then
			return
		else
			-- do stuff with buffer contents
			local json_shop = buff -- util.Decompress(buff)

			if not json_shop then
				ErrorNoHalt("SHOP decompression failed!\n")
			else
				-- convert the json string back to a table
				local tmp = util.JSONToTable(json_shop)

				if istable(tmp) then
					for subrole, tbl in pairs(tmp) do
						-- init
						Equipment = Equipment or {}

						if not Equipment[subrole] then
							GetEquipmentForRole(nil, subrole, true) -- TODO test
						end

						for _, equip in pairs(tbl) do
							local equip_table = not items.IsItem(equip) and weapons.GetStored(equip) or items.GetStored(equip)
							if equip_table then
								equip_table.CanBuy = equip_table.CanBuy or {}

								if add then
									AddEquipmentToRoleEquipment(subrole, equip_table)
								else
									RemoveEquipmentFromRoleEquipment(subrole, equip_table)
								end
							end
						end
					end
				else
					ErrorNoHalt("SHOP decoding failed!\n")
				end
			end

			-- flush
			buff = ""
		end
	end
	net.Receive("TTT2SyncEquipment", TTT2SyncEquipment)
end

-- support this old item system too
function GetEquipmentItem(role, id)
	return items.GetRoleItem(role, id)
end
