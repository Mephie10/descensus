extends BaseEnemy

const ARROW_SCENE = preload("res://scenes/arrow.tscn")

@onready var anim = $AnimatedSprite2D
@onready var nav_agent = $NavigationAgent2D
@onready var collision = $CollisionShape2D
@onready var shadow = $Shadow

var speed = 60.0
var chase_radius = 220.0
var shoot_radius = 170.0
var retreat_radius = 70.0
var attack_damage = 12.0
var attack_cooldown = 1.6

# --- Pfeil ---
const ARROW_SPEED = 300.0
const ARROW_SPAWN_OFFSET = 14.0
const AIM_LEAD_FACTOR = 1.0 # volle Vorhersage der Spielerbewegung -> man muss wirklich ausweichen

# --- Freie Schussbahn (keine Wand/kein anderer Gegner im Weg) ---
const LOS_COLLISION_MASK = 3 # Welt + Spieler (Gegner liegen ebenfalls auf Layer 1)
var reposition_target: Vector2 = Vector2.ZERO
var reposition_timer = 0.0
const REPOSITION_INTERVAL = 0.5

var can_attack = true

# --- Wegdrücken durch den Spieler ---
var push_velocity: Vector2 = Vector2.ZERO
var push_friction = 220.0
var max_push_speed = speed * 1.4 # deutlich schneller als die eigene Bewegung, sonst kann man ihn in Ecken nie wirklich wegdrücken

# --- Wegdrücken zwischen Gegnern ---
const ENEMY_TO_ENEMY_PUSH_FORCE = 250.0
var _physics_delta = 0.0

# --- Rückstoß bei Treffern ---
var knockback_strength = 80.0
var knockback_to_player = 70.0
const PUSH_CANCEL_THRESHOLD = 12.0

# --- Sehr langsame Bewegung während des Schießens (Kiting) ---
# Nur wenn "bedroht, aber noch nicht am Fliehen": mittlere Distanz zum Spieler
const SHOOT_MOVE_SPEED_FACTOR = 0.12
const THREATENED_DISTANCE = 115.0

# --- Notschuss, wenn kein Ausweg mehr bleibt oder der Spieler zu nah ist ---
const PANIC_DISTANCE = 40.0
const PANIC_ANIM_SPEED_SCALE = 1.6
const PANIC_COOLDOWN_FACTOR = 0.6
var is_panic_shot = false

# --- Wandern ---
var wander_speed = speed * 0.45
var wander_radius = 70.0
var wander_timer = 0.0
const MAX_WANDER_TIME = 5.0
var is_waiting = false
var wander_target_valid = false
var start_position: Vector2

# --- Stuck-Erkennung beim Wandern ---
var stuck_timer = 0.0
var stuck_check_position: Vector2
const STUCK_TIME_THRESHOLD = 0.6
const STUCK_DISTANCE_THRESHOLD = 4.0

# --- Stuck-Erkennung speziell bei der Flucht ---
var retreat_stuck_timer = 0.0
var retreat_stuck_check_position: Vector2
const RETREAT_STUCK_TIME_THRESHOLD = 0.4
var current_flee_dir: Vector2 = Vector2.ZERO
var no_escape_found = false

var player = null
var is_attacking = false
var is_dead = false
var attack_interrupted = false
var last_direction = Vector2.DOWN
var enemy_id = ""

# --- Münz-Drop bei Tod: gleiche Wahrscheinlichkeit wie beim Warrior ---
const COIN_DROP_WEIGHTS = [1, 2, 5, 1]

func _init():
	current_health = 75.0 # haelt 3 Treffer vom Spieler (25 Schaden) aus

func _ready():
	enemy_id = Global.object_id(self)

	# Schon getötet -> gar nicht erst erscheinen
	if Global.dead_enemies.has(enemy_id):
		is_dead = true
		queue_free()
		return

	# Gespeicherte HP wiederherstellen (Position bleibt die Spawn-Position)
	if Global.enemy_health.has(enemy_id):
		current_health = Global.enemy_health[enemy_id]

	player = get_tree().get_first_node_in_group("player")
	start_position = global_position
	stuck_check_position = global_position
	retreat_stuck_check_position = global_position

	nav_agent.velocity_computed.connect(_on_safe_velocity_computed)
	nav_agent.target_desired_distance = 8.0
	nav_agent.path_desired_distance = 4.0

	call_deferred("_setup_navigation")

