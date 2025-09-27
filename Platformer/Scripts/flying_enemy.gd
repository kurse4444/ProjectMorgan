# FlyingEnemy.gd — modes: IDLE, PATROL, SEEK, PATROL_SEEK (with linger)
# Scene:
# CharacterBody2D (root) [this script]
# ├─ CollisionShape2D                  # main body collider (NOT under Rig)
# ├─ Slowable
# ├─ DetectionZone (Area2D + CollisionShape2D)   # mask must include player
# └─ Rig (Node2D) -> AnimatedSprite2D, TopSensor (Area2D), Hurtbox (Area2D)
# Optional: two Marker2D waypoints; set via inspector (waypoint_a_path / waypoint_b_path)

extends CharacterBody2D

enum Behavior { IDLE, PATROL, SEEK, PATROL_SEEK }

@onready var rig: Node2D = $Rig
@onready var anim: AnimatedSprite2D = $Rig/AnimatedSprite2D
@onready var top_sensor: Area2D = $Rig/TopSensor
@onready var hurtbox: Area2D = $Rig/Hurtbox
@onready var slowable: Slowable = $Slowable
@onready var detection: Area2D = $DetectionZone

@export var speed := 80.0
@export var bob_amplitude := 6.0
@export var bob_speed := 2.0
@export var arrive_threshold := 8.0
@export var start_dir := -1            # -1 left, +1 right (art authored facing left)
@export var stomp_bounce := 420.0

# behavior config
@export var behavior: Behavior = Behavior.SEEK
@export var linger_time := 1.0         # seconds to keep chasing after player leaves (PATROL_SEEK)

# optional waypoints for PATROL
@export var waypoint_a_path: NodePath
@export var waypoint_b_path: NodePath

var _dir := -1
var _dead := false
var _t := 0.0
var _a: Node2D
var _b: Node2D
var _target_is_a := false

var _player: CharacterBody2D = null
var _player_inside := false
var _linger_left := 0.0

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("slowable")

	_a = get_node_or_null(waypoint_a_path)
	_b = get_node_or_null(waypoint_b_path)

	_dir = sign(start_dir)
	_apply_facing()

	# signals
	if not top_sensor.body_entered.is_connected(_on_top_sensor_entered):
		top_sensor.body_entered.connect(_on_top_sensor_entered)
	if not hurtbox.body_entered.is_connected(_on_hurtbox_entered):
		hurtbox.body_entered.connect(_on_hurtbox_entered)
	if is_instance_valid(detection):
		if not detection.body_entered.is_connected(_on_detection_enter):
			detection.body_entered.connect(_on_detection_enter)
		if not detection.body_exited.is_connected(_on_detection_exit):
			detection.body_exited.connect(_on_detection_exit)

	if anim:
		anim.play("fly")

func _physics_process(delta: float) -> void:
	if _dead: return

	var ts_h := slowable.ts_h()
	var d := slowable.td(delta)

	# bob timer (slows in bubbles)
	_t += d * bob_speed
	# linger countdown (PATROL_SEEK)
	_linger_left = max(0.0, _linger_left - d)

	match behavior:
		Behavior.IDLE:
			velocity = Vector2.ZERO
			velocity.y += sin(_t) * bob_amplitude

		Behavior.PATROL:
			_do_patrol(ts_h)
			# idle-ish bob on top of patrol motion
			velocity.y += sin(_t) * bob_amplitude
			_clear_stale_player()

		Behavior.SEEK:
			if _player_inside and is_instance_valid(_player) and _player.is_inside_tree():
				_seek_to_player(ts_h)
			else:
				velocity = Vector2.ZERO
				velocity.y += sin(_t) * bob_amplitude
				_clear_stale_player()

		Behavior.PATROL_SEEK:
			var chasing := (_player_inside and is_instance_valid(_player) and _player.is_inside_tree()) or _linger_left > 0.0
			if chasing:
				_seek_to_player(ts_h)
			else:
				_do_patrol(ts_h)
			velocity.y += sin(_t) * bob_amplitude
			if not chasing:
				_clear_stale_player()

	# face move dir (flip Rig; art authored facing LEFT)
	if absf(velocity.x) > 0.01:
		_dir = -1 if velocity.x < 0.0 else 1
		_apply_facing()

	move_and_slide()

	# anim speed scales with horizontal slow
	if anim:
		anim.speed_scale = ts_h
		var chasing_now := (
			(behavior == Behavior.SEEK and _player_inside) or
			(behavior == Behavior.PATROL_SEEK and (_player_inside or _linger_left > 0.0))
		)
		if behavior == Behavior.IDLE or not chasing_now:
			if anim.sprite_frames and anim.sprite_frames.has_animation("idle"):
				anim.play("idle")
			else:
				anim.play("fly")
		else:
			anim.play("fly")

# --- helpers ---
func _do_patrol(ts_h: float) -> void:
	var target := _pick_patrol_target()
	var to_target := target - global_position
	velocity = to_target.normalized() * speed * ts_h
	if to_target.length() <= arrive_threshold:
		_target_is_a = !_target_is_a

func _seek_to_player(ts_h: float) -> void:
	if is_instance_valid(_player):
		var to_target := _player.global_position - global_position
		velocity = to_target.normalized() * speed * ts_h
	else:
		velocity = Vector2.ZERO

func _pick_patrol_target() -> Vector2:
	if is_instance_valid(_a) and is_instance_valid(_b):
		return _a.global_position if _target_is_a else _b.global_position
	# fallback: hover left/right 100px from spawn
	return global_position + Vector2(-100, 0) if _target_is_a else global_position + Vector2(100, 0)

func _apply_facing() -> void:
	if is_instance_valid(rig):
		rig.scale.x = -1.0 if _dir > 0 else 1.0

func _clear_stale_player() -> void:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = null
		_player_inside = false

# --- detection ---
func _on_detection_enter(body: Node) -> void:
	if _dead: return
	if body.is_in_group("player") and body is CharacterBody2D:
		_player = body as CharacterBody2D
		_player_inside = true
		_linger_left = linger_time  # refresh on entry too

func _on_detection_exit(body: Node) -> void:
	if _dead: return
	if body == _player:
		_player_inside = false
		_linger_left = linger_time  # start linger countdown

# --- collisions ---
func _on_top_sensor_entered(body: Node) -> void:
	if _dead: return
	if body.is_in_group("player") and body is CharacterBody2D:
		var p := body as CharacterBody2D
		# BEFORE: p.velocity.y = -stomp_bounce * slowable.ts_v()
		p.velocity.y = -stomp_bounce  # unscaled by enemy bubble slow
		die()

func _on_hurtbox_entered(body: Node) -> void:
	if _dead: return
	if body.is_in_group("player") and "die" in body:
		body.die()

# --- death ---
func die() -> void:
	if _dead: return
	_dead = true
	
	add_to_group("dying")  # <-- tell spawner we're no longer occupying a slot
	
	# disable collisions / sensors
	if is_instance_valid(hurtbox): hurtbox.set_deferred("monitoring", false)
	if is_instance_valid(top_sensor): top_sensor.set_deferred("monitoring", false)
	if is_instance_valid(detection): detection.set_deferred("monitoring", false)

	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO

	# play death anim with custom speed scale
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("die"):
		anim.play("die")
		# force minimum animation speed
		anim.speed_scale = max(anim.speed_scale, 0.4)   # 1.0 = normal speed
		if not anim.animation_finished.is_connected(_on_die_anim_done):
			anim.animation_finished.connect(_on_die_anim_done, CONNECT_ONE_SHOT)
	else:
		queue_free()


func _on_die_anim_done() -> void:
	queue_free()
