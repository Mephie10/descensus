extends Control

const MAIN_MENU_SCENE = "res://scenes/UI/main_menu.tscn"

@onready var coin_label = $Panel/CoinLabel

func _ready():
	get_tree().paused = false
	Global.set_menu_cursor()

	# Der Fortschritt wird bewusst erst beim Verlassen verworfen, sonst stünde
	# hier immer eine 0.
	coin_label.text = str(Global.player_total_coins)

func _on_back_button_pressed() -> void:
	Global.reset_progress()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
