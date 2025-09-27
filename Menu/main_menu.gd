extends Control

# Preload your level scenes
#@onready var idle_level = preload("res://Test3D.tscn")
@onready var pf_level = preload("res://Platformer/Scenes/test_world.tscn")

func _ready():
	pass

func _on_button_idle_pressed():
	#get_tree().change_scene_to_packed(idle_level)
	pass

func _on_button_pf_pressed():
	get_tree().change_scene_to_packed(pf_level)
	
func _on_button_rpg_pressed():
	pass # Replace with function body.


func _on_button_quit_pressed():
	get_tree().quit()
