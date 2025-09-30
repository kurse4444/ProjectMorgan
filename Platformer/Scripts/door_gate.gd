extends StaticBody2D
class_name DoorGate

signal opened
signal closed
signal condition_changed(is_satisfied: bool)

# -------- Config --------
enum Mode { ALL, ANY, K_OF_N, SEQUENCE }
@export var mode: Mode = Mode.ALL
@export var inputs: Array[NodePath] = []          # PlateButtons or any node with is_active():bool
@export var k_required: int = 2                   # for K_OF_N
@export var seq_step_time: float = 0.5            # per-step window for SEQUENCE (slowable)
@export var inputs_affect_logic: bool = true
@export var inputs_affect_visuals: bool = false

# Open/close behavior (all slowable)
@export var open_duration: float = 0.0            # >0 = auto-close after this time regardless of inputs
@export var grace_after_release: float = 0.6      # used when open_duration == 0
@export var start_open: bool = false              # start already open
@export var start_idle_closed: bool = true       # if true (and not start_open), spawn directly in idle_closed

# Beep feedback (slowable cadence + pitch)
@export var beep_count: int = 4                   # number of beeps across the window
@export var beep_on_open_window: bool = true      # used when open_duration > 0
@export var beep_on_grace_window: bool = true     # used when open_duration == 0

# --- One-shot SFX for opening/closing (assign in Inspector) ---
@export var open_stream: AudioStream
@export var close_stream: AudioStream
@export var open_volume_db: float = 10
@export var close_volume_db: float = 10
@export var sfx_pitch_tracks_visual_slow: bool = true  # pitch slows only if the *gate* is bubbled

@onready var s_open: AudioStreamPlayer2D = get_node_or_null("OpenSfx") as AudioStreamPlayer2D
@onready var s_close: AudioStreamPlayer2D = get_node_or_null("CloseSfx") as AudioStreamPlayer2D

# --- One-shot SFX when the inputs become satisfied (gate "unlocks") ---
@export var unlock_stream: AudioStream
@export var unlock_volume_db: float = 0.0
@export var play_unlock_only_when_closed: bool = true  # avoid spam if already open

@onready var s_unlock: AudioStreamPlayer2D = get_node_or_null("UnlockSfx") as AudioStreamPlayer2D

# Timescale inheritance: when true, the gate uses the MIN time scale of itself and its inputs.
@export var inherit_input_timescale: bool = true

# Optional: assign explicitly; if empty we auto-detect
@export_node_path var collider_path: NodePath

@export var debug_gate: bool = true
@export var debug_every: float = 0.25
var _dbg_accum := 0.0

# -------- Nodes --------
@onready var slow: Slowable = $Slowable
@onready var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var beep: AudioStreamPlayer = (
	get_node_or_null("Beep") as AudioStreamPlayer
	if get_node_or_null("Beep") != null
	else get_node_or_null("Beep2D") as AudioStreamPlayer
)

var _collider: CollisionShape2D = null

# -------- Runtime --------
var _targets: Array[Node] = []
var _is_open := false
var _grace_timer := 0.0
var _open_timer := 0.0

# sequence
var _seq_index := 0
var _seq_timer := 0.0

# beeps
var _beep_period := 0.0
var _beep_timer := 0.0
var _beeps_left := 0

# pending idle after a transition finishes
var _pending_idle: StringName = &""

# cache effective scale to avoid redundant property sets
var _last_eff_ts: float = 1.0

# --- Physical slide of the blocking collider (in pixels/sec) ---
@export var open_travel: float = 32.0     # how far the collider sinks when door opens
@export var open_speed:  float = 160.0    # px/sec downward
@export var close_speed: float = 200.0    # px/sec upward

var _base_collider_y: float = 0.0         # rest Y of the collider (closed)
var _target_collider_y: float = 0.0       # where we want it this frame
var _prev_condition := false


