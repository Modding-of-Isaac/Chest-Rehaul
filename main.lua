CRE = RegisterMod("Chest Rehaul", 1)

local game = Game()
local player = nil
local room = nil
local level = nil

CRE:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, function(_, p)
	player = p
end)
CRE:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
	room = game:GetRoom()
	level = game:GetLevel()
end)

local json = require("json")

CRE.DEFAULT_DATA = { -- all start values of the moddata
	run = {
		FirstTimeChest = true,
		ChestFightRoom = false,
		ChestBossRoom = nil,
		SpawnBigChest = false,
	}
}

if Isaac.HasModData(CRE) then -- loading moddata
	CRE.DATA = json.decode(Isaac.LoadModData(CRE))
else
	CRE.DATA = CRE.DEFAULT_DATA
end

CRE.Debug = function(v) -- for testing
	if type(v) == "table" then
		v = json.encode(v)
	elseif type(v) ~= "string" then
		v = tostring(v)
	end
	Isaac.DebugString(v)
	Isaac.ConsoleOutput(v)
end

CRE:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, savestate) -- everything in CRE.DATA.run gets reset at the start of the run
	if not savestate then
		CRE.DATA.run = CRE.DEFAULT_DATA.run
	end
end)

local function ent(name) -- easy way to organize all entities types and variants
	return {id = Isaac.GetEntityTypeByName(name), variant = Isaac.GetEntityVariantByName(name)}
end

CRE.ENT = {
	CHEST_MEGA = ent("Chest Mega"),
	ROLLING_COIN = ent("Rolling Coin"),
	SEALED_CHEST = ent("Sealed Chest")
}

CRE:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
	math.randomseed(Isaac.GetTime())
	Isaac.SaveModData(CRE, json.encode(CRE.DATA))
end)

CRE.RegisteredEntities = {}

function CRE.RegisterEntity(e)
	if CRE.RegisteredEntities[level:GetCurrentRoomIndex()] == nil then CRE.RegisteredEntities[level:GetCurrentRoomIndex()] = {} end
	CRE.RegisteredEntities[level:GetCurrentRoomIndex()][e.Index] = {Type = e.Type, Variant = e.Variant, Pos = e.Position, Vel = e.Velocity, Data = e:GetData()}
end

function CRE.UnRegisterEntity(e)
	CRE.RegisteredEntities[level:GetCurrentRoomIndex()][e.Index] = nil
end

CRE:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
	if not room:IsFirstVisit() then
		for _,v in pairs(CRE.RegisteredEntities[level:GetCurrentRoomIndex()]) do
			local ent = Isaac.Spawn(v.Type, v.Variant, 0, v.Pos, v.Vel, nil)
			for k,v2 in pairs(v.Data) do
				ent:GetData()[k] = v2
			end
		end
	end
	CRE.RegisteredEntities[level:GetCurrentRoomIndex()] = {}
end)

CRE:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
	CRE.RegisteredEntities = {}
end)

function CRE.GetPlayerItems(player)
	local items = {}
	for itemid=1, CollectibleType.NUM_COLLECTIBLES do
		if player:HasCollectible(itemid) then
			table.insert(items, itemid)
		end
	end
	return items
end

----------------
-- CHEST MEGA --
----------------

-- all possible items that the boss can use as attack
CRE.LivingChestItems = {CollectibleType.COLLECTIBLE_TAMMYS_HEAD, CollectibleType.COLLECTIBLE_BOBS_ROTTEN_HEAD,
CollectibleType.COLLECTIBLE_BLOOD_BAG, CollectibleType.COLLECTIBLE_IV_BAG, CollectibleType.COLLECTIBLE_GUPPYS_HEAD}

-- for guppy's head attack
CRE.ChestSpawnableFlies = {EntityType.ENTITY_FLY, EntityType.ENTITY_POOTER, EntityType.ENTITY_ATTACKFLY, 
EntityType.ENTITY_BOOMFLY, EntityType.ENTITY_MOTER, EntityType.ENTITY_RING_OF_FLIES, 
EntityType.ENTITY_FULL_FLY, EntityType.ENTITY_DART_FLY}