func _setup_navigation():
	await get_tree().physics_frame
	if not is_inside_tree() or is_dead:
		return
	_pick_new_wander_target()

func _physics_process(delta):
	_physics_delta = delta

	if push_velocity != Vector2.ZERO:
		push_velocity = push_velocity.move_toward(Vector2.ZERO, push_friction * delta)

	if is_dead:
		return

	if is_attacking:
		# Zu weit weggedrückt, um noch zu treffen -> normalen Schuss abbrechen (Notschuss nie)
		if push_velocity.length() > PUSH_CANCEL_THRESHOLD and player != null and not is_panic_shot:
			var push_dist = global_position.distance_to(player.global_position)
			if push_dist > shoot_radius:
				attack_interrupted = true

		# Ganz langsame Ausweichbewegung während dem Schießen, aber nur wenn "bedroht,
		# aber noch nicht am Fliehen" (mittlere Distanz) - bei Notschuss oder auf
		# entspannter Distanz bleibt er stehen
		var shoot_velocity = Vector2.ZERO
		if not is_panic_shot and player != null and is_instance_valid(player) and not player.is_dead:
			var dist_now = global_position.distance_to(player.global_position)
			if dist_now > retreat_radius and dist_now <= THREATENED_DISTANCE:
				var away_dir = global_position - player.global_position
				if away_dir.length() > 0.001:
					shoot_velocity = away_dir.normalized() * (speed * SHOOT_MOVE_SPEED_FACTOR)

		velocity = _compose_velocity(shoot_velocity)
		move_and_slide()
		_push_colliding_enemies(delta)
		return

	var player_alive = player != null and is_instance_valid(player) and not player.is_dead

	var distance_to_player = INF
	if player_alive:
		distance_to_player = global_position.distance_to(player.global_position)

	var facing_override = Vector2.ZERO

	# Bei Rückstoß zum Spieler ausgerichtet bleiben
	if player_alive and push_velocity.length() > 5.0 and distance_to_player <= chase_radius:
		facing_override = player.global_position - global_position

	if player_alive and distance_to_player <= retreat_radius:
		_reset_wander_state()
		_reset_reposition_state()
		facing_override = player.global_position - global_position
		face_player()
		_retreat_from_player(delta)

		# Kein Ausweg mehr oder Spieler schon zu nah -> sofortiger Notschuss
		if can_attack and (no_escape_found or distance_to_player <= PANIC_DISTANCE):
			attack(true)
	elif player_alive and distance_to_player <= shoot_radius:
		_reset_wander_state()
		_reset_retreat_state()
		facing_override = player.global_position - global_position
		face_player()

		# Nur schießen, wenn die Schussbahn frei ist (keine Wand/kein anderer Gegner im Weg) -
		# sonst versuchen, sich für einen freien Schuss zu positionieren
		if _is_shot_clear_from(global_position):
			_reset_reposition_state()
			idle()
			if can_attack:
				attack(false)
		else:
			_move_toward_clear_shot(delta)
	elif player_alive and distance_to_player <= chase_radius:
		_reset_wander_state()
		_reset_retreat_state()
		_reset_reposition_state()
		chase_player()
	else:
		_reset_retreat_state()
		_reset_reposition_state()
		_wander(delta)

	update_animation(facing_override)

func _reset_wander_state():
	is_waiting = false
	wander_target_valid = false
	wander_timer = 0.0
	stuck_timer = 0.0

func _reset_retreat_state():
	current_flee_dir = Vector2.ZERO
	no_escape_found = false
	retreat_stuck_timer = 0.0
	retreat_stuck_check_position = global_position

func _reset_reposition_state():
	reposition_target = Vector2.ZERO
	reposition_timer = 0.0

