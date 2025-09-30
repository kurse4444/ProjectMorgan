extends RigidBody2D

@export var min_gap_px: float = 12.0   # required space to walls
@export var margin_px: float = 1.0     # small slack to avoid jitter

@onready var poly: CollisionPolygon2D = $CollisionPolygon2D
@onready var ray_left: RayCast2D = $RayLeft
@onready var ray_right: RayCast2D = $RayRight
@export var air_drag: float = 40.0       # px/s^2 applied in air
@export var floor_drag: float = 220.0     # px/s^2 on floor (if you want extra grip)
@export var max_correct_speed: float = 320.0  # px/s cap for horizontal correction
@export var gap_slack_px: float = 0.5          # small slack to avoid flutter


var _half_w: float = 0.0
var _half_h: float = 0.0
var _center_off_x: float = 0.0
var _center_off_y: float = 0.0
var _block_left := false
var _block_right := false

func _ready() -> void:
	_compute_poly_extents()
	ray_left.add_exception(self)
	ray_right.add_exception(self)
	lock_rotation = true
	# Recommended when things are moving fast while airborne:
	# continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE

func _compute_poly_extents() -> void:
	if poly == null or poly.polygon.is_empty():
		_half_w = 0.0
		_half_h = 0.0
		_center_off_x = 0.0
		_center_off_y = 0.0
		return
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for p in poly.polygon:
		if p.x < min_x: min_x = p.x
		if p.x > max_x: max_x = p.x
		if p.y < min_y: min_y = p.y
		if p.y > max_y: max_y = p.y
	_half_w = (max_x - min_x) * 0.5
	_half_h = (max_y - min_y) * 0.5
	var bbox_center_x := (min_x + max_x) * 0.5
	var bbox_center_y := (min_y + max_y) * 0.5
	_center_off_x = bbox_center_x + poly.position.x
	_center_off_y = bbox_center_y + poly.position.y

func _notification(what):
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		_compute_poly_extents()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _half_w <= 0.0:
		return

	var dt := state.step

	# --- grounded check ---
	var on_floor := false
	for i in range(state.get_contact_count()):
		var n := state.get_contact_local_normal(i)
		if n.y < -0.7:
			on_floor = true
			break

	# --- side probes ---
	var want := (min_gap_px + margin_px + gap_slack_px)
	var gap_r := _side_probe_gap(state, true, on_floor)
	var gap_l := _side_probe_gap(state, false, on_floor)
	_block_right = (gap_r <= want)
	_block_left  = (gap_l <= want)

	# --- velocity edits ---
	var vel := state.linear_velocity

	# Kill velocity *into* a blocked side
	if _block_right and vel.x > 0.0:
		vel.x = 0.0
	if _block_left and vel.x < 0.0:
		vel.x = 0.0

	# Apply horizontal drag (much smaller in air, bigger on floor)
	var drag := floor_drag if on_floor else air_drag
	if drag > 0.0:
		vel.x = move_toward(vel.x, 0.0, drag * dt)

	# --- position correction with a per-frame cap ---
	var correct_dir := 0  # +1 = push left (away from right wall), -1 = push right
	var correct_amt := 0.0

	if gap_r < want and (gap_l == INF or gap_r <= gap_l):
		correct_dir = +1
		correct_amt = want - gap_r
	elif gap_l < want:
		correct_dir = -1
		correct_amt = want - gap_l

	if correct_dir != 0 and correct_amt > 0.0:
		# Limit how much we can correct this frame → avoids big sideways shoves
		var max_corr := max_correct_speed * dt
		if correct_amt > max_corr:
			correct_amt = max_corr

		var t := state.transform
		if correct_dir > 0:
			t.origin.x -= correct_amt  # move left, away from right wall
		else:
			t.origin.x += correct_amt  # move right, away from left wall
		state.transform = t

	state.linear_velocity = vel


# Let the player ask whether pushing toward a side is allowed
func can_push_toward(dir: int) -> bool:
	if dir > 0:
		return not _block_right
	elif dir < 0:
		return not _block_left
	return false

# Returns the measured gap (in px) from the crate's edge to a wall on that side.
# If no wall within range, returns INF.
# Returns the measured gap to a wall on that side; INF if none.
func _side_probe_gap(state: PhysicsDirectBodyState2D, right_side: bool, on_floor: bool) -> float:
	var space := state.get_space_state()
	var dir := 1.0
	if not right_side:
		dir = -1.0

	# World extents of the crate
	var top_world_y := (state.transform * Vector2(0.0, _center_off_y - _half_h)).y
	var bot_world_y := (state.transform * Vector2(0.0, _center_off_y + _half_h)).y
	var interior_top := top_world_y + 2.0
	var interior_bot := bot_world_y - 2.0

	# Edge x in world
	var center := state.transform.origin
	var edge_local_x := _center_off_x + dir * _half_w
	var edge_world_x := center.x + edge_local_x

	var cast_len := min_gap_px + margin_px + 6.0

	# Sample heights: mid & near top; include near-bottom only when not on floor
	var yo := _half_h * 0.6
	var y_offsets := [ _center_off_y, _center_off_y - yo ]
	if not on_floor:
		y_offsets.append(_center_off_y + yo)

	var best_gap := INF

	for y_local in y_offsets:
		var from := state.transform * Vector2(edge_local_x + dir * 0.5, y_local)
		var to := from + Vector2(dir * cast_len, 0.0)

		var p := PhysicsRayQueryParameters2D.create(from, to)
		p.exclude = [self]
		p.hit_from_inside = true
		if right_side:
			p.collision_mask = ray_right.collision_mask
		else:
			p.collision_mask = ray_left.collision_mask

		var hit := space.intersect_ray(p)
		if hit.is_empty():
			continue

		var n: Vector2 = hit["normal"]
		var pos: Vector2 = hit["position"]

		# 1) Must be horizontally-facing surface (ignore floor/corner)
		#    Require almost no vertical component and strong horizontal.
		if abs(n.y) > 0.25:
			continue
		if right_side:
			if n.x > -0.9:  # want a normal pointing left
				continue
		else:
			if n.x < 0.9:   # want a normal pointing right
				continue

		# 2) Contact point must lie inside the crate's vertical span
		if not (pos.y > interior_top and pos.y < interior_bot):
			continue

		# Valid side wall: compute gap
		var gap := (pos.x - edge_world_x) * dir  # signed into +dir
		if gap < best_gap:
			best_gap = gap

	return best_gap
