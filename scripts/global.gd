extends Node

var player_current_health = 100.0
var player_total_coins = 0
var player_healing_flasks = 0
var checkpoint_health = 100.0
var checkpoint_coins = 0
var checkpoint_healing_flasks = 0

# --- Schlüssel (1=Bronze, 2=Silber, 3=Gold), Reihenfolge = Sammelreihenfolge ---
var player_keys: Array = []
var checkpoint_keys: Array = []

# --- Bereits aufgeschlossene Türen ---
var unlocked_doors: Array = []
var checkpoint_unlocked_doors: Array = []

# --- Bereits geöffnete Kisten/Crates ---
var opened_chests: Array = []
var checkpoint_opened_chests: Array = []

# --- Bereits zerstörte Barrels ---
var destroyed_barrels: Array = []
var checkpoint_destroyed_barrels: Array = []

# --- Bereits zerschlagene Spinnweben ---
var destroyed_cobwebs: Array = []
var checkpoint_destroyed_cobwebs: Array = []

# --- Bereits eingesammelte Pickups (Coins, Keys, Flasks) ---
var collected_pickups: Array = []
var checkpoint_collected_pickups: Array = []

# --- Bereits getötete Gegner ---
var dead_enemies: Array = []
var checkpoint_dead_enemies: Array = []

# --- HP noch lebender, aber schon verletzter Gegner ---
var enemy_health: Dictionary = {}
var checkpoint_enemy_health: Dictionary = {}

# --- Spawnpunkt für die nächste Sublevel-Ankunft (durch welche Tür man kommt) ---
var pending_spawn_id: String = ""
var checkpoint_pending_spawn_id: String = ""

# Gewichteter Zufallswert: weights[i] = Gewicht für Ergebnis i
func weighted_random(weights: Array) -> int:
	var total = 0
	for w in weights:
		total += w

	var roll = randi() % total
	var cumulative = 0
	for i in weights.size():
		cumulative += weights[i]
		if roll < cumulative:
			return i

	return weights.size() - 1

# --- Beschwörung: sterbende Skelette hinterlassen manchmal einen Skull ---
const SKULL_SCENE = preload("res://scenes/Enemies/skull.tscn")
const SUMMONED_SKULL_HEALTH = 10.0

var summoned_skulls: Array = []
var checkpoint_summoned_skulls: Array = []

var _next_summon_id = 1

# Instanz-ID der zuletzt gesehenen Szene, um Szenenwechsel UND Reloads zu erkennen
var _last_scene_instance_id = 0

func _process(_delta):
	var scene = get_tree().current_scene
	if scene == null or scene.get_instance_id() == _last_scene_instance_id:
		return

	_last_scene_instance_id = scene.get_instance_id()
	_restore_summoned_skulls(scene)

func try_spawn_skull(source: Node2D, chance: float) -> Node2D:
	if source == null or not source.is_inside_tree():
		return null

	if randf() >= chance:
		return null

	var scene = source.get_tree().current_scene
	if scene == null or scene.scene_file_path == "":
		return null

	var record = {
		"id": _next_summon_id,
		"scene": scene.scene_file_path,
		"position": source.global_position,
		"health": SUMMONED_SKULL_HEALTH,
	}
	_next_summon_id += 1
	summoned_skulls.append(record)

	return _instantiate_summoned_skull(scene, record)

# Beim Betreten/Neuladen einer Szene alle dort hinterlegten Skulls zurückholen
func _restore_summoned_skulls(scene: Node) -> void:
	if scene.scene_file_path == "":
		return

	for record in summoned_skulls:
		if record["scene"] == scene.scene_file_path:
			_instantiate_summoned_skull(scene, record)

func _instantiate_summoned_skull(parent: Node, record: Dictionary) -> Node2D:
	var skull = SKULL_SCENE.instantiate()
	skull.is_summoned = true
	skull.summon_id = record["id"]
	skull.max_health = SUMMONED_SKULL_HEALTH
	skull.current_health = record["health"]

	parent.add_child(skull)

	var spawn_position: Vector2 = record["position"]
	skull.global_position = spawn_position
	skull.start_position = spawn_position
	skull.stuck_check_position = spawn_position

	return skull

func update_summoned_skull(id: int, position: Vector2, health: float) -> void:
	for record in summoned_skulls:
		if record["id"] == id:
			record["position"] = position
			record["health"] = health
			return

func remove_summoned_skull(id: int) -> void:
	for i in summoned_skulls.size():
		if summoned_skulls[i]["id"] == id:
			summoned_skulls.remove_at(i)
			return

# Stabile, Sublevel-eindeutige ID für ein Objekt (über Reloads hinweg konstant)
func object_id(node: Node) -> String:
	var scene_root = node
	var tree_root = node.get_tree().root
	while scene_root.get_parent() != null and scene_root.get_parent() != tree_root:
		scene_root = scene_root.get_parent()
	return str(scene_root.scene_file_path) + "::" + str(scene_root.get_path_to(node))

