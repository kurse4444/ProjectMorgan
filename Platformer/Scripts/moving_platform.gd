extends AnimatableBody2D

@onready var slowable: Slowable = $Slowable

# Waypoint mode: use child markers A/B so designers can place them visually
@export var use_markers := true
@export var a: Vector2 = Vector2.ZERO
@export var b: Vector2 = Vector2(256, 0)

@export var speed := 120.0       # units/sec at normal time
@export var wait_time := 0.4     # pause at endpoints (seconds)

var _dir := 1                    # 1: A→B, -1: B→A
var _wait_left := 0.0

func _ready() -> void:
	add_to_group("slowable")  # so bubbles affect it
	if use_markers and has_node("A") and has_node("B"):
		a = $A.global_position
		b = $B.global_position
		$A.visible = false
		$B.visible = false
	global_position = a

func _physics_process(delta: float) -> void:
	var d := slowable.td(delta)

	# optional visual: dim a bit when slowed
	if has_node("Sprite2D"):
		$Sprite2D.modulate.a = lerp(0.6, 1.0, slowable.time_scale)

	# endpoint wait
	if _wait_left > 0.0:
		_wait_left = max(0.0, _wait_left - d)
		return

	var target := b if (_dir == 1) else a
	var to_vec := target - global_position
	var dist := to_vec.length()
	if dist == 0.0:
		_flip_direction()
		return

	var step := speed * d
	if step >= dist:
		global_position = target
		_start_wait()
	else:
		global_position += to_vec.normalized() * step

func _start_wait() -> void:
	_wait_left = wait_time
	_flip_direction()

func _flip_direction() -> void:
	_dir *= -1
