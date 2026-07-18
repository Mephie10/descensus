extends StaticBody2D

@onready var intact_sprite = $IntactSprite
@onready var rubble_sprite = $RubbleSprite
@onready var shadow = $Shadow
@onready var collision = $CollisionShape2D
@onready var gold_coin: Area2D = $GoldCoin

var is_destroyed = false

func _ready():
	# Zerstörten Zustand wiederherstellen (Coin entfernt sich selbst, falls schon gesammelt)
	if Global.destroyed_barrels.has(Global.object_id(self)):
		is_destroyed = true
		_show_destroyed()

func smash():
	if is_destroyed:
		return

	is_destroyed = true
	Global.destroyed_barrels.append(Global.object_id(self))
	_show_destroyed()

# --- Zerstörte Optik ---
func _show_destroyed():
	intact_sprite.hide()
	rubble_sprite.show()
	shadow.hide()
	gold_coin.show()
	$NavigationObstacle2D.avoidance_enabled = false
	collision.set_deferred("disabled", true)
