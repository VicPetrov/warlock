--- Pawn - hero actor
-- @author Krzysztof Lis (Adynathos)

Pawn = class(Actor)
Pawn.WALK_SPEED = 1000
Pawn.WALK_SPEED_SQ = Pawn.WALK_SPEED*Pawn.WALK_SPEED

function Pawn:init(def)
	-- initial state
	def.name = "pawn_player_"..def.owner.id
	def.location = def.unit:GetAbsOrigin()
	def.location.z = Config.GAME_Z
	def.mass = 100

	-- actor constructor
	Pawn.super.init(self, def)

	-- coll component
	self:addCollisionComponent{
		id 					= 'pawn',
		channel 			= def.coll_channel or CollisionComponent.CHANNEL_PLAYER,
		coll_mat = CollisionComponent.createCollMatSimple(
			{Player.ALLIANCE_ENEMY, Player.ALLIANCE_ALLY},
			{CollisionComponent.CHANNEL_PLAYER , CollisionComponent.CHANNEL_PROJECTILE, CollisionComponent.CHANNEL_OBSTACLE}),
		radius 				= 30,
		ellastic 			= true,
		ellasticity 		= 0.5
	}

	-- Pawn data structures
	self.walk_velocity = Vector(0, 0, 0)

	-- Prepare unit
	self.unit:SetMinimumGoldBounty(Config.CASH_REWARD_KILL)
	self.unit:SetMaximumGoldBounty(Config.CASH_REWARD_KILL)

	-- Set max level
	for i = 1, Config.MAX_LEVEL do
		self.unit:HeroLevelUp(false)
	end

	self.unit:SetAbilityPoints(0)

	-- Stats
	self.kb_factor = 1
	self.dmg_factor = 1
	self.dmg_reduction = 0
	self.max_hp = Config.PAWN_MAX_LIFE
	self.move_speed = Config.PAWN_MOVE_SPEED
	self.hp_regen = Config.PAWN_HEALTH_REG
	self.health = self.max_hp

	-- Model scale
	self.unit:SetModelScale(Config.PAWN_MODEL_SCALE)

	add_start_item(self.unit,"item_warlock_fireball",1,def.owner.id)
	add_start_item(self.unit,"item_warlock_scourge",0,def.owner.id)
	
	self:respawn()
end

function Pawn:enable()
	Pawn.super.enable(self)

	GAME.pawns:add(self)
end

function Pawn:disable()
	Pawn.super.disable(self)

	GAME.pawns:remove(self)
end

function Pawn:applyStats()
	local u = self.unit
	u:SetBaseMoveSpeed(math.max(0, self.move_speed))
	u:SetMaxHealth(self.max_hp)
	u:SetBaseHealthRegen(self.hp_regen)
	u:SetHealth(self.health)
end

function Pawn:setHealth(health)
	if(health > self.max_hp) then
		self.health = self.max_hp
	else
		self.health = health
	end

	self.unit:SetHealth(health)
end


-- Methods for adding and removing native modifiers, stats need to be reapplied after
-- because they get reset by dota
function Pawn:addNativeModifier(mod_name)
	self.unit:AddNewModifier(self.unit, nil, mod_name, nil)
	self:applyStats()
end

function Pawn:removeNativeModifier(mod_name)
	self.unit:RemoveModifierByName(mod_name)
	self:applyStats()
end

function Pawn:respawn()
	self.velocity = Vector(0, 0, 0)
	self.walk_velocity = Vector(0, 0, 0)
	self.location = GAME:getRespawnLocation(self)
	self.last_hitter = nil

	self:enable()

	if not self.unit:IsAlive() then
		self.unit:RespawnHero(false, false, false)
		--GAME.team_alive_count[self.owner.team] = (GAME.team_alive_count[self.owner.team] or 0) + 1
	end
	

	if self.unit:HasModifier(Config.ABILITY_KILL_MODIFIER) then
		warning("Pawn has DOOM modifier during respawn")
		self.unit:RemoveModifier(Config.ABILITY_KILL_MODIFIER)
	end

	self.unit:SetMana(0)
	self:resetCooldowns()
	self.health = self.max_hp
	self:applyStats()
	
