extends RigidBody2D

@onready var slowable: Slowable = $Slowable                          # NEW
@onready var fuse_anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var area: Area2D = $BlastArea
@onready var blast_shape: CollisionShape2D = $BlastArea/CollisionShape2D
@onready var top_sensor: Area2D = $TopSensor
@onready var tilemap: TileMapLayer = _find_tilemaplayer()

# Tuning
@export var fuse_time: float = 1.0
@export var arm_time: float = 0.4
@export var boost_power: float = 500.0
@export var side_knockback: float = 200.0
@export var upright_damp := 10.0

@export var self_destruct_time: float = 1.2	# seconds; set ≈ your longest explode clip

@export var player_layer_bit: int = 2			# you said Player is on layer 2
@export var throw_grace_time: float = 0.10		# initial tiny delay before we start checking

# SFX
@export var explode_sfx: AudioStream
@export var explode_sfx_bus: StringName = &"SFX"	# pick your audio bus
@export var explode_sfx_volume_db: float = 0.0		# tweak loudness

@onready var body_shape: CollisionShape2D = $BombShape


func _set_mask_bit(bit: int, enable: bool) -> void:
	var flag := 1 << (bit - 1)
	collision_mask = (collision_mask | flag) if enable else (collision_mask & ~flag)

enum ExplodeMode { NORMAL, STOMP }
var _mode: int = ExplodeMode.NORMAL

# State
var _armed: bool = false
var _started: bool = false
var _effects_fired: bool = false
var _stomped_body: CharacterBody2D = null
const ANIM_EXPLODE := "explode"
const ANIM_EXPLODE_STOMP := "explode_stomp"

# Time-dilated countdowns (replace Timers so bubbles affect them)
var _fuse_left: float = 0.0
var _arm_left: float = 0.0

# For smooth time-scale transitions (optional but nice)
var _prev_ts_h := 1.0
var _prev_ts_v := 1.0

func _ready() -> void:
	add_to_group("slowable")                               # bomb is slowable, too
	add_to_group("bomb")

	# Start idle anim
	if fuse_anim:
		fuse_anim.play("idle")

	# Initialize per-axis scales and connect change signal (keeps motion consistent
	# when entering/exiting a bubble mid-flight)
	_prev_ts_h = slowable.ts_h()
	_prev_ts_v = slowable.ts_v()
	if not slowable.is_connected("time_scale_changed", Callable(self, "_on_ts_changed")):
		slowable.time_scale_changed.connect(_on_ts_changed)

	# Arm/fuse start (time-dilated)
	_arm_left = arm_time
	_fuse_left = fuse_time

	# Stomp detection
	if not top_sensor.body_entered.is_connected(_on_top_sensor_entered):
		top_sensor.body_entered.connect(_on_top_sensor_entered)
	# Disarm sensor until armed to avoid spawn-overlap stomps
	top_sensor.set_deferred("monitoring", false)

	# Arm TopSensor after real-time delay (unaffected by bubble)
	var arm_t := get_tree().create_timer(arm_time)
	arm_t.timeout.connect(func():
		_armed = true
		top_sensor.set_deferred("monitoring", true)
	)


	angular_damp = 12.0

func _on_ts_changed(_old: float, _new: float) -> void:
	# Rescale current velocities so entering a bubble doesn’t overshoot
	var nh := slowable.ts_h()
	var nv := slowable.ts_v()
	if _prev_ts_h > 0.0:
		linear_velocity.x *= nh / _prev_ts_h
		angular_velocity   *= nh / _prev_ts_h
	if _prev_ts_v > 0.0:
		linear_velocity.y *= nv / _prev_ts_v
	_prev_ts_h = nh
	_prev_ts_v = nv

