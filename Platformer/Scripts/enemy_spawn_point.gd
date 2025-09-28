# EnemySpawnPoint.gd — Godot 4.x
@tool
extends Node2D

signal spawned(enemy: Node)
signal enemy_despawned(enemy: Node)
signal all_cleared()

# ---------------- Enemy & placement ----------------
@export var enemy_scene: PackedScene
@export var spawn_parent_path: NodePath      # if empty → use get_parent()
@export var spawn_positions_path: NodePath   # e.g. "SpawnPositions" with Marker2D children
@export var randomize_positions := true

# --- Optional: set initial mode/behavior on each spawned enemy ---
enum EnemyMode { INHERIT = -1, IDLE = 0, PATROL = 1, SEEK = 2, PATROL_SEEK = 3 }

@export var set_behavior_on_spawn := true
@export var behavior_mode: EnemyMode = EnemyMode.INHERIT  # choose from the list
@export var behavior_name: String = ""                    # OR type "IDLE", "PATROL", "SEEK", "PATROL_SEEK"

# ---------------- Spawn cadence ----------------
@export var spawn_on_ready := true
@export var initial_delay := 0.0             # seconds before first wave try
@export var spawn_interval := 5.0            # seconds between wave tries
@export var spawn_interval_jitter := 0.0     # +/- seconds added to intervals
@export var per_wave_count := 1              # max new spawns per wave/refill tick
@export var per_spawn_delay := 0.08          # seconds between spawns inside a wave/refill (0 = no delay)
@export var spawn_position_jitter := Vector2(8, 2)  # small random offset so they don’t overlap; set (0,0) to disable

# ---------------- Limits / targets ----------------
@export var max_concurrent := 1              # 0 = unlimited
@export var total_max_spawns := 0            # 0 = unlimited total over lifetime

# Maintain a constant number of active enemies (target).
# If >0, this is the target. If 0, it uses max_concurrent (if >0). If both 0 → no maintenance.
@export var target_concurrent := 0
@export var maintain_active := true

# ---------------- Respawn after death ----------------
@export var respawn_on_death := true
@export var respawn_delay := 2.0             # seconds between refill ticks

# ---------------- Activation gates (optional) ----------------
@export var require_player_in_radius := false
@export var activation_radius := 450.0
@export var require_on_screen := false       # needs a VisibleOnScreenNotifier2D child

# --- Optional: pass 2-marker patrol waypoints to enemies on spawn ---
@export var set_waypoints_on_spawn := false
@export var waypoint_a: NodePath
@export var waypoint_b: NodePath
@export var arrive_threshold_override := 0.0   # 0 = leave enemy's default
@export var pause_at_marker_override := -1.0   # <0 = leave enemy's default

# ---------------- Debug & editor viz ----------------
@export var debug_draw := true
@export var debug_color: Color = Color(0.2, 1.0, 0.4, 0.6)
@export var debug_print := false   # enable/disable console debug prints

const MIN_WAIT := 0.001

var _active: Array[Node] = []
var _total_spawned := 0
var _spawn_timer: Timer
var _first_tick_done := false
var _refill_timer: Timer
var _positions: Array[Node2D] = []
var _spawn_parent: Node
var _notifier: VisibleOnScreenNotifier2D

var _pending_wave := false
var _pending_wave_wait := 0.0
var _pending_refill := false
var _pending_refill_wait := 0.0

func _ready() -> void:
	_positions = _collect_positions()
	_spawn_parent = get_node_or_null(spawn_parent_path)
	if _spawn_parent == null:
		_spawn_parent = get_parent()

	_notifier = get_node_or_null("VisibleOnScreenNotifier2D") as VisibleOnScreenNotifier2D

	if Engine.is_editor_hint():
		queue_redraw()
		return

	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = false
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)

	if spawn_on_ready:
		_schedule_next_wave(initial_delay)
	else:
		_first_tick_done = true

	_refill_timer = Timer.new()
	_refill_timer.one_shot = true
	add_child(_refill_timer)
	_refill_timer.timeout.connect(_on_refill_timeout)
	
	# --- flush any pending schedules now that timers exist and we're in-tree ---
	if _pending_wave and _spawn_timer:
		var wv := _pending_wave_wait
		_pending_wave = false
		_pending_wave_wait = 0.0
		call_deferred("_deferred_start_spawn", wv)

	if _pending_refill and _refill_timer:
		var rv := _pending_refill_wait
		_pending_refill = false
		_pending_refill_wait = 0.0
		call_deferred("_deferred_start_refill", rv)


func _deferred_start_spawn(wait: float) -> void:
	if not is_inside_tree() or _spawn_timer == null:
		return
	_spawn_timer.stop()
	_spawn_timer.wait_time = max(wait, MIN_WAIT)
	_spawn_timer.start()

func _deferred_start_refill(wait: float) -> void:
	if not is_inside_tree() or _refill_timer == null:
		return
	_refill_timer.stop()
	_refill_timer.wait_time = max(wait, MIN_WAIT)
	_refill_timer.start()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and debug_draw:
		queue_redraw()

