extends Area2D
class_name UnlockArea2D

@export var milestone_on_enter: String = ""   # e.g., "WORLD:GateAOpened"
@export var player_group: String = "player"
@export var one_shot: bool = true            # make area inert after activation

# AnimatedSprite2D child + animation names
@onready var _anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var _shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
@export var idle_anim: String = "idle"
@export var activate_anim: String = "activate"    # should NOT loop
@export var activated_anim: String = "activated"  # should loop

var _used: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

	# If this milestone was already earned earlier, start in permanent-activated.
	if milestone_on_enter != "" and Unlocks.has_milestone(milestone_on_enter):
		_enter_permanent_activated_state()
	else:
		_play_if_exists(idle_anim)

	# If something else in the game awards this milestone later, reflect it.
	Unlocks.milestone_marked.connect(_on_any_milestone_marked)

func _on_any_milestone_marked(id: String) -> void:
	if id == milestone_on_enter and not _used:
		_enter_permanent_activated_state()

func _on_body_entered(body: Node) -> void:
	if _used or not body.is_in_group(player_group):
		return
	_used = true

	if milestone_on_enter != "":
		Unlocks.mark_milestone(milestone_on_enter)

	if _anim and _has_anim(activate_anim):
		_anim.play(activate_anim)
		# Wait for the one-shot activation anim to finish, then lock into activated.
		await _anim.animation_finished
	_enter_permanent_activated_state()

func _enter_permanent_activated_state() -> void:
	_used = true
	_play_if_exists(activated_anim)
	if one_shot:
		# Make the area inert going forward (defer to avoid in/out-signal errors).
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		if _shape:
			_shape.set_deferred("disabled", true)

func _play_if_exists(anim_name: String) -> void:
	if _anim and _has_anim(anim_name):
		_anim.play(anim_name)

func _has_anim(anim_name: String) -> bool:
	return _anim and _anim.sprite_frames and _anim.sprite_frames.has_animation(anim_name)