func _physics_process(dt: float) -> void:
	# Time-dilated dt for countdowns and “fake forces”
	var d := slowable.td(dt)
	var ts_h := slowable.ts_h()
	var ts_v := slowable.ts_v()

	# Upright damping slowed by bubble
	angular_velocity -= rotation * upright_damp * d

	if not _started:
		_fuse_left -= d
		if _fuse_left <= 0.0:
			_mode = ExplodeMode.NORMAL
			explode()

	# Slow the animation to match horizontal time
	if fuse_anim:
		fuse_anim.speed_scale = ts_h

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Per-axis “time scale” for rigidbody movement each physics tick.
	# This approximates true slow-mo for RB2D by scaling velocities.
	var ts_h := slowable.ts_h()
	var ts_v := slowable.ts_v()
	var v := state.linear_velocity
	v.x *= ts_h
	v.y *= ts_v
	state.linear_velocity = v
	state.angular_velocity *= ts_h

func get_blast_radius() -> float:
	var circle := blast_shape.shape as CircleShape2D
	return circle.radius if circle else 0.0

func _on_top_sensor_entered(body: Node) -> void:
	if not (body is CharacterBody2D): return
	if not _armed or _effects_fired: return
	print("STOMP ENTER: armed=", _armed, " started=", _started, " mode=", _mode)
	if _started and _mode == ExplodeMode.NORMAL:
		call_deferred("_convert_normal_explosion_to_stomp", body as CharacterBody2D)
		return

	if _started: return
	_stomped_body = body as CharacterBody2D
	_mode = ExplodeMode.STOMP
	call_deferred("explode")

func _convert_normal_explosion_to_stomp(p: CharacterBody2D) -> void:
	if _effects_fired: return
	_mode = ExplodeMode.STOMP
	_stomped_body = p

	# 1) Fire stomp effects immediately (launch player, clear tiles, etc.)
	_do_explosion_effects()
	_effects_fired = true

	# 2) If we were in the long explode, switch to the short stomp clip
	if fuse_anim and fuse_anim.sprite_frames and fuse_anim.sprite_frames.has_animation(ANIM_EXPLODE_STOMP):
		fuse_anim.play(ANIM_EXPLODE_STOMP)
		# Make sure we still free on animation end
		if not fuse_anim.animation_finished.is_connected(_on_explode_anim_done):
			fuse_anim.animation_finished.connect(_on_explode_anim_done, CONNECT_ONE_SHOT)
	else:
		# 3) Safety: if no stomp clip exists, free soon anyway
		var t := get_tree().create_timer(0.30)
		t.timeout.connect(_on_explode_anim_done, CONNECT_ONE_SHOT)


func explode() -> void:
	if _started: return
	_started = true

	# Pick clip and play
	if _mode == ExplodeMode.STOMP:
		fuse_anim.play(ANIM_EXPLODE_STOMP)
	else:
		fuse_anim.play(ANIM_EXPLODE)

	# Fire effects immediately on stomp
	if _mode == ExplodeMode.STOMP and not _effects_fired:
		_do_explosion_effects()
		_effects_fired = true

	# ALWAYS connect finish handler so we free after any explode clip
	if fuse_anim and not fuse_anim.animation_finished.is_connected(_on_explode_anim_done):
		fuse_anim.animation_finished.connect(_on_explode_anim_done, CONNECT_ONE_SHOT)

	# Fallback self-destruct in case the clip is misconfigured (looping/missing)
	_start_fallback_despawn()

	# If there's no sprite, do effects & free immediately
	if not fuse_anim:
		if not _effects_fired:
			_do_explosion_effects()
			_effects_fired = true
		queue_free()


func _on_explode_anim_done() -> void:
	# fire effects if they haven't run yet
	if not _effects_fired:
		_do_explosion_effects()
		_effects_fired = true
	queue_free()


