extends Control

const LEVEL_SELECT_SCENE = "res://scenes/UI/level_select.tscn"
const CONTROLS_SCENE = "res://scenes/UI/controls_screen.tscn"

func _ready():
	# Falls man aus einem laufenden Spiel zurückkommt, ist der Baum evtl. noch
	# pausiert und der Cursor versteckt.
	get_tree().paused = false
	Global.set_menu_cursor()

func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)

func _on_controls_button_pressed() -> void:
	get_tree().change_scene_to_file(CONTROLS_SCENE)

func _on_quit_button_pressed() -> void:
	get_tree().quit()
