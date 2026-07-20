extends Area2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 230.0
var damage: float = 10.0
var knockback_strength: float = 70.0
var shooter: Node = null

const MAX_LIFETIME = 2.5
var _lifetime = 0.0

func _ready():
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta):
	if not is_inside_tree():
		return

	global_position += direction * speed * delta

	_lifetime += delta
	if _lifetime > MAX_LIFETIME:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.name != "Hurtbox":
		return

	var hit_player = area.get_parent()
	if not hit_player.is_in_group("player"):
		return

	if hit_player == shooter:
		return

	if hit_player.has_method("take_damage"):
		hit_player.take_damage(damage, "arrow")

	if hit_player.has_method("apply_knockback"):
		hit_player.apply_knockback(direction.normalized(), knockback_strength)

	queue_free()

func _on_body_entered(body):
	if body == shooter:
		return

	if body.is_in_group("enemies"):
		return

	if body.is_in_group("player"):
		return

	queue_free()
