# res://Singletons/Unlocks.gd
extends Node

signal milestone_marked(id: String)
signal action_unlocked(id: String)
signal state_loaded()

@export_file("*.json") var config_path := "res://platformer/data/unlocks.json"

# Loaded from JSON:
var _action_requirements: Dictionary = {}  # "MODE:Action" -> Array[String] of milestone IDs
var _friendly_names: Dictionary = {}       # optional "ID" -> "Display Name"

# Persistent progress (we only save milestones):
var _milestones: Dictionary = {}           # "MODE:Thing" -> true
var _unlocked: Dictionary = {}             # cache: "MODE:Action" -> bool

const SAVE_PATH := "user://progress.json"

func _ready() -> void:
	_load_requirements()
	load_save()
	recompute_unlocked()

# --------- Public API ---------

func mark_milestone(id: String) -> void:
	if _milestones.get(id, false):
		return
	_milestones[id] = true
	emit_signal("milestone_marked", id)
	recompute_unlocked()
	save()

func has_milestone(id: String) -> bool:
	return _milestones.get(id, false)

func can(action_id: String) -> bool:
	if _unlocked.has(action_id):
		return _unlocked[action_id]
	return _check_action_now(action_id)

func missing_requirements(action_id: String) -> Array[String]:
	var reqs: Array = _action_requirements.get(action_id, [])
	var missing: Array[String] = []
	for r in reqs:
		if not has_milestone(r):
			missing.append(r)
	return missing

func explain_gate(action_id: String) -> String:
	var miss := missing_requirements(action_id)
	if miss.is_empty():
		return ""
	var pretty: Array[String] = []
	for id in miss:
		pretty.append(_friendly_names.get(id, id))
	return "Locked: do " + ", ".join(pretty)

# Optional helpers:
func name_of(id: String) -> String:
	return _friendly_names.get(id, id)

func reload_config() -> void:
	_load_requirements()
	recompute_unlocked()

# --------- Core logic ---------

func recompute_unlocked() -> void:
	var newly_unlocked: Array[String] = []
	for action_id in _action_requirements.keys():
		var before: bool = _unlocked.get(action_id, false)
		var now := _check_action_now(action_id)
		_unlocked[action_id] = now
		if now and not before:
			newly_unlocked.append(action_id)
	for a in newly_unlocked:
		emit_signal("action_unlocked", a)

func _check_action_now(action_id: String) -> bool:
	var reqs: Array = _action_requirements.get(action_id, [])
	for r in reqs:
		if not has_milestone(r):
			return false
	return true

# --------- Save / Load progress ---------

func save() -> void:
	var data := {
		"milestones": _milestones
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var data := parsed as Dictionary
		_milestones = data.get("milestones", {})
		recompute_unlocked()
		emit_signal("state_loaded")
	else:
		push_error("[Unlocks] Save file is not a JSON object.")

# --------- JSON loading & validation ---------

func _load_requirements() -> void:
	if not FileAccess.file_exists(config_path):
		push_error("[Unlocks] JSON not found: %s" % config_path)
		_action_requirements = {}
		_friendly_names = {}
		return

	var f := FileAccess.open(config_path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		push_error("[Unlocks] Invalid JSON in %s" % config_path)
		return

	if parsed is Dictionary:
		var dict := parsed as Dictionary
		_action_requirements = dict.get("actions", {})
		_friendly_names = dict.get("names", {})
	else:
		push_error("[Unlocks] Root must be a JSON object (Dictionary).")

	_validate_dependencies()

func _validate_dependencies() -> void:
	# Warn on unknown shapes / non-arrays
	for action_id in _action_requirements.keys():
		var reqs = _action_requirements[action_id]
		if typeof(reqs) != TYPE_ARRAY:
			push_warning("[Unlocks] '%s' requirements must be an array." % action_id)
	# Tiny hygiene check on IDs
	for action_id in _action_requirements.keys():
		if action_id.find(":") == -1:
			push_warning("[Unlocks] Action id '%s' should look like 'MODE:Action'." % action_id)
