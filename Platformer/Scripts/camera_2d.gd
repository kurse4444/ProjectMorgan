extends Camera2D

@export var player_path: NodePath
@onready var player: CharacterBody2D = get_node_or_null(player_path)

@export_group("Look-ahead")
@export var lookahead_distance := 140.0
@export var flip_smooth_speed := 6.0
@export var min_move_to_flip := 20.0

@export_group("Follow Speeds")
@export var follow_speed_x := 8.0
@export var follow_speed_y := 6.0

@export_group("Vertical Behavior")
@export var vertical_deadzone := 80.0              # requested deadzone
@export var bounce_speed_threshold := -600.0
@export var bounce_raise := 48.0
@export var bounce_decay_speed := 2.5

@export_group("Screen & Clamp")
@export var screen_size: Vector2i = Vector2i(320, 180)
@export var clamp_enabled := true
@export var auto_bounds_from_tilemap := true
@export var tilemap_path: NodePath
@export var level_bounds: Rect2 = Rect2(0, 0, 0, 0)

@export_group("Debug & Pixel Art")
@export var debug_draw := false
@export var pixel_snap := true

# When headroom is tiny, optionally lock Y to center instead of micro-scrolling
@export var lock_y_if_tight_headroom := true
@export var tight_headroom_px := 12.0             # if camera can move <= this, lock Y

var _aim_offset_x: float = 0.0
var _bounce_bias: float = 0.0
var _last_face: int = 1

var _bounds: Rect2 = Rect2()
var _has_bounds: bool = false

var _effective_vertical_deadzone: float = 80.0    # for debug overlay

# Exponential smoothing (framerate-independent)
func soft_follow(current: float, target: float, speed: float, delta: float) -> float:
	if speed <= 0.0:
		return current
	var t: float = 1.0 - exp(-speed * delta)
	return lerpf(current, target, t)

func _ready() -> void:
	if player:
		if player.has_method("facing_dir"):
			_last_face = int(player.call("facing_dir"))
		else:
			if player.velocity.x >= 0.0:
				_last_face = 1
			else:
				_last_face = -1
		_aim_offset_x = lookahead_distance * float(_last_face)
		global_position = player.global_position + Vector2(_aim_offset_x, 0.0)

	position_smoothing_enabled = false
	_refresh_bounds()

func _refresh_bounds() -> void:
	_has_bounds = false

	if auto_bounds_from_tilemap and tilemap_path != NodePath():
		var tm: TileMap = get_node_or_null(tilemap_path) as TileMap
		if tm:
			var used: Rect2i = tm.get_used_rect()
			if used.size != Vector2i.ZERO:
				var ts_i: Vector2i = tm.tile_set.tile_size
				var ts: Vector2 = Vector2(ts_i.x, ts_i.y)

				var tl_local: Vector2 = Vector2(
					float(used.position.x) * ts.x,
					float(used.position.y) * ts.y
				)
				var br_cells_x: int = used.position.x + used.size.x
				var br_cells_y: int = used.position.y + used.size.y
				var br_local: Vector2 = Vector2(
					float(br_cells_x) * ts.x,
					float(br_cells_y) * ts.y
				)

				var tl_world: Vector2 = tm.to_global(tl_local)
				var br_world: Vector2 = tm.to_global(br_local)

				var min_x: float = minf(tl_world.x, br_world.x)
				var min_y: float = minf(tl_world.y, br_world.y)
				var max_x: float = maxf(tl_world.x, br_world.x)
				var max_y: float = maxf(tl_world.y, br_world.y)

				var pos: Vector2 = Vector2(min_x, min_y)
				var size: Vector2 = Vector2(max_x - min_x, max_y - min_y)

				_bounds = Rect2(pos, size)
				_has_bounds = true

	if not _has_bounds and level_bounds.size != Vector2.ZERO:
		_bounds = level_bounds
		_has_bounds = true

