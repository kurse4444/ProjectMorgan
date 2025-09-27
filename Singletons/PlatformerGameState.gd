# res://GameState.gd
extends Node

const SAVE_PATH := "user://checkpoints.cfg"

# scene_path -> checkpoint_id (String)
var _scene_checkpoint: Dictionary = {}

func _ready() -> void:
	_load()

func set_checkpoint_id(checkpoint_id: String) -> void:
	var scene_path := get_tree().current_scene.scene_file_path
	_scene_checkpoint[scene_path] = checkpoint_id
	_save()

func get_checkpoint_id_for_current_scene() -> String:
	var scene_path := get_tree().current_scene.scene_file_path
	return str(_scene_checkpoint.get(scene_path, ""))

func has_checkpoint_for_current_scene() -> bool:
	return get_checkpoint_id_for_current_scene() != ""

func get_spawn_for_scene(scene: Node) -> Vector2:
	var wanted_id := get_checkpoint_id_for_current_scene()
	if wanted_id == "":
		return Vector2.ZERO

	for cp in scene.get_tree().get_nodes_in_group("checkpoints"):
		if cp is Checkpoint and str(cp.checkpoint_id) == wanted_id:
			return cp.spawn_marker.global_position

	return Vector2.ZERO


# --- Save/Load (ID only) ---
func _save() -> void:
	var cfg := ConfigFile.new()
	for scene_path in _scene_checkpoint.keys():
		cfg.set_value("checkpoints", scene_path, _scene_checkpoint[scene_path])
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if cfg.has_section("checkpoints"):
		for scene_path in cfg.get_section_keys("checkpoints"):
			_scene_checkpoint[scene_path] = str(cfg.get_value("checkpoints", scene_path, ""))
