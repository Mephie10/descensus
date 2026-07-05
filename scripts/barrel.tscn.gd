extends StaticBody2D

@onready var intact_sprite = $IntactSprite
@onready var rubble_sprite = $RubbleSprite
@onready var collision = $CollisionShape2D

var is_destroyed = false

func smash():
	if is_destroyed:
		return
		
	is_destroyed = true
	
	intact_sprite.hide()
	rubble_sprite.show()
	
	collision.set_deferred("disabled", true)
