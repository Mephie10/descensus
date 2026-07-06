extends CharacterBody2D

const SPEED = 110.0

@onready var anim = $AnimatedSprite2D
@onready var hitbox = $Hitbox 
@onready var hitbox_shape = $Hitbox/CollisionShape2D 
@onready var shadow = $Shadow 

var last_dir = "down" 
var is_attacking = false
var max_health = 100.0
var current_health = 100.0
var attack_damage = 25.0
var is_dead = false

func _process(_delta):
	if is_dead:
		return
	
	if is_attacking:
		return 

	if Input.is_action_just_pressed("attack"):
		attack()
		return

	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if direction != Vector2.ZERO:
		velocity = direction * SPEED
		
		# --- BEWEGUNG ---
		if direction.x > 0:
			anim.flip_h = false
			anim.play("run_side")
			last_dir = "right"
			shadow.position = Vector2(0, 7) 
			
		elif direction.x < 0:
			anim.flip_h = true
			anim.play("run_side")
			last_dir = "left"
			shadow.position = Vector2(-4, 7) 
			
		elif direction.y > 0:
			anim.flip_h = false 
			anim.play("run_down")
			last_dir = "down"
			shadow.position = Vector2(-1, 7) 
			
		elif direction.y < 0:
			anim.flip_h = false 
			anim.play("run_up")
			last_dir = "up"
			shadow.position = Vector2(-3, 7) 
			
	else:
		velocity = Vector2.ZERO
		
		# --- STEHEN (IDLE) ---
		if last_dir == "right":
			anim.flip_h = false
			anim.play("idle_side")
			shadow.position = Vector2(0, 7)
			
		elif last_dir == "left":
			anim.flip_h = true
			anim.play("idle_side")
			shadow.position = Vector2(-4, 7)
			
		elif last_dir == "down":
			anim.flip_h = false 
			anim.play("idle_down")
			shadow.position = Vector2(-1, 7)
			
		elif last_dir == "up":
			anim.flip_h = false 
			anim.play("idle_up")
			shadow.position = Vector2(-3, 7)

	move_and_slide()

func attack():
	is_attacking = true
	velocity = Vector2.ZERO 
	
	# --- ANGRIFF ---
	if last_dir == "right":
		anim.flip_h = false
		anim.play("attack_side")
		hitbox.position = Vector2(15, 0)
		shadow.position = Vector2(0, 7)
		
	elif last_dir == "left":
		anim.flip_h = true
		anim.play("attack_side")
		hitbox.position = Vector2(-15, 0)
		shadow.position = Vector2(-4, 7)
		
	elif last_dir == "down":
		anim.flip_h = false 
		anim.play("attack_down")
		hitbox.position = Vector2(0, 10)
		shadow.position = Vector2(-1, 7)
		
	elif last_dir == "up":
		anim.flip_h = false 
		anim.play("attack_up")
		hitbox.position = Vector2(0, -0)
		shadow.position = Vector2(-3, 7)
		
	await get_tree().create_timer(0.25).timeout
	hitbox_shape.set_deferred("disabled", false)
	await anim.animation_finished
	
	hitbox_shape.set_deferred("disabled", true) 
	hitbox.position = Vector2.ZERO 
	is_attacking = false

func _on_hitbox_body_entered(body):
	
	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(attack_damage)
			
	elif body.is_in_group("destructibles"):
		if body.has_method("smash"):
			body.smash()
		
func take_damage(amount):
	current_health -= amount
	print("Spieler getroffen! Aktuelle HP: ", current_health)
	
	var tween = create_tween()
	tween.tween_property(anim, "modulate", Color.RED, 0.1)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.1)
	
	if current_health <= 0:
		die()

func die():
	if is_dead:
		return
		
	is_dead = true
	velocity = Vector2.ZERO
	
	hitbox_shape.set_deferred("disabled", true)
	
	anim.play("death")
	
	await anim.animation_finished
	
	$GameOverUI.show()

func _on_button_pressed() -> void:
	get_tree().reload_current_scene()
