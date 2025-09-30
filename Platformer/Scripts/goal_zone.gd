extends Area2D

@onready var music: AudioStreamPlayer = $AudioStreamPlayer
var triggered := false

const DELAY_BEFORE_SEC := 1.0
const DELAY_AFTER_SEC  := 1.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if triggered or not body.is_in_group("player"):
		return
	triggered = true

	PlatformerMusic.stop()
	
	# (Optional) If you previously froze the player, delete those lines to keep gameplay going.

	# ---- Delay BEFORE music (game continues) ----
	await get_tree().create_timer(DELAY_BEFORE_SEC).timeout

	if music.stream == null:
		push_error("No audio stream set on AudioStreamPlayer.")
		return

	# Make sure you're using a non-looping stream, or 'finished' won't fire.
	music.stop()
	music.play()

	await music.finished  # wait for music to end (no pausing the game)

	# ---- Delay AFTER music (game continues) ----
	await get_tree().create_timer(DELAY_AFTER_SEC).timeout

	# End (or change scene)
	get_tree().change_scene_to_file("res://Menu/main_menu.tscn")
	#get_tree().quit()
