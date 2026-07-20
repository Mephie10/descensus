extends CanvasLayer

const MAIN_MENU_SCENE = "res://scenes/UI/main_menu.tscn"

func _ready():
	hide()

func _unhandled_input(event):

	if event.is_action_pressed("ESC"):
		toggle_pause()

func toggle_pause():

	var is_paused = not get_tree().paused
	get_tree().paused = is_paused

	if is_paused:
		show()
		Global.set_menu_cursor()
	else:
		hide()
		Global.set_gameplay_cursor()


func _on_resume_button_pressed() -> void:
	toggle_pause()

func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	Global.reset_progress()
	Global.set_menu_cursor()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_restart_button_pressed():
	Global.load_checkpoint()
	get_tree().paused = false
	Global.set_gameplay_cursor()
	TransitionScreen.reload_scene()