CRE:AddCallback(ModCallbacks.MC_POST_UPDATE, function() -- replacing the big chest in the ??? boss fight with chest mega
	if room:GetType() == RoomType.ROOM_BOSS and level:GetAbsoluteStage() == LevelStage.STAGE6 and CRE.DATA.run.FirstTimeChest then
		local bigchests = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_BIGCHEST, 0, false, false)
		if #bigchests ~= 0 then
			Isaac.Spawn(CRE.ENT.CHEST_MEGA.id, CRE.ENT.CHEST_MEGA.variant, 1, bigchests[1].Position, Vector(0,0), nil)
			bigchests[1]:Remove()
		end
	end
end)

CRE:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
	if CRE.DATA.run.ChestFightRoom then -- set up of the chest fight room
		CRE.DATA.run.ChestFightRoom = false
		CRE.DATA.run.FirstTimeChest = false
		for i=0, 7 do
			room:RemoveDoor(i)
		end
		for _,e in ipairs(Isaac.GetRoomEntities()) do
			if e.Type == EntityType.ENTITY_PICKUP or e:IsEnemy() then
				e:Remove()
			end
		end
		Isaac.Spawn(CRE.ENT.CHEST_MEGA.id, CRE.ENT.CHEST_MEGA.variant, 0, room:GetCenterPos(), Vector(0,0), nil)
	end
	
	if CRE.DATA.run.SpawnBigChest then -- for after the chest fight, spawning the big chest to end the game
		CRE.DATA.run.SpawnBigChest = false
		Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_BIGCHEST, 0, room:GetCenterPos(), Vector(0,0), nil)
	end
	
	if CRE.DATA.run.ChestBossRoom == level:GetCurrentRoomIndex() then -- making sure chest mega keeps being there even if you leave the room
		if CRE.DATA.run.FirstTimeChest then
			local bigchests = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_BIGCHEST, 0, false, false)
			if #bigchests == 0 then
				Isaac.Spawn(CRE.ENT.CHEST_MEGA.id, CRE.ENT.CHEST_MEGA.variant, 1, room:GetCenterPos(), Vector(0,0), nil)
			end
		end
	end
end)

CRE:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, function(_, rng, pos) -- canceling reward drops in the chest fight room after the fight has ended
	if CRE.DATA.run.ChestFightRoom then
		return true
	end
end)

CRE:AddCallback(ModCallbacks.MC_POST_NPC_INIT, function(_, npc)
	if npc.Variant ~= CRE.ENT.CHEST_MEGA.variant then return end
	local sprite,data = npc:GetSprite(),npc:GetData()
	npc:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK)
	npc:AddEntityFlags(EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
	npc:AddEntityFlags(EntityFlag.FLAG_NO_BLOOD_SPLASH)
	data.Hops = 0
	data.Timer = 0
	data.Item = 0
	
	if CRE.DATA.run.FirstTimeChest then
		npc:AddEntityFlags(EntityFlag.FLAG_DONT_COUNT_BOSS_HP)
		CRE.DATA.run.ChestBossRoom = level:GetCurrentRoomIndex()
	end
end, CRE.ENT.CHEST_MEGA.id)

