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

@export_group("Region Rooms (Non-rect Worlds)")
@export var use_region_bounds := false
@export var region_bounds: Array[Rect2] = []   # add rooms/corridors here
@export var region_stick_margin := 24.0        # px: grow current room to avoid flicker
@export var region_switch_bias := 12.0         # px: new room must beat current depth by

@export_group("Region Transition (Pan on switch)")
@export var region_transition_enabled := true
@export var region_transition_speed := 6.0     # 1/s: higher = faster pan

@export_group("Reset/Snap Control")
@export var snap_on_level_load := true         # hard snap on first physics frame
@export var snap_if_far := true                # hard snap if camera is far from player
@export var snap_far_distance := 800.0         # px distance that counts as "far"
@export var transition_freeze_after_snap := 0.15 # s to disable tweening after snap

@export_group("Debug & Pixel Art")
@export var debug_draw := false
@export var pixel_snap := true

# When headroom is tiny, optionally lock Y to center instead of micro-scrolling
@export var lock_y_if_tight_headroom := true
@export var tight_headroom_px := 12.0             # if camera can move <= this, lock Y

var _aim_offset_x: float = 0.0
var _bounce_bias: float = 0.0
var _last_face: int = 1

# Single full-level bounds (TileMap or manual Rect2)
var _bounds: Rect2 = Rect2()
var _has_bounds: bool = false

# Active region (when use_region_bounds = true)
var _active_region: Rect2 = Rect2()
var _has_active_region: bool = false

# Animated clamp rect (lerps toward the target bounds for smooth panning)
var _bounds_anim: Rect2 = Rect2()
var _has_bounds_anim: bool = false

var _effective_vertical_deadzone: float = 80.0    # for debug overlay

# Snap state
var _pending_initial_snap: bool = true
var _transition_freeze: float = 0.0

# --------- Smoothing ----------
func soft_follow(current: float, target: float, speed: float, delta: float) -> float:
	if speed <= 0.0:
		return current
	var t: float = 1.0 - exp(-speed * delta)
	return lerpf(current, target, t)

# --------- Ready / bounds setup ----------
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
	var t0: Rect2 = _target_bounds()
	_bounds_anim = t0
	_has_bounds_anim = true

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

# --------- Physics + follow ----------
func _physics_process(delta: float) -> void:
	if not player:
		return

	# One-time hard snap after load (run after player has likely positioned itself)
	if snap_on_level_load and _pending_initial_snap:
		_hard_snap_to_player()
		_pending_initial_snap = false

	# Determine active region (if using region mode)
	if use_region_bounds and region_bounds.size() > 0:
		_pick_active_region(player.global_position)

	# Update animated bounds toward current target (for smooth panning on switch)
	_update_animated_bounds(delta)

	var ppos: Vector2 = player.global_position
	var speed_x: float = absf(player.velocity.x)

	# Optional: if we ever get very far from the player (teleport/respawn), hard snap
	if snap_if_far:
		var dist: float = (global_position - ppos).length()
		if dist > snap_far_distance:
			_hard_snap_to_player()

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

	# 3) Vertical deadzone (auto-shrinks to fit available headroom of current bounds)
	var cam_y: float = global_position.y
	var half_dz: float = vertical_deadzone * 0.5

	var headroom: float = _vertical_headroom()
	if headroom < vertical_deadzone:
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
		if _has_any_bounds():
			var b0: Rect2 = _current_bounds()
			target_y = b0.position.y + b0.size.y * 0.5

	# 4) Smooth follow
	var target_x: float = ppos.x + _aim_offset_x
	var nx: float = soft_follow(global_position.x, target_x, follow_speed_x, delta)
	var ny: float = soft_follow(global_position.y, target_y, follow_speed_y, delta)
	var new_pos: Vector2 = Vector2(nx, ny)

	# 5) Clamp to bounds (animated region/level bounds)
	new_pos = _clamp_to_bounds(new_pos)

	# Pixel snap for crisp sprites
	if pixel_snap:
		new_pos = new_pos.round()

	global_position = new_pos

	if debug_draw:
		queue_redraw()

# --------- Region selection (overlap-smart) ----------
func _inside_depth(p: Vector2, r: Rect2) -> float:
	# Positive => inside; value = min distance to the four edges.
	# Negative => outside; value = -distance outside along nearest edge.
	var dx_left: float = p.x - r.position.x
	var dx_right: float = (r.position.x + r.size.x) - p.x
	var dy_top: float = p.y - r.position.y
	var dy_bottom: float = (r.position.y + r.size.y) - p.y
	return minf(minf(dx_left, dx_right), minf(dy_top, dy_bottom))

func _pick_active_region(player_pos: Vector2) -> void:
	# 1) Stick with current region as long as player is inside its grown rect
	if _has_active_region and region_stick_margin > 0.0:
		var grown: Rect2 = _active_region.grow(region_stick_margin)
		if grown.has_point(player_pos):
			return

	# 2) Among all regions that contain the player, pick the deepest (most interior)
	var best_idx: int = -1
	var best_depth: float = -1.0e12
	for i in range(region_bounds.size()):
		var r: Rect2 = region_bounds[i]
		var depth: float = _inside_depth(player_pos, r)
		if depth >= 0.0:
			if depth > best_depth:
				best_depth = depth
				best_idx = i

	# If at least one containing region, maybe switch
	if best_idx != -1:
		if _has_active_region and region_switch_bias > 0.0:
			var cur_depth: float = _inside_depth(player_pos, _active_region)
			if best_depth <= cur_depth + region_switch_bias:
				return
		_active_region = region_bounds[best_idx]
		_has_active_region = true
		return

	# 3) Otherwise, pick nearest region center (standing between rooms)
	var nearest_idx: int = -1
	var nearest_d: float = 1.0e20
	for i in range(region_bounds.size()):
		var r2: Rect2 = region_bounds[i]
		var c: Vector2 = r2.position + r2.size * 0.5
		var d: float = (c - player_pos).length()
		if d < nearest_d:
			nearest_d = d
			nearest_idx = i

	if nearest_idx != -1:
		_active_region = region_bounds[nearest_idx]
		_has_active_region = true
	else:
		_has_active_region = false

