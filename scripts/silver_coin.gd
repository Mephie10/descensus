extends Area2D

func _on_body_entered(_body: Node2D) -> void:
	print("+1 silver coin!")
	queue_free()