CRE:AddCallback(ModCallbacks.MC_NPC_UPDATE, function(_, npc)
	if npc.Variant ~= CRE.ENT.CHEST_MEGA.variant then return end
	local sprite,data = npc:GetSprite(),npc:GetData()
	
	if CRE.DATA.run.FirstTimeChest then -- chest acts as portal to the chest fight
		npc.CollisionDamage = 0
		if sprite:IsFinished("Appear") then
			sprite:Play("OpenStart", true)
		end
		if sprite:IsFinished("OpenStart") then
			sprite:Play("Open", true)
		end
		if sprite:IsPlaying("Open") and (npc.Position-player.Position):Length() <= 35 then
			player.Visible = false
			player.ControlsEnabled = false
			sprite:Play("SuckPlayerIn", true)
		end
		if sprite:IsEventTriggered("PlayerSuckedIn") then
			CRE.DATA.run.ChestFightRoom = true
			Isaac.ExecuteCommand("goto d.0")
		end
		return
	end
	
	if data.Timer ~= 0 then -- updating the timer, used for various attacks
		data.Timer = data.Timer-1
	end
	
	if sprite:IsFinished("Appear") then
		sprite:Play("Hop", true)
	end
	
	if sprite:IsFinished("Hop") and data.Hops == 3 then -- after hopping three times do a special attack
		data.Hops = 0
		if math.random(1,3) == 1 then -- rolling coins attack
			sprite:Play("HopToSide", true)
		else -- random item attack
			data.Item = CRE.LivingChestItems[math.random(#CRE.LivingChestItems)]
			sprite:ReplaceSpritesheet(1, "gfx/items/collectibles/"..tostring(data.Item)..".png")
			sprite:LoadGraphics()
			sprite:Play("OpenStart", true)
		end
	elseif sprite:IsFinished("Hop") then -- counting hops
		data.Hops = data.Hops+1
		sprite:Play("Hop", true)
	end
	
	if sprite:IsFinished("OpenStart") then -- start item attack
		sprite:Play("UseItem", true)
	end
	if sprite:IsFinished("UseItem") then
		sprite:Play("Item", true)
		data.Timer = 120
		if data.Item == CollectibleType.COLLECTIBLE_BLOOD_BAG then
			data.Timer = 50
		end
	end
	if sprite:IsPlaying("Item") then -- all item attacks
		if data.Item == CollectibleType.COLLECTIBLE_TAMMYS_HEAD then
			if npc.FrameCount%5 == 0 then
				local r = math.random(0,359)
				for i=0, 7 do
					Isaac.Spawn(EntityType.ENTITY_PROJECTILE, ProjectileVariant.PROJECTILE_TEAR, 0, Vector.FromAngle(i*45+r)*20+npc.Position, Vector.FromAngle(i*45+r)*12, npc)
				end
			end
			
		elseif data.Item == CollectibleType.COLLECTIBLE_BOBS_ROTTEN_HEAD then
			if npc.FrameCount%10 == 0 then
				local dirtoplayer = (player.Position-npc.Position):Normalized()
				local tear = Isaac.Spawn(EntityType.ENTITY_TEAR, TearVariant.BOBS_HEAD, 0, dirtoplayer*20+npc.Position, dirtoplayer*16, npc)
				tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_PLAYERONLY
				tear:GetData().DiesWhenCloseToPlayer = true
			end
			
		elseif data.Item == CollectibleType.COLLECTIBLE_BLOOD_BAG then
			npc.HitPoints = math.min(npc.HitPoints+10, npc.MaxHitPoints)
			
		elseif data.Item == CollectibleType.COLLECTIBLE_IV_BAG then
			if npc.FrameCount%8 == 0 then
				npc:TakeDamage(10, 0, EntityRef(npc), 0)
				local angle = math.random(0,359)
				local ent = Isaac.Spawn(CRE.ENT.ROLLING_COIN.id, CRE.ENT.ROLLING_COIN.variant, 0, Vector.FromAngle(angle)*20+npc.Position, Vector.FromAngle(angle)*6, npc)
				ent:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
			end
			
		elseif data.Item == CollectibleType.COLLECTIBLE_GUPPYS_HEAD then
			if npc.FrameCount%5 == 0 then
				local ent = Isaac.Spawn(CRE.ChestSpawnableFlies[math.random(#CRE.ChestSpawnableFlies)], 0, 0, Vector.FromAngle(math.random(0,359))*math.random(30,50)+npc.Position, Vector(0,0), npc)
				ent:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
			end
		end
	end
	if sprite:IsPlaying("Item") and data.Timer == 0 then
		sprite:Play("ItemEnd", true)
	end
	if sprite:IsFinished("ItemEnd") then
		sprite:Play("Hop")
	end
	
	if sprite:IsFinished("HopToSide") then -- start rolling coins attack
		sprite:Play("OnSide", true)
		data.Timer = 90
	end
	if sprite:IsPlaying("OnSide") and data.Timer == 0 then
		sprite:Play("OnSideEnd", true)
	end
	if sprite:IsFinished("OnSideEnd") then
		sprite:Play("Hop", true)
	end
	if sprite:IsPlaying("OnSide") and npc.FrameCount%12 == 0 then
		local ent = Isaac.Spawn(CRE.ENT.ROLLING_COIN.id, CRE.ENT.ROLLING_COIN.variant, 0, Vector(math.random(-10,10),10)+npc.Position, Vector.FromAngle(math.random(30)+165)*6, npc)
		ent:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
	end
	
	-- movement and the hop attack
	if sprite:IsEventTriggered("StartHop") then
		npc.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
		if sprite:IsPlaying("Hop") then
			npc.Velocity = (player.Position-npc.Position):Resized(10)
		end
	end
	if sprite:IsEventTriggered("EndHop") then
		npc.Velocity = Vector(0,0)
		npc.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
		for i=0, 5 do
			Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.ROCK_EXPLOSION , 0, Vector.FromAngle(i*60)*30+npc.Position, Vector(0,0), npc)
		end
		game:ShakeScreen(10)
		npc:PlaySound(SoundEffect.SOUND_FORESTBOSS_STOMPS, 1, 0, false, 1)
		local r = math.random(0,89)
		for i=1, 4 do
			local proj = Isaac.Spawn(EntityType.ENTITY_PROJECTILE, ProjectileVariant.PROJECTILE_COIN, 0, Vector.FromAngle(i*90+r)*10+npc.Position, Vector.FromAngle(i*90+r)*7, npc)
			proj:GetData().RotatingCoinProj = true
			proj.CollisionDamage = 2
		end
	end
end, CRE.ENT.CHEST_MEGA.id)

CRE:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, function(_, npc) -- returning the player to the original room after beating the chest boss
	if npc.Variant ~= CRE.ENT.CHEST_MEGA.variant then return end
	if level:GetAbsoluteStage() ~= LevelStage.STAGE6 then
		CRE.DATA.run.FirstTimeChest = true
	end
	CRE.DATA.run.SpawnBigChest = true
	level:ChangeRoom(CRE.DATA.run.ChestBossRoom)
end, CRE.ENT.CHEST_MEGA.id)

CRE:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, e, dmg, flag, src, invuln) -- preventing the chest from taking damage when it acts as portal
	if e.Variant ~= CRE.ENT.CHEST_MEGA.variant then return end
	if CRE.DATA.run.FirstTimeChest then
		return false
	end
end, CRE.ENT.CHEST_MEGA.id)

CRE:AddCallback(ModCallbacks.MC_POST_PROJECTILE_UPDATE, function(_, proj)
	if proj:GetData().RotatingCoinProj then -- coin projectiles that rotates to the right
		proj.Velocity = Vector.FromAngle(proj.Velocity:GetAngleDegrees()+4):Resized(proj.Velocity:Length())
	end
end)

CRE:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
	if tear:GetData().DiesWhenCloseToPlayer then -- for bob's rotten head not hitting the player otherwise
		if (tear.Position-player.Position):Length() <= 20 then
			tear:Die()
		end
	end
end)

