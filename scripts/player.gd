extends CharacterBody2D

const SPEED = 160.0

@onready var anim = $AnimatedSprite2D
var last_dir = "down" # Speichert die Blickrichtung für die Idle-Animation

func _physics_process(_delta):
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if direction != Vector2.ZERO:
		velocity = direction * SPEED
		
		# Bewegung auf der X-Achse
		if direction.x > 0:
			anim.flip_h = false
			anim.play("run_side")
			last_dir = "side"
		elif direction.x < 0:
			anim.flip_h = true
			anim.play("run_side")
			last_dir = "side"
			
		# Bewegung auf der Y-Achse
		elif direction.y > 0:
			anim.play("run_down")
			last_dir = "down"
		elif direction.y < 0:
			anim.play("run_up")
			last_dir = "up"
			
	else:
		velocity = Vector2.ZERO
		
		# Spielt die Idle-Animation der letzten Laufrichtung ab
		if last_dir == "side":
			anim.play("idle_side")
		elif last_dir == "down":
			anim.play("idle_down")
		elif last_dir == "up":
			anim.play("idle_up")

	# Führt Bewegung und Wand-Kollision aus
	move_and_slide()
