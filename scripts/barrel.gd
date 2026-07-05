extends StaticBody2D

@onready var intact_sprite = $IntactSprite
@onready var rubble_sprite = $RubbleSprite
@onready var collision = $CollisionShape2D

var is_destroyed = false

func smash():
	# Wenn das Fass schon kaputt ist, brechen wir hier ab, 
	# damit der Code nicht unnötig doppelt läuft.
	if is_destroyed:
		return
		
	is_destroyed = true
	
	# Das heile Bild verstecken und den Schutt anzeigen
	intact_sprite.hide()
	rubble_sprite.show()
	
	# Die Kollision sicher ausschalten, damit der Spieler über den Schutt laufen kann
	collision.set_deferred("disabled", true)
