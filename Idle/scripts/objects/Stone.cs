using Godot;
using System;

public partial class Stone : MeshInstance3D
{
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}

	public bool interact(CharacterBody3d player)
	{
		// check for selected item bomb
		if (player.GetInventory().GetSelectedItem().Id == "bomb")
		{
			GD.Print("Interacted with stone with bomb");
			Destroy();
			return true;
		}
		else
		{
			GD.Print("Interacted with stone without bomb");
			return false;
		}
	}

	public void Destroy()
	{
		// start 5 second timer
		GetNode<Timer>("Timer").Start(5);
		// make bomb visible
		GetNode<Node3D>("bomb").Visible = true;
		// on timeout, call _on_Timer_timeout
		GetNode<Timer>("Timer").Timeout += _on_Timer_timeout;
	}
	public void _on_Timer_timeout()
	{
		// turn collision off
		GetNode<CollisionShape3D>("Interactable/CollisionShape3D").Disabled = true;
		// play sound
		GetNode<AudioStreamPlayer3D>("Bomb").Play();
		// turn visibility off
		this.Visible = false;
		// turn timer off
		GetNode<Timer>("Timer").Stop();
	}
}