func _ready() -> void:
	add_to_group("slowable")

	# Collect input targets
	for p in inputs:
		var n := get_node_or_null(p)
		if n != null:
			_targets.append(n)
			if n.has_signal("active_changed"):
				n.connect("active_changed", Callable(self, "_on_input_active_changed"))

	_validate_setup()
	
# --- Collect a shape (by TYPE) ---
	if collider_path != NodePath():
		_collider = get_node_or_null(collider_path) as CollisionShape2D

	if _collider == null:
		# Look under this StaticBody2D for the first CollisionShape2D by TYPE
		_collider = _find_first_collider(self)

	if _collider == null:
		push_warning("DoorGate: No CollisionShape2D found under StaticBody2D. Assign collider_path or add a shape.")
	else:
		#print_debug("[DoorGate] Using collider:", _collider.get_path())
		_base_collider_y = _collider.position.y
		_target_collider_y = _base_collider_y

	# cache base Y and set initial collider position based on start flags
	if is_instance_valid(_collider):
		_base_collider_y = _collider.position.y
		_target_collider_y = _base_collider_y  # default (closed)
	
	# Update visuals/audio speeds whenever our own slow changes
	slow.time_scale_changed.connect(func(_o,_n): _apply_effective_speeds())

	# Initial state
	if start_open:
		_force_open()
	else:
		if start_idle_closed:
			_spawn_idle_state(false)   # snap straight to idle_closed
		else:
			_apply_open_state(false)   # normal close flow

	if start_open:
		# already calls _force_open(); ensure collider starts in the lowered (open) pose
		if is_instance_valid(_collider):
			_collider.position.y = _base_collider_y + open_travel
			_target_collider_y = _collider.position.y
	elif start_idle_closed:
		# closed pose
		if is_instance_valid(_collider):
			_collider.position.y = _base_collider_y
			_target_collider_y = _collider.position.y

	# Ensure initial speeds reflect inputs too
	_apply_effective_speeds()
	
	# --- Open/Close SFX setup ---
	if s_open == null:
		s_open = AudioStreamPlayer2D.new()
		s_open.name = "OpenSfx"
		add_child(s_open)
	if s_close == null:
		s_close = AudioStreamPlayer2D.new()
		s_close.name = "CloseSfx"
		add_child(s_close)

	# Assign streams from Inspector (optional—can also set directly on the child nodes)
	if open_stream != null:
		s_open.stream = open_stream
	if close_stream != null:
		s_close.stream = close_stream

	s_open.volume_db = open_volume_db
	s_close.volume_db = close_volume_db

	_update_sfx_pitch()  # set initial pitch

		# --- Unlock SFX setup ---
	if s_unlock == null:
		s_unlock = AudioStreamPlayer2D.new()
		s_unlock.name = "UnlockSfx"
		add_child(s_unlock)

	if unlock_stream != null:
		s_unlock.stream = unlock_stream
	s_unlock.volume_db = unlock_volume_db