# ---------------- Public API ----------------
func start_spawning() -> void:
	if _spawn_timer == null:
		return
	_schedule_next_wave(initial_delay if not _first_tick_done else spawn_interval)

func stop_spawning(clear_active := false) -> void:
	if _spawn_timer: _spawn_timer.stop()
	if _refill_timer: _refill_timer.stop()
	if clear_active: _clear_all()

func force_spawn_now(count := 1) -> void:
	_try_spawn(count, true)

# ---------------- Timer callback ----------------
func _on_spawn_timer_timeout() -> void:
	_first_tick_done = true
	_compact_active_list()
	_dbg("wave-before")
		# Spawn up to per_wave_count but never beyond our target / limits
	var need := _remaining_to_target()
	if need > 0:
		var want : int = min(per_wave_count, need)
		if debug_print:
			print("[wave] want=", want)
		var if_spawned := await _try_spawn(want, true)
		if debug_print:
			print("[wave] spawned=", if_spawned)
	_dbg("wave-after")
	_schedule_next_wave(spawn_interval)

# ---------------- Refill timer (coalesced) ----------------
func _queue_refill_after(wait: float) -> void:
	var w : float = max(MIN_WAIT, wait)
	
	# If we're not in the tree (e.g., during level reset), pend this request
	if not is_inside_tree():
		_pending_refill = true
		_pending_refill_wait = w
		return
		
	_refill_timer.stop()          # coalesce multiple deaths into one refill tick
	_refill_timer.wait_time = w
	_refill_timer.start()

func _on_refill_timeout() -> void:
	_compact_active_list()
	await _incremental_refill()

# Spawn at most per_wave_count now; if still missing, schedule another tick.
func _incremental_refill() -> void:
	if not respawn_on_death:
		return
	var need := _remaining_to_target()
	if need <= 0:
		return
	var spawned_now := await _try_spawn(min(per_wave_count, need), true)
	need -= spawned_now
	if need > 0:
		# keep trickling in more after respawn_delay
		_queue_refill_after(respawn_delay)

# ---------------- Core spawn logic ----------------
func _try_spawn(wanted: int, enforce_target := true) -> int:
	if enemy_scene == null:
		push_warning("%s: enemy_scene is not set" % name)
		return 0

	var spawned_now := 0
	for i in range(wanted):
		# Re-check limits *each* spawn (caps/targets may change while we wait)
		if total_max_spawns > 0 and _total_spawned >= total_max_spawns:
			break
		if require_on_screen and _notifier and not _notifier.is_on_screen():
			break
		if require_player_in_radius and not _player_within_radius():
			break

		var capacity := _remaining_concurrent()
		var allowed := capacity
		if enforce_target:
			allowed = min(allowed, _remaining_to_target())
		if allowed <= 0:
			break

		var enemy := _spawn_one(spawned_now)
		if enemy != null:
			spawned_now += 1

		# Stagger next spawn in this wave/refill
		if i < wanted - 1 and per_spawn_delay > 0.0:
			await get_tree().create_timer(per_spawn_delay).timeout

	return spawned_now


# ---------------- Target math ----------------
func _remaining_concurrent() -> int:
	if max_concurrent <= 0:
		return 999999
	return max(0, max_concurrent - _alive_active_count())

func _remaining_to_target() -> int:
	var target := _target_count()
	if target <= 0:
		return _remaining_concurrent()
	return clamp(target - _alive_active_count(), 0, _remaining_concurrent())

func _target_count() -> int:
	if not maintain_active:
		return 0
	if target_concurrent > 0:
		return target_concurrent
	return max(0, max_concurrent)

# ---------------- Utils ----------------
func _player_within_radius() -> bool:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p == null: return false
	return p.global_position.distance_squared_to(global_position) <= activation_radius * activation_radius

func _schedule_next_wave(base: float) -> void:
	if _spawn_timer == null:
		return
	var wait := base + _jitter_amount()
	if wait <= 0.0:
		call_deferred("_run_wave_now")
		return
	
	# If we're not in the tree yet, remember it and do it later
	if not is_inside_tree():
		_pending_wave = true
		_pending_wave_wait = max(wait, MIN_WAIT)
		return
	
	_spawn_timer.stop()
	_spawn_timer.wait_time = max(wait, MIN_WAIT)
	_spawn_timer.start()

func _run_wave_now() -> void:
	_first_tick_done = true
	_compact_active_list()
	var need := _remaining_to_target()
	if need > 0:
		await _try_spawn(min(per_wave_count, need), true)
	if spawn_interval > 0.0:
		_schedule_next_wave(spawn_interval)

func _jitter_amount() -> float:
	if spawn_interval_jitter <= 0.0: return 0.0
	return randf_range(-spawn_interval_jitter, spawn_interval_jitter)

