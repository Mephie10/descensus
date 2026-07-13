extends StaticBody2D

@onready var intact_sprite = $IntactSprite
@onready var rubble_sprite = $RubbleSprite
@onready var collision = $CollisionShape2D
@onready var silver_coin: Area2D = $SilverCoin

var is_destroyed = false

func smash():
	if is_destroyed:
		return
		
	is_destroyed = true
	
	intact_sprite.hide()
	rubble_sprite.show()
	silver_coin.show()
	
	$NavigationObstacle2D.avoidance_enabled = false
	
	collision.set_deferred("disabled", true)
