extends Node
class_name Slowable

signal time_scale_changed(old_value: float, new_value: float)

# Active slows: { bubble_node: factor }
var _slow_sources: Dictionary[Node, float] = {}

# Raw min-of-sources before shaping
var time_scale: float = 1.0

# --- Per-entity tuning knobs (set these per actor in the Inspector) ---
@export var immune_to_slow := false     # ignore bubbles entirely for this actor
@export var min_factor := 0.05          # clamp floor to avoid freezing
@export var max_factor := 1.0           # usually 1.0
@export var power_h := 1.0              # horizontal response: >1 = stronger slow, <1 = lighter
@export var power_v := 1.0              # vertical response

func add_slow(source: Node, factor: float) -> void:
	if source == null or immune_to_slow:
		return
	var f: float = clamp(factor, min_factor, max_factor)
	_slow_sources[source] = f
	# Auto-cleanup if the source leaves the tree
	var cb := Callable(self, "_on_source_exited").bind(source)
	if not source.is_connected("tree_exited", cb):
		source.tree_exited.connect(cb, Object.CONNECT_ONE_SHOT)
	_recompute()

func remove_slow(source: Node) -> void:
	if immune_to_slow:
		return
	if source in _slow_sources:
		_slow_sources.erase(source)
	_recompute()

func _on_source_exited(source: Node) -> void:
	remove_slow(source)

func _recompute() -> void:
	if immune_to_slow:
		_set_time_scale(1.0)
		return
	var f := 1.0
	for src in _slow_sources.keys():
		if is_instance_valid(src):
			f = min(f, _slow_sources[src])
		else:
			_slow_sources.erase(src) # prune invalid refs
	_set_time_scale(clamp(f, min_factor, max_factor))

# Centralized setter that emits a signal when time scale changes
func _set_time_scale(new_val: float) -> void:
	if !is_equal_approx(time_scale, new_val):
		var old := time_scale
		time_scale = new_val
		time_scale_changed.emit(old, new_val)

# --- Convenience: shaped scales per axis for THIS entity ---
func ts_h() -> float:
	return 1.0 if immune_to_slow else pow(time_scale, power_h)

func ts_v() -> float:
	return 1.0 if immune_to_slow else pow(time_scale, power_v)

# Time-dilated deltas by axis (optional helpers)
func td(delta: float) -> float:
	return delta if immune_to_slow else delta * time_scale

func td_h(delta: float) -> float:
	return delta if immune_to_slow else delta * ts_h()

func td_v(delta: float) -> float:
	return delta if immune_to_slow else delta * ts_v()

func is_slowed() -> bool:
	return time_scale < 0.999 and !immune_to_slow

func get_time_scale() -> float:
	return 1.0 if immune_to_slow else time_scale
