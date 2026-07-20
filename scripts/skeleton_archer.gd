extends BaseEnemy

const ARROW_SCENE = preload("res://scenes/Enemies/arrow.tscn")

@onready var anim = $AnimatedSprite2D
@onready var nav_agent = $NavigationAgent2D
@onready var collision = $CollisionShape2D
@onready var shadow = $Shadow

# --- Verhalten (fern -> nah): wandern, verfolgen, schießen, repositionieren, Panik ---
var speed = 65.0
var chase_radius = 180.0
var shoot_radius = 130.0
var reposition_radius = 120.0
var attack_damage = 10.0
var attack_cooldown = 2.0

# --- Pfeil ---
const ARROW_SPEED = 300.0
const ARROW_SPAWN_OFFSET = 14.0
# Zufällige Vorhersage-Genauigkeit der Spielerbewegung pro Schuss
const AIM_LEAD_MIN = 0.3
const AIM_LEAD_MAX = 0.85
# Zufällige Grundstreuung pro Schuss
const ACCURACY_SPREAD_MIN_DEGREES = 4.0
const ACCURACY_SPREAD_MAX_DEGREES = 11.0

# --- Freie Schussbahn (Gegner werden ignoriert) ---
const LOS_COLLISION_MASK = 3 # Welt + Spieler
var los_reposition_target: Vector2 = Vector2.ZERO
var los_reposition_timer = 0.0
const LOS_REPOSITION_INTERVAL = 0.5

var can_attack = true

# --- Wegdrücken durch den Spieler ---
var push_velocity: Vector2 = Vector2.ZERO
var push_friction = 220.0
var max_push_speed = speed * 0.55

# --- Wegdrücken zwischen Gegnern ---
const ENEMY_TO_ENEMY_PUSH_FORCE = 250.0
var _physics_delta = 0.0

# --- Rückstoß bei Treffern ---
var knockback_strength = 80.0
var knockback_to_player = 70.0

# --- Schatten-Versatz je Blickrichtung ---
const SHADOW_OFFSET_RIGHT = Vector2(0, 0)
const SHADOW_OFFSET_LEFT = Vector2(-2, 0)
const SHADOW_OFFSET_DOWN = Vector2(0, 0)
const SHADOW_OFFSET_UP = Vector2(-1, 0)
var shadow_base_position: Vector2

# --- Panik: steht still, schießt schneller, aber schwächer ---
const PANIC_DISTANCE = 80.0
const PANIC_ANIM_SPEED_SCALE = 1.5
const PANIC_COOLDOWN_FACTOR = 0.6
const PANIC_DAMAGE_FACTOR = 0.5 # immer abgerundet

# --- Repositionieren: einmaliger Ausweichschritt, kein Dauer-Fliehen ---
const REPOSITION_DISTANCE = 90.0
const REPOSITION_SPEED_FACTOR = 0.8
const REPOSITION_STUCK_TIME_THRESHOLD = 0.5
var proximity_target: Vector2 = Vector2.ZERO
var proximity_giving_up = false
var proximity_stuck_timer = 0.0
var proximity_stuck_check_position: Vector2

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

var player = null
var is_attacking = false
var is_dead = false
var last_direction = Vector2.DOWN
var enemy_id = ""

var _footsteps: AudioStreamPlayer2D

# --- Münz-Drop bei Tod ---
const COIN_DROP_WEIGHTS = [1, 2, 5, 1]

# --- Chance, beim Tod einen Skull zu hinterlassen ---
const SKULL_SPAWN_CHANCE = 0.5

func _init():
	current_health = 70.0

func _ready():
	enemy_id = Global.object_id(self)

	# Schon getötet -> nicht erscheinen
	if Global.dead_enemies.has(enemy_id):
		is_dead = true
		queue_free()
		return

	# Gespeicherte HP wiederherstellen
	if Global.enemy_health.has(enemy_id):
		current_health = Global.enemy_health[enemy_id]

	player = get_tree().get_first_node_in_group("player")
	_footsteps = AudioManager.attach_loop(self, "archer_footsteps")
	start_position = global_position
	shadow_base_position = shadow.position
	stuck_check_position = global_position
	proximity_stuck_check_position = global_position

	nav_agent.velocity_computed.connect(_on_safe_velocity_computed)
	nav_agent.target_desired_distance = 8.0
	nav_agent.path_desired_distance = 4.0

	call_deferred("_setup_navigation")

