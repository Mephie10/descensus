extends BaseEnemy

const CHASE_SPEED = 60.0
const WANDER_SPEED = 30.0

@onready var anim = $AnimatedSprite2D
@onready var collision = $CollisionShape2D
@onready var nav_agent = $NavigationAgent2D
@onready var hitbox = $Hitbox
@onready var hitbox_collision = $Hitbox/CollisionShape2D

# Angriffsrichtung, für Hitbox-Versatz und Treffer-Kegel
var attack_direction = Vector2.DOWN
const HITBOX_OFFSET = 11.0

var player = null
var is_dead = false
var max_health = 30.0
var attack_damage = 10.0
var enemy_id = ""

# Zur Laufzeit von einem sterbenden Skelett beschworen. Solche Skulls werden
# nicht über enemy_id, sondern über Global.summoned_skulls gespeichert.
var is_summoned = false
var summon_id = 0

# --- Münz-Drop bei Tod: 0-2, meistens 1 ---
const COIN_DROP_WEIGHTS = [1, 4, 1]

var start_position: Vector2
var wander_target: Vector2
var is_chasing = false
var is_waiting = false

var is_attacking = false
var can_attack = true

var wander_radius = 60.0
var detection_radius = 110.0
var attack_radius = 34.0
var attack_cooldown = 1.25
var last_direction = Vector2.DOWN

var wander_timer = 0.0
const MAX_WANDER_TIME = 5.0

# --- Wegdrücken durch den Spieler ---
var push_velocity: Vector2 = Vector2.ZERO
var push_friction = 175.0
var max_push_speed = CHASE_SPEED * 0.6

# --- Wegdrücken zwischen Gegnern ---
const ENEMY_TO_ENEMY_PUSH_FORCE = 250.0
var _physics_delta = 0.0

# --- Rückstoß bei Treffern ---
var knockback_strength = 88.0
var knockback_to_player = 90.0

# Push-Stärke, ab der ein laufender Dash abgebrochen wird
const PUSH_CANCEL_THRESHOLD = 12.0

# Dash-Bewegung, getrennt von velocity/push gehalten
var attack_move_velocity: Vector2 = Vector2.ZERO

# --- Nahkampf-Hysterese ---
var in_melee_range = false
var melee_hysteresis = 8.0

var wander_target_valid = false

# _pick_new_wander_target() läuft über mehrere Frames. Ohne diese Sperre kann es
# bei Dauerkontakt pro Physikframe erneut starten und dutzende Coroutinen
# überschreiben sich gegenseitig das Navigationsziel.
var _picking_wander_target = false

# --- Stuck-Erkennung beim Wandern ---
var stuck_timer = 0.0
var stuck_check_position: Vector2
const STUCK_TIME_THRESHOLD = 0.6
const STUCK_DISTANCE_THRESHOLD = 4.0

func _init():
	current_health = 30.0

func _ready():
	# Beschworene Skulls sind flüchtig und nehmen am Speichersystem nicht teil
	if not is_summoned:
		enemy_id = Global.object_id(self)

		# Schon getötet -> gar nicht erst erscheinen
		if Global.dead_enemies.has(enemy_id):
			is_dead = true
			queue_free()
			return

	super()
	if is_queued_for_deletion():
		return

	# Gespeicherte HP wiederherstellen (Position bleibt die Spawn-Position)
	if not is_summoned and Global.enemy_health.has(enemy_id):
		current_health = Global.enemy_health[enemy_id]

	player = get_tree().get_first_node_in_group("player")
	start_position = global_position
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

func _exit_tree():
	if not is_summoned or is_dead:
		return
	if not is_instance_valid(Global):
		return
	Global.update_summoned_skull(summon_id, global_position, current_health)

func _on_safe_velocity_computed(safe_velocity: Vector2):
	if is_dead or is_attacking:
		return

	velocity = _compose_velocity(safe_velocity)
	move_and_slide()

	for i in get_slide_collision_count():
		var slide_col = get_slide_collision(i)
		if slide_col.get_collider() == player:
			if not is_chasing and not is_attacking:
				_pick_new_wander_target()
			velocity = Vector2.ZERO
			break

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

