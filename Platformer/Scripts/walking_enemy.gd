# WalkingEnemy.gd — adds PATROL_SEEK (patrol ↔ seek with linger)
extends CharacterBody2D

enum Behavior { IDLE, PATROL, SEEK, PATROL_SEEK }

@onready var rig: Node2D = $Rig
@onready var anim: AnimatedSprite2D = $Rig/AnimatedSprite2D
@onready var wall_check: RayCast2D = $Rig/WallCheck
@onready var ground_check: RayCast2D = $Rig/GroundCheck
@onready var top_sensor: Area2D = $Rig/TopSensor
@onready var hurtbox: Area2D = $Rig/Hurtbox
@onready var slowable: Slowable = $Slowable
@onready var detection: Area2D = $DetectionZone

# Movement/feel
@export var speed := 60.0
@export var gravity := 1200.0
@export var max_fall_speed := 900.0
@export var stomp_bounce := 420.0
@export var start_dir := -1            # -1 left, +1 right (art authored facing left)

# Behavior (choose in Inspector)
@export var behavior: Behavior = Behavior.PATROL_SEEK
@export var linger_time := 1.0         # seconds to keep chasing after player leaves (for PATROL_SEEK)

var _dir := -1
var _dead := false
var _player: CharacterBody2D = null
var _player_inside := false
var _linger_left := 0.0

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("slowable")

	_dir = sign(start_dir)
	_apply_facing()

	if not top_sensor.body_entered.is_connected(_on_top_sensor_entered):
		top_sensor.body_entered.connect(_on_top_sensor_entered)
	if not hurtbox.body_entered.is_connected(_on_hurtbox_entered):
		hurtbox.body_entered.connect(_on_hurtbox_entered)
	if is_instance_valid(detection):
		if not detection.body_entered.is_connected(_on_detection_enter):
			detection.body_entered.connect(_on_detection_enter)
		if not detection.body_exited.is_connected(_on_detection_exit):
			detection.body_exited.connect(_on_detection_exit)

	if is_instance_valid(wall_check): wall_check.enabled = true
	if is_instance_valid(ground_check): ground_check.enabled = true

	if anim: anim.play("walk")

func _physics_process(delta: float) -> void:
	if _dead: return

	var ts_h := slowable.ts_h()
	var ts_v := slowable.ts_v()
	var d := slowable.td(delta)
	var d_v := slowable.td_v(delta)

	# Gravity
	if not is_on_floor():
		velocity.y = min(velocity.y + gravity * d_v, max_fall_speed * ts_v)
	else:
		velocity.y = 0.0

	# Linger countdown (only used by PATROL_SEEK)
	_linger_left = max(0.0, _linger_left - d)

	match behavior:
		Behavior.IDLE:
			velocity.x = 0.0

		Behavior.PATROL:
			_do_patrol(ts_h)

		Behavior.SEEK:
			if _player_inside and is_instance_valid(_player) and _player.is_inside_tree():
				_seek_horizontal(ts_h)
			else:
				velocity.x = 0.0
				_clear_stale_player()

		Behavior.PATROL_SEEK:
			var chasing := (_player_inside and is_instance_valid(_player) and _player.is_inside_tree()) or _linger_left > 0.0
			if chasing:
				_seek_horizontal(ts_h)
			else:
				_do_patrol(ts_h)
				_clear_stale_player()

	move_and_slide()

	# Anim
	if anim:
		anim.speed_scale = ts_h
		if not is_on_floor():
			if anim.sprite_frames and anim.sprite_frames.has_animation("fall"):
				anim.play("fall")
			else:
				anim.play("walk")
		else:
			var chasing_now := (
				(behavior == Behavior.SEEK and _player_inside) or
				(behavior == Behavior.PATROL_SEEK and (_player_inside or _linger_left > 0.0))
			)
			if behavior == Behavior.IDLE or not chasing_now:
				if anim.sprite_frames and anim.sprite_frames.has_animation("idle"):
					anim.play("idle")
				else:
					anim.play("walk")
			else:
				anim.play("walk")

# --- behavior helpers ---
func _do_patrol(ts_h: float) -> void:
	var hitting_wall := is_instance_valid(wall_check) and wall_check.is_colliding()
	var no_ground_ahead := is_instance_valid(ground_check) and not ground_check.is_colliding()
	if hitting_wall or no_ground_ahead:
		_dir *= -1
		_apply_facing()
	velocity.x = _dir * speed * ts_h

func _seek_horizontal(ts_h: float) -> void:
	# Move horizontally toward player's X while seeking/patrol-seeking
	if is_instance_valid(_player):
		var dx := _player.global_position.x - global_position.x
		_dir = -1 if dx < 0.0 else 1
		_apply_facing()
	velocity.x = _dir * speed * ts_h

func _clear_stale_player() -> void:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = null
		_player_inside = false

# --- facing ---
func _apply_facing() -> void:
	# Art & sensors authored facing LEFT; flip only the Rig subtree (keep physics root unflipped)
	if is_instance_valid(rig):
		rig.scale.x = -1.0 if _dir > 0 else 1.0

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
