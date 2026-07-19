extends Area2D

var collected = false

func _ready():
	# Schon eingesammelt -> nicht mehr anzeigen
	if Global.collected_pickups.has(Global.object_id(self)):
		collected = true
		queue_free()

func _on_body_entered(body):
	if collected:
		return

	if body.name == "Player" or body.is_in_group("player"):
		if body.has_method("add_coins"):
			collected = true
			Global.collected_pickups.append(Global.object_id(self))
			body.add_coins(2)
			queue_free()