func _physics_process(delta: float) -> void:
	var logic_ts := effective_logic_ts()
	var dt := delta * logic_ts

	# keep visuals/audio in sync when the visual scale changes
	var vts := effective_visual_ts()
	if !is_equal_approx(vts, _last_eff_ts):
		_apply_effective_speeds()

	var satisfied := _evaluate_condition(dt)
	condition_changed.emit(satisfied)
	# Play "unlock" when condition goes false -> true
	var just_unlocked := satisfied and !_prev_condition
	if just_unlocked:
		if !play_unlock_only_when_closed or !_is_open:
			if is_instance_valid(s_unlock) and s_unlock.stream != null:
				# ensure pitch is up-to-date at play time
				s_unlock.pitch_scale = effective_visual_ts()
				s_unlock.volume_db = unlock_volume_db
				s_unlock.play()
	_prev_condition = satisfied

	if satisfied:
		if !_is_open: _open()
		_grace_timer = grace_after_release
	else:
		_grace_timer = max(0.0, _grace_timer - dt)
		if _is_open and open_duration == 0.0 and beep_on_grace_window and _grace_timer > 0.0:
			if _beeps_left == 0:
				_start_beeps(grace_after_release)

	if _is_open and open_duration > 0.0:
		_open_timer = max(0.0, _open_timer - dt)
		if _open_timer <= 0.0:
			_close()
	elif _is_open and open_duration == 0.0 and _grace_timer <= 0.0:
		_close()

	_update_beeps(dt)
	
	# --- Slide collider toward target with time-dilated speed ---
	# dt is already time-dilated: dt = delta * effective_time_scale()
	if is_instance_valid(_collider) and is_instance_valid(anim) and anim.is_playing():
		var anim_name := anim.animation
		var dur := _anim_duration(anim_name)
		if dur > 0.0:
			# Progress in [0,1]; AnimatedSprite2D advances with speed_scale already
			var frames := anim.sprite_frames.get_frame_count(anim_name)
			var p := 0.0
			if frames > 1:
				p = float(anim.frame) / float(frames - 1)
			# Map progress → collider y depending on state
			# Assume "open" goes 0→1 downward; "close" goes 1→0 upward
			if anim_name == "open":
				_collider.position.y = _base_collider_y + open_travel * p
			elif anim_name == "close":
				_collider.position.y = _base_collider_y + open_travel * (1.0 - p)
	else:
		# Not in a transition: snap to target (idle states)
		if is_instance_valid(_collider):
			_collider.position.y = _target_collider_y

	if debug_gate:
		_dbg_accum += delta
	if _dbg_accum >= debug_every:
		_dbg_accum = 0.0
		_dbg_dump(satisfied, logic_ts, vts)



func _on_input_active_changed(_active: bool) -> void:
	# inputs toggled; speed may need to change
	_apply_effective_speeds()

# ---------- Condition evaluation ----------
func _evaluate_condition(dt: float) -> bool:
	match mode:
		Mode.ALL:
			for t in _targets:
				if !_is_active(t): return false
			return _targets.size() > 0
		Mode.ANY:
			for t in _targets:
				if _is_active(t): return true
			return false
		Mode.K_OF_N:
			var c := 0
			for t in _targets:
				if _is_active(t): c += 1
			return c >= max(1, k_required)
		Mode.SEQUENCE:
			return _evaluate_sequence(dt)
	return false

func _evaluate_sequence(dt: float) -> bool:
	if _targets.is_empty(): return false
	_seq_timer = max(0.0, _seq_timer - dt)

	var current := _targets[_seq_index]
	if _is_active(current):
		_seq_index += 1
		_seq_timer = seq_step_time
		if _seq_index >= _targets.size():
			return true
	elif _seq_timer <= 0.0 and _seq_index > 0:
		_seq_index = 0
		_seq_timer = 0.0
	return false

func _is_active(n: Node) -> bool:
	if n == null:
		return false
	# Prefer a richer signal if the input provides it
	if "is_effectively_active" in n:
		return n.is_effectively_active()
	if "is_active" in n:
		return n.is_active()
	return false


# ---------- Open / Close ----------
func _open() -> void:
	_is_open = true
	_seq_index = 0
	_seq_timer = 0.0
	_play_state(true)
	if is_instance_valid(s_open) and s_open.stream != null:  # <-- play open SFX
		s_open.volume_db = open_volume_db
		s_open.play()
	opened.emit()

	if open_duration > 0.0:
		_open_timer = open_duration
		if beep_on_open_window:
			_start_beeps(open_duration)
	else:
		_open_timer = 0.0

func _close() -> void:
	_is_open = false
	_stop_beeps()
	_play_state(false)
	if is_instance_valid(s_close) and s_close.stream != null: # <-- play close SFX
		s_close.volume_db = close_volume_db
		s_close.play()
	closed.emit()

