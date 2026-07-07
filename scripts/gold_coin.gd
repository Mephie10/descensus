extends Area2D

func _on_body_entered(_body: Node2D) -> void:
	print("+1 gold coin!")
	queue_free()
