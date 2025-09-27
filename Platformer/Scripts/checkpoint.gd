# res://Checkpoint.gd
class_name Checkpoint
extends Area2D
@onready var spawn_marker: Marker2D = $Spawn

@export var checkpoint_id: StringName = ""  # set this in the inspector
var _activated := false

func _ready() -> void:
	add_to_group("checkpoints")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _activated:
		return
	if body.is_in_group("player"):
		if str(checkpoint_id) == "":
			push_warning("Checkpoint has empty checkpoint_id")
			return
		GameState.set_checkpoint_id(str(checkpoint_id))
		_mark_active()

func _mark_active() -> void:
	_activated = true
	# Optional: visuals/SFX (e.g., change sprite/modulate/animation)
