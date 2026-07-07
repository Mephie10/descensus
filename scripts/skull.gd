extends CharacterBody2D

const CHASE_SPEED = 63.0
const WANDER_SPEED = 30.0

@onready var anim = $AnimatedSprite2D
@onready var collision = $CollisionShape2D
@onready var nav_agent = $NavigationAgent2D
@onready var hitbox_collision = $Hitbox/CollisionShape2D

var player = null
var is_dead = false
var max_health = 30.0
var current_health = 30.0
var attack_damage = 15.0

# --- KI Variablen ---
var start_position: Vector2
var wander_target: Vector2
var is_chasing = false
var is_waiting = false

var is_attacking = false 
var can_attack = true 

var wander_radius = 60.0
var detection_radius = 110.0
var attack_radius = 35.0
var attack_cooldown = 1.25 
var last_direction = Vector2.DOWN 

var wander_timer = 0.0
const MAX_WANDER_TIME = 4.0 

func _ready():
	player = get_tree().get_first_node_in_group("player")
	start_position = global_position
	nav_agent.velocity_computed.connect(_on_safe_velocity_computed)
	call_deferred("_setup_navigation")

func _setup_navigation():
	await get_tree().physics_frame
	_pick_new_wander_target()

func _on_safe_velocity_computed(safe_velocity: Vector2):
	if is_dead:
		return

	velocity = safe_velocity
	move_and_slide()

	for i in get_slide_collision_count():
		var slide_col = get_slide_collision(i)
		
		if slide_col.get_collider() == player:
			
			if not is_chasing and not is_attacking:
				_pick_new_wander_target()
				
			velocity = Vector2.ZERO
			break

func _physics_process(delta):
	if is_dead:
		return

	if is_instance_valid(player) and not player.is_dead:
		var distance_to_player = global_position.distance_to(player.global_position)
		
		if distance_to_player <= attack_radius and can_attack and not is_attacking:
			_attack_player()
			
		if distance_to_player < detection_radius:
			is_chasing = true
			is_waiting = false 
		elif distance_to_player > detection_radius * 1.5: 
			is_chasing = false
	else:
		is_chasing = false

	if is_chasing:
		_chase_player()
	else:
		_wander(delta) 

	if not is_dead:
		nav_agent.velocity = velocity

func _attack_player():
	is_attacking = true
	can_attack = false 
	
	var direction = (player.global_position - global_position).normalized()
	last_direction = direction
	
	if abs(direction.x) > abs(direction.y):
		anim.play("attack_side")
		anim.flip_h = direction.x < 0
	elif direction.y > 0:
		anim.play("attack_down")
		anim.flip_h = false
	elif direction.y < 0:
		anim.play("attack_up")
		anim.flip_h = false
	
	velocity = direction * (CHASE_SPEED * 2.5)
	
	await get_tree().create_timer(0.20).timeout
	
	if is_dead:
		return
	
	hitbox_collision.set_deferred("disabled", false)
	await get_tree().physics_frame 
	await get_tree().physics_frame 
	hitbox_collision.set_deferred("disabled", true)
	
	velocity = Vector2.ZERO 
	await anim.animation_finished
	is_attacking = false 
	
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func _chase_player():
	nav_agent.target_position = player.global_position
	
	var distance_to_player = global_position.distance_to(player.global_position)
	var next_path_position = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_position)
	
	if distance_to_player > 28.0:
		velocity = direction * CHASE_SPEED
	else:
		velocity = Vector2.ZERO
		
	_update_animation(direction, true)

func _wander(delta):
	wander_timer += delta
	nav_agent.target_position = wander_target
	
	if nav_agent.is_navigation_finished() or wander_timer > MAX_WANDER_TIME:
		velocity = Vector2.ZERO
		_update_animation(Vector2.ZERO, false)
		
		if not is_waiting:
			is_waiting = true
			await get_tree().create_timer(randf_range(1.0, 3.0)).timeout
			if not is_chasing and not is_dead: 
				_pick_new_wander_target()
				is_waiting = false
	else:
		var next_path_position = nav_agent.get_next_path_position()
		var direction = global_position.direction_to(next_path_position)
		
		velocity = direction * WANDER_SPEED
		_update_animation(direction, true)

func _pick_new_wander_target():
	for i in range(10):
		var random_x = randf_range(-wander_radius, wander_radius)
		var random_y = randf_range(-wander_radius, wander_radius)
		var potential_target = start_position + Vector2(random_x, random_y)
		
		nav_agent.target_position = potential_target
		
		if nav_agent.is_target_reachable():
			wander_target = potential_target
			wander_timer = 0.0
			return
			
	wander_target = global_position
	wander_timer = 0.0

func _update_animation(direction: Vector2, is_moving: bool):
	if is_attacking:
		return
		
	if velocity.length() < 5.0:
		is_moving = false

	if is_moving:
		last_direction = direction
		
		if abs(direction.x) > abs(direction.y):
			anim.play("run_side")
			anim.flip_h = direction.x < 0
		elif direction.y > 0:
			anim.play("run_down")
			anim.flip_h = false
		elif direction.y < 0:
			anim.play("run_up")
			anim.flip_h = false
	else:
		if abs(last_direction.x) > abs(last_direction.y):
			anim.play("idle_side")
			anim.flip_h = last_direction.x < 0
		elif last_direction.y > 0:
			anim.play("idle_down")
			anim.flip_h = false
		elif last_direction.y < 0:
			anim.play("idle_up")
			anim.flip_h = false

func take_damage(amount):
	if is_dead:
		return
		
	current_health -= amount
	print("Schädel getroffen! Restliche HP: ", current_health)
	
	var tween = create_tween()
	tween.tween_property(anim, "modulate", Color.RED, 0.1)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.1)
	
	if current_health <= 0:
		is_dead = true
		velocity = Vector2.ZERO 
		
		anim.play("death")
		collision.set_deferred("disabled", true) 
		
		await anim.animation_finished
		queue_free()


func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.name == "Hurtbox":
		var hit_player = area.get_parent() 
		if hit_player.has_method("take_damage"):
			hit_player.take_damage(attack_damage)