func _collect_positions() -> Array[Node2D]:
	var arr: Array[Node2D] = []
	var holder := get_node_or_null(spawn_positions_path)
	if holder:
		for c in holder.get_children():
			if c is Node2D:
				arr.append(c)
	return arr

func _compact_active_list() -> void:
	for e in _active.duplicate():
		if not is_instance_valid(e) or not e.is_inside_tree():
			_active.erase(e)

func _clear_all() -> void:
	for e in _active.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	_active.clear()
	all_cleared.emit()
	
func _alive_active_count() -> int:
	var count := 0
	for e in _active:
		if is_instance_valid(e) and e.is_inside_tree() and not e.is_in_group("dying"):
			count += 1
	return count

func _pick_spawn_position(spawned_index: int) -> Vector2:
	var pos := global_position
	if _positions.size() > 0:
		pos = (_positions[randi() % _positions.size()]
			if randomize_positions
			else _positions[spawned_index % _positions.size()]).global_position
	if spawn_position_jitter != Vector2.ZERO:
		pos += Vector2(
			randf_range(-spawn_position_jitter.x, spawn_position_jitter.x),
			randf_range(-spawn_position_jitter.y, spawn_position_jitter.y)
		)
	return pos

func _spawn_one(spawned_index: int) -> Node:
	var enemy := enemy_scene.instantiate()
	if enemy == null:
		return null
		
	_apply_initial_mode(enemy)
	_apply_waypoints(enemy)
		
	var pos := _pick_spawn_position(spawned_index)
	if enemy is Node2D:
		(enemy as Node2D).global_position = pos
	_spawn_parent.add_child(enemy)
	_active.append(enemy)
	_total_spawned += 1
	enemy.tree_exited.connect(_on_enemy_gone.bind(enemy), CONNECT_ONE_SHOT)
	spawned.emit(enemy)
	return enemy

func _has_property(obj: Object, prop: StringName) -> bool:
	var plist := obj.get_property_list()
	for p in plist:
		if p.name == prop:
			return true
	return false

func _mode_from_name(enemy_mode: String) -> int:
	var n := enemy_mode.strip_edges().to_upper()
	match n:
		"IDLE": return EnemyMode.IDLE
		"PATROL": return EnemyMode.PATROL
		"SEEK": return EnemyMode.SEEK
		"PATROL_SEEK", "PATROL-SEEK", "PATROLSEEK": return EnemyMode.PATROL_SEEK
		_: return EnemyMode.INHERIT

func _apply_initial_mode(enemy: Object) -> void:
	if not set_behavior_on_spawn:
		return
	var mode := EnemyMode.INHERIT
	if behavior_name != "":
		mode = _mode_from_name(behavior_name)
	else:
		mode = behavior_mode
	if mode == EnemyMode.INHERIT:
		return
	# Only set if the enemy actually has an exported "behavior" property
	if _has_property(enemy, "behavior"):
		enemy.set("behavior", mode)

func _apply_waypoints(enemy: Object) -> void:
	if not set_waypoints_on_spawn:
		return

	var a_node := get_node_or_null(waypoint_a)
	var b_node := get_node_or_null(waypoint_b)
	if a_node == null or b_node == null:
		return

	var a_path: NodePath = a_node.get_path()
	var b_path: NodePath = b_node.get_path()

	# Always assign spawner’s waypoints if available
	if _has_property(enemy, "waypoint_a_path"):
		enemy.set("waypoint_a_path", a_path)
	if _has_property(enemy, "waypoint_b_path"):
		enemy.set("waypoint_b_path", b_path)

	# Also make sure enemy actually uses them if it has that toggle
	if _has_property(enemy, "use_waypoints_if_set"):
		enemy.set("use_waypoints_if_set", true)

	# Optional overrides
	if arrive_threshold_override > 0.0 and _has_property(enemy, "arrive_threshold"):
		enemy.set("arrive_threshold", arrive_threshold_override)

	if pause_at_marker_override >= 0.0 and _has_property(enemy, "pause_at_marker"):
		enemy.set("pause_at_marker", pause_at_marker_override)

# ---------------- Callbacks ----------------
func _on_enemy_gone(enemy: Node) -> void:
	_active.erase(enemy)
	enemy_despawned.emit(enemy)
	if respawn_on_death:
		_queue_refill_after(respawn_delay + _jitter_amount())

# ---------------- Editor gizmos ----------------
func _draw() -> void:
	if not debug_draw:
		return
	if require_player_in_radius and activation_radius > 0.0:
		draw_circle(Vector2.ZERO, activation_radius, debug_color)
	var pts := _collect_positions()
	for m in pts:
		var g := to_local(m.global_position)
		draw_circle(g, 6.0, debug_color)
		draw_line(Vector2.ZERO, g, debug_color, 2.0)

func _dbg(tag: String) -> void:
	if not debug_print:
		return
	print("[%s] per_wave=%d alive=%d activeSize=%d need=%d max_conc=%d target=%d" % [
		tag, per_wave_count, _alive_active_count(), _active.size(),
		_remaining_to_target(), max_concurrent, _target_count()
	])