func _physics_process(delta: float) -> void:
	if not player:
		return

	var ppos: Vector2 = player.global_position
	var speed_x: float = absf(player.velocity.x)

	# 1) Smooth look-ahead flip toward facing
	var face: int = _last_face
	if speed_x >= min_move_to_flip:
		if player.has_method("facing_dir"):
			face = int(player.call("facing_dir"))
		else:
			if player.velocity.x >= 0.0:
				face = 1
			else:
				face = -1
		_last_face = face

	var target_offset_x: float = lookahead_distance * float(face)
	var flip_speed: float = 0.0
	if speed_x >= min_move_to_flip:
		flip_speed = flip_smooth_speed
	_aim_offset_x = soft_follow(_aim_offset_x, target_offset_x, flip_speed, delta)

	# 2) Vertical bounce bias on strong upward motion
	if player.velocity.y < bounce_speed_threshold:
		_bounce_bias = maxf(_bounce_bias, bounce_raise)
	_bounce_bias = soft_follow(_bounce_bias, 0.0, bounce_decay_speed, delta)

	# 3) Vertical deadzone (auto-shrinks to fit available headroom)
	var cam_y: float = global_position.y
	var half_dz: float = vertical_deadzone * 0.5

	var headroom: float = _vertical_headroom()
	if headroom < vertical_deadzone:
		# shrink deadzone to headroom (never bigger than what's scrollable)
		half_dz = maxf(0.0, headroom * 0.5)

	_effective_vertical_deadzone = half_dz * 2.0

	var baseline_y: float = cam_y
	if ppos.y > cam_y + half_dz:
		baseline_y = ppos.y - half_dz
	elif ppos.y < cam_y - half_dz:
		baseline_y = ppos.y + half_dz

	var target_y: float = baseline_y - _bounce_bias

	# If headroom is basically zero, optionally pin Y to bounds center (no jitter)
	if lock_y_if_tight_headroom and headroom <= tight_headroom_px:
		if _has_bounds:
			target_y = _bounds.position.y + _bounds.size.y * 0.5

	# 4) Smooth follow
	var target_x: float = ppos.x + _aim_offset_x
	var nx: float = soft_follow(global_position.x, target_x, follow_speed_x, delta)
	var ny: float = soft_follow(global_position.y, target_y, follow_speed_y, delta)
	var new_pos: Vector2 = Vector2(nx, ny)

	# 5) Clamp to bounds (320x180 aware)
	new_pos = _clamp_to_bounds(new_pos)

	# Pixel snap for crisp sprites
	if pixel_snap:
		new_pos = new_pos.round()

	global_position = new_pos

	if debug_draw:
		queue_redraw()

func _clamp_to_bounds(target: Vector2) -> Vector2:
	if not clamp_enabled or not _has_bounds:
		return target

	var he: Vector2 = _half_extents_world()
	var minx: float = _bounds.position.x + he.x
	var maxx: float = _bounds.position.x + _bounds.size.x - he.x
	var miny: float = _bounds.position.y + he.y
	var maxy: float = _bounds.position.y + _bounds.size.y - he.y

	var out: Vector2 = target

	# X clamp (center if level narrower than view)
	if _bounds.size.x <= he.x * 2.0:
		out.x = _bounds.position.x + _bounds.size.x * 0.5
	else:
		out.x = clampf(target.x, minx, maxx)

	# Y clamp (center if level shorter than view)
	if _bounds.size.y <= he.y * 2.0:
		out.y = _bounds.position.y + _bounds.size.y * 0.5
	else:
		out.y = clampf(target.y, miny, maxy)

	return out

func _half_extents_world() -> Vector2:
	var zx: float = maxf(zoom.x, 0.0001)
	var zy: float = maxf(zoom.y, 0.0001)
	return Vector2(float(screen_size.x) * 0.5 * zx, float(screen_size.y) * 0.5 * zy)

func _vertical_headroom() -> float:
	# How many pixels can the camera center move vertically inside bounds?
	if not _has_bounds:
		return 999999.0
	var he: Vector2 = _half_extents_world()
	var h: float = _bounds.size.y - he.y * 2.0
	if h < 0.0:
		h = 0.0
	return h

func _draw() -> void:
	if not debug_draw:
		return

	var he: Vector2 = _half_extents_world()

	# Visible view box
	draw_rect(Rect2(Vector2(-he.x, -he.y), he * 2.0), Color(1, 1, 1, 0.08), false, 1.0)

	# Effective vertical deadzone band (after shrink)
	var hz: float = _effective_vertical_deadzone
	draw_rect(Rect2(Vector2(-he.x, -hz * 0.5), Vector2(he.x * 2.0, hz)), Color(0.3, 0.8, 1.0, 0.10), true)

	# Look-ahead marker
	draw_circle(Vector2(_aim_offset_x, 0), 2.0, Color(1.0, 0.95, 0.2, 0.85))
