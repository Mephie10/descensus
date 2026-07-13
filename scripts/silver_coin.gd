extends Area2D

func _on_body_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		if body.has_method("add_coins"):
			body.add_coins(1)
			queue_free()
			