func _force_open() -> void:
	_is_open = true
	_play_state(true)

# ---------- Visuals / Collider ----------
func _spawn_idle_state(open: bool) -> void:
	# Set the desired collider pose for this state
	if is_instance_valid(_collider):
		_collider.position.y = _base_collider_y + (open_travel if open else 0.0)
		_target_collider_y = _collider.position.y

	# Snap to the matching idle if present; else fall back gracefully
	if is_instance_valid(anim):
		anim.speed_scale = effective_visual_ts()
		var idle_name := "idle_open" if open else "idle_closed"
		if anim.sprite_frames != null and anim.sprite_frames.has_animation(idle_name):
			anim.play(idle_name)
		else:
			var trans := "open" if open else "close"
			if anim.sprite_frames != null and anim.sprite_frames.has_animation(trans):
				anim.play(trans)
			else:
				anim.stop()

func _apply_open_state(open: bool) -> void:
	# Set the desired collider pose for this state
	if is_instance_valid(_collider):
		_target_collider_y = _base_collider_y + (open_travel if open else 0.0)
		#print_debug("[DoorGate] target_y =", _target_collider_y)

	# Animate transitions → idle
	if !is_instance_valid(anim):
		return

	anim.speed_scale = effective_visual_ts()

	var trans_name := "open" if open else "close"
	var idle_name := "idle_open" if open else "idle_closed"

	var has_trans := anim.sprite_frames != null and anim.sprite_frames.has_animation(trans_name)
	var has_idle := anim.sprite_frames != null and anim.sprite_frames.has_animation(idle_name)

	# sync collider speed to the animation's base duration (so both end together)
	var base_dur := _anim_duration(trans_name)  # seconds; -1 if not found
	if base_dur > 0.0 and open_travel > 0.0:
		# dt is scaled, and anim.speed_scale is scaled, so using base duration aligns them
		if open:
			open_speed = open_travel / base_dur
		else:
			close_speed = open_travel / base_dur


	# Clear any previous pending idle and connection
	_pending_idle = &""
	if anim.is_connected("animation_finished", Callable(self, "_on_transition_finished")):
		anim.disconnect("animation_finished", Callable(self, "_on_transition_finished"))

	if has_trans:
		anim.play(trans_name)
		if has_idle:
			_pending_idle = idle_name
			# Switch to idle after the transition ends
			anim.animation_finished.connect(_on_transition_finished, Object.CONNECT_ONE_SHOT)
	else:
		# No transition clip → jump straight to idle or stop
		if has_idle:
			anim.play(idle_name)
		else:
			anim.stop()

func _play_state(open: bool) -> void:
	_apply_open_state(open)
	_apply_effective_speeds()  # ensure speeds match current state immediately

func _on_transition_finished() -> void:
	if is_instance_valid(anim) and _pending_idle != &"":
		if anim.sprite_frames != null and anim.sprite_frames.has_animation(_pending_idle):
			anim.play(_pending_idle)
	_pending_idle = &""

func _find_first_collider(n: Node) -> CollisionShape2D:
	if n is CollisionShape2D:
		return n
	for c in n.get_children():
		var r := _find_first_collider(c)
		if r != null:
			return r
	return null

# ---------- Beeps ----------
func _start_beeps(window: float) -> void:
	if !is_instance_valid(beep) or beep_count <= 0 or window <= 0.0:
		return
	_beeps_left = beep_count
	_beep_period = window / float(beep_count)
	_beep_timer = _beep_period
	beep.pitch_scale = effective_time_scale()

func _stop_beeps() -> void:
	_beeps_left = 0
	_beep_timer = 0.0

func _update_beeps(dt: float) -> void:
	if _beeps_left <= 0: return
	_beep_timer -= dt
	if _beep_timer <= 0.0:
		if is_instance_valid(beep):
			beep.pitch_scale = effective_time_scale()
			beep.play()
		_beeps_left -= 1
		if _beeps_left > 0:
			_beep_timer += _beep_period