# --- Prüfen, ob von "from_pos" aus eine freie Schussbahn zum Spieler besteht ---
# (kein anderer Gegner und keine Wand im Weg - beide liegen auf Layer 1)
func _is_shot_clear_from(from_pos: Vector2) -> bool:
	if player == null or not is_instance_valid(player):
		return false

	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from_pos, player.global_position)
	query.collision_mask = LOS_COLLISION_MASK
	query.exclude = [get_rid()]

	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return true

	return result.collider == player

# --- Nächstgelegene Position rund um den Spieler suchen, von der aus die Schussbahn frei ist ---
func _find_clear_shot_position() -> Vector2:
	var to_player = player.global_position - global_position
	if to_player.length() < 0.001:
		return Vector2.ZERO

	var side = to_player.normalized().rotated(deg_to_rad(90))
	var candidate_offsets = [
		side * 40.0, -side * 40.0,
		side * 75.0, -side * 75.0,
		side * 40.0 - to_player.normalized() * 25.0,
		-side * 40.0 - to_player.normalized() * 25.0,
		-to_player.normalized() * 40.0,
	]

	for offset in candidate_offsets:
		var candidate_pos = global_position + offset
		nav_agent.target_position = candidate_pos
		if nav_agent.is_target_reachable() and _is_shot_clear_from(candidate_pos):
			return candidate_pos

	return Vector2.ZERO

# --- Sich für einen freien Schuss auf den Spieler positionieren ---
func _move_toward_clear_shot(delta: float) -> void:
	reposition_timer += delta

	if reposition_target == Vector2.ZERO or nav_agent.is_navigation_finished() or reposition_timer > REPOSITION_INTERVAL:
		reposition_target = _find_clear_shot_position()
		reposition_timer = 0.0

	if reposition_target == Vector2.ZERO:
		idle()
		return

	nav_agent.target_position = reposition_target

	if nav_agent.is_navigation_finished():
		idle()
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	nav_agent.set_velocity(direction * speed * 0.7)

func apply_push(direction: Vector2, strength: float) -> void:
	if is_dead:
		return
	push_velocity += direction.normalized() * strength
	if push_velocity.length() > max_push_speed:
		push_velocity = push_velocity.normalized() * max_push_speed

func apply_knockback(direction: Vector2) -> void:
	if is_dead:
		return
	push_velocity = direction.normalized() * knockback_strength

# Push isotrop machen (Eigenbewegung entgegen der Push-Richtung abziehen)
func _compose_velocity(self_velocity: Vector2) -> Vector2:
	if push_velocity == Vector2.ZERO:
		return self_velocity

	# Bei spürbarem Rückstoß die KI-Bewegung kurz komplett unterdrücken (siehe Warrior)
	if push_velocity.length() > PUSH_CANCEL_THRESHOLD:
		return push_velocity

	var push_dir = push_velocity.normalized()
	var along = self_velocity.dot(push_dir)
	if along < 0.0:
		self_velocity -= push_dir * along

	return self_velocity + push_velocity

func face_player():
	if player == null:
		return
	var to_player = player.global_position - global_position
	if to_player.length() > 0.001:
		last_direction = to_player.normalized()

func chase_player():
	nav_agent.target_position = player.global_position

	if nav_agent.is_navigation_finished():
		idle()
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	nav_agent.set_velocity(direction * speed)

# --- Auf Distanz zum Spieler bleiben (Kiting), mit Stuck-Erkennung ---
func _retreat_from_player(delta: float) -> void:
	var away_dir = (global_position - player.global_position)
	if away_dir.length() < 0.001:
		away_dir = -last_direction
	away_dir = away_dir.normalized()

	if global_position.distance_to(retreat_stuck_check_position) < STUCK_DISTANCE_THRESHOLD:
		retreat_stuck_timer += delta
	else:
		retreat_stuck_timer = 0.0
		retreat_stuck_check_position = global_position

	# Noch keine Fluchtrichtung gewählt oder auf der Stelle geblieben -> sofort neu wählen
	if current_flee_dir == Vector2.ZERO or retreat_stuck_timer > RETREAT_STUCK_TIME_THRESHOLD:
		current_flee_dir = _pick_escape_direction(away_dir)
		retreat_stuck_timer = 0.0
		retreat_stuck_check_position = global_position
		no_escape_found = current_flee_dir == Vector2.ZERO

	if no_escape_found:
		idle()
		return

	nav_agent.target_position = global_position + current_flee_dir * 60.0

	if nav_agent.is_navigation_finished():
		idle()
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	nav_agent.set_velocity(direction * speed)

