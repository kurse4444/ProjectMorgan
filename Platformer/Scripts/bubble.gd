extends Area2D

@export var slow_factor: float = 0.1
@export var duration: float = 1.0
@export var fade_out_time: float = 0.5

@onready var life_timer: Timer = $LifeTimer
@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var sfx: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _ready() -> void:
	add_to_group("bubble")

	if not is_instance_valid(shape) or shape.shape == null:
		push_warning("Bubble: CollisionShape2D has no shape set.")
	elif not (shape.shape is CircleShape2D):
		push_warning("Bubble: Shape isn't a CircleShape2D. That's fine if intentional.")

	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	life_timer.one_shot = true
	life_timer.wait_time = duration
	life_timer.start()
	life_timer.timeout.connect(_on_life_timeout)
	
	# 🔊 Play sound effect when bubble spawns
	if sfx:
		sfx.play()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("slowable"):
		var s := body.get_node_or_null("Slowable")
		if s != null and "add_slow" in s:
			s.add_slow(self, slow_factor)
			print_debug("[Bubble] +slow", slow_factor, "→", body.name)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("slowable"):
		var s := body.get_node_or_null("Slowable")
		if s != null and "remove_slow" in s:
			s.remove_slow(self)
			print_debug("[Bubble] -slow →", body.name)

func _on_life_timeout() -> void:
	if has_node("Sprite2D"):
		var tw := get_tree().create_tween()
		tw.tween_property($Sprite2D, "modulate:a", 0.0, fade_out_time)
		tw.finished.connect(queue_free)
	else:
		queue_free()

func _exit_tree() -> void:
	# Safety cleanup for lingering overlaps
	for body in get_overlapping_bodies():
		if is_instance_valid(body) and body.is_in_group("slowable"):
			var s := body.get_node_or_null("Slowable")
			if s != null and "remove_slow" in s:
				s.remove_slow(self)
				print_debug("[Bubble] cleanup -slow →", body.name)
