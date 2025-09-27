extends Node2D

@export var bubble_scene: PackedScene
@export var bubble_cooldown := 0.3
@export var bubble_action_id := "PF:Bubble"   # action key in unlocks.json
@onready var bgm := $AudioStreamPlayer2D

var _can_place := true
var _current_bubble: Node2D = null   # ← track the active bubble

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	#_force_loop(bgm.stream)
	#if not bgm.playing:
		#bgm.play()

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("place_bubble") and _can_place:
		# Block unless PF:Bubble is defined AND currently unlocked
		if not Unlocks.can(bubble_action_id):
			# Optional: feedback like show_toast("Bubble locked")
			return
		_spawn_bubble(get_global_mouse_position())

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