------------------
-- ROLLING COIN --
------------------

CRE:AddCallback(ModCallbacks.MC_POST_NPC_INIT, function(_, npc)
	npc:AddEntityFlags(EntityFlag.FLAG_NO_BLOOD_SPLASH)
end, CRE.ENT.ROLLING_COIN.id)

CRE:AddCallback(ModCallbacks.MC_NPC_UPDATE, function(_, npc)
	if npc.Variant ~= CRE.ENT.ROLLING_COIN.variant then return end
	-- adjusting the angle of the enemy to face the player
	if (Vector.FromAngle(npc.Velocity:GetAngleDegrees()-6)*6+npc.Position-player.Position):Length() <= (Vector.FromAngle(npc.Velocity:GetAngleDegrees()+6)*6+npc.Position-player.Position):Length() then
		npc.Velocity = Vector.FromAngle(npc.Velocity:GetAngleDegrees()-5)*6
	else
		npc.Velocity = Vector.FromAngle(npc.Velocity:GetAngleDegrees()+5)*6
	end
	
	local angle,sprite = npc.Velocity:GetAngleDegrees(),npc:GetSprite()
	if angle < 0 then
		angle = angle+360
	end
	sprite:SetFrame(tostring(math.floor(angle%180/15)), 0) -- sets the animation based on the angle of the velocity
end, CRE.ENT.ROLLING_COIN.id)

------------------
-- SEALED CHEST --
------------------

