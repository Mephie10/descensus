extends StaticBody2D

@onready var intact_sprite = $IntactSprite
@onready var rubble_sprite = $RubbleSprite
@onready var shadow = $Shadow
@onready var collision = $CollisionShape2D

var is_destroyed = false

func _ready():
	# Zerstörten Zustand wiederherstellen
	if Global.destroyed_barrels.has(Global.object_id(self)):
		is_destroyed = true
		_show_destroyed()

func smash():
	if is_destroyed:
		return

	is_destroyed = true
	Global.destroyed_barrels.append(Global.object_id(self))
	AudioManager.play_at("barrels_destroyed", global_position)
	_show_destroyed()

# --- Zerstörte Optik ---
func _show_destroyed():
	intact_sprite.hide()
	rubble_sprite.show()
	shadow.hide()
	$NavigationObstacle2D.avoidance_enabled = false
	collision.set_deferred("disabled", true)