func _setup_navigation():
	await get_tree().physics_frame
	if not is_inside_tree() or is_dead:
		return
	_pick_new_wander_target()

# --- Zustandsmaschine ---
func _physics_process(delta):
	_physics_delta = delta

	if push_velocity != Vector2.ZERO:
		push_velocity = push_velocity.move_toward(Vector2.ZERO, push_friction * delta)

	if is_dead:
		return

	if is_attacking:
		# Steht still während des Schusses, nur Rückstoß wirkt weiter
		velocity = _compose_velocity(Vector2.ZERO)
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

	if player_alive and distance_to_player <= PANIC_DISTANCE:
		# Panik
		_reset_wander_state()
		_reset_proximity_state()
		_reset_los_reposition_state()
		facing_override = player.global_position - global_position
		face_player()
		idle()
		if can_attack:
			attack(true)
	elif player_alive and distance_to_player <= reposition_radius:
		# Repositionieren
		_reset_wander_state()
		_reset_los_reposition_state()
		facing_override = player.global_position - global_position
		face_player()
		_reposition_from_proximity(delta)
	elif player_alive and distance_to_player <= shoot_radius:
		# Angriff aus Distanz
		_reset_wander_state()
		_reset_proximity_state()
		facing_override = player.global_position - global_position
		face_player()

		if _is_shot_clear_from(global_position):
			_reset_los_reposition_state()
			idle()
			if can_attack:
				attack(false)
		else:
			_move_toward_clear_shot(delta)
	elif player_alive and distance_to_player <= chase_radius:
		# Verfolgen
		_reset_wander_state()
		_reset_proximity_state()
		_reset_los_reposition_state()
		chase_player()
	else:
		# Wandern
		_reset_proximity_state()
		_reset_los_reposition_state()
		_wander(delta)

	update_animation(facing_override)

func _reset_wander_state():
	is_waiting = false
	wander_target_valid = false
	wander_timer = 0.0
	stuck_timer = 0.0

func _reset_proximity_state():
	proximity_target = Vector2.ZERO
	proximity_giving_up = false
	proximity_stuck_timer = 0.0
	proximity_stuck_check_position = global_position

func _reset_los_reposition_state():
	los_reposition_target = Vector2.ZERO
	los_reposition_timer = 0.0

# --- Sichtlinie zum Spieler frei? (Gegner zählen nicht als Hindernis) ---
func _is_shot_clear_from(from_pos: Vector2) -> bool:
	if player == null or not is_instance_valid(player):
		return false

	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from_pos, player.global_position)
	query.collision_mask = LOS_COLLISION_MASK
	query.exclude = _get_los_exclude_rids()

	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return true

	return result.collider == player

# --- Sich selbst und alle anderen Gegner von der LOS-Prüfung ausschließen ---
func _get_los_exclude_rids() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy != self and enemy is CollisionObject2D:
			rids.append(enemy.get_rid())
	return rids

# --- Nächste Position mit freier Schussbahn suchen ---
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

# --- Für freien Schuss positionieren (LOS blockiert) ---
func _move_toward_clear_shot(delta: float) -> void:
	los_reposition_timer += delta

	if los_reposition_target == Vector2.ZERO or nav_agent.is_navigation_finished() or los_reposition_timer > LOS_REPOSITION_INTERVAL:
		los_reposition_target = _find_clear_shot_position()
		los_reposition_timer = 0.0

	if los_reposition_target == Vector2.ZERO:
		idle()
		return

	nav_agent.target_position = los_reposition_target

	if nav_agent.is_navigation_finished():
		idle()
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	nav_agent.set_velocity(direction * speed * 0.7)