# ---------- Effective time scale (inherit from inputs) ----------
func _get_node_time_scale(n: Node) -> float:
	if n == null:
		return 1.0
	if n.has_node("Slowable"):
		var s := n.get_node("Slowable")
		if s != null and "get_time_scale" in s:
			return s.get_time_scale()
	if "get_time_scale" in n:
		return n.get_time_scale()
	return 1.0

func effective_time_scale() -> float:
	var ts := slow.get_time_scale()
	if !inherit_input_timescale or _targets.is_empty():
		return ts
	for t in _targets:
		ts = min(ts, _get_node_time_scale(t))
	return ts

func _apply_effective_speeds() -> void:
	var vts := effective_visual_ts()
	if is_instance_valid(anim):
		anim.speed_scale = vts
	if is_instance_valid(beep):
		beep.pitch_scale = vts
	_update_sfx_pitch()
	_last_eff_ts = vts

func _anim_duration(anim_name: StringName) -> float:
	if anim == null or anim.sprite_frames == null: return -1.0
	if !anim.sprite_frames.has_animation(anim_name): return -1.0
	var sf := anim.sprite_frames
	var frames := sf.get_frame_count(anim_name)
	var total := 0.0
	for i in frames:
		# Godot 4: per-frame durations are supported; falls back to 1/animation_fps in editor defaults
		total += sf.get_frame_duration(anim_name, i)
	return max(0.0, total)
	
func _inputs_min_ts() -> float:
	var ts := 1.0
	for t in _targets:
		ts = min(ts, _get_node_time_scale(t))
	return ts

func effective_logic_ts() -> float:
	var ts := slow.get_time_scale()
	if inputs_affect_logic and !_targets.is_empty():
		ts = min(ts, _inputs_min_ts())
	return ts

func effective_visual_ts() -> float:
	var ts := slow.get_time_scale()
	if inputs_affect_visuals and !_targets.is_empty():
		ts = min(ts, _inputs_min_ts())
	return ts

func _dbg_dump(satisfied: bool, logic_ts: float, visual_ts: float) -> void:
	if !debug_gate:
		return
	var parts: Array[String] = []
	parts.append("GateDbg: mode=" + str(mode) + " k=" + str(k_required))
	parts.append("inputs=" + str(_targets.size()))
	parts.append("logic_ts=" + String.num(logic_ts, 2))
	parts.append("visual_ts=" + String.num(visual_ts, 2))

	var states: Array[String] = []
	for t in _targets:
		var nm : String = t.name if t != null else "<null>"
		var act := false
		if t != null:
			if "is_effectively_active" in t:
				act = t.is_effectively_active()
			elif "is_active" in t:
				act = t.is_active()
		var ts := _get_node_time_scale(t) if t != null else 1.0
		states.append(nm + ":" + ("1" if act else "0") + "@" + String.num(ts, 2))

	parts.append("[" + ", ".join(states) + "]")
	parts.append("satisfied=" + ("1" if satisfied else "0") + " open=" + ("1" if _is_open else "0"))
	print_debug(" | ".join(parts))


func _validate_setup() -> void:
	if _targets.is_empty():
		push_error("DoorGate: inputs list is EMPTY. Assign both PlateButtons in the DoorGate Inspector.")
	for t in _targets:
		if t == null:
			push_warning("DoorGate: an input path points to null.")
		elif !("is_active" in t):
			push_error("DoorGate: input '" + t.name + "' has no is_active().")

func _update_sfx_pitch() -> void:
	var p := effective_visual_ts() if sfx_pitch_tracks_visual_slow else 1.0
	if is_instance_valid(s_unlock): s_unlock.pitch_scale = p
	if is_instance_valid(s_open):  s_open.pitch_scale = p
	if is_instance_valid(s_close): s_close.pitch_scale = p