end

function Pawn:die(dmg_info)
	local source_actor = nil
	local source_unit = nil

	if dmg_info.source then
		source_actor = dmg_info.source

	elseif self.last_hitter then
		-- lava damage - becasue it has not source
		source_actor = self.last_hitter
	else
		source_actor = self
	end

	source_unit = source_actor.unit

	killUnitWithNativeDamage(self.unit, source_unit)

	-- disable the actor
	self:disable()

	GAME:PawnKilled{victim=self, killer=source_actor}
end

function Pawn:resetCooldowns()
	-- Reset spell cds
	for spell_name, _ in pairs(Spell.spells) do
		local abil = self.unit:FindAbilityByName(spell_name)

		if abil then
			abil:EndCooldown()
		end
	end
	
	-- Reset item cds
	for slot = 0, 5 do
		local item = self.unit:GetItemInSlot(slot)
		if item then
			item:EndCooldown()
		end
	end
end

function Pawn:_updateLocation()
	self.unit:SetAbsOrigin(self.location + Config.PAWN_OFFSET )
end

function Pawn:increaseKBPoints(amount)
	local kb_points = self.unit:GetMana()
	kb_points = kb_points + amount
	self.unit:SetMana(kb_points)
end

function Pawn:receiveDamage(dmg_info)
	--print("DMG receive from ", dmg_info.source, " unit = ", dmg_info.source.unit)

	if not GAME.combat then
		return
	end
	
	if not self.enabled then
		return
	end
	
	if self.invulnerable then
		return
	end

	-- Modifier damage change
	dmg_info.amount = dmg_info.amount * self.dmg_factor
	dmg_info.amount = dmg_info.amount - self.dmg_reduction
	if(dmg_info.amount <= 0) then
		return
	end

	-- Allow modifiers to have a final decision on damage
	dmg_info.amount = dmg_info.amount + GAME:modDamageTaken(self, dmg_info)
	if(dmg_info.amount <= 0) then
		return
	end

	-- kb points
	self:increaseKBPoints(dmg_info.amount * (dmg_info.knockback_vulnerability_factor or 1))

	if dmg_info.hit_normal then
		-- Knockback
		local kb_points = self.unit:GetMana()
		local kb_amount = math.max(0, self.kb_factor) * dmg_info.amount * Config.KB_DMG_TO_VELOCITY * (1 + kb_points/1000) * (dmg_info.knockback_factor or 1)
		self:applyMomentum(kb_amount*dmg_info.hit_normal*self.mass)
	end

	dmg_info.amount = dmg_info.amount + GAME:modDamagePostKB(self, dmg_info)

	if dmg_info.source and dmg_info.source.owner then
		dmg_info.source.owner.damage = dmg_info.source.owner.damage + dmg_info.amount
	end
	
	if dmg_info.source then
		self.last_hitter = dmg_info.source

		-- Display damage text
		GAME:showFloatingNum {
			num = dmg_info.amount,
			location = self.location,
			duration = 1,
			color = dmg_info.text_color or Vector(255, 50, 50)
		}
	end

	-- Set life
	local life = self.health - dmg_info.amount

	if life > 0 then
		self.health = life
		self.unit:SetHealth(life)
	else
		self.health = 0
		self:die(dmg_info)
	end
end

function Pawn:onPreTick(dt)
	-- remove previous walk vel
	self.velocity = self.velocity - self.walk_velocity

	-- apply friction
	self.velocity = self.velocity * Config.FRICTION

	-- get new walk velocity
	self.walk_velocity = (self.unit:GetAbsOrigin() - self.location)/dt
	self.walk_velocity.z = 0

	if self.walk_velocity:Dot(self.walk_velocity) > self.WALK_SPEED_SQ then
		self.walk_velocity = self.walk_velocity:Normalized() * self.WALK_SPEED
	end

	-- add new walk vel
	self.velocity = self.velocity + self.walk_velocity
	
	-- pretick for modifiers
	GAME:modOnPreTick(self, dt)
