class_name BaseEnemy extends CharacterBody2D 

var current_health = 50.0

func _ready():
	if Global.destroyed_objects.has(str(get_path())):
		queue_free()
		return
	
	if Global.enemy_data.has(str(get_path())):
		var saved_data = Global.enemy_data[str(get_path())]
		global_position = saved_data["position"]
		current_health = saved_data["hp"]

func die():
	Global.destroyed_objects.append(str(get_path()))
	if Global.enemy_data.has(str(get_path())):
		Global.enemy_data.erase(str(get_path()))
	queue_free()
