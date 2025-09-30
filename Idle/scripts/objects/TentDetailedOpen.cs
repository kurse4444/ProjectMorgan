using Godot;
using System;

public partial class TentDetailedOpen : MeshInstance3D
{
	private Store store;
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}

	public void interact(CharacterBody3D player)
	{
		store = player.GetNode<Store>("CanvasLayer/Store");
		store.Visible = true;
		// play sound
		GetNode<AudioStreamPlayer3D>("AudioStreamPlayer3D").Play();
	}


	public override void _Input(InputEvent @event)
	{
		// Add null check here
		if (store == null) return;
		
		// Only process input if the panel is visible
		if (!store.Visible) return;

		// Close the panel on any key press or mouse button press
		if (@event is InputEventKey keyEvent && keyEvent.Pressed ||
			@event is InputEventJoypadButton joypadEvent && joypadEvent.Pressed)
		{
			store.Visible = false;
		}
	}
}