# --- Nächstbesten erreichbaren Fluchtpunkt rund um die bevorzugte Richtung suchen ---
func _pick_escape_direction(preferred_dir: Vector2) -> Vector2:
	var angle_offsets = [0.0, 35.0, -35.0, 70.0, -70.0, 110.0, -110.0, 145.0, -145.0, 180.0]

	for offset in angle_offsets:
		var candidate_dir = preferred_dir.rotated(deg_to_rad(offset))
		nav_agent.target_position = global_position + candidate_dir * 60.0
		if nav_agent.is_target_reachable():
			return candidate_dir

	return Vector2.ZERO

func idle():
	nav_agent.set_velocity(Vector2.ZERO)

func _wander(delta):
	if is_waiting:
		idle()
		return

	wander_timer += delta

	if velocity.length() > 1.0:
		if global_position.distance_to(stuck_check_position) < STUCK_DISTANCE_THRESHOLD:
			stuck_timer += delta
		else:
			stuck_timer = 0.0
			stuck_check_position = global_position
	else:
		stuck_timer = 0.0
		stuck_check_position = global_position

	var should_stop = not wander_target_valid \
		or nav_agent.is_navigation_finished() \
		or wander_timer > MAX_WANDER_TIME \
		or stuck_timer > STUCK_TIME_THRESHOLD

	if should_stop:
		idle()
		_start_waiting()
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	nav_agent.set_velocity(direction * wander_speed)

func _start_waiting():
	if is_waiting:
		return

	is_waiting = true
	wander_target_valid = false

	await get_tree().create_timer(randf_range(1.5, 3.5)).timeout

	if is_dead or not is_inside_tree():
		return

	is_waiting = false
	_pick_new_wander_target()

func _pick_new_wander_target():
	# Physik-Frame abwarten, bevor is_target_reachable() geprüft wird
	for _attempt in range(8):
		if is_dead:
			return

		var candidate = start_position + Vector2(
			randf_range(-wander_radius, wander_radius),
			randf_range(-wander_radius, wander_radius)
		)
		nav_agent.target_position = candidate

		await get_tree().physics_frame

		if is_dead or not is_inside_tree():
			return

		if nav_agent.is_target_reachable():
			wander_target_valid = true
			wander_timer = 0.0
			stuck_timer = 0.0
			stuck_check_position = global_position
			return

	wander_target_valid = false

func _on_safe_velocity_computed(safe_velocity: Vector2):
	if is_dead or is_attacking:
		return

	velocity = _compose_velocity(safe_velocity)
	move_and_slide()
	_push_colliding_enemies(_physics_delta)

# --- Gegenseitiges Wegdrücken zwischen Gegnern ---
func _push_colliding_enemies(delta: float) -> void:
	for i in get_slide_collision_count():
		var slide_collision = get_slide_collision(i)
		var collider = slide_collision.get_collider()

		if collider and collider != self and collider.is_in_group("enemies") and collider.has_method("apply_push"):
			var push_dir = -slide_collision.get_normal()
			if push_dir.length() > 0.001:
				collider.apply_push(push_dir.normalized(), ENEMY_TO_ENEMY_PUSH_FORCE * delta)

# --- panic: Notschuss mit erhöhtem Tempo, wenn kein Ausweg bleibt oder der Spieler zu nah ist ---
func attack(panic: bool = false) -> void:
	is_attacking = true
	can_attack = false
	attack_interrupted = false
	is_panic_shot = panic
	nav_agent.set_velocity(Vector2.ZERO)

	anim.speed_scale = PANIC_ANIM_SPEED_SCALE if panic else 1.0

	var shot_direction = last_direction

	if abs(shot_direction.x) > abs(shot_direction.y):
		anim.flip_h = shot_direction.x < 0
		anim.play("attack_side")
	elif shot_direction.y >= 0:
		anim.flip_h = false
		anim.play("attack_down")
	else:
		anim.flip_h = false
		anim.play("attack_up")

	# Pfeil wird erst am Ende der Animation abgefeuert
	while anim.is_playing() and not is_dead and is_inside_tree() and not attack_interrupted:
		await get_tree().process_frame

	anim.speed_scale = 1.0

	if is_dead or not is_inside_tree():
		return

	if attack_interrupted:
		_end_attack_early()
		return

	_spawn_arrow(shot_direction)

	is_attacking = false
	is_panic_shot = false

	var cooldown = attack_cooldown * (PANIC_COOLDOWN_FACTOR if panic else 1.0)
	await get_tree().create_timer(cooldown).timeout

	if not is_inside_tree():
		return
	can_attack = true