func _physics_process(delta):
	if is_dead:
		return

	_physics_delta = delta

	if push_velocity != Vector2.ZERO:
		push_velocity = push_velocity.move_toward(Vector2.ZERO, push_friction * delta)

	var facing_override = Vector2.ZERO

	if is_instance_valid(player) and not player.is_dead:
		var distance_to_player = global_position.distance_to(player.global_position)
		var effective_attack_radius = attack_radius + (melee_hysteresis if in_melee_range else 0.0)

		if distance_to_player <= effective_attack_radius:
			in_melee_range = true
			if global_position.distance_squared_to(player.global_position) > 0.0001:
				facing_override = global_position.direction_to(player.global_position)
			if can_attack and not is_attacking:
				_attack_player()
		else:
			in_melee_range = false

		if distance_to_player < detection_radius:
			is_chasing = true
			is_waiting = false
		elif distance_to_player > detection_radius * 1.5:
			is_chasing = false
	else:
		is_chasing = false
		in_melee_range = false

	if is_attacking:
		# Push bricht laufenden Dash ab
		if push_velocity.length() > PUSH_CANCEL_THRESHOLD:
			attack_move_velocity = Vector2.ZERO

		if is_instance_valid(player):
			var current_dist = global_position.distance_to(player.global_position)
			if current_dist <= 22.0:
				attack_move_velocity = Vector2.ZERO

		velocity = _compose_velocity(attack_move_velocity)
		move_and_slide()
		_push_colliding_enemies(delta)

	else:
		if is_chasing:
			_chase_player()
		else:
			_wander(delta)

		nav_agent.velocity = velocity

		var move_dir = Vector2.ZERO
		if velocity.length() > 5.0:
			move_dir = velocity.normalized()

		_update_animation(move_dir, move_dir != Vector2.ZERO, facing_override)

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

# Push isotrop machen (Eigenbewegung entgegen der Push-Richtung abziehen)
func _compose_velocity(self_velocity: Vector2) -> Vector2:
	if push_velocity == Vector2.ZERO:
		return self_velocity

	var push_dir = push_velocity.normalized()
	var along = self_velocity.dot(push_dir)
	if along < 0.0:
		self_velocity -= push_dir * along

	return self_velocity + push_velocity

func _attack_player():
	is_attacking = true
	can_attack = false

	var direction = (player.global_position - global_position).normalized()
	last_direction = direction
	attack_direction = direction

	if abs(direction.x) > abs(direction.y):
		anim.play("attack_side")
		anim.flip_h = direction.x < 0
	elif direction.y > 0:
		anim.play("attack_down")
		anim.flip_h = false
	elif direction.y < 0:
		anim.play("attack_up")
		anim.flip_h = false

	hitbox.position = direction * HITBOX_OFFSET

	attack_move_velocity = direction * (CHASE_SPEED * 1.4)
	velocity = attack_move_velocity

	await get_tree().create_timer(0.30).timeout

	if is_dead or not is_inside_tree():
		return

	attack_move_velocity = Vector2.ZERO
	velocity = Vector2.ZERO

	hitbox_collision.set_deferred("disabled", false)
	await get_tree().physics_frame

	if not is_inside_tree():
		return
	await get_tree().physics_frame
	hitbox_collision.set_deferred("disabled", true)
	hitbox.position = Vector2.ZERO

	if is_dead or not is_inside_tree():
		return

	await anim.animation_finished

	if not is_inside_tree():
		return

	is_attacking = false

	await get_tree().create_timer(attack_cooldown).timeout

	if not is_inside_tree():
		return
	can_attack = true

func _chase_player():
	nav_agent.target_position = player.global_position

	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return

	var next_path_position = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_position)

	velocity = direction * CHASE_SPEED

