# PlatformerMusic.gd (AutoLoad)
extends Node

var player: AudioStreamPlayer
var _t: Tween = null

var _base_gain_db := -10.0      # user/base volume (persist if you ever add settings)
var _duck_offset_db := 0.0    # temporary duck; NEVER saved

func _ready() -> void:
	if player == null:
		player = AudioStreamPlayer.new()
		add_child(player)
		player.bus = "Music"                     # or "Master"
		player.process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_volume()

func play_bgm(stream: AudioStream) -> void:
	if player.stream == stream and player.playing:
		return
	player.stream = stream
	_apply_volume()
	player.play()

func stop_bgm() -> void:
	if player.playing:
		player.stop()

func set_base_gain_db(db: float) -> void:
	_base_gain_db = db
	_apply_volume()

func duck(to_db := -12.0, fade := 0.25) -> void:
	_make_tween()
	_t.tween_method(_set_duck_offset, _duck_offset_db, to_db, fade)

func unduck(fade := 0.25) -> void:
	_make_tween()
	_t.tween_method(_set_duck_offset, _duck_offset_db, 0.0, fade)

func duck_for(hold_seconds: float, to_db := -12.0, fade := 0.25) -> void:
	_make_tween()
	_t.tween_method(_set_duck_offset, _duck_offset_db, to_db, fade)
	_t.tween_interval(hold_seconds)
	_t.tween_method(_set_duck_offset, _duck_offset_db, 0.0, fade)

func force_normal(immediate := true) -> void:
	_kill_tween()
	_duck_offset_db = 0.0
	if immediate:
		_apply_volume()
	else:
		unduck(0.1)

func get_volume_db() -> float:
	return player.volume_db

# --- internals ---
func _apply_volume() -> void:
	player.volume_db = _base_gain_db + _duck_offset_db

func _set_duck_offset(val: float) -> void:
	_duck_offset_db = val
	_apply_volume()

func _kill_tween() -> void:
	if is_instance_valid(_t):
		_t.kill()
	_t = null

func _make_tween() -> void:
	_kill_tween()
	_t = create_tween()
	# Keep working when the game/tree is paused:
	_t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	
# Stop immediately
func stop() -> void:
	_kill_tween()
	_duck_offset_db = 0.0
	_apply_volume()
	player.stop()

# Fade out, then stop (safe across scene reloads)
func fade_out_and_stop(secs := 0.4, to_db := -60.0) -> void:
	_kill_tween()
	_t = create_tween()
	_t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var target_offset := to_db - _base_gain_db  # total -> to_db
	_t.tween_method(_set_duck_offset, _duck_offset_db, target_offset, secs)
	_t.tween_callback(Callable(self, "_on_fade_stop"))

func _on_fade_stop() -> void:
	player.stop()
	_duck_offset_db = 0.0
	_apply_volume()

# (Optional) pause/resume without losing position
func pause() -> void:
	player.stream_paused = true

func resume() -> void:
	player.stream_paused = false
