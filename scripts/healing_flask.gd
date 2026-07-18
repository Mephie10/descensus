extends Area2D

func _ready():
	# Schon eingesammelt -> nicht mehr anzeigen
	if Global.collected_pickups.has(Global.object_id(self)):
		queue_free()
		return
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.name != "Player" and not body.is_in_group("player"):
		return

	if not body.has_method("can_collect_healing_flask") or not body.can_collect_healing_flask():
		return

	body.add_healing_flask()
	Global.collected_pickups.append(Global.object_id(self))
	queue_free()
