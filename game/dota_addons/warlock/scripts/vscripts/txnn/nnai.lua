NNAI = class()

function NNAI:init(def)
    self.player = def.player
    self.pawn = self.player.pawn

    self.total_rewards = {}
    self.q_history = {}
    self.q_episode = {}

    self.think_interval = def.think_interval

    self.action_size = 6
    self.state_size = 17 + self.action_size

    self.learner = SDRRL:new(self.state_size, self.action_size, 128)

    -- Add think task
    self.ai_task = GAME:addTask {
        id = "nnai controller " .. tostring(self.player.id),
        period = self.think_interval,
        func = function()
            self:think(self.think_interval)
        end
    }

    self.last_action = {}
    for i = 1, self.action_size do
        self.last_action[i] = 0
    end

    -- Find fireball and scourge
    for i = 0, 5 do
        local item = self.pawn.unit:GetItemInSlot(i)
        
        if item then
            local item_name = item:GetAbilityName()

            if item_name == "item_warlock_fireball1" then
                log("Found fireball in slot " .. tostring(i))
                self.fireball = item
            end

            if item_name == "item_warlock_scourge1" or item_name == "item_warlock_scourge2" or item_name == "item_warlock_scourge3" then
                log("Found scourge in slot " .. tostring(i))
                self.scourge = item
            end
        end
    end

    self.waiting = true
end

function NNAI:destroy()
    GAME.ai_controllers[self.player] = nil
    self.ai_task:cancel()
end

function NNAI:getState()
    local state = {}

    self.enemy_pawn = self:getClosestEnemyPawn()

    state[1] = self.pawn.location.x / 2000.0
    state[2] = self.pawn.location.y / 2000.0
    state[3] = self.pawn.health / 1000.0
    state[4] = self.pawn.unit:GetMana() / 1000.0
    state[5] = self.enemy_pawn and self.enemy_pawn.location.x / 2000.0 or 0
    state[6] = self.enemy_pawn and self.enemy_pawn.location.y / 2000.0 or 0
    state[7] = self.enemy_pawn and self.enemy_pawn.health / 1000.0 or 0
    state[8] = self.pawn.unit:GetMana() / 1000.0
    state[9] = self.enemy_pawn and self.enemy_pawn.velocity.x / 2000.0 or 0
    state[10] = self.enemy_pawn and self.enemy_pawn.velocity.y / 2000.0 or 0
    state[11] = self.enemy_pawn and self.enemy_pawn.walk_velocity.x / Config.PAWN_MOVE_SPEED or 0
    state[12] = self.enemy_pawn and self.enemy_pawn.walk_velocity.y / Config.PAWN_MOVE_SPEED or 0
    state[13] = self.fireball:GetCooldownTimeRemaining() / 4.8
    state[14] = self.pawn.velocity.x / 2000.0
    state[15] = self.pawn.velocity.y / 2000.0
    state[16] = self.pawn.walk_velocity.x / Config.PAWN_MOVE_SPEED
    state[17] = self.pawn.walk_velocity.y / Config.PAWN_MOVE_SPEED

    for i = 1, self.action_size do
        state[self.state_size - self.action_size + i] = self.last_action[i]
    end

    return state
end

function NNAI:executeAction(action)
    -- Action from 0 to 1 for x and y
    -- Move relative to the character
    local target = self.pawn.location + 500 * 2 * Vector(action[1] - 0.5, action[2] - 0.5, 0)
    self.pawn.unit:MoveToPosition(target)

    if action[3] == 1 and self.fireball:IsFullyCastable() then
        local fb_target = self.pawn.location + 500 * 2 * Vector(action[4] - 0.5, action[5] - 0.5, 0)
        self.pawn.unit:CastAbilityOnPosition(fb_target, self.fireball, self.player.id)
    elseif action[6] == 1 and self.scourge:IsFullyCastable() then
        self.pawn.unit:CastAbilityNoTarget(self.scourge, self.player.id)
    end
end

function NNAI:think()
    if not self.active then
        if self.player:isAlive() and GAME.combat then
            self.active = true
        else
            return
        end
    end
    
    local state = self:getState()

    local is_terminal = false
    local reward = 0

    -- Check if we are running but dead
    if self.active and not self.player:isAlive() then
        is_terminal = true
        reward = -5
    elseif self.active and not GAME.combat then
        is_terminal = true
        reward = 5
    end

    if self.prev_state then
        -- Subtract the lost hp from reward
        if state[3] < self.prev_state[3] then
            reward = reward - 10 * (self.prev_state[3] - state[3])
        end

        -- Subtract the lost mana from reward
        if state[4] > self.prev_state[4] then
            reward = reward + 10 * (self.prev_state[4] - state[4])
        end

        -- Add the lost hp to reward
        if state[7] < self.prev_state[7] then
            reward = reward + 10 * (self.prev_state[7] - state[7])
        end

        -- Subtract the lost mana from reward
        if state[8] > self.prev_state[8] then
            reward = reward - 10 * (self.prev_state[8] - state[8])
        end
    end

    if not self.pawn.on_lava then
        reward = reward + 0.01 * self.think_interval
    end

    self.total_reward = (self.total_reward or 0) + reward

    print("Reward:", reward)

    -- Inform the learner of the new state
    self.learner:update(state, reward, is_terminal)

    table.insert(self.q_episode, self.learner.prev_q)

    -- Execute a new action if we are not done
    if not is_terminal then
        local action = self.learner:getAction()

        -- Save the action as the last action
        self.last_action = {}
        for i = 1, #action do
            self.last_action[i] = action[i]
        end

        print("Action:")
        PrintTable(action)
        self:executeAction(action)

        self.prev_state = state
    else
        -- Save reward history
        table.insert(self.total_rewards, self.total_reward)
        self.total_reward = 0

        -- Save Q history
        table.insert(self.q_history, self.q_episode)
        self.q_episode = {}

        -- Reset last actions
        for i = 1, self.action_size do
            self.last_action[i] = 0
        end

        self.prev_state = nil

        -- Set inactive
        self.active = false
    end
end

-- Gets the closest enemy
function NNAI:getClosestEnemyPawn()
    local min_dist_sq = 99999999
	local min_pawn = nil
	
	-- Get closest enemy pawn
	for pawn, _ in pairs(GAME.pawns) do
		if pawn.owner.is_bot and pawn.owner:getAlliance(self.player) == Player.ALLIANCE_ENEMY then
			local dir = pawn.location - self.pawn.location
			local dist_sq = dir:Dot(dir)
			if dist_sq < min_dist_sq then
				min_dist_sq = dist_sq
				min_pawn = pawn
			end
		end
	end

    return min_pawn
end