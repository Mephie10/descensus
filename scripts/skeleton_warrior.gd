extends BaseEnemy

@onready var anim = $AnimatedSprite2D
@onready var nav_agent = $NavigationAgent2D
@onready var hitbox = $Hitbox
@onready var hitbox_shape = $Hitbox/CollisionShape2D
@onready var shadow = $Sprite2D

var speed = 60.0
var chase_radius = 110.0
var attack_radius = 26.0
var attack_damage = 15.0

var attack_cooldown = 0.78
var can_attack = true

# --- Wegdrücken durch den Spieler ---
var push_velocity: Vector2 = Vector2.ZERO
var push_friction = 300.0
var max_push_speed = speed * 0.5

# --- Wegdrücken zwischen Gegnern ---
const ENEMY_TO_ENEMY_PUSH_FORCE = 250.0
var _physics_delta = 0.0

# --- Rückstoß bei Treffern ---
var knockback_strength = 100.0
var knockback_to_player = 90.0

# --- Schatten-Versatz je Blickrichtung ---
const SHADOW_OFFSET_RIGHT = Vector2(-1, -1)
const SHADOW_OFFSET_LEFT = Vector2(-2, -1)
const SHADOW_OFFSET_DOWN = Vector2(0, -1)
const SHADOW_OFFSET_UP = Vector2(-1, -1)
var shadow_base_position: Vector2

# --- Ausfallschritt beim Angriff (kleiner als beim Skull) ---
var lunge_speed = speed * 1.05
var lunge_duration = 0.2
var lunge_stop_distance = 18.0
const PUSH_CANCEL_THRESHOLD = 12.0
var attack_move_velocity: Vector2 = Vector2.ZERO

# --- Nahkampf-Hysterese ---
var in_melee_range = false
var melee_hysteresis = 10.0

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
var last_dir = "down"
var attack_interrupted = false
var enemy_id = ""

var _footsteps: AudioStreamPlayer2D

# --- Münz-Drop bei Tod: 0-3, meistens 2 ---
const COIN_DROP_WEIGHTS = [1, 2, 5, 1]

# --- Chance, beim Tod einen Skull zu hinterlassen ---
const SKULL_SPAWN_CHANCE = 0.5

func _init():
	current_health = 70.0

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
	_footsteps = AudioManager.attach_loop(self, "warrior_footsteps")
	hitbox_shape.set_deferred("disabled", true)
	start_position = global_position
	shadow_base_position = shadow.position
	stuck_check_position = global_position

	nav_agent.velocity_computed.connect(_on_safe_velocity_computed)

	nav_agent.target_desired_distance = attack_radius
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
		# Rückstoß bricht Ausfallschritt ab
		if push_velocity.length() > PUSH_CANCEL_THRESHOLD:
			attack_move_velocity = Vector2.ZERO

			# Zu weit weggedrückt, um den Spieler noch treffen zu können -> Angriff abbrechen
			if player != null:
				var push_dist = global_position.distance_to(player.global_position)
				if push_dist > attack_radius + melee_hysteresis:
					attack_interrupted = true

		if player != null:
			var current_dist = global_position.distance_to(player.global_position)
			if current_dist <= lunge_stop_distance:
				attack_move_velocity = Vector2.ZERO

		velocity = _compose_velocity(attack_move_velocity)
		move_and_slide()
		_push_colliding_enemies(delta)
		return

	var player_alive = player != null and is_instance_valid(player) and not player.is_dead

	var distance_to_player = INF
	if player_alive:
		distance_to_player = global_position.distance_to(player.global_position)

	var effective_attack_radius = attack_radius + (melee_hysteresis if in_melee_range else 0.0)

	var facing_override = Vector2.ZERO

	# Bei Rückstoß zum Spieler ausgerichtet bleiben
	if player_alive and push_velocity.length() > 5.0 and distance_to_player <= chase_radius:
		facing_override = player.global_position - global_position

	if player_alive and distance_to_player <= effective_attack_radius:
		in_melee_range = true
		_reset_wander_state()
		facing_override = player.global_position - global_position
		face_player()

		# Nur wirklich stehen bleiben, wenn schon nah genug dran (sonst z.B. nach Rückstoß weiter annähern)
		if distance_to_player > attack_radius:
			chase_player()
		else:
			idle()

		# Angriff schon in der Hysterese-Zone, Ausfallschritt schließt die Lücke
		if can_attack:
			attack()
	elif player_alive and distance_to_player <= chase_radius:
		in_melee_range = false
		_reset_wander_state()
		chase_player()
	else:
		in_melee_range = false
		_wander(delta)

	update_animation(facing_override)

