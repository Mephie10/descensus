extends Area2D

@export var next_sublevel: PackedScene 

var player_in_range = false

func _process(_delta):

	if player_in_range and Input.is_action_just_pressed("interact"):
		if next_sublevel != null:
			
			var enemies_in_level = get_tree().get_nodes_in_group("enemies")
			for enemy in enemies_in_level:
				var data_packet = {
					"position": enemy.global_position,
					"hp": enemy.current_health
				}
				Global.enemy_data[str(enemy.get_path())] = data_packet
				
			Global.save_checkpoint()
			TransitionScreen.change_scene(next_sublevel)
		else:
			print("Fehler: Du hast vergessen, das nächste Level im Inspektor einzutragen!")


func _on_body_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body):
	if body.name == "Player" or body.is_in_group("player"):
		player_in_range = false
