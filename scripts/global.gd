extends Node

var player_current_health = 100.0
var player_total_coins = 0
var checkpoint_health = 100.0
var checkpoint_coins = 0

func save_checkpoint():
	checkpoint_health = player_current_health
	checkpoint_coins = player_total_coins

func load_checkpoint():
	player_current_health = checkpoint_health
	player_total_coins = checkpoint_coins