func _reset_wander_state():
	is_waiting = false
	wander_target_valid = false
	wander_timer = 0.0
	stuck_timer = 0.0

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
	attack_move_velocity = Vector2.ZERO

func _last_dir_vector() -> Vector2:
	match last_dir:
		"right": return Vector2.RIGHT
		"left": return Vector2.LEFT
		"up": return Vector2.UP
		_: return Vector2.DOWN

# Push isotrop machen (Eigenbewegung entgegen der Push-Richtung abziehen)
func _compose_velocity(self_velocity: Vector2) -> Vector2:
	if push_velocity == Vector2.ZERO:
		return self_velocity

	var push_dir = push_velocity.normalized()
	var along = self_velocity.dot(push_dir)
	if along < 0.0:
		self_velocity -= push_dir * along

	return self_velocity + push_velocity

func face_player():
	var to_player = player.global_position - global_position
	if abs(to_player.x) > abs(to_player.y):
		last_dir = "right" if to_player.x > 0 else "left"
	else:
		last_dir = "down" if to_player.y > 0 else "up"

func chase_player():
	nav_agent.target_position = player.global_position

	if nav_agent.is_navigation_finished():
		idle()
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	nav_agent.set_velocity(direction * speed)

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
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()

		if collider and collider != self and collider.is_in_group("enemies") and collider.has_method("apply_push"):
			var push_dir = -collision.get_normal()
			if push_dir.length() > 0.001:
				collider.apply_push(push_dir.normalized(), ENEMY_TO_ENEMY_PUSH_FORCE * delta)

func attack():
	is_attacking = true
	can_attack = false
	attack_interrupted = false
	nav_agent.set_velocity(Vector2.ZERO)
	velocity = Vector2.ZERO
	_set_footsteps(false)
	AudioManager.play_at("warrior_attack", global_position)

	var lunge_dir = Vector2.DOWN

	if last_dir == "right":
		anim.flip_h = false
		anim.play("attack_side")
		hitbox.position = Vector2(15, 0)
		_apply_shadow_offset(SHADOW_OFFSET_RIGHT)
		lunge_dir = Vector2.RIGHT

	elif last_dir == "left":
		anim.flip_h = true
		anim.play("attack_side")
		hitbox.position = Vector2(-15, 0)
		_apply_shadow_offset(SHADOW_OFFSET_LEFT)
		lunge_dir = Vector2.LEFT

	elif last_dir == "down":
		anim.flip_h = false
		anim.play("attack_down")
		hitbox.position = Vector2(0, 10)
		_apply_shadow_offset(SHADOW_OFFSET_DOWN)
		lunge_dir = Vector2.DOWN

	elif last_dir == "up":
		anim.flip_h = false
		anim.play("attack_up")
		hitbox.position = Vector2(0, -10)
		_apply_shadow_offset(SHADOW_OFFSET_UP)
		lunge_dir = Vector2.UP

	# Kurzer Ausfallschritt zu Beginn des Angriffs
	attack_move_velocity = lunge_dir * lunge_speed
	await get_tree().create_timer(lunge_duration).timeout

	if is_dead or not is_inside_tree():
		return

	attack_move_velocity = Vector2.ZERO

	# Zu weit weggedrückt -> Angriff abbrechen, wieder annähern
	if attack_interrupted:
		_end_attack_early()
		return

	# Schaden im letzten Drittel der Animation
	var frame_count = anim.sprite_frames.get_frame_count(anim.animation)
	var last_third_frame = int(ceil(frame_count * 2.0 / 3.0))
	if last_third_frame >= frame_count:
		last_third_frame = frame_count - 1

	while anim.is_playing() and anim.frame < last_third_frame and not is_dead and is_inside_tree() and not attack_interrupted:
		await get_tree().process_frame

	if is_dead or not is_inside_tree():
		return

	if attack_interrupted:
		_end_attack_early()
		return

	hitbox_shape.set_deferred("disabled", false)
	await get_tree().physics_frame

	if not is_inside_tree():
		return

	# Auch im offenen Trefferfenster noch abbrechen können, sonst landet der
	# Schaden trotz weggedrücktem und optisch abgebrochenem Angriff.
	if attack_interrupted:
		_end_attack_early()
		return

	await get_tree().physics_frame
	hitbox_shape.set_deferred("disabled", true)

	if is_dead or not is_inside_tree():
		return

	if anim.is_playing():
		await anim.animation_finished

	if not is_inside_tree():
		return

	hitbox.position = Vector2.ZERO
	is_attacking = false

	await get_tree().create_timer(attack_cooldown).timeout

	if not is_inside_tree():
		return
	can_attack = true

