extends CanvasLayer

@onready var color_rect = $ColorRect

var fade_time = 0.5

func _ready():
	color_rect.modulate.a = 0.0
	process_mode = Node.PROCESS_MODE_ALWAYS

func change_scene(next_scene_path: String):
	get_tree().paused = true

	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(color_rect, "modulate:a", 1.0, fade_time)
	await tween.finished

	await RenderingServer.frame_post_draw
	await get_tree().process_frame

	get_tree().change_scene_to_file(next_scene_path)

	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	var tween_out = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween_out.tween_property(color_rect, "modulate:a", 0.0, fade_time)
	await tween_out.finished

	get_tree().paused = false

func reload_scene():
	get_tree().paused = true

	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(color_rect, "modulate:a", 1.0, fade_time)
	await tween.finished

	await RenderingServer.frame_post_draw
	await get_tree().process_frame

	get_tree().reload_current_scene()

	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	var tween_out = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween_out.tween_property(color_rect, "modulate:a", 0.0, fade_time)
	await tween_out.finished

	get_tree().paused = false