# --- Schuss wegen Rückstoß vorzeitig abbrechen, sofort wieder angriffsbereit ---
func _end_attack_early() -> void:
	anim.speed_scale = 1.0
	is_attacking = false
	is_panic_shot = false
	can_attack = true

# --- Pfeil in Richtung des Spielers abschießen, mit leichter Vorhersage der Bewegung ---
func _spawn_arrow(shot_direction: Vector2) -> void:
	if not is_inside_tree():
		return

	var direction = shot_direction

	if is_instance_valid(player):
		var predicted_position = player.global_position
		var travel_distance = global_position.distance_to(player.global_position)
		if travel_distance > 0.001 and player.velocity.length() > 0.001:
			var travel_time = travel_distance / ARROW_SPEED
			predicted_position += player.velocity * travel_time * AIM_LEAD_FACTOR

		var to_player = predicted_position - global_position
		if to_player.length() > 0.001:
			direction = to_player.normalized()

	if direction == Vector2.ZERO:
		direction = Vector2.DOWN

	var arrow = ARROW_SCENE.instantiate()
	arrow.direction = direction
	arrow.speed = ARROW_SPEED
	arrow.damage = attack_damage
	arrow.knockback_strength = knockback_to_player
	arrow.shooter = self

	get_tree().current_scene.add_child(arrow)
	arrow.global_position = global_position + direction * ARROW_SPAWN_OFFSET

func update_animation(facing_override: Vector2 = Vector2.ZERO) -> void:
	if is_attacking:
		return

	var is_moving = velocity.length() > 5.0
	var move_dir = velocity.normalized() if is_moving else Vector2.ZERO
	var facing = facing_override if facing_override != Vector2.ZERO else move_dir

	if is_moving and facing != Vector2.ZERO:
		last_direction = facing
		_play_run(facing)
	elif facing_override != Vector2.ZERO:
		last_direction = facing_override
		_play_idle(facing_override)
	else:
		_play_idle(last_direction)

func _play_run(direction: Vector2) -> void:
	if abs(direction.x) > abs(direction.y):
		anim.play("run_side")
		anim.flip_h = direction.x < 0
	elif direction.y >= 0:
		anim.play("run_down")
		anim.flip_h = false
	else:
		anim.play("run_up")
		anim.flip_h = false

func _play_idle(direction: Vector2) -> void:
	if abs(direction.x) > abs(direction.y):
		anim.play("idle_side")
		anim.flip_h = direction.x < 0
	elif direction.y >= 0:
		anim.play("idle_down")
		anim.flip_h = false
	else:
		anim.play("idle_up")
		anim.flip_h = false

func take_damage(amount):
	if is_dead:
		return

	current_health -= amount
	Global.enemy_health[enemy_id] = current_health

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
	Global.dead_enemies.append(enemy_id)
	Global.enemy_health.erase(enemy_id)

	nav_agent.set_velocity(Vector2.ZERO)
	velocity = Vector2.ZERO
	push_velocity = Vector2.ZERO
	anim.speed_scale = 1.0

	collision.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)

	_drop_coins()

	anim.play("death")
	await anim.animation_finished

	die()

# --- Zufällige Münzen beim Tod gutschreiben (gleiche Wahrscheinlichkeit wie der Warrior) ---
func _drop_coins() -> void:
	var amount = Global.weighted_random(COIN_DROP_WEIGHTS)
	if amount > 0 and is_instance_valid(player) and player.has_method("add_coins"):
		player.add_coins(amount)
