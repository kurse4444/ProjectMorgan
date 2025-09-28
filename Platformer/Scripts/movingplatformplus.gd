extends AnimatableBody2D
class_name MovingPlatformPlus

# --- Nodes ---
@onready var slowable: Slowable = $Slowable

# --- Waypoints ---
@export var use_markers: bool = true
@export var markers_root: NodePath = NodePath("Markers")  # Node2D containing Marker2D children
@export var a: Vector2 = Vector2.ZERO                      # fallback start
@export var b: Vector2 = Vector2(256, 0)                   # fallback end

# --- Motion ---
enum LoopMode { PING_PONG, LOOP_PATH }
@export var loop_mode: LoopMode = LoopMode.PING_PONG

enum TravelMode { BY_SPEED, BY_DURATION }
@export var travel_mode: TravelMode = TravelMode.BY_SPEED

@export_range(1.0, 2000.0, 1.0) var speed: float = 120.0       # units/sec when BY_SPEED
@export_range(0.05, 30.0, 0.01) var duration: float = 2.0      # seconds *per segment* when BY_DURATION

# --- Easing ---
@export var easing: Curve     # if null, linear

# --- Endpoint waits ---
@export_range(0.0, 10.0, 0.01) var wait_time: float = 0.4
@export var waits_use_slow_time: bool = true
@export var wait_at_all_points: bool = true


# --- State ---
var _dir: int = 1            # +1 forward through the list, -1 backward
var _t: float = 0.0          # normalized progress along *current segment*
var _wait_left: float = 0.0
var _prev_pos: Vector2 = Vector2.ZERO

var platform_velocity: Vector2 = Vector2.ZERO

# Waypoint cache
var _points: Array[Vector2] = []
var _i_from: int = 0         # current segment start index in _points
var _i_to: int = 1           # current segment end   index in _points

func _ready() -> void:
	add_to_group("slowable")

	_build_points()
	_init_motion()

func _build_points() -> void:
	_points.clear()

	if use_markers:
		var root := get_node_or_null(markers_root)
		if root:
			for c in root.get_children():
				if c is Node2D:
					_points.append((c as Node2D).global_position)
					# Hide markers visually (optional)
					if c is CanvasItem:
						(c as CanvasItem).visible = false

	# Fallbacks if no markers or too few:
	if _points.size() < 2:
		if has_node("A") and has_node("B"):
			_points = [($A as Node2D).global_position, ($B as Node2D).global_position]
			($A as CanvasItem).visible = false
			($B as CanvasItem).visible = false
		else:
			_points = [a, b]

func _init_motion() -> void:
	# Start at first point; go forward
	_i_from = 0
	_i_to   = min(1, _points.size() - 1)
	_dir    = 1
	_t      = 0.0
	global_position = _points[0]
	_prev_pos = global_position

func _physics_process(delta: float) -> void:
	var d: float = slowable.td(delta)
	var rt: float = delta

	# Optional visual feedback when slowed
	if has_node("Sprite2D"):
		($Sprite2D as Sprite2D).modulate.a = lerp(0.6, 1.0, slowable.time_scale)

	# Waits (endpoints only)
	if _wait_left > 0.0:
		_wait_left = max(0.0, _wait_left - (d if waits_use_slow_time else rt))
		platform_velocity = Vector2.ZERO
		_prev_pos = global_position
		return

	# Guard: need at least two points
	if _points.size() < 2:
		platform_velocity = Vector2.ZERO
		return

	# Current segment endpoints
	var start: Vector2 = _points[_i_from]
	var target: Vector2 = _points[_i_to]

	# Advance normalized progress along the current segment
	var leg_len: float = (target - start).length()
	var dt_norm: float = 0.0
	if travel_mode == TravelMode.BY_SPEED:
		var norm_speed: float = speed / max(leg_len, 0.0001)
		dt_norm = norm_speed * d
	else:
		dt_norm = (1.0 / max(duration, 0.0001)) * d

	_t = clamp(_t + dt_norm, 0.0, 1.0)

	# Easing
	var eased_t: float = (easing.sample_baked(_t) if easing else _t)

	# New position
	var new_pos: Vector2 = start.lerp(target, eased_t)

	# Velocity for riders
	var frame_delta: Vector2 = new_pos - global_position
	platform_velocity = (frame_delta / max(d, 1e-6)) if d > 0.0 else Vector2.ZERO

	# Apply
	global_position = new_pos

	# Segment finished?
	if _t >= 1.0:
		_on_segment_finished()

	_prev_pos = global_position

func _on_segment_finished() -> void:
	_t = 0.0

	# Wait here?
	if wait_time > 0.0:
		if wait_at_all_points:
			_wait_left = wait_time
		else:
			var at_end_forward := (_i_to == _points.size() - 1) and (_dir == 1)
			var at_end_backward := (_i_to == 0) and (_dir == -1)
			if at_end_forward or at_end_backward:
				_wait_left = wait_time

	# Advance to the next segment
	_i_from = _i_to
	var next_to: int = _i_to + _dir

	if next_to < 0 or next_to >= _points.size():
		if loop_mode == LoopMode.PING_PONG:
			_dir *= -1
			next_to = _i_to + _dir
		else:
			# LOOP_PATH: wrap to start
			_i_from = 0
			_i_to = 1
			global_position = _points[0]
			return

	_i_to = next_to


# --- Debug gizmo in editor ---
func _draw() -> void:
	if Engine.is_editor_hint():
		# draw the waypoint polyline + points
		for i in range(_points.size() - 1):
			draw_line(_points[i] - global_position, _points[i + 1] - global_position, Color(0.3, 0.9, 1.0), 2.0)
		for p in _points:
			draw_circle(p - global_position, 4.0, Color(0.6, 0.6, 1.0))

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()
