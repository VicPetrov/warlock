--- Base mode
-- @author Krzysztof Lis (Adynathos)

Mode = class()
Mode.SHOP_TIME = 20
Mode.ROUND_NUMBER = 11
Mode.OBSTACLE_COUNT_MIN = 2
Mode.OBSTACLE_COUNT_MAX = 8

function Mode:roundName(round_to_print)
	return 'Round ' .. (round_to_print or self.round or 0)
end

function Mode:init()
	self.round = 0
end

function Mode:onStart()

	for id, player in pairs(GAME.players) do
		player:setCash(Config.CASH_ON_START)
	end
	
	self:prepareForRound()
end

function Mode:prepareForRound()
	GAME:setCombat(false)
	GAME:removeProjectiles()
	GAME:setShop(true)
	GAME.arena:setAutoShrink(false)
	
	-- obstacles
	GAME:clearObstacles()
	GAME:setRandomObstacleVariation()
	Arena:setPlatformType(Obstacle.variation) -- arena platform type matches obstacle variation
	GAME.arena:setLayer(0) -- delete the remaining tiles (to create new platform type)
	GAME.arena:setLayer(16) -- corresponding to 1 player
	GAME:addRandomObstacles(math.random(Mode.OBSTACLE_COUNT_MIN, Mode.OBSTACLE_COUNT_MAX))

	for id, player in pairs(GAME.players) do
		if player.pawn then
			player.pawn:respawn()
			player.pawn.unit:SetAbilityPoints(1)
		end
	end

	GAME:addTask{
		id='round start',
		time=self.SHOP_TIME,
		func= function()
			self:onRoundStart()
		end
	}

 	-- Every 5 s print time till shoptime ends
	local shoptime_end = GAME:time() + self.SHOP_TIME

	local function print_shoptime_countdown()
		local time_to_round_start = math.ceil(shoptime_end - GAME:time())
		display(self:roundName(self.round+1) ..' in ' .. time_to_round_start .. 's')
	end

	for t = 0, self.SHOP_TIME-1, 5 do
		GAME:addTask{
			id='shoptime countdown',
			time=t,
			func=print_shoptime_countdown
		}
	end

	-- Print the last 3 seconds bigger
	local function print_shoptime_final_countdown()
		local time_to_round_start = math.ceil(shoptime_end - GAME:time())
		GAME:showMessage(tostring(time_to_round_start), 0.7)
	end

	for t = self.SHOP_TIME-3, self.SHOP_TIME-1 do
		GAME:addTask{
			id='shoptime final countdown',
			time=t,
			func=print_shoptime_final_countdown
		}
	end

	GAME:addTask{
		id="shoptime help",
		time = 1,
		func=function()
			display('Buy new spells in the shop')
			display('Assign ability points to buy spell upgrades (remember this costs money)')
		end
	}

	GAME:addTask {
		id ='shoptime fight',
		time = self.SHOP_TIME,
		func = function()
			GAME:showMessage("FIGHT!", 1.0)
		end
	}

	-- Show SHOPTIME message at the top
	GAME:showMessage("SHOPTIME", self.SHOP_TIME - 5)
end

function Mode:onRoundStart()

	self.round = self.round + 1
	display(self:roundName())

	GAME:setShop(false)
	GAME:removeProjectiles()
	GAME:setCombat(true)

	for id, player in pairs(GAME.players) do
		if player.pawn then
			player.pawn:respawn()
			player.pawn.unit:SetAbilityPoints(0)
		end
		player.damage = 0
	end
	
	-- initial invul
	for pawn, _ in pairs(GAME.pawns) do
		pawn:addNativeModifier("modifier_omninight_guardian_angel")
		pawn.invulnerable = true
	end
	
	-- remove initial invul after some time
	GAME:addTask {
		time = 2,
		func = function()
			for pawn, _ in pairs(GAME.pawns) do
				pawn:removeNativeModifier("modifier_omninight_guardian_angel")
				pawn.invulnerable = false
			end
		end
	}
    
	
	GAME.arena:setLayer(15+GAME.player_count*1)
	GAME.arena:setAutoShrink(true)

	-- modifier event
	GAME:modOnReset()
