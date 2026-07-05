extends CharacterBody2D

const CHASE_SPEED = 65.0
const WANDER_SPEED = 30.0

@onready var anim = $AnimatedSprite2D
@onready var collision = $CollisionShape2D

var player = null
var is_dead = false
var max_health = 25.0
var current_health = 25.0
var attack_damage = 10.0

# --- KI Variablen ---
var start_position: Vector2
var wander_target: Vector2
var is_chasing = false
var is_waiting = false

var is_attacking = false 
var can_attack = true 

var wander_radius = 60.0
var detection_radius = 120.0
var attack_radius = 25.0
var attack_cooldown = 1.5 
var last_direction = Vector2.DOWN 

var wander_timer = 0.0
const MAX_WANDER_TIME = 4.0 

func _ready():
	player = get_tree().get_first_node_in_group("player")
	start_position = global_position
	_pick_new_wander_target()

func _process(delta):
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

	move_and_slide()

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
		
	await anim.animation_finished
	
	if is_dead:
		return
	
	if is_instance_valid(player) and player.has_method("take_damage"):
		if global_position.distance_to(player.global_position) <= attack_radius + 5.0:
			player.take_damage(attack_damage) 
			
	is_attacking = false 
	
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func _chase_player():
	var distance = global_position.distance_to(player.global_position)
	var direction = (player.global_position - global_position).normalized()
	
	if distance > 25.0:
		velocity = direction * CHASE_SPEED
	else:
		velocity = Vector2.ZERO
		
	_update_animation(direction, true)

func _wander(delta):
	wander_timer += delta
	
	if is_on_wall() or wander_timer > MAX_WANDER_TIME:
		_pick_new_wander_target()
		return
		
	if global_position.distance_to(wander_target) < 5.0:
		velocity = Vector2.ZERO
		_update_animation(Vector2.ZERO, false)
		
		if not is_waiting:
			is_waiting = true
			await get_tree().create_timer(randf_range(1.0, 3.0)).timeout
			if not is_chasing and not is_dead: 
				_pick_new_wander_target()
				is_waiting = false
	else:
		var direction = (wander_target - global_position).normalized()
		velocity = direction * WANDER_SPEED
		_update_animation(direction, true)

# --- OPTIMIERTE ZIELFINDUNG ---
func _pick_new_wander_target():
	var space_state = get_world_2d().direct_space_state
	
	# Versucht bis zu 5 Mal, einen Punkt ohne Hindernis im Weg zu finden
	for i in range(5):
		var random_x = randf_range(-wander_radius, wander_radius)
		var random_y = randf_range(-wander_radius, wander_radius)
		var potential_target = start_position + Vector2(random_x, random_y)
		
		# Erstellt die Laser-Abfrage von der aktuellen Position zum Zielpunkt
		var query = PhysicsRayQueryParameters2D.create(global_position, potential_target)
		query.exclude = [self] # Ignoriert den eigenen Körper bei der Abfrage
		
		var result = space_state.intersect_ray(query)
		
		# result.is_empty() bedeutet: Der Weg ist absolut frei!
		if result.is_empty():
			wander_target = potential_target
			wander_timer = 0.0
			return
			
	# Wenn nach 5 Versuchen alles blockiert ist, bleibt er sicherheitshalber stehen
	wander_target = global_position
	wander_timer = 0.0
# ----------------------------------------

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
	
	# Treffer-Feedback (Schädel blinkt rot)
	var tween = create_tween()
	tween.tween_property(anim, "modulate", Color.RED, 0.1)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.1)
	
	# Erst sterben, wenn die HP auf 0 oder darunter fallen
	if current_health <= 0:
		is_dead = true
		velocity = Vector2.ZERO 
		
		anim.play("death")
		collision.set_deferred("disabled", true) 
		
		await anim.animation_finished
		queue_free()
