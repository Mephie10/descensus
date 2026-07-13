extends BaseEnemy

@onready var anim = $AnimatedSprite2D
@onready var nav_agent = $NavigationAgent2D
@onready var hitbox = $Hitbox
@onready var hitbox_shape = $Hitbox/CollisionShape2D

var speed = 55.0
var chase_radius = 120.0
var attack_radius = 45.0
var attack_damage = 20.0 

var attack_cooldown = 1.5
var can_attack = true

var player = null
var is_attacking = false
var is_dead = false
var last_dir = "down" 

func _init():
	current_health = 60.0 

func _ready():
	player = get_tree().get_first_node_in_group("player")
	hitbox_shape.set_deferred("disabled", true)
	
	nav_agent.velocity_computed.connect(_on_safe_velocity_computed)
	call_deferred("_setup_navigation")

func _setup_navigation():
	await get_tree().physics_frame

func _physics_process(_delta):
	if is_dead or is_attacking or player == null:
		return
		
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player <= attack_radius and can_attack:
		attack()
	elif distance_to_player <= chase_radius:
		chase_player()
	else:
		idle()
		
	update_animation()

func chase_player():
	nav_agent.target_position = player.global_position
	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	nav_agent.set_velocity(direction * speed)

func idle():
	nav_agent.set_velocity(Vector2.ZERO)

func _on_safe_velocity_computed(safe_velocity: Vector2):
	if not is_dead and not is_attacking:
		velocity = safe_velocity
		move_and_slide()

func attack():
	is_attacking = true
	can_attack = false
	nav_agent.set_velocity(Vector2.ZERO)
	velocity = Vector2.ZERO 
	
	if last_dir == "right":
		anim.flip_h = false
		anim.play("attack_side")
		hitbox.position = Vector2(15, 0)
		
	elif last_dir == "left":
		anim.flip_h = true
		anim.play("attack_side")
		hitbox.position = Vector2(-15, 0)
		
	elif last_dir == "down":
		anim.flip_h = false 
		anim.play("attack_down")
		hitbox.position = Vector2(0, 10)
		
	elif last_dir == "up":
		anim.flip_h = false 
		anim.play("attack_up")
		hitbox.position = Vector2(0, -10) 
		
	await get_tree().create_timer(0.25).timeout
	hitbox_shape.set_deferred("disabled", false)
	
	await anim.animation_finished
	
	hitbox_shape.set_deferred("disabled", true) 
	hitbox.position = Vector2.ZERO 
	is_attacking = false
	
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func update_animation():
	if is_attacking:
		return 
		
	if velocity != Vector2.ZERO:
		if abs(velocity.x) > abs(velocity.y):
			if velocity.x > 0:
				anim.flip_h = false
				anim.play("run_side")
				last_dir = "right"
			else:
				anim.flip_h = true
				anim.play("run_side")
				last_dir = "left"
		else: 
			if velocity.y > 0:
				anim.flip_h = false 
				anim.play("run_down")
				last_dir = "down"
			else:
				anim.flip_h = false 
				anim.play("run_up")
				last_dir = "up"
	else:
		if last_dir == "right":
			anim.flip_h = false
			anim.play("idle_side")
		elif last_dir == "left":
			anim.flip_h = true
			anim.play("idle_side")
		elif last_dir == "down":
			anim.flip_h = false 
			anim.play("idle_down")
		elif last_dir == "up":
			anim.flip_h = false 
			anim.play("idle_up")

func _on_hitbox_body_entered(body):
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(attack_damage)

func take_damage(amount):
	if is_dead:
		return
		
	current_health -= amount
	
	var tween = create_tween()
	tween.tween_property(anim, "modulate", Color.RED, 0.15)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.1)
	
	if current_health <= 0:
		die_with_animation()

func die_with_animation():
	if is_dead:
		return
		
	is_dead = true
	is_attacking = false
	
	nav_agent.set_velocity(Vector2.ZERO)
	velocity = Vector2.ZERO
	
	hitbox_shape.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
	$CollisionShape2D.set_deferred("disabled", true)
	
	anim.play("death")
	await anim.animation_finished
	
	die()