CRE.SealedChestDisabledItems = { -- these are one-time reward items, the chest won't take these items from you
	[11]=1,[12]=1,[15]=1,[16]=1,[17]=1,[18]=1,[19]=1,[22]=1,[23]=1,[24]=1,[25]=1,[26]=1,[72]=1,[74]=1,[81]=1,[83]=1,
	[92]=1,[100]=1,[106]=1,[125]=1,[137]=1,[140]=1,[141]=1,[184]=1,[190]=1,[195]=1,[196]=1,[198]=1,[209]=1,[218]=1,
	[219]=1,[223]=1,[226]=1,[227]=1,[238]=1,[239]=1,[252]=1,[256]=1,[260]=1,[262]=1,[301]=1,[304]=1,[312]=1,[327]=1,[328]=1,[334]=1,
	[343]=1,[344]=1,[346]=1,[353]=1,[354]=1,[366]=1,[367]=1,[380]=1,[409]=1,[415]=1,[428]=1,[438]=1,[438]=1,[449]=1,[451]=1,
	[454]=1,[456]=1,[457]=1,[458]=1,[464]=1,[501]=1,[517]=1
}
CRE.TimerSinceUsedSealedChest = 0 -- there is some delay before you can get an item from other chests

CRE:AddCallback(ModCallbacks.MC_POST_UPDATE, function() -- timer for CRE.TimerSinceUsedSealedChest
	if CRE.TimerSinceUsedSealedChest ~= 0 then
		CRE.TimerSinceUsedSealedChest = CRE.TimerSinceUsedSealedChest-1
	end
end)

