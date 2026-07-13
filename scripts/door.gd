extends Area2D

@export_file("*.tscn") var next_sublevel_path: String

var player_in_range = false

func _process(_delta):
	if player_in_range and Input.is_action_just_pressed("interact"):
		if next_sublevel_path != "":
			Global.save_checkpoint()
			TransitionScreen.change_scene(next_sublevel_path)
		else:
			print("Fehler: Du hast vergessen, das nächste Level im Inspektor einzutragen!")

func _on_body_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body):
	if body.name == "Player" or body.is_in_group("player"):
		player_in_range = false
