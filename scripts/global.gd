extends Node

var player_current_health = 100.0
var player_total_coins = 0
var checkpoint_health = 100.0
var checkpoint_coins = 0
var destroyed_objects: Array = []
var checkpoint_destroyed_objects: Array = []
var enemy_data: Dictionary = {}
var checkpoint_enemy_data: Dictionary = {}

func save_checkpoint():
	checkpoint_health = player_current_health
	checkpoint_coins = player_total_coins
	checkpoint_destroyed_objects = destroyed_objects.duplicate()
	checkpoint_enemy_data = enemy_data.duplicate(true)

func load_checkpoint():
	player_current_health = checkpoint_health
	player_total_coins = checkpoint_coins
	destroyed_objects = checkpoint_destroyed_objects.duplicate()
	enemy_data = checkpoint_enemy_data.duplicate(true)