end

function Mode:onRoundWon(winner_team)
	GAME:setCombat(false)

	GAME:addTask{
		id='round end',
		time=2,
		func=function()
			self:onRoundEnd()
		end}

	if winner_team then
		display('Team '.. GAME:teamName(winner_team) .. ' has won the round')
		
		-- Get player that dealt the highest damage
		local highest_dmg = -1
		local highest_dmg_player
		for id, player in pairs(GAME.players) do
			if player.damage > highest_dmg then
				highest_dmg = player.damage
				highest_dmg_player = player
			end
		end
		
		if highest_dmg_player and highest_dmg > 0 then
			local dmg_text = string.format("%.0f", highest_dmg)
			display(highest_dmg_player.name .. " has dealt the highest damage (" .. dmg_text .. ")")
		end
		
		GAME:addTeamScore(winner_team, 1)

		-- rewards for winning
		for id, player in pairs(GAME.players) do
			if player.team == winner_team then
				player:addCash(Config.CASH_REWARD_WIN_ROUND)
			end
		end
	else
		display('Draw')
	end
end

function Mode:onRoundEnd()
	display(self:roundName()..' has ended')

	-- rewards for ending the round
	for id, player in pairs(GAME.players) do
		player:addCash(Config.CASH_EVERY_ROUND)
	end

	--if self.round < self.ROUND_NUMBER then

	-- Best of X, first to win floor(X/2)+1 wins game (usually 11 and 6)
	local game_end = false
	for team, alives in pairs(GAME.team_alive_count) do
		if GAME:getTeamScore(team) > math.floor(self.ROUND_NUMBER / 2) then
			game_end = true
			break
		end
	end

	if not game_end then
		self:prepareForRound()
	else
		-- that was the last round, display end game
		self:onGameEnd()
	end
end

function Mode:onGameEnd()
	-- find the winning team
	local winner_team = nil
	local best_score = 0

	for team, score in pairs(GAME.team_score) do
		if score > best_score then
			winner_team = team
			best_score = score
		end
	end

	if winner_team then
		display("TEAM "..string.upper(GAME:teamName(winner_team)).." HAS WON THE GAME.")
		GameRules:SetGameWinner(winner_team)
	else
		display("THE GAME ENDS IN A DRAW")
	end
	
	display("If you have found any bugs or have feedback please visit us at warlockbrawl.com or the d2modd.in forums.")
end

function Mode:onKill(event)
	-- give reward for kill
	if event.killer and event.killer.owner and event.killer ~= event.victim then
		local player_to_reward = event.killer.owner

		-- the player may get some naive rewards, so update his cash
		-- after that potentially happens
		GAME:addTask{
			time = 1,
			func = function()
				player_to_reward:addCash(Config.CASH_REWARD_KILL)
			end
		}
	end
end

function Mode:getRespawnLocation(pawn)
	--playerteams are 2 and 3, make them 0 and 1
	local team = pawn.owner.team % 2
	local radius = 650 + 50 * GAME.player_count

	-- Spawn teams at top and bottom with an offset for each player
	local angle = math.pi * team + math.pi / 2.0
	local angle_offset = 0.2 * (pawn.owner.team_player_index - (GAME.team_size[pawn.owner.team]-1) / 2.0)
	angle = angle + angle_offset

	return Vector(radius * math.cos(angle), radius * math.sin(angle), Config.GAME_Z)
end

ModeLTS = class(Mode)
ModeLTS.ROUND_NUMBER = 11

-- check for victory conditions
function ModeLTS:onKill(event)
	ModeLTS.super.onKill(self, event)

	if GAME.combat then
		local winner_team = nil
		local b_one_team_left = true

		for team, alives in pairs(GAME.team_alive_count) do
			if alives > 0 then
				if winner_team == nil then
					winner_team = team
				else
					b_one_team_left = false
				end
			end
		end

		if b_one_team_left then
			self:onRoundWon(winner_team)
		end
	end
end