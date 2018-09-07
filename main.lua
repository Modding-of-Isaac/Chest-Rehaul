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
	ROLLING_COIN = ent("Rolling Coin")
}

CRE:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
	math.randomseed(Isaac.GetTime())
	Isaac.SaveModData(CRE, json.encode(CRE.DATA))
end)

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