# --- Angriff wegen Rückstoß vorzeitig beenden, sofort wieder angriffsbereit ---
func _end_attack_early() -> void:
	hitbox_shape.set_deferred("disabled", true)
	hitbox.position = Vector2.ZERO
	is_attacking = false
	can_attack = true

func update_animation(facing_override: Vector2 = Vector2.ZERO) -> void:
	if is_attacking:
		_set_footsteps(false)
		return

	if velocity != Vector2.ZERO:
		_set_footsteps(true)
		var dir = facing_override if facing_override != Vector2.ZERO else velocity

		if abs(dir.x) > abs(dir.y):
			if dir.x > 0:
				anim.flip_h = false
				anim.play("run_side")
				last_dir = "right"
				_apply_shadow_offset(SHADOW_OFFSET_RIGHT)
			else:
				anim.flip_h = true
				anim.play("run_side")
				last_dir = "left"
				_apply_shadow_offset(SHADOW_OFFSET_LEFT)
		else:
			if dir.y > 0:
				anim.flip_h = false
				anim.play("run_down")
				last_dir = "down"
				_apply_shadow_offset(SHADOW_OFFSET_DOWN)
			else:
				anim.flip_h = false
				anim.play("run_up")
				last_dir = "up"
				_apply_shadow_offset(SHADOW_OFFSET_UP)
	else:
		_set_footsteps(false)
		if last_dir == "right":
			anim.flip_h = false
			anim.play("idle_side")
			_apply_shadow_offset(SHADOW_OFFSET_RIGHT)
		elif last_dir == "left":
			anim.flip_h = true
			anim.play("idle_side")
			_apply_shadow_offset(SHADOW_OFFSET_LEFT)
		elif last_dir == "down":
			anim.flip_h = false
			anim.play("idle_down")
			_apply_shadow_offset(SHADOW_OFFSET_DOWN)
		elif last_dir == "up":
			anim.flip_h = false
			anim.play("idle_up")
			_apply_shadow_offset(SHADOW_OFFSET_UP)

func _on_hitbox_body_entered(body):
	if is_dead:
		return

	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(attack_damage)

		if body.has_method("apply_knockback"):
			var dir = body.global_position - global_position
			if dir.length() < 0.001:
				dir = _last_dir_vector()
			body.apply_knockback(dir.normalized(), knockback_to_player)

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

	hitbox_shape.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
	$CollisionShape2D.set_deferred("disabled", true)

	if grants_reward:
		_drop_coins()

	anim.play("death")
	await anim.animation_finished

	Global.try_spawn_skull(self, SKULL_SPAWN_CHANCE)

	die()

# --- Zufällige Münzen beim Tod gutschreiben ---
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