# --- Einmaligen Ausweichschritt ausführen, mit Aufgeben-Schutz ---
func _reposition_from_proximity(delta: float) -> void:
	if proximity_giving_up:
		idle()
		return

	if proximity_target == Vector2.ZERO:
		var away_dir = (global_position - player.global_position)
		if away_dir.length() < 0.001:
			away_dir = -last_direction
		away_dir = away_dir.normalized()

		var escape_dir = _pick_escape_direction(away_dir)
		if escape_dir == Vector2.ZERO:
			# Keine erreichbare Stelle -> gar nicht erst versuchen
			proximity_giving_up = true
			idle()
			return

		proximity_target = global_position + escape_dir * REPOSITION_DISTANCE
		proximity_stuck_timer = 0.0
		proximity_stuck_check_position = global_position

	# Kommt nicht voran -> aufgeben
	if global_position.distance_to(proximity_stuck_check_position) < STUCK_DISTANCE_THRESHOLD:
		proximity_stuck_timer += delta
	else:
		proximity_stuck_timer = 0.0
		proximity_stuck_check_position = global_position

	if proximity_stuck_timer > REPOSITION_STUCK_TIME_THRESHOLD:
		proximity_giving_up = true
		idle()
		return

	nav_agent.target_position = proximity_target

	if nav_agent.is_navigation_finished():
		# Ziel erreicht, nicht erneut versuchen
		proximity_giving_up = true
		idle()
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	nav_agent.set_velocity(direction * speed * REPOSITION_SPEED_FACTOR)

# --- Erreichbare Ausweichrichtung suchen (Winkel-Sampling) ---
func _pick_escape_direction(preferred_dir: Vector2) -> Vector2:
	var angle_offsets = [0.0, 35.0, -35.0, 70.0, -70.0, 110.0, -110.0, 145.0, -145.0, 180.0]

	for offset in angle_offsets:
		var candidate_dir = preferred_dir.rotated(deg_to_rad(offset))
		nav_agent.target_position = global_position + candidate_dir * REPOSITION_DISTANCE
		if nav_agent.is_target_reachable():
			return candidate_dir

	return Vector2.ZERO

func idle():
	nav_agent.set_velocity(Vector2.ZERO)

# --- Wandern ---
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

# --- Push isotrop machen (Eigenbewegung entgegen der Push-Richtung abziehen) ---
func _compose_velocity(self_velocity: Vector2) -> Vector2:
	if push_velocity == Vector2.ZERO:
		return self_velocity

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

# --- Angriff: panic = schneller, aber schwächer ---
func attack(panic: bool = false) -> void:
	is_attacking = true
	can_attack = false
	nav_agent.set_velocity(Vector2.ZERO)

	anim.speed_scale = PANIC_ANIM_SPEED_SCALE if panic else 1.0

	var shot_direction = last_direction

	if abs(shot_direction.x) > abs(shot_direction.y):
		if shot_direction.x > 0:
			anim.flip_h = false
			anim.play("attack_side")
			_apply_shadow_offset(SHADOW_OFFSET_RIGHT)
		else:
			anim.flip_h = true
			anim.play("attack_side")
			_apply_shadow_offset(SHADOW_OFFSET_LEFT)
	elif shot_direction.y >= 0:
		anim.flip_h = false
		anim.play("attack_down")
		_apply_shadow_offset(SHADOW_OFFSET_DOWN)
	else:
		anim.flip_h = false
		anim.play("attack_up")
		_apply_shadow_offset(SHADOW_OFFSET_UP)

	# Pfeil fliegt erst am Ende der Animation los, dann aber immer
	if anim.is_playing():
		await anim.animation_finished

	anim.speed_scale = 1.0

	if is_dead or not is_inside_tree():
		return

	_spawn_arrow(shot_direction, panic)

	is_attacking = false

	var cooldown = attack_cooldown * (PANIC_COOLDOWN_FACTOR if panic else 1.0)
	await get_tree().create_timer(cooldown).timeout

	if not is_inside_tree():
		return
	can_attack = true

