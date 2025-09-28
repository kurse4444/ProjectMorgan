extends CharacterBody2D

@onready var anim := $AnimatedSprite2D
@onready var slowable: Slowable = $Slowable

# --- Basic movement tuning ---
@export var move_speed := 220.0      # horizontal movement speed (pixels/sec)
@export var jump_speed := -400.0     # initial jump velocity (negative = up)
@export var gravity := 1200.0        # base gravity force (pixels/sec^2)
@export var max_fall_speed := 900.0 # terminal velocity cap (max downward speed)
@export var no_boots_jump_speed := -280.0      # before the milestone
@export var high_jump_action_id := "PF:HighJump"

# --- Jump/Gravity extras ---
@export var coyote_time := 0.12          # "grace time" (in seconds) after walking off a ledge where you can still jump
@export var jump_buffer_time := 0.15     # buffer window (in seconds) before landing that will trigger a jump on contact
@export var fall_multiplier := 1.5       # multiplier to make falls feel faster than rise
@export var low_jump_multiplier := 1.2   # extra gravity if jump key isn’t held (short hop)
@export var jump_cut_multiplier := 0.5   # factor applied if jump released early (cuts upward velocity)

@export var bubble_h_power := 1.0   # 1.0 = linear slow for horizontal
@export var bubble_v_power := 1.0   # >1.0 = stronger slow for vertical (jump/fall)
@export var bubble_min_ts := 0.10   # optional floor so nothing freezes

@export var max_bomb_boost := -950.0 # cap the upward boost so it feels consistent

# --- Internal timers (runtime state, not exported) ---
var _coyote_left := 0.0   # time remaining in coyote window (counts down each frame)
var _buffer_left := 0.0   # time remaining in jump buffer (counts down each frame)

# Prev states
var _prev_ts_h: float = 1.0
var _prev_ts_v: float = 1.0

# Bomb
@export var bomb_action_id := "PF:Bomb"   # action key in unlocks.json
@export var bomb_knock_additive_scale := 0.1	# how much of radial knock to add if impulse points down
var _bomb_impulse: Vector2 = Vector2.ZERO
var _bomb_protect_frames: int = 0	# skip floor-zero and jump-cut for a couple frames
var _bomb_side_boost_x: float = 0.0
var _bomb_side_frames: int = 0

@export var bomb_scene: PackedScene
@export var throw_cooldown := 1.5 			# seconds between throws
@export var throw_speed := 50.0			# horizontal strength
@export var throw_arc := 70.0				# upward strength
@export var bomb_spawn_offset := Vector2(18, -10)	# from player center

var _current_bomb: RigidBody2D = null
var _can_throw := true
var _face := 1								# 1 right, -1 left

# Checkpoints and Spawn
@export var default_spawn_path: NodePath    # set to ../DefaultSpawn in the editor
@onready var _default_spawn: Marker2D = get_node_or_null(default_spawn_path)
signal died

# Crate
@export var push_impulse: float = 120.0   # increase if crate is heavy
@export var side_contact_threshold: float = 0.7

func _ready() -> void:
	add_to_group("player")
	add_to_group("slowable")
	# Initialize prev scales and connect to slowable changes
	_prev_ts_h = slowable.ts_h()
	_prev_ts_v = slowable.ts_v()
	if not slowable.is_connected("time_scale_changed", Callable(self, "_on_ts_changed")):
		slowable.time_scale_changed.connect(_on_ts_changed)

	call_deferred("_place_at_spawn")

func _place_at_spawn() -> void:
	var spawn := GameState.get_spawn_for_scene(get_tree().current_scene)
	if spawn != Vector2.ZERO:
		global_position = spawn
	elif _default_spawn:
		global_position = _default_spawn.global_position
	
# Rescale existing velocity so motion is consistent when ts changes mid-air
func _on_ts_changed(_old_val: float, _new_val: float) -> void:
	var new_h : float = slowable.ts_h()
	var new_v : float = slowable.ts_v()
	if _prev_ts_v > 0.0:
		velocity.y *= new_v / _prev_ts_v
	if _prev_ts_h > 0.0:
		velocity.x *= new_h / _prev_ts_h
	_prev_ts_h = new_h
	_prev_ts_v = new_v

@warning_ignore("unused_parameter")
func _input(event: InputEvent) -> void:
	#if _can_throw and Input.is_action_just_pressed("throw_bomb"):
	if Input.is_action_just_pressed("throw_bomb"):
		_throw_bomb()


