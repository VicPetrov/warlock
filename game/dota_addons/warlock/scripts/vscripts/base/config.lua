--- Configs
-- @author Krzysztof Lis (Adynathos)


Config = {}

Config.GAME_START_TIME				= 10

Config.GAME_TICK_RATE 				= 0.035
Config.GAME_CAMERA_DISTANCE 		= 1100
Config.GAME_Z 						= 120
Config.GAME_ARENA_RADIUS 			= 5910
Config.GAME_ARENA_RADIUS_SQ 		= Config.GAME_ARENA_RADIUS*Config.GAME_ARENA_RADIUS

Config.CASH_REWARD_KILL 			= 0
Config.CASH_REWARD_WIN_ROUND		= 0
Config.CASH_EVERY_ROUND				= 10
Config.CASH_ON_START				= 30

Config.PAWN_HERO 					= 'npc_dota_hero_warlock' --'npc_dota_hero_invoker'
Config.PAWN_MAX_LIFE 				= 1000
Config.PAWN_MOVE_SPEED				= 210
Config.PAWN_HEALTH_REG				= 5.0
Config.PAWN_MODEL_SCALE				= 0.75
Config.PAWN_OFFSET 					= Vector(0, 0, -55)
Config.KB_DMG_TO_VELOCITY 			= 10.0

Config.LOCUST_UNIT 					= "npc_dummy_unit"
--Config.ABILITY_KILL 				= "warlock_tech_kill"

-- see killUnitWithNativeDamage in base/pawn
Config.ABILITY_KILL 				= "doom_bringer_doom"
Config.ABILITY_KILL_MODIFIER		= "modifier_doom_bringer_doom"


Config.DEVELOPMENT 					= true
Config.MAX_LEVEL					= 100

Config.OBSTACLE_MAX_COORD			= 1000

Config.FRICTION = 0.96