# --- Pfeil abschießen: Vorhersage + Streuung, zufällig pro Schuss ---
func _spawn_arrow(shot_direction: Vector2, panic: bool = false) -> void:
	if not is_inside_tree():
		return

	AudioManager.play_at("archer_attack", global_position)

	var direction = shot_direction

	if is_instance_valid(player):
		var predicted_position = player.global_position
		var travel_distance = global_position.distance_to(player.global_position)
		if travel_distance > 0.001 and player.velocity.length() > 0.001:
			var travel_time = travel_distance / ARROW_SPEED
			var shot_accuracy = randf_range(AIM_LEAD_MIN, AIM_LEAD_MAX)
			predicted_position += player.velocity * travel_time * shot_accuracy

		var to_player = predicted_position - global_position
		if to_player.length() > 0.001:
			direction = to_player.normalized()

	if direction == Vector2.ZERO:
		direction = Vector2.DOWN

	# Grundstreuung, Stärke ebenfalls zufällig pro Schuss
	var spread_limit = randf_range(ACCURACY_SPREAD_MIN_DEGREES, ACCURACY_SPREAD_MAX_DEGREES)
	direction = direction.rotated(deg_to_rad(randf_range(-spread_limit, spread_limit)))

	var damage = attack_damage
	if panic:
		damage = floor(attack_damage * PANIC_DAMAGE_FACTOR)

	var arrow = ARROW_SCENE.instantiate()
	arrow.direction = direction
	arrow.speed = ARROW_SPEED
	arrow.damage = damage
	arrow.knockback_strength = knockback_to_player
	arrow.shooter = self

	get_tree().current_scene.add_child(arrow)
	arrow.global_position = global_position + direction * ARROW_SPAWN_OFFSET

func update_animation(facing_override: Vector2 = Vector2.ZERO) -> void:
	if is_attacking:
		_set_footsteps(false)
		return

	var is_moving = velocity.length() > 5.0
	_set_footsteps(is_moving)
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
		if direction.x > 0:
			anim.play("run_side")
			anim.flip_h = false
			_apply_shadow_offset(SHADOW_OFFSET_RIGHT)
		else:
			anim.play("run_side")
			anim.flip_h = true
			_apply_shadow_offset(SHADOW_OFFSET_LEFT)
	elif direction.y >= 0:
		anim.play("run_down")
		anim.flip_h = false
		_apply_shadow_offset(SHADOW_OFFSET_DOWN)
	else:
		anim.play("run_up")
		anim.flip_h = false
		_apply_shadow_offset(SHADOW_OFFSET_UP)

func _play_idle(direction: Vector2) -> void:
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			anim.play("idle_side")
			anim.flip_h = false
			_apply_shadow_offset(SHADOW_OFFSET_RIGHT)
		else:
			anim.play("idle_side")
			anim.flip_h = true
			_apply_shadow_offset(SHADOW_OFFSET_LEFT)
	elif direction.y >= 0:
		anim.play("idle_down")
		anim.flip_h = false
		_apply_shadow_offset(SHADOW_OFFSET_DOWN)
	else:
		anim.play("idle_up")
		anim.flip_h = false
		_apply_shadow_offset(SHADOW_OFFSET_UP)

# Szenenposition + richtungsabhängiger Versatz
func _apply_shadow_offset(offset: Vector2) -> void:
	shadow.position = shadow_base_position + offset

# grants_reward = false, wenn der Tod nicht dem Spieler zuzurechnen ist
# (z.B. eine Falle). Dann gibt es keine Muenzen.
func take_damage(amount, grants_reward: bool = true):
	if is_dead:
		return

	current_health -= amount
	Global.enemy_health[enemy_id] = current_health
	AudioManager.play_at("enemy_hit", global_position)

	var tween = create_tween()
	tween.tween_property(anim, "modulate", Color.RED, 0.15)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.1)

	if current_health <= 0:
		die_with_animation(grants_reward)

func die_with_animation(grants_reward: bool = true):
	if is_dead:
		return

	is_dead = true
	is_attacking = false
	_set_footsteps(false)
	Global.dead_enemies.append(enemy_id)
	Global.enemy_health.erase(enemy_id)

	nav_agent.set_velocity(Vector2.ZERO)
	velocity = Vector2.ZERO
	push_velocity = Vector2.ZERO
	anim.speed_scale = 1.0

	collision.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)

	if grants_reward:
		_drop_coins()

	anim.play("death")
	await anim.animation_finished

	Global.try_spawn_skull(self, SKULL_SPAWN_CHANCE)

	die()

# --- Zufällige Münzen beim Tod ---
func _drop_coins() -> void:
	var amount = Global.weighted_random(COIN_DROP_WEIGHTS)
	if amount > 0 and is_instance_valid(player) and player.has_method("add_coins"):
		player.add_coins(amount)

# Startet/stoppt den Fußschritt-Loop nur bei echtem Zustandswechsel.
func _set_footsteps(active: bool) -> void:
	if _footsteps == null:
		return
	if active and not _footsteps.playing:
		_footsteps.play()
	elif not active and _footsteps.playing:
		_footsteps.stop()