CRE:AddCallback(ModCallbacks.MC_NPC_UPDATE, function(_, npc)
	if npc.Variant ~= CRE.ENT.SEALED_CHEST.variant then return end
	local data,sprite = npc:GetData(),npc:GetSprite()
	
	CRE.RegisterEntity(npc) -- this function makes the enemy persist in this room
	if sprite:IsEventTriggered("BreakChain") then -- projectile attack whenever a chain breaks
		local r = math.random(1,45)
		for i=1, 8 do
			Isaac.Spawn(EntityType.ENTITY_PROJECTILE, 0, 0, npc.Position, Vector.FromAngle(i*45+r)*8, npc)
		end
	end
	if not data.SealedItem then -- if the enemy has no item selected yet, it will do so
		npc:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK)
		npc:AddEntityFlags(EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
		local items = CRE.GetPlayerItems(player) -- gives all items the player currently has
		local nondisableditems = {}
		for _,v in ipairs(items) do -- removing all one-time reward items
			if not CRE.SealedChestDisabledItems[v] then
				table.insert(nondisableditems, v)
			end
		end
		if #nondisableditems ~= 0 then -- chest takes a random item from you
			data.SealedItem = nondisableditems[math.random(#nondisableditems)]
			data.SealedItemCharge = player:GetActiveCharge()
			player:RemoveCollectible(data.SealedItem)
			sprite:ReplaceSpritesheet(1, "gfx/items/collectibles/"..tostring(data.SealedItem)..".png")
			sprite:LoadGraphics()
			sprite:Play("CollectItem", true)
		else -- couldn't get any items from you
			data.SealedItem = "none"
			sprite:ReplaceSpritesheet(1, "gfx/items/collectibles/0.png")
			sprite:LoadGraphics()
			sprite:Play("CollectItem", true)
		end
		data.Chains = 3
	elseif not sprite:IsPlaying("CollectItem") then
		local hopping = sprite:IsPlaying("Hop") or sprite:IsPlaying("Hop3Chains") or sprite:IsPlaying("Hop2Chains") or sprite:IsPlaying("Hop1Chains")
		local isbreakingchain = sprite:IsPlaying("BreakChain1") or sprite:IsPlaying("BreakChain2") or sprite:IsPlaying("BreakChain3")
		if not hopping and not isbreakingchain and data.Chains > 0 then -- whenever the chest hits the ground or has just broken a chain
			npc.Velocity = Vector(0,0) -- reseting velocity for after a hop
			if room:IsClear() then -- breaks the chains himself if the room is cleared
				npc.HitPoints = 1
				if not isbreakingchain then
					sprite:Play("BreakChain"..tostring(data.Chains), true)
					data.Chains = data.Chains-1
				end
			elseif data.Chains == 3 and npc.HitPoints <= npc.MaxHitPoints/3*2 then -- 2/3 of health, first chain breaks
				data.Chains = 2
				sprite:Play("BreakChain3", true)
			elseif data.Chains == 2 and npc.HitPoints <= npc.MaxHitPoints/3 then -- 1/3 of health, second chain breaks
				data.Chains = 1
				sprite:Play("BreakChain2", true)
			elseif data.Chains == 1 and npc.HitPoints == 1 then -- basically death (but it gets prevented), thrid chain breaks
				data.Chains = 0
				sprite:Play("BreakChain1", true)
			else
				local bestdir = -1
				local distancefromplayer = 0
				local currentlengthtoplayer = (player.Position-npc.Position):Length()
				for i=1, 18 do -- calculates what the best hop would be
					local vel = Vector.FromAngle(i*20)*5
					local newlengthtoplayer = (player.Position-(npc.Position+vel*12)):Length()
					local grid = room:GetGridEntity(room:GetGridIndex(vel))
					if not grid or grid and grid.Desc.Type == GridEntityType.GRID_DECORATION then
						grid = "none"
					end
					if grid == "none" and newlengthtoplayer > currentlengthtoplayer and newlengthtoplayer > distancefromplayer then
						distancefromplayer = newlengthtoplayer
						bestdir = i*20
					end
				end
				if data.Chains ~= 0 then -- chooses hop animation based on how many chains it has
					sprite:Play("Hop"..tostring(data.Chains).."Chains", true)
				else
					sprite:Play("Hop", true)
				end
				if bestdir ~= -1 then -- set velocity, and some randomness to the hop
					npc.Velocity = Vector.FromAngle(bestdir+(math.random()-0.5)*40)*5
				end
			end
		elseif data.Chains == 0 and not isbreakingchain then -- turning into item pedestal mode
			npc.CollisionDamage = 0
			npc:ClearEntityFlags(EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
			npc.Velocity = npc.Velocity*0.5 -- prevents the chest from sliding over the ground
			if data.SealedItem ~= "none" and not sprite:IsPlaying("ItemPedestal") then -- sets up the item for the player to pick
				sprite:ReplaceSpritesheet(1, "gfx/items/collectibles/"..tostring(data.SealedItem)..".png")
				sprite:LoadGraphics()
				sprite:Play("ItemPedestal", true)
			end
			-- when the player gets close enough to pick up the item
			if sprite:IsPlaying("ItemPedestal") and (player.Position-npc.Position):Length() <= player.Size+npc.Size+2 and CRE.TimerSinceUsedSealedChest == 0 then
				CRE.TimerSinceUsedSealedChest = 43
				local activeitem = player:GetActiveItem()
				local charge = player:GetActiveCharge()
				player:AddCollectible(data.SealedItem, data.SealedItemCharge, false)
				player:AnimateCollectible(data.SealedItem, "Pickup", "PlayerPickup")
				data.SealedItem = "none"
				-- if the player had an active item, and picks up a new active item, put the other active item in the chest
				if activeitem ~= 0 and activeitem ~= player:GetActiveItem() then
					data.SealedItem = activeitem
					data.SealedItemCharge = charge
					sprite:ReplaceSpritesheet(1, "gfx/items/collectibles/"..tostring(data.SealedItem)..".png")
					sprite:LoadGraphics()
				end
			end
			if data.SealedItem == "none" and not sprite:IsFinished("IdleOpen") then
				sprite:SetFrame("IdleOpen", 0)
			end
		end
	end
end, CRE.ENT.SEALED_CHEST.id)

CRE:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, e, dmg, flag, src, invuln) -- preventing the chest from taking damage when it acts as portal
	if e.Variant ~= CRE.ENT.SEALED_CHEST.variant then return end
	if e.HitPoints == 1 then -- chest cannot get under 1 hitpoints, he'll become invulnerable
		return false
	elseif e.HitPoints-dmg < 1 then
		e:TakeDamage(e.HitPoints-1, flag, src, invuln)
		return false
	end
end, CRE.ENT.SEALED_CHEST.id)