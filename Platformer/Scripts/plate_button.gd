extends StaticBody2D
class_name PlateButton

signal pressed_started
signal pressed_ended
signal active_changed(is_active: bool) # true while something is on the plate

# --- Press logic ---
@export var recover_delay: float = 0.15            # delay after last body leaves before rising (slowable)
@export var press_groups: Array[StringName] = ["player", "enemy", "crate", "bomb"]

# --- Physical depression of the TOP collider (in pixels) ---
@export var depress_depth: float = 4.0             # how far the top sinks when pressed
@export var press_speed: float = 120.0             # px/sec toward down position (slowable)
@export var rise_speed: float = 180.0              # px/sec toward up position (slowable)

# --- Nodes ---
@onready var slow: Slowable = $Slowable
@onready var top_col: CollisionPolygon2D = $TopCollider
@onready var hitbox: Area2D = $Hitbox
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# --- State ---
enum State { IDLE, PRESSED, RECOVERING }
var _state: State = State.IDLE
var _present_count := 0
var _recover_timer := 0.0
var _is_active := false

# --- Sound ---
@export var pitch_tracks_slow: bool = true  # pitch follows Slowable.time_scale
@export_range(0.0, 0.3, 0.01) var pitch_jitter: float = 0.05  # tiny random variation
@export var click_volume_db: float = 0.0
@export var release_volume_db: float = 0.0

@onready var s_click: AudioStreamPlayer2D = $Click
@onready var s_release: AudioStreamPlayer2D = $Release


# movement target for the collider (local Y offset relative to its rest position)
var _target_y: float = 0.0
var _rest_y: float = 0.0

func _ready() -> void:
	add_to_group("slowable")
	#slow.time_scale_changed.connect(func(old_val: float, new_val: float):
		#print_debug("[", name, "] time_scale:", old_val, "→", new_val)
	#)

	# Remember the rest position of the walkable collider
	_rest_y = top_col.position.y
	_target_y = _rest_y

	# Hook contacts
	hitbox.body_entered.connect(_on_body_entered)
	hitbox.body_exited.connect(_on_body_exited)

	# Animated sprite speed follows local time
	if is_instance_valid(anim):
		anim.play("idle")
		anim.speed_scale = slow.get_time_scale()
		slow.time_scale_changed.connect(func(_o,_n): anim.speed_scale = slow.get_time_scale())

	if is_instance_valid(s_click):
		s_click.volume_db = click_volume_db
	if is_instance_valid(s_release):
		s_release.volume_db = release_volume_db

	# optional: keep pitch tied to local time scale live
	#slow.time_scale_changed.connect(func(_o,_n):
		#_update_audio_pitch()
	#)
	_update_audio_pitch()


func _physics_process(delta: float) -> void:
	var dt := slow.td(delta)

	# Timer for recover delay
	if _state == State.RECOVERING:
		_recover_timer -= dt
		if _recover_timer <= 0.0:
			_enter_idle()

	# Move the walkable top toward its target (slowable speeds)
	var y := top_col.position.y
	var speed := rise_speed if _target_y == _rest_y else press_speed
	var dir := signf(_target_y - y)
	if dir != 0.0:
		var step := speed * dt * dir
		# Clamp to avoid overshoot
		if absf(step) > absf(_target_y - y): 
			y = _target_y
		else:
			y += step
		top_col.position.y = y

func _on_body_entered(body: Node) -> void:
	#print_debug("[Button] body_entered:", body.name, " type:", body.get_class())
	if !_body_counts(body):
		#print_debug("[Button]   -> ignored (not in press_groups)")
		return
	_present_count += 1
	#print_debug("[Button]   -> counted, present_count =", _present_count)
	if _present_count == 1:
		_enter_pressed()

func _on_body_exited(body: Node) -> void:
	#print_debug("[Button] body_exited:", body.name)
	if !_body_counts(body):
		#print_debug("[Button]   -> ignored (not in press_groups)")
		return
	_present_count = max(0, _present_count - 1)
	#print_debug("[Button]   -> counted, present_count =", _present_count)
	if _present_count == 0:
		_enter_recovering()

func _body_counts(body: Node) -> bool:
	for g in press_groups:
		if body.is_in_group(g):
			return true
	return false

# ---------- State changes ----------
func _enter_pressed() -> void:
	_state = State.PRESSED
	_set_active(true)
	_target_y = _rest_y + depress_depth
	if is_instance_valid(anim):
		anim.play("press")
	_play_with_jitter(s_click)
	pressed_started.emit()

func _enter_recovering() -> void:
	_state = State.RECOVERING
	_recover_timer = recover_delay
	_set_active(false)
	_target_y = _rest_y  # start rising immediately (visual + physical), but final "idle" fires after delay
	if is_instance_valid(anim):
		anim.play("release")

func _enter_idle() -> void:
	_state = State.IDLE
	if is_instance_valid(anim):
		anim.play("idle")
	_play_with_jitter(s_release)
	pressed_ended.emit()

func _set_active(v: bool) -> void:
	if _is_active == v:
		return
	_is_active = v
	active_changed.emit(_is_active)

func is_active() -> bool:
	return _is_active
	
func _update_audio_pitch() -> void:
	var p := slow.get_time_scale() if pitch_tracks_slow else 1.0
	if is_instance_valid(s_click):   s_click.pitch_scale = p
	if is_instance_valid(s_release): s_release.pitch_scale = p

func _play_with_jitter(player: AudioStreamPlayer2D) -> void:
	if !is_instance_valid(player) or player.stream == null: return
	var base := player.pitch_scale
	var j := randf_range(-pitch_jitter, pitch_jitter)
	player.pitch_scale = max(0.01, base + j)
	player.play()
	player.pitch_scale = base  # restore for next time