func _do_explosion_effects() -> void:
	# Play sound
	_play_explode_sfx()
	
	# Disable top sensor after exploding (avoid re-triggers)
	if is_instance_valid(top_sensor):
		top_sensor.set_deferred("monitoring", false)

	var radius := get_blast_radius()

	# 1) Tiles
	if tilemap and radius > 0.0:
		_clear_tiles_in_radius(global_position, radius)

	# 2) Bodies
	var bodies: Array = area.get_overlapping_bodies()

	# STOMP: direct launch for the stomper
	if _mode == ExplodeMode.STOMP and _stomped_body and _stomped_body.is_inside_tree():
		if _stomped_body.has_method("apply_bomb_boost"):
			_stomped_body.call("apply_bomb_boost", Vector2(0, -boost_power), global_position)

	for b in bodies:
		if not (b is Node): continue
		var node := b as Node
		if not node.is_inside_tree(): continue

		# Enemies die
		if node.has_method("die") and node.is_in_group("enemy"):
			node.call("die")
			continue

		# Player/actors
		if node.has_method("apply_bomb_boost") and (node is Node2D):
			if _mode == ExplodeMode.STOMP:
				if node == _stomped_body:
					continue
				continue
			else:
				# NORMAL (post-anim): side shove only
				var dir := ((node as Node2D).global_position - global_position).normalized()
				dir.y = 0.0
				if dir == Vector2.ZERO:
					dir = Vector2.RIGHT
				node.call("apply_bomb_boost", dir * side_knockback, global_position)

func _play_explode_sfx() -> void:
	if explode_sfx == null:
		return

	var p := AudioStreamPlayer2D.new()
	p.stream = explode_sfx
	p.bus = explode_sfx_bus
	p.volume_db = explode_sfx_volume_db
	p.global_position = global_position	# spawn where the bomb is
	# Optional spatial tuning:
	# p.max_distance = 2000.0
	# p.attenuation = 1.0

	# Parent somewhere that won't get freed with the bomb.
	# Using the bomb's parent keeps it in the same canvas/layer.
	var host := get_parent()
	if host == null:
		host = get_tree().current_scene
	host.add_child(p)

	# Auto-free when done (Godot 4 has "finished"; add a fallback just in case)
	if p.has_signal("finished"):
		p.finished.connect(func(): p.queue_free(), CONNECT_ONE_SHOT)
	else:
		var dur := p.stream.get_length()
		if dur > 0.0:
			var t := get_tree().create_timer(dur)
			t.timeout.connect(func():
				if is_instance_valid(p):
					p.queue_free()
			, CONNECT_ONE_SHOT)

	p.play()


func _clear_tiles_in_radius(center_world: Vector2, radius_px: float) -> void:
	var local_center: Vector2 = tilemap.to_local(center_world)
	var center_cell: Vector2i = tilemap.local_to_map(local_center)

	var cell_size: Vector2i = tilemap.tile_set.tile_size
	var rx: int = int(ceil(radius_px / float(cell_size.x)))
	var ry: int = int(ceil(radius_px / float(cell_size.y)))

	for dy in range(-ry, ry + 1):
		for dx in range(-rx, rx + 1):
			var cell: Vector2i = center_cell + Vector2i(dx, dy)
			var cell_world: Vector2 = tilemap.to_global(tilemap.map_to_local(cell))
			if cell_world.distance_to(center_world) > radius_px:
				continue
			var td: TileData = tilemap.get_cell_tile_data(cell)
			if td and (td.get_custom_data("destructible") == true):
				tilemap.erase_cell(cell)

func _find_tilemaplayer() -> TileMapLayer:
	var g := get_tree().get_first_node_in_group("DestructibleLayer")
	if g and g is TileMapLayer:
		return g as TileMapLayer
	var root: Node = get_tree().root
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is TileMapLayer:
			return n as TileMapLayer
		for c in n.get_children():
			stack.append(c)
	return null

func _start_fallback_despawn() -> void:
	var st := get_tree().create_timer(self_destruct_time)
	st.timeout.connect(func():
		if not is_inside_tree(): return
		if not _effects_fired:
			_do_explosion_effects()
			_effects_fired = true
		queue_free(), CONNECT_ONE_SHOT)
