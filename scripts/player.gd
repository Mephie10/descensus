extends CharacterBody2D

const SPEED = 175.0

@onready var anim = $AnimatedSprite2D
@onready var hitbox = $Hitbox 
@onready var hitbox_shape = $Hitbox/CollisionShape2D 

var last_dir = "down" 
var is_attacking = false 

func _process(_delta):
	# Blockiert die Bewegung
	if is_attacking:
		return 

	# Angriff auslösen
	if Input.is_action_just_pressed("attack"):
		attack()
		return

	# Bewegung einlesen
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if direction != Vector2.ZERO:
		velocity = direction * SPEED
		
		# Links / Rechts laufen
		if direction.x > 0:
			anim.flip_h = false
			anim.play("run_side")
			last_dir = "side"
		elif direction.x < 0:
			anim.flip_h = true
			anim.play("run_side")
			last_dir = "side"
			
		# Oben / Unten laufen
		elif direction.y > 0:
			anim.flip_h = false 
			anim.play("run_down")
			last_dir = "down"
		elif direction.y < 0:
			anim.flip_h = false 
			anim.play("run_up")
			last_dir = "up"
			
	else:
		velocity = Vector2.ZERO
		
		# Idle-Animationen je nach letzter Blickrichtung
		if last_dir == "side":
			anim.play("idle_side")
		elif last_dir == "down":
			anim.flip_h = false 
			anim.play("idle_down")
		elif last_dir == "up":
			anim.flip_h = false 
			anim.play("idle_up")

	move_and_slide()

func attack():
	is_attacking = true
	velocity = Vector2.ZERO 
	
	# Animation starten und Hitbox passend verschieben
	if last_dir == "side":
		anim.play("attack_side")
		hitbox.position = Vector2(-20, 0) if anim.flip_h else Vector2(20, 0)
		
	elif last_dir == "down":
		anim.flip_h = false 
		anim.play("attack_down")
		hitbox.position = Vector2(0, 10)
		
	elif last_dir == "up":
		anim.flip_h = false 
		anim.play("attack_up")
		hitbox.position = Vector2(0, 0)
		
	
	await get_tree().create_timer(0.25).timeout
		
	# Erst JETZT wird die Hitbox für den Treffer aktiv geschaltet
	hitbox_shape.set_deferred("disabled", false)
		
	# Wartet, bis die Animation komplett zu Ende gelaufen ist
	await anim.animation_finished
	
	# Hitbox wieder ausschalten und aufräumen
	hitbox_shape.set_deferred("disabled", true) 
	hitbox.position = Vector2.ZERO 
	is_attacking = false

# Kollisions-Erkennung für Gegner und Fässer
func _on_hitbox_body_entered(body):
	if body.is_in_group("enemies"):
		print("Gegner getroffen: ", body.name)
		
	elif body.is_in_group("destructibles"):
		body.smash()