func _physics_process(delta: float) -> void:
	# Per-axis time scales from Slowable (already include per-entity shaping)
	var ts_h : float = slowable.ts_h()   # horizontal direct scaling (walk/anim)
	var ts_v : float = slowable.ts_v()   # vertical direct scaling (jump/gravity)

	# Time-dilated delta for vertical accumulation (gravity, jump timers)
	var d_v := slowable.td_v(delta)

	# Cache floor state BEFORE move_and_slide()
	var on_floor := is_on_floor()
	var just_jumped := false

	# --- Timers (use vertical-dilated delta so bubble slows the windows too) ---
	if on_floor:
		_coyote_left = coyote_time
	else:
		_coyote_left = max(0.0, _coyote_left - d_v)
	_buffer_left = max(0.0, _buffer_left - d_v)

	# Buffer jump input
	if Input.is_action_just_pressed("jump"):
		_buffer_left = jump_buffer_time

	# CONSUME BOMB IMPULSE FIRST, so later logic doesn't wipe it
	if _bomb_impulse != Vector2.ZERO:
		# Straight-up launch; clamp by max_bomb_boost (negative cap)
		velocity.y = max(_bomb_impulse.y, max_bomb_boost)
		on_floor = false
		just_jumped = true
		_bomb_impulse = Vector2.ZERO


	# --- Jump impulse (direct value scaled by vertical time scale) ---
	var can_jump := on_floor or _coyote_left > 0.0
	if _buffer_left > 0.0 and can_jump:
		velocity.y = _jump_speed_now() * ts_v
		_buffer_left = 0.0
		_coyote_left = 0.0
		on_floor = false
		just_jumped = true

	# --- Jump cut (short hop if you release early) ---
	if (_bomb_protect_frames <= 0) and Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier

	# --- Gravity (accumulated with vertical-dilated delta) ---
	if not on_floor:
		var g := gravity
		if velocity.y > 0.0:
			g *= fall_multiplier
		elif not Input.is_action_pressed("jump"):
			g *= low_jump_multiplier
		velocity.y = min(velocity.y + g * d_v, max_fall_speed * ts_v)
	else:
		# Grounded: only zero Y if we didn't just start a jump and we're not moving up
		if (_bomb_protect_frames <= 0) and not just_jumped and velocity.y >= 0.0:
			velocity.y = 0.0

	# --- Horizontal (direct scaling by horizontal time scale) ---
	var dir := Input.get_axis("run_left", "run_right")
	if dir != 0:
		_face = 1 if (dir > 0) else -1
	var push_dir : int = sign(dir)
	velocity.x = move_speed * dir * ts_h
	
	if _bomb_side_frames > 0:
		# Apply directly (feel free to scale). Using 1.0 makes it snappy.
		velocity.x += _bomb_side_boost_x * 1.0
		_bomb_side_frames -= 1

	# Flip sprite if moving left/right
	if dir < 0:
		anim.flip_h = true
	elif dir > 0:
		anim.flip_h = false

	# --- Apply physics ---
	move_and_slide()
	
	# --- Find the rigidbody you're standing on (if any)
	var stood_on_rb: RigidBody2D = null
	if is_on_floor():
		var floor_cos := cos(floor_max_angle)     # CharacterBody2D property
		for i in range(get_slide_collision_count()):
			var c := get_slide_collision(i)
			var n := c.get_normal()
			# floor if angle between n and up_direction is small enough
			if up_direction.dot(n) >= floor_cos:
				stood_on_rb = c.get_collider() as RigidBody2D
				if stood_on_rb:
					break

	for i in range(get_slide_collision_count()):
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody2D
		if rb == null:
			continue

		# ❌ Never push the rigidbody you're standing on
		if rb == stood_on_rb:
			continue

		var n := c.get_normal()

		# Only push on strong side contacts (avoid corner/top)
		if push_dir != 0 \
		and abs(n.x) >= 0.8 and abs(n.y) <= 0.2 \
		and push_dir == -sign(n.x):

			# If your crate implements the wall-gap guard, respect it
			if rb.has_method("can_push_toward") and not rb.can_push_toward(push_dir):
				continue

			rb.sleeping = false
			rb.apply_impulse(Vector2(push_impulse * push_dir, 0.0))


	# --- Animations (match horizontal scale) ---
	anim.speed_scale = ts_h
	if not is_on_floor():
		anim.play("jump")
	elif dir != 0:
		anim.play("run")
	else:
		anim.play("idle")
		
	# Decrement protection at end of frame
	if _bomb_protect_frames > 0:
		_bomb_protect_frames -= 1