func _wander(delta):
	if is_waiting:
		velocity = Vector2.ZERO
		return

	wander_timer += delta
	nav_agent.target_position = wander_target

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
		velocity = Vector2.ZERO
		_start_waiting()
		return

	var next_path_position = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_position)

	velocity = direction * WANDER_SPEED

func _start_waiting():
	if is_waiting:
		return

	is_waiting = true
	wander_target_valid = false

	await get_tree().create_timer(randf_range(1.0, 3.0)).timeout

	if is_dead or not is_inside_tree():
		return

	if not is_chasing:
		is_waiting = false
		_pick_new_wander_target()

func _pick_new_wander_target():
	if _picking_wander_target:
		return

	_picking_wander_target = true

	# Physik-Frame abwarten, bevor is_target_reachable() geprüft wird
	for _attempt in range(8):
		if is_dead:
			_picking_wander_target = false
			return

		var random_x = randf_range(-wander_radius, wander_radius)
		var random_y = randf_range(-wander_radius, wander_radius)
		var candidate = start_position + Vector2(random_x, random_y)

		nav_agent.target_position = candidate
		await get_tree().physics_frame

		if is_dead or not is_inside_tree():
			_picking_wander_target = false
			return

		if nav_agent.is_target_reachable():
			wander_target = candidate
			wander_target_valid = true
			wander_timer = 0.0
			stuck_timer = 0.0
			stuck_check_position = global_position
			_picking_wander_target = false
			return

	wander_target_valid = false
	wander_target = global_position
	wander_timer = 0.0
	_picking_wander_target = false

func _update_animation(move_direction: Vector2, is_moving: bool, facing_override: Vector2 = Vector2.ZERO) -> void:
	if is_attacking:
		return

	if velocity.length() < 5.0:
		is_moving = false

	var facing = facing_override if facing_override != Vector2.ZERO else move_direction

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

# grants_reward = false, wenn der Tod nicht dem Spieler zuzurechnen ist
# (z.B. eine Falle). Dann gibt es keine Muenzen.
func take_damage(amount, grants_reward: bool = true):
	if is_dead:
		return

	current_health -= amount
	if is_summoned:
		Global.update_summoned_skull(summon_id, global_position, current_health)
	else:
		Global.enemy_health[enemy_id] = current_health
	print("Schädel getroffen! Restliche HP: ", current_health)

	var tween = create_tween()
	tween.tween_property(anim, "modulate", Color.RED, 0.15)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.1)

	if current_health <= 0:
		is_dead = true
		if is_summoned:
			Global.remove_summoned_skull(summon_id)
		else:
			Global.dead_enemies.append(enemy_id)
			Global.enemy_health.erase(enemy_id)
		velocity = Vector2.ZERO
		push_velocity = Vector2.ZERO
		attack_move_velocity = Vector2.ZERO

		if grants_reward:
			_drop_coins()

		anim.play("death")
		collision.set_deferred("disabled", true)
		$Hurtbox/CollisionShape2D.set_deferred("disabled", true)

		await anim.animation_finished
		queue_free()

# --- Zufällige Münzen beim Tod gutschreiben ---
func _drop_coins() -> void:
	var amount = Global.weighted_random(COIN_DROP_WEIGHTS)
	if amount > 0 and is_instance_valid(player) and player.has_method("add_coins"):
		player.add_coins(amount)


func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.name != "Hurtbox":
		return

	var hit_player = area.get_parent()

	# Nur der Spieler wird getroffen, keine anderen Gegner
	if not hit_player.is_in_group("player"):
		return

	# Kein Treffer von hinten/der Seite
	var to_player = (hit_player.global_position - global_position)
	if to_player.length() > 0.001 and to_player.normalized().dot(attack_direction) < -0.1:
		return

	if hit_player.has_method("take_damage"):
		hit_player.take_damage(attack_damage)

	if hit_player.has_method("apply_knockback"):
		var dir = to_player
		if dir.length() < 0.001:
			dir = attack_direction
		hit_player.apply_knockback(dir.normalized(), knockback_to_player)