# --- Mauszeiger ---
const MENU_CURSOR_PATH = "res://assets/UI/cursor.png"
const MENU_CURSOR_HOTSPOT = Vector2(0, 0)
const MENU_CURSOR_SCALE = 2.0
const MENU_CURSOR_MAX_SIZE = 256

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

	var cursor_texture = _load_scaled_cursor(MENU_CURSOR_PATH, MENU_CURSOR_SCALE)
	if cursor_texture:
		Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, MENU_CURSOR_HOTSPOT * MENU_CURSOR_SCALE)
	set_gameplay_cursor()

func _load_scaled_cursor(path: String, scale: float) -> ImageTexture:
	var texture = load(path)
	if texture == null:
		return null

	var image: Image = texture.get_image()
	if image == null:
		return null

	image = image.duplicate()

	var new_width = int(image.get_width() * scale)
	var new_height = int(image.get_height() * scale)
	new_width = clampi(new_width, 1, MENU_CURSOR_MAX_SIZE)
	new_height = clampi(new_height, 1, MENU_CURSOR_MAX_SIZE)

	# Nearest-Neighbor, damit Pixel-Art beim Hochskalieren scharf bleibt.
	image.resize(new_width, new_height, Image.INTERPOLATE_NEAREST)

	return ImageTexture.create_from_image(image)

func set_gameplay_cursor():
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func set_menu_cursor():
	# Nur zentrieren, wenn der Zeiger vorher versteckt war - also beim Wechsel
	# aus dem Spiel in ein Menü. Zwischen zwei Menübildschirmen ist er ohnehin
	# schon sichtbar und bleibt dann liegen, wo der Spieler ihn gelassen hat.
	var came_from_gameplay = Input.mouse_mode == Input.MOUSE_MODE_HIDDEN

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if came_from_gameplay:
		center_mouse()

# Im Gameplay ist der Zeiger versteckt und wandert trotzdem mit. Ohne das
# Zentrieren taucht er beim Öffnen von Pausenmenü oder Todesscreen an einer
# beliebigen Stelle wieder auf.
func center_mouse() -> void:
	var window = get_window()
	if window == null:
		return

	Input.warp_mouse(Vector2(window.size) / 2.0)

# Eine Heilung, die beim Szenenwechsel noch lief, nachträglich gutschreiben.
# Der Checkpoint wird mit angehoben: Die Tür setzt ihn beim Durchgehen, also zu
# einem Zeitpunkt, an dem der Trank bereits verbraucht war. Ohne die Korrektur
# stünde man nach einem späteren Tod wieder ohne Trank und ohne HP da.
func credit_pending_heal(amount: float, max_health: float) -> void:
	player_current_health = min(player_current_health + amount, max_health)
	checkpoint_health = min(checkpoint_health + amount, max_health)

func save_checkpoint():
	checkpoint_health = player_current_health
	checkpoint_coins = player_total_coins
	checkpoint_healing_flasks = player_healing_flasks
	checkpoint_keys = player_keys.duplicate()
	checkpoint_unlocked_doors = unlocked_doors.duplicate()
	checkpoint_opened_chests = opened_chests.duplicate()
	checkpoint_destroyed_barrels = destroyed_barrels.duplicate()
	checkpoint_destroyed_cobwebs = destroyed_cobwebs.duplicate()
	checkpoint_collected_pickups = collected_pickups.duplicate()
	checkpoint_dead_enemies = dead_enemies.duplicate()
	checkpoint_enemy_health = enemy_health.duplicate()
	checkpoint_summoned_skulls = summoned_skulls.duplicate(true)
	checkpoint_pending_spawn_id = pending_spawn_id

# Setzt den kompletten Fortschritt zurück. Ohne diesen Aufruf würde ein neu
# gestartetes Spiel mit allen getöteten Gegnern, geöffneten Truhen und
# eingesammelten Items der vorherigen Runde beginnen. Muss aufgerufen werden,
# sobald es einen "Neues Spiel"-Einstieg gibt.
func reset_progress():
	player_current_health = 100.0
	player_total_coins = 0
	player_healing_flasks = 0
	player_keys.clear()

	unlocked_doors.clear()
	opened_chests.clear()
	destroyed_barrels.clear()
	destroyed_cobwebs.clear()
	collected_pickups.clear()
	dead_enemies.clear()
	enemy_health.clear()
	summoned_skulls.clear()
	pending_spawn_id = ""

	save_checkpoint()

func load_checkpoint():
	player_current_health = checkpoint_health
	player_total_coins = checkpoint_coins
	player_healing_flasks = checkpoint_healing_flasks
	player_keys = checkpoint_keys.duplicate()
	unlocked_doors = checkpoint_unlocked_doors.duplicate()
	opened_chests = checkpoint_opened_chests.duplicate()
	destroyed_barrels = checkpoint_destroyed_barrels.duplicate()
	destroyed_cobwebs = checkpoint_destroyed_cobwebs.duplicate()
	collected_pickups = checkpoint_collected_pickups.duplicate()
	dead_enemies = checkpoint_dead_enemies.duplicate()
	enemy_health = checkpoint_enemy_health.duplicate()
	summoned_skulls = checkpoint_summoned_skulls.duplicate(true)
	pending_spawn_id = checkpoint_pending_spawn_id