func _jump_speed_now() -> float:
	return jump_speed if Unlocks.can(high_jump_action_id) else no_boots_jump_speed

# Called by bombs on detonation if inside radius
@warning_ignore("unused_parameter")
func apply_bomb_boost(impulse: Vector2, origin: Vector2) -> void:
	# Upward launch path (no distance scaling)
	if impulse.y < -0.001:
		_bomb_impulse += impulse
		_bomb_protect_frames = 2
		return

	# Side knockback path (NORMAL explosion)
	if absf(impulse.y) <= 0.001:
		_bomb_side_boost_x = impulse.x     # magnitude & direction from the bomb
		_bomb_side_frames = 6              # ~0.1s @ 60fps; tweak to taste
		return

	# (If you ever send downward impulses, handle here if needed)

func _throw_bomb() -> void:
	# Block if one is still alive
	if is_instance_valid(_current_bomb) or not Unlocks.can(bomb_action_id):
		return

	if bomb_scene == null:
		push_warning("Player: bomb_scene not assigned")
		return

	var b := bomb_scene.instantiate()
	if b == null:
		return

	# guarantee bomb ignores the player from its very first frame
	if b.has_method("pre_spawn_ignore_player"):
		b.pre_spawn_ignore_player(2)   # your Player layer bit


	# Spawn slightly in front of the player
	var spawn := global_position + Vector2(bomb_spawn_offset.x * _face, bomb_spawn_offset.y)
	if b is Node2D:
		(b as Node2D).global_position = spawn

	# Add to the world (same parent as player is fine)
	get_parent().add_child(b)
	
	# --- prevent spawn pushback: temporary collision exception ---
	if b is RigidBody2D:
		# ignore collisions between player and bomb for a short window
		add_collision_exception_with(b)
		(b as RigidBody2D).add_collision_exception_with(self)

		var t := get_tree().create_timer(0.20)	# 0.2s feels good; tweak if needed
		t.timeout.connect(func():
			if is_instance_valid(b):
				remove_collision_exception_with(b)
				(b as RigidBody2D).remove_collision_exception_with(self)
		)


	# Track the active bomb and auto-clear when it’s gone
	_current_bomb = b
	var cb := Callable(self, "_on_bomb_gone").bind(b)
	if not b.is_connected("tree_exited", cb):
		b.tree_exited.connect(cb, Object.CONNECT_ONE_SHOT)

	# Give it an initial impulse (Godot 4 RigidBody2D)
	if b is RigidBody2D:
		var impulse := Vector2(throw_speed * _face, -throw_arc)
		(b as RigidBody2D).apply_impulse(impulse)
		(b as RigidBody2D).angular_velocity = 0.0   # stop inherited spin
		
	# Play throw animation if available ---
	if anim and anim.sprite_frames.has_animation("throw"):
		anim.play("throw")

	# Optional: pass any tuning into the bomb
	# (uncomment if you want to override per-level)
	# if b.has_variable("boost_power"):
	# 	b.boost_power = 900.0

	## Cooldown
	#_can_throw = false
	#var t := Timer.new()
	#t.one_shot = true
	#t.wait_time = throw_cooldown
	#add_child(t)
	#t.timeout.connect(func():
		#_can_throw = true
		#t.queue_free())
	#t.start()

func _on_bomb_gone(bomb: Node) -> void:
	# Clear the handle when the bomb frees itself (explode/queue_free)
	if _current_bomb == bomb:
		_current_bomb = null

func die() -> void:
	# play death FX, freeze input, etc., then:
	emit_signal("died")
	respawn()

func respawn() -> void:
	var spawn := GameState.get_spawn_for_scene(get_tree().current_scene)
	if spawn == Vector2.ZERO and _default_spawn:
		spawn = _default_spawn.global_position

	# Reset motion state so physics stays sane after teleport:
	velocity = Vector2.ZERO
	_coyote_left = 0.0
	_buffer_left = 0.0
	_bomb_impulse = Vector2.ZERO
	_bomb_protect_frames = 0
	_bomb_side_boost_x = 0.0
	_bomb_side_frames = 0

	global_position = spawn

func facing_dir() -> int:
	return _face   # 1 right, -1 left
