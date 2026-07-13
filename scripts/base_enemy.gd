class_name BaseEnemy extends CharacterBody2D 

var current_health = 50.0 

func _ready():
	pass

func die():
	queue_free()
