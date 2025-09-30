# Crate.gd
extends RigidBody2D

@export var min_gap_px: float = 12.0   # required space to walls
@export var margin_px: float = 1.0     # small slack to avoid jitter

@onready var poly: CollisionPolygon2D = $CollisionPolygon2D
@onready var ray_left: RayCast2D = $RayLeft
@onready var ray_right: RayCast2D = $RayRight

var _half_w: float = 0.0
var _center_off_x: float = 0.0
var _block_left := false
var _block_right := false

func _ready() -> void:
	_compute_poly_extents()
	# Rays shouldn’t hit this crate
	ray_left.add_exception(self)
	ray_right.add_exception(self)
	lock_rotation = true
	#continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

func _compute_poly_extents() -> void:
	if poly == null or poly.polygon.is_empty():
		_half_w = 0.0
		_center_off_x = 0.0
		return
	var min_x := INF
	var max_x := -INF
	for p in poly.polygon:
		if p.x < min_x: min_x = p.x
		if p.x > max_x: max_x = p.x
	_half_w = (max_x - min_x) * 0.5
	var bbox_center_x := (min_x + max_x) * 0.5
	_center_off_x = bbox_center_x + poly.position.x

func _notification(what):
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		_compute_poly_extents()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _half_w <= 0.0:
		return

	#var center_x := state.transform.origin.x
	#var right_edge := center_x + _center_off_x + _half_w
	#var left_edge := center_x + _center_off_x - _half_w

	# Compute block flags using ray hits
	#_block_right = false
	#if ray_right.is_colliding():
		#var hit_x := ray_right.get_collision_point().x
		#var gap_right := hit_x - right_edge
		#if gap_right <= (min_gap_px + margin_px):
			#_block_right = true
#
	#_block_left = false
	#if ray_left.is_colliding():
		#var hit_x := ray_left.get_collision_point().x
		#var gap_left := left_edge - hit_x
		#if gap_left <= (min_gap_px + margin_px):
			#_block_left = true
			
	#_block_right = false
	#if _is_side_hit(ray_right, true):
		#var hit_x := ray_right.get_collision_point().x
		#var right_edge := state.transform.origin.x + _center_off_x + _half_w
		#_block_right = (hit_x - right_edge) <= (min_gap_px + margin_px)
#
	#_block_left = false
	#if _is_side_hit(ray_left, false):
		#var hit_x := ray_left.get_collision_point().x
		#var left_edge := state.transform.origin.x + _center_off_x - _half_w
		#_block_left = (left_edge - hit_x) <= (min_gap_px + margin_px)
		
	# Kill velocity *into* blocked side — no position snapping
	#var vel := state.linear_velocity
	#if _block_right and vel.x > 0.0:
		#vel.x = 0.0
	#if _block_left and vel.x < 0.0:
		#vel.x = 0.0
	#state.linear_velocity = vel
	
	_block_right = _side_blocked(state, true)
	_block_left  = _side_blocked(state, false)

	var vel := state.linear_velocity
	if _block_right and vel.x > 0.0:
		vel.x = 0.0
	if _block_left and vel.x < 0.0:
		vel.x = 0.0
	state.linear_velocity = vel

# Let the player ask whether pushing toward a side is allowed
func can_push_toward(dir: int) -> bool:
	if dir > 0:
		return not _block_right
	elif dir < 0:
		return not _block_left
	return false

func _is_side_hit(ray: RayCast2D, right_side: bool) -> bool:
	if not ray.is_colliding():
		return false
	var n := ray.get_collision_normal()
	# We only care about near-horizontal normals.
	# Right side should see a normal pointing left (~(-1, 0)).
	if right_side:
		return n.x < -0.7
	else:
		return n.x > 0.7

func _side_blocked(state: PhysicsDirectBodyState2D, right_side: bool) -> bool:
	var space := state.get_space_state()

	# pick ray and y offset
	var y_off: float
	if right_side:
		y_off = ray_right.position.y
	else:
		y_off = ray_left.position.y

	# start point at the crate's side, mid-height
	var from_local_x := _center_off_x
	if right_side:
		from_local_x += _half_w
	else:
		from_local_x -= _half_w

	var from := state.transform * Vector2(from_local_x, y_off)

	# cast horizontally outwards
	var cast_len := min_gap_px + margin_px + 4.0
	var to := from
	if right_side:
		to.x += cast_len
	else:
		to.x -= cast_len

	var p := PhysicsRayQueryParameters2D.create(from, to)
	p.exclude = [self]
	if right_side:
		p.collision_mask = ray_right.collision_mask
	else:
		p.collision_mask = ray_left.collision_mask

	var hit := space.intersect_ray(p)
	if hit.is_empty():
		return false

	# Only treat near-horizontal hits as side walls
	var n: Vector2 = hit["normal"]
	if right_side:
		if n.x > -0.7:
			return false
	else:
		if n.x < 0.7:
			return false

	return true