end

function Pawn:onPostTick(dt)
	if self.unit:IsAlive() then
		self.health = math.min(self.max_hp, self.health + self.hp_regen * dt)
	end
end

--- utility damage
-- requires: dmg_info.amount or dmg_info.amount_min and dmg_info.amount_max
function Pawn:damageArea(target, radius, dmg_info)
	dmg_info.source = self

	local b_scaled = (dmg_info.amount_min ~= nil and dmg_info.amount_max ~= nil)
	local kb_scaled = (dmg_info.kb_factor_min ~= nil and dmg_info.kb_factor_max ~= nil)

	local dmg_base = dmg_info.amount_min
	local dmg_gain = nil

	if b_scaled then
		dmg_gain = (dmg_info.amount_max - dmg_base) / radius
	end
	
	local count = 0
	
	for pawn, _ in pairs(GAME.pawns) do
		if pawn.enabled and self.owner:getAlliance(pawn.owner) == Player.ALLIANCE_ENEMY then
			local diff = pawn.location - target
			diff.z = 0

			local dst = diff:Length()

			if dst < radius then
				dmg_info.hit_normal = diff:Normalized()
				
				count = count + 1
				
				if b_scaled then
					dmg_info.amount = dmg_base + dmg_gain * (radius - dst)
				end

				-- Linearly interpolate knockback factor between min and max
				if kb_scaled then
					local t = 1 - dst / radius
					dmg_info.knockback_factor = (1 - t) * dmg_info.kb_factor_min + t * dmg_info.kb_factor_max
				end
				
				pawn:receiveDamage(dmg_info)
			end
		end
	end
	
	return count 
end

function add_start_item(unit,abil_name,i,id)
	ItemID[id][i] = CreateItem( abil_name, unit, unit)
	WarlockItems[id][i] = nil
	ItemLevel[id][i] = 0
	AbilityLevel[id][i] = 0
	unit:AddItem(ItemID[id][i])
end

function add_and_set_level(unit, abil_name, level)
	if not unit:HasAbility(abil_name) then
		unit:AddAbility(abil_name)
	end

	local abil = unit:FindAbilityByName(abil_name)
	abil:SetLevel(level)
end

--- Kills a unit using native mechanisms
-- The killer is given the ability doom and scripts apply the doom debuff
-- to the victim, which ensured the kill
-- The previous approach with casting an ability sometimes failed.
function killUnitWithNativeDamage(victim, killer)

	-- create a casting unit
	local killer_unit = CreateUnitByName(Config.LOCUST_UNIT, Vector(0,0,0), false, killer, killer, killer:GetTeamNumber())
	killer_unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
	killer_unit:AddNewModifier(unit, nil, "modifier_phased", {})

	-- give it the doom ability
	local kill_ability_name = Config.ABILITY_KILL
	killer_unit:AddAbility(kill_ability_name)
	local kill_ability = killer_unit:FindAbilityByName(kill_ability_name)
	kill_ability:SetLevel(1)

	-- Ensure hes low on life
	victim:SetHealth(1)

	-- Add the doom debuff reliably
	victim:AddNewModifier(killer_unit, kill_ability, Config.ABILITY_KILL_MODIFIER, {})

	-- remove the casting unit
	GAME:addTask{id="remove_killer_unit", time=0.5, func=function()
		killer_unit:Destroy()
	end}
end

function Game:filterPawns(filter)
	local pawns = {}

	if(not filter) then
		log("Warning: filter in filterPawns was nil, returning empty list")
		return pawns
	end

	for pawn, _ in pairs(GAME.pawns) do
		if(filter(pawn)) then
			table.insert(pawns, pawn)
		end
	end

	return pawns
end