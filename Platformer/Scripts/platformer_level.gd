extends Node2D

@export var bubble_scene: PackedScene
@export var bubble_cooldown := 0.3
@export var bubble_action_id := "PF:Bubble"   # action key in unlocks.json
@onready var bgm := $AudioStreamPlayer2D

var _can_place := true
var _current_bubble: Node2D = null   # ← track the active bubble

@export var player_path: NodePath
@onready var player := get_node(player_path)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	#_force_loop(bgm.stream)
	#if not bgm.playing:
		#bgm.play()
	PlatformerMusic.play_bgm(preload("res://Platformer/Assets/Sound/8 bit main theme.wav"))
	player.died.connect(_on_player_died)

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("place_bubble") and _can_place:
		# Block unless PF:Bubble is defined AND currently unlocked
		if not Unlocks.can(bubble_action_id):
			# Optional: feedback like show_toast("Bubble locked")
			return
		_spawn_bubble(get_global_mouse_position())
		
	if Input.is_action_just_pressed("reset_level"):
		_reset_level()

func _spawn_bubble(pos: Vector2) -> void:
	if bubble_scene == null:
		push_error("Assign bubble_scene in Level.gd!")
		return

	# 1) Remove previous bubble if it exists
	if is_instance_valid(_current_bubble):
		_current_bubble.queue_free()  # its _exit_tree will clear slows

	# 2) Spawn new bubble
	var b := bubble_scene.instantiate()
	if b is Node2D:
		(b as Node2D).global_position = pos
	add_child(b)

	# 3) Track it and auto-clear when it dies
	_current_bubble = b
	# When the bubble leaves the tree (timer, fadeout, or we replaced it), forget it.
	b.tree_exited.connect(func():
		if _current_bubble == b:
			_current_bubble = null
	)

	# 4) Start cooldown
	_start_cd()

func _start_cd() -> void:
	_can_place = false
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = bubble_cooldown
	add_child(t)
	t.timeout.connect(func():
		_can_place = true
		t.queue_free())
	t.start()

func _force_loop(stream: AudioStream) -> void:
	if stream == null:
		return
	# OGG / MP3
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	# WAV
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD

func _on_player_died() -> void:
	var should_reset_level := true
	if should_reset_level:
		_reset_level()
	else:
		player.respawn()

func _reset_level() -> void:
	# Get parent before removing self
	var parent = get_parent()
	parent.call_deferred("ResetPlatformerLevel")


func HideLevel():
	visible = false
	PlatformerMusic.stop_bgm()
	# Disable run_left, run_right
	InputMap.action_erase_events("run_left")
	InputMap.action_erase_events("run_right")
	InputMap.action_erase_events("place_bubble")
	InputMap.action_erase_events("reset_level")
	InputMap.action_erase_events("throw_bomb")

func ShowLevel():
	visible = true
	PlatformerMusic.play_bgm(preload("res://Platformer/Assets/Sound/8 bit main theme.wav"))
	
	# Enable run_left, run_right
	var left_event := InputEventKey.new()
	left_event.keycode = KEY_A
	InputMap.action_add_event("run_left", left_event)

	var right_event := InputEventKey.new()
	right_event.keycode = KEY_D
	InputMap.action_add_event("run_right", right_event)


	var bubble_event := InputEventMouseButton.new()
	bubble_event.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("place_bubble", bubble_event)

	var reset_event := InputEventKey.new()
	reset_event.keycode = KEY_R
	InputMap.action_add_event("reset_level", reset_event)

	var esc_event := InputEventKey.new()
	esc_event.keycode = KEY_W
	InputMap.action_add_event("throw_bomb", esc_event)
	
