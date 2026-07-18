extends Area2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 260.0
var damage: float = 12.0
var knockback_strength: float = 70.0
var shooter: Node = null

const MAX_LIFETIME = 2.5
var _lifetime = 0.0

func _ready():
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if not is_inside_tree():
		return

	global_position += direction * speed * delta

	_lifetime += delta
	if _lifetime > MAX_LIFETIME:
		queue_free()

# --- Trifft Spieler oder bleibt an einer Wand/einem Hindernis stecken ---
func _on_body_entered(body):
	if body == shooter:
		return

	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)

		if body.has_method("apply_knockback"):
			body.apply_knockback(direction.normalized(), knockback_strength)

	queue_free()
