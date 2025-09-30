# KillZone.gd
extends Area2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("die"):
		body.die()

	# Bombs
	if body.is_in_group("bomb"):
		body.queue_free()				# silent vanish
