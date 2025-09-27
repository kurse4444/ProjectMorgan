extends AnimatableBody2D
class_name MovingPlatformPlus

# --- Nodes ---
@onready var slowable: Slowable = $Slowable
#@onready var passenger_area: Area2D = $PassengerArea

# --- Waypoints ---
@export var use_markers := true
@export var a: Vector2 = Vector2.ZERO
@export var b: Vector2 = Vector2(256, 0)

# --- Motion ---
enum LoopMode { PING_PONG, LOOP_AB }
@export var loop_mode: LoopMode = LoopMode.PING_PONG

enum TravelMode { BY_SPEED, BY_DURATION }
@export var travel_mode: TravelMode = TravelMode.BY_SPEED

@export_range(1.0, 2000.0, 1.0) var speed := 120.0      # units/sec when BY_SPEED
@export_range(0.05, 30.0, 0.01) var duration := 2.0     # seconds A→B when BY_DURATION

# --- Easing ---
# If null, movement is linear. Use a Curve that maps [0..1] -> [0..1] (e.g. ease in/out)
@export var easing: Curve

# --- Endpoint waits ---
@export_range(0.0, 10.0, 0.01) var wait_time := 0.4          # seconds to pause at endpoints
@export var waits_use_slow_time := true                       # if false, waits are real-time

# --- Passengers (optional) ---
@export var carry_passengers := true
#@export var passenger_group := "passenger"   # bodies in this group will be moved with the platform

# --- State ---
var _dir := 1                  # 1: A→B, -1: B→A
var _t := 0.0                  # normalized progress along current leg [0..1]
var _wait_left := 0.0
var _prev_pos := Vector2.ZERO

# Velocity the platform moved *this physics frame*; others can read it
var platform_velocity: Vector2 = Vector2.ZERO

# For carrying
#var _passengers := {}  # Set[Node2D]

func _ready() -> void:
	add_to_group("slowable")  # so bubbles affect it
	if use_markers and has_node("A") and has_node("B"):
		a = $A.global_position
		b = $B.global_position
		$A.visible = false
		$B.visible = false

	global_position = a
	_prev_pos = global_position
	_t = 0.0
	_dir = 1

	#if is_instance_valid(passenger_area):
		## Track who stands on the platform
		#passenger_area.monitoring = true
		#passenger_area.body_entered.connect(_on_passenger_entered)
		#passenger_area.body_exited.connect(_on_passenger_exited)

func _physics_process(delta: float) -> void:
	var d := slowable.td(delta)
	var rt := delta  # real time (unscaled)

	# Optional visual feedback when slowed
	if has_node("Sprite2D"):
		$Sprite2D.modulate.a = lerp(0.6, 1.0, slowable.time_scale)

	# Handle waits (choose time base)
	if _wait_left > 0.0:
		_wait_left = max(0.0, _wait_left - (d if waits_use_slow_time else rt))
		# Still update velocity (zero while waiting)
		platform_velocity = Vector2.ZERO
		_prev_pos = global_position
		return

	# Advance normalized t along the current leg
	var leg_len := (b - a).length()
	var dt_norm := 0.0
	if travel_mode == TravelMode.BY_SPEED:
		# Convert world speed to normalized speed
		var norm_speed : float = (speed / max(leg_len, 0.0001))
		dt_norm = norm_speed * d
	else:
		# BY_DURATION: finish the leg exactly in 'duration' (slowable scales motion)
		dt_norm = (1.0 / max(duration, 0.0001)) * d

	_t += dt_norm

	# Clamp/ease position
	var raw_t : float = clamp(_t, 0.0, 1.0)
	var eased_t : float = easing.sample_baked(raw_t) if easing else raw_t

	var start := a if _dir == 1 else b
	var target := b if _dir == 1 else a
	var new_pos := start.lerp(target, eased_t)

	# Compute per-frame velocity before applying position (for riders)
	var frame_delta := new_pos - global_position
	platform_velocity = (frame_delta / max(d, 1e-6)) if d > 0.0 else Vector2.ZERO

	# Apply motion
	global_position = new_pos

	# Carry passengers by the *same displacement* this frame (safer than teleport on join)
	#if carry_passengers and frame_delta != Vector2.ZERO:
		#_carry_passengers(frame_delta)

	# Reached end of leg?
	if _t >= 1.0:
		_on_leg_finished()

	_prev_pos = global_position

func _on_leg_finished() -> void:
	_t = 0.0
	if wait_time > 0.0:
		_wait_left = wait_time

	if loop_mode == LoopMode.PING_PONG:
		_dir *= -1
	else:
		# LOOP_AB: jump back to A after reaching B, always move A->B
		if _dir == 1:
			# finished A->B; start B->A only to reset, then immediately flip back
			global_position = b
		else:
			global_position = a
		_dir = 1

#func _on_passenger_entered(body: Node) -> void:
	#if not carry_passengers:
		#return
	#if body.is_in_group(passenger_group) and body is Node2D:
		#_passengers[body] = true

#func _on_passenger_exited(body: Node) -> void:
	#_passengers.erase(body)
#
#func _carry_passengers(frame_delta: Vector2) -> void:
	## Move any tracked passenger by the exact platform displacement this frame.
	## This is simple and works for Node2D/CharacterBody2D. (RigidBody2D is not recommended.)
	#for p in _passengers.keys():
		#if is_instance_valid(p) and p is Node2D:
			## Only nudge if still roughly on top (avoids pulling from the side)
			#p.global_position += frame_delta

# --- Debug gizmo in editor ---
func _draw() -> void:
	if Engine.is_editor_hint():
		draw_line(a - global_position, b - global_position, Color(0.3, 0.9, 1.0), 2.0)
		draw_circle(a - global_position, 4.0, Color(0.6, 0.6, 1.0))
		draw_circle(b - global_position, 4.0, Color(0.6, 0.6, 1.0))

func _notification(what):
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()