# --------- Bounds helpers & transition ----------
func _target_bounds() -> Rect2:
	if use_region_bounds and region_bounds.size() > 0 and _has_active_region:
		return _active_region
	return _bounds

func _update_animated_bounds(delta: float) -> void:
	# Freeze tweening briefly after a snap to avoid panning from wrong rect
	if _transition_freeze > 0.0:
		_transition_freeze -= delta
		_bounds_anim = _target_bounds()
		_has_bounds_anim = true
		return

	if not region_transition_enabled:
		_bounds_anim = _target_bounds()
		_has_bounds_anim = true
		return

	var tgt: Rect2 = _target_bounds()
	if not _has_bounds_anim:
		_bounds_anim = tgt
		_has_bounds_anim = true
		return

	var s: float = region_transition_speed
	_bounds_anim.position.x = soft_follow(_bounds_anim.position.x, tgt.position.x, s, delta)
	_bounds_anim.position.y = soft_follow(_bounds_anim.position.y, tgt.position.y, s, delta)
	_bounds_anim.size.x = soft_follow(_bounds_anim.size.x, tgt.size.x, s, delta)
	_bounds_anim.size.y = soft_follow(_bounds_anim.size.y, tgt.size.y, s, delta)

func _current_bounds() -> Rect2:
	if _has_bounds_anim:
		return _bounds_anim
	return _target_bounds()

func _has_any_bounds() -> bool:
	if use_region_bounds and region_bounds.size() > 0:
		return _has_active_region or _has_bounds_anim
	return _has_bounds or _has_bounds_anim

func _clamp_to_bounds(target: Vector2) -> Vector2:
	if not clamp_enabled or not _has_any_bounds():
		return target

	var b: Rect2 = _current_bounds()
	var he: Vector2 = _half_extents_world()
	var minx: float = b.position.x + he.x
	var maxx: float = b.position.x + b.size.x - he.x
	var miny: float = b.position.y + he.y
	var maxy: float = b.position.y + b.size.y - he.y

	var out: Vector2 = target

	# X clamp (center if region/level narrower than view)
	if b.size.x <= he.x * 2.0:
		out.x = b.position.x + b.size.x * 0.5
	else:
		out.x = clampf(target.x, minx, maxx)

	# Y clamp (center if region/level shorter than view)
	if b.size.y <= he.y * 2.0:
		out.y = b.position.y + b.size.y * 0.5
	else:
		out.y = clampf(target.y, miny, maxy)

	return out

func _half_extents_world() -> Vector2:
	var zx: float = maxf(zoom.x, 0.0001)
	var zy: float = maxf(zoom.y, 0.0001)
	return Vector2(float(screen_size.x) * 0.5 * zx, float(screen_size.y) * 0.5 * zy)

func _vertical_headroom() -> float:
	# How many pixels can the camera center move vertically inside the CURRENT (animated) bounds?
	if not _has_any_bounds():
		return 999999.0
	var b: Rect2 = _current_bounds()
	var he: Vector2 = _half_extents_world()
	var h: float = b.size.y - he.y * 2.0
	if h < 0.0:
		h = 0.0
	return h

# --------- Snap helpers ----------
func _hard_snap_to_player() -> void:
	if not player:
		return

	# Refresh facing for look-ahead
	if player.has_method("facing_dir"):
		_last_face = int(player.call("facing_dir"))
	else:
		if player.velocity.x >= 0.0:
			_last_face = 1
		else:
			_last_face = -1

	_aim_offset_x = lookahead_distance * float(_last_face)

	# Place camera directly on player (no smoothing), then seed bounds/tween freeze
	global_position = player.global_position + Vector2(_aim_offset_x, 0.0)
	_seed_bounds_after_snap()

	if pixel_snap:
		global_position = global_position.round()

func _seed_bounds_after_snap() -> void:
	_bounds_anim = _target_bounds()
	_has_bounds_anim = true
	_transition_freeze = maxf(_transition_freeze, transition_freeze_after_snap)

# --------- Debug draw ----------
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

	# Regions and bounds overlays
	if use_region_bounds and region_bounds.size() > 0:
		for r in region_bounds:
			var tl_local_all: Vector2 = r.position - global_position
			draw_rect(Rect2(tl_local_all, r.size), Color(0.4, 0.8, 1.0, 0.15), false, 1.0)
		if _has_active_region:
			var tl_local_act: Vector2 = _active_region.position - global_position
			draw_rect(Rect2(tl_local_act, _active_region.size), Color(1.0, 0.95, 0.2, 0.9), false, 2.0)

	# Animated clamp rect (blue)
	if _has_bounds_anim:
		var bcur: Rect2 = _current_bounds()
		var tl_local_b: Vector2 = bcur.position - global_position
		draw_rect(Rect2(tl_local_b, bcur.size), Color(0.2, 0.55, 1.0, 0.8), false, 2.0)
