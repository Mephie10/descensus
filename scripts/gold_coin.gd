extends Area2D

func _on_body_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		if body.has_method("add_coins"):
			body.add_coins(5)
			queue_free()

func _ready():
	if Global.destroyed_objects.has(str(get_path())):
		queue_